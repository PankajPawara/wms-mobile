import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../../core/database/app_database.dart';
import '../../picking/repositories/order_repository.dart';

class OcrReviewScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> extractedItems;
  final String? customerName;
  final String? customerLocation;
  final String? memoNumber;

  const OcrReviewScreen({
    super.key,
    required this.extractedItems,
    this.customerName,
    this.customerLocation,
    this.memoNumber,
  });

  @override
  ConsumerState<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends ConsumerState<OcrReviewScreen> {
  late List<Map<String, dynamic>> _items;
  bool _isLoading = true;
  late TextEditingController _customerNameController;
  late TextEditingController _customerLocationController;
  late TextEditingController _memoNumberController;

  @override
  void initState() {
    super.initState();
    _customerNameController = TextEditingController(text: widget.customerName);
    _customerLocationController = TextEditingController(text: widget.customerLocation);
    _memoNumberController = TextEditingController(text: widget.memoNumber);
    _resolveExtractedItems();
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

  const _OcrItemCard({
    required this.item,
    required this.onQtyChanged,
    required this.onRemove,
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
                'Stock: $stock NOS',
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
