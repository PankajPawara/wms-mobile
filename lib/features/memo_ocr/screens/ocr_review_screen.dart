import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/services/gemini_fallback_service.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../core/database/app_database.dart';
import '../../picking/repositories/order_repository.dart';

class OcrReviewScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> extractedItems;
  final String? customerName;
  final String? customerLocation;
  final String? memoNumber;
  final String? rawText;
  final String? imagePath;

  const OcrReviewScreen({
    super.key,
    required this.extractedItems,
    this.customerName,
    this.customerLocation,
    this.memoNumber,
    this.rawText,
    this.imagePath,
  });

  @override
  ConsumerState<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends ConsumerState<OcrReviewScreen> {
  late List<Map<String, dynamic>> _items;
  bool _isLoading = true;
  bool _isAiEnhancing = false;
  String? _geminiRawResponse;

  late TextEditingController _customerNameController;
  late TextEditingController _customerLocationController;
  late TextEditingController _memoNumberController;

  @override
  void initState() {
    super.initState();
    _customerNameController = TextEditingController(text: widget.customerName);
    _customerLocationController = TextEditingController(text: widget.customerLocation);
    _memoNumberController = TextEditingController(text: widget.memoNumber);
    _resolveExtractedItems().then((_) {
      if (widget.rawText != null && widget.rawText!.isNotEmpty) {
        _runGeminiEnhancement();
      }
    });
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerLocationController.dispose();
    _memoNumberController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>?> _resolvePartNo(String rawPartNo) async {
    final db = ref.read(appDatabaseProvider);
    
    // 1. Direct query
    var matches = await (db.select(db.inventory)..where((t) => t.partNo.equals(rawPartNo))).get();
    if (matches.isNotEmpty) {
      return {
        'part_no': rawPartNo,
        'item': matches.first,
      };
    }
    
    // 2. Try stripping leading garbage characters (like '1', 'l', '|', '!', '/')
    var cleaned = rawPartNo;
    while (cleaned.length > 5 && (cleaned.startsWith('1') || cleaned.startsWith('l') || cleaned.startsWith('|') || cleaned.startsWith('!') || cleaned.startsWith('/'))) {
      cleaned = cleaned.substring(1);
      matches = await (db.select(db.inventory)..where((t) => t.partNo.equals(cleaned))).get();
      if (matches.isNotEmpty) {
        return {
          'part_no': cleaned,
          'item': matches.first,
        };
      }
    }
    
    // 3. Try partial case-insensitive query matching
    matches = await (db.select(db.inventory)..where((t) => t.partNo.like('%$rawPartNo%'))).get();
    if (matches.isNotEmpty) {
      return {
        'part_no': matches.first.partNo,
        'item': matches.first,
      };
    }
    
    return null;
  }

  Future<void> _resolveExtractedItems() async {
    final List<Map<String, dynamic>> resolved = [];
    for (final item in widget.extractedItems) {
      final partNo = item['part_no'] as String;
      final requiredQty = item['required_qty'] as int? ?? 1;
      final price = item['price'] as double? ?? 0.0;
      final ocrDescription = item['description'] as String?;
      final ocrLocation = item['location'] as String?;
      final ocrStock = item['stock'] as int?;
      final ocrPack = item['pack'] as int?;

      final resolvedResult = await _resolvePartNo(partNo);
      if (resolvedResult != null) {
        final dbItem = resolvedResult['item'] as InventoryData;
        resolved.add({
          'part_no': resolvedResult['part_no'],
          'required_qty': requiredQty,
          'price': price > 0 ? price : dbItem.price,
          'description': dbItem.description != null && dbItem.description!.isNotEmpty
              ? dbItem.description!
              : (ocrDescription != null && ocrDescription.isNotEmpty ? ocrDescription : ''),
          'location': dbItem.location.isNotEmpty
              ? dbItem.location
              : (ocrLocation != null && ocrLocation.isNotEmpty ? ocrLocation : 'LOCATION NOT DEFINED'),
          'stock': dbItem.stock > 0 ? dbItem.stock : (ocrStock ?? 0),
          'pack': ocrPack ?? 0,
          'match_status': 'verified',
        });
      } else {
        resolved.add({
          'part_no': partNo,
          'required_qty': requiredQty,
          'price': price,
          'description': ocrDescription != null && ocrDescription.isNotEmpty
              ? ocrDescription
              : 'Unrecognized Part',
          'location': ocrLocation != null && ocrLocation.isNotEmpty
              ? ocrLocation
              : 'LOCATION NOT DEFINED',
          'stock': ocrStock ?? 0,
          'pack': ocrPack ?? 0,
          'match_status': 'unmatched',
        });
      }
    }

    if (mounted) {
      setState(() {
        _items = resolved;
        _isLoading = false;
      });
    }
  }

  void _updateQty(int index, int qty) {
    setState(() => _items[index]['required_qty'] = qty.clamp(1, 999));
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  Future<void> _editItem(int index) async {
    final updatedItem = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _EditItemDialog(item: _items[index]),
    );

    if (updatedItem != null) {
      setState(() {
        _items[index] = updatedItem;
      });
    }
  }

  Future<void> _generatePickupList() async {
    if (_items.isEmpty) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final repo = ref.read(orderRepositoryProvider);
      final List<Map<String, dynamic>> orderItems = [];

      for (final item in _items) {
        final partNo = item['part_no'] as String;
        final requiredQty = item['required_qty'] as int? ?? 1;
        final price = item['price'] as double? ?? 0.0;
        final desc = item['description'] as String? ?? '';
        final loc = item['location'] as String? ?? 'LOCATION NOT DEFINED';

        orderItems.add({
          'part_no': partNo,
          'description': desc,
          'location': loc,
          'required_qty': requiredQty,
          'unit_price': price,
        });
      }

      final localId = await repo.createLocalOrder(
        memoNumber: _memoNumberController.text.trim(),
        customerName: _customerNameController.text.trim(),
        customerLocation: _customerLocationController.text.trim(),
        items: orderItems,
      );

      if (!mounted) return;
      context.pop(); // Dismiss loader
      context.go('/picking/$localId');
    } catch (e) {
      if (mounted) {
        context.pop(); // Dismiss loader
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate pickup list: $e')),
        );
      }
    }
  }

  Future<void> _runGeminiEnhancement() async {
    if (!mounted) return;
    setState(() => _isAiEnhancing = true);

    try {
      final header = {
        'customerName': widget.customerName ?? '',
        'customerLocation': widget.customerLocation ?? '',
        'memoNumber': widget.memoNumber ?? '',
      };

      File? imageFile;
      if (widget.imagePath != null) {
        imageFile = File(widget.imagePath!);
      }

      final result = await GeminiFallbackService.correctOcrData(
        widget.rawText!,
        header,
        widget.extractedItems,
        imageFile: imageFile,
      );

      if (!mounted) return;
      
      setState(() {
        _geminiRawResponse = const JsonEncoder.withIndent('  ').convert(result);
      });

      // Update Header if Gemini found better ones
      final newHeader = result['header'] as Map<String, dynamic>?;
      if (newHeader != null) {
        if (newHeader['customer'] != null && newHeader['customer'].toString().isNotEmpty) {
          _customerNameController.text = newHeader['customer'].toString();
        }
        if (newHeader['area'] != null && newHeader['area'].toString().isNotEmpty) {
          _customerLocationController.text = newHeader['area'].toString();
        }
        if (newHeader['memo_no'] != null && newHeader['memo_no'].toString().isNotEmpty) {
          _memoNumberController.text = newHeader['memo_no'].toString();
        }
      }

      // Update Items
      final newItems = result['items'] as List<dynamic>?;
      if (newItems != null && newItems.isNotEmpty) {
        final List<Map<String, dynamic>> updatedExtracted = newItems.map((e) => e as Map<String, dynamic>).toList();
        
        // Re-resolve the items to get DB stock/location
        final List<Map<String, dynamic>> resolved = [];
        for (final item in updatedExtracted) {
          final partNo = item['part_no']?.toString() ?? '';
          final requiredQty = int.tryParse(item['qty']?.toString() ?? '1') ?? 1;
          final price = double.tryParse(item['mrp']?.toString() ?? '0') ?? 0.0;
          final ocrDescription = item['description']?.toString();
          final ocrLocation = item['location']?.toString();
          final ocrStock = int.tryParse(item['stock']?.toString() ?? '0');
          final ocrPack = int.tryParse(item['pack']?.toString() ?? '0');

          final resolvedResult = await _resolvePartNo(partNo);
          if (resolvedResult != null) {
            final dbItem = resolvedResult['item'] as InventoryData;
            resolved.add({
              'part_no': resolvedResult['part_no'],
              'required_qty': requiredQty,
              'price': price > 0 ? price : dbItem.price,
              'description': dbItem.description != null && dbItem.description!.isNotEmpty
                  ? dbItem.description!
                  : (ocrDescription != null && ocrDescription.isNotEmpty ? ocrDescription : ''),
              'location': dbItem.location.isNotEmpty
                  ? dbItem.location
                  : (ocrLocation != null && ocrLocation.isNotEmpty ? ocrLocation : 'LOCATION NOT DEFINED'),
              'stock': dbItem.stock > 0 ? dbItem.stock : (ocrStock ?? 0),
              'pack': ocrPack ?? 0,
              'match_status': 'verified',
            });
          } else {
            resolved.add({
              'part_no': partNo,
              'required_qty': requiredQty,
              'price': price,
              'description': ocrDescription != null && ocrDescription.isNotEmpty
                  ? ocrDescription
                  : 'Unrecognized Part',
              'location': ocrLocation != null && ocrLocation.isNotEmpty
                  ? ocrLocation
                  : 'LOCATION NOT DEFINED',
              'stock': ocrStock ?? 0,
              'pack': ocrPack ?? 0,
              'match_status': 'unmatched',
            });
          }
        }
        
        if (mounted) {
          setState(() {
            _items = resolved;
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ AI Enhancement complete!'), backgroundColor: AppColors.success),
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('AI Enhancement failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isAiEnhancing = false);
      }
    }
  }

  void _showDebugDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Developer Debug Panel', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
                    ],
                  ),
                  const Divider(),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      children: [
                        _buildDebugSection('RAW ML Kit Output', widget.rawText ?? 'No local OCR text available.'),
                        const SizedBox(height: 24),
                        _buildDebugSection('RAW Gemini JSON', _geminiRawResponse ?? 'No Gemini response yet.'),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDebugSection(String title, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
            TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Copy'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$title copied to clipboard!')));
              },
            ),
          ],
        ),
        Container(
          height: 200,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.grey.shade900,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            child: Text(
              content,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.greenAccent),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          AppStrings.reviewItems,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: _showDebugDrawer,
            tooltip: 'Debug Panel',
          ),
          Padding(
            padding: const EdgeInsets.only(right: AppDimensions.md),
            child: Center(
              child: Text(
                '${_items.length} item${_items.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_isAiEnhancing)
                  Container(
                    width: double.infinity,
                    color: Colors.blue.shade50,
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '🤖 AI is enhancing extraction. Please wait...',
                          style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.w500, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                if (_isAiEnhancing)
                  const LinearProgressIndicator(minHeight: 2),
                // Memo Details Header Form
                Container(
                  padding: const EdgeInsets.all(AppDimensions.md),
                  color: Theme.of(context).colorScheme.surface,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _memoNumberController,
                              decoration: const InputDecoration(
                                labelText: 'Memo Number',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: AppDimensions.sm),
                          Expanded(
                            child: TextField(
                              controller: _customerLocationController,
                              decoration: const InputDecoration(
                                labelText: 'Area / Location',
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: OutlineInputBorder(),
                              ),
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.sm),
                      TextField(
                        controller: _customerNameController,
                        decoration: const InputDecoration(
                          labelText: 'Customer Name',
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant),
                Expanded(
                  child: _items.isEmpty
                      ? Center(
                          child: Text(AppStrings.noItemsExtracted,
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)))
                      : ListView.separated(
                          padding: const EdgeInsets.all(AppDimensions.md),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: AppDimensions.sm),
                          itemBuilder: (context, index) =>
                              _OcrItemCard(
                            item: _items[index],
                            onQtyChanged: (qty) => _updateQty(index, qty),
                            onRemove: () => _removeItem(index),
                            onEdit: () => _editItem(index),
                          ),
                        ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    color: Theme.of(context).colorScheme.surface,
                    padding: const EdgeInsets.fromLTRB(AppDimensions.md, AppDimensions.md, AppDimensions.md, AppDimensions.md),
                    child: AppButton(
                      label: AppStrings.generatePickupList,
                      icon: Icons.check_rounded,
                      onPressed: _items.isEmpty ? null : _generatePickupList,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _OcrItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final ValueChanged<int> onQtyChanged;
  final VoidCallback onRemove;
  final VoidCallback onEdit;

  const _OcrItemCard({
    required this.item,
    required this.onQtyChanged,
    required this.onRemove,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final partNo = item['part_no'] as String? ?? '--';
    final location = item['location'] as String? ?? '';
    final description = item['description'] as String? ?? '';
    final qty = item['required_qty'] as int? ?? 1;
    final matchStatus = item['match_status'] as String? ?? 'unknown';
    final price = item['price'] as double? ?? 0.0;
    final stock = item['stock'] as int? ?? 0;
    final pack = item['pack'] as int? ?? 0;

    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  partNo,
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: colorScheme.onSurface),
                ),
              ),
              StatusBadge(status: matchStatus),
              const SizedBox(width: AppDimensions.sm),
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    color: AppColors.primary, size: 20),
                onPressed: onEdit,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: AppDimensions.sm),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppColors.danger, size: 20),
                onPressed: onRemove,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: AppDimensions.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (location.isNotEmpty)
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                      location,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.primary, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              Text(
                'Stock: $stock NOS ${pack > 0 ? '| Pack: $pack' : ''}',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: stock > 0 ? AppColors.success : AppColors.danger),
              ),
            ],
          ),
          if (description.isNotEmpty) ...
            [
              const SizedBox(height: AppDimensions.xs),
              Text(
                description,
                style: TextStyle(
                    fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ],
          const SizedBox(height: AppDimensions.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Price: ₹${price.toStringAsFixed(2)}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface),
              ),
              Row(
                children: [
                  Text('Qty:',
                      style: TextStyle(
                          fontSize: 13, color: colorScheme.onSurfaceVariant)),
                  const SizedBox(width: AppDimensions.sm),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: AppColors.primary, size: 20),
                    onPressed: () => onQtyChanged(qty - 1),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppDimensions.sm),
                    child: Text(
                      '$qty',
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline,
                        color: AppColors.primary, size: 20),
                    onPressed: () => onQtyChanged(qty + 1),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EditItemDialog extends StatefulWidget {
  final Map<String, dynamic> item;
  const _EditItemDialog({required this.item});

  @override
  State<_EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<_EditItemDialog> {
  late TextEditingController _partNoCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _locCtrl;
  late TextEditingController _packCtrl;
  late TextEditingController _stockCtrl;
  late TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _partNoCtrl = TextEditingController(text: widget.item['part_no']?.toString());
    _descCtrl = TextEditingController(text: widget.item['description']?.toString());
    _locCtrl = TextEditingController(text: widget.item['location']?.toString());
    _packCtrl = TextEditingController(text: widget.item['pack']?.toString());
    _stockCtrl = TextEditingController(text: widget.item['stock']?.toString());
    _priceCtrl = TextEditingController(text: widget.item['price']?.toString());
  }

  @override
  void dispose() {
    _partNoCtrl.dispose();
    _descCtrl.dispose();
    _locCtrl.dispose();
    _packCtrl.dispose();
    _stockCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: _partNoCtrl,
                decoration: const InputDecoration(labelText: 'Part No', isDense: true, border: OutlineInputBorder()),
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            TextField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Description', isDense: true, border: OutlineInputBorder()),
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            TextField(
                controller: _locCtrl,
                decoration: const InputDecoration(labelText: 'Location', isDense: true, border: OutlineInputBorder()),
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                      controller: _packCtrl,
                      decoration: const InputDecoration(labelText: 'Pack', isDense: true, border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                      controller: _stockCtrl,
                      decoration: const InputDecoration(labelText: 'Stock', isDense: true, border: OutlineInputBorder()),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
                controller: _priceCtrl,
                decoration: const InputDecoration(labelText: 'Price', isDense: true, border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 12),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final updated = Map<String, dynamic>.from(widget.item);
            updated['part_no'] = _partNoCtrl.text.trim();
            updated['description'] = _descCtrl.text.trim();
            updated['location'] = _locCtrl.text.trim();
            updated['pack'] = int.tryParse(_packCtrl.text.trim()) ?? 0;
            updated['stock'] = int.tryParse(_stockCtrl.text.trim()) ?? 0;
            updated['price'] = double.tryParse(_priceCtrl.text.trim()) ?? 0.0;
            Navigator.pop(context, updated);
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
