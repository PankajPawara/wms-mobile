import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/extracted_memo.dart';
import '../../../core/providers/gemini_verification_provider.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../core/database/app_database.dart';
import '../../picking/repositories/order_repository.dart';

class OcrReviewScreen extends ConsumerStatefulWidget {
  final MemoOcrResult ocrResult;

  const OcrReviewScreen({super.key, required this.ocrResult});

  @override
  ConsumerState<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends ConsumerState<OcrReviewScreen> {
  late List<ExtractedMemoItem> _items;
  late TextEditingController _customerNameCtrl;
  late TextEditingController _areaCtrl;
  late TextEditingController _memoNumberCtrl;
  late TextEditingController _memoDateCtrl;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.ocrResult.items);
    final h = widget.ocrResult.header;
    _customerNameCtrl = TextEditingController(text: h.customerName);
    _areaCtrl = TextEditingController(text: h.area);
    _memoNumberCtrl = TextEditingController(text: h.memoNumber);
    _memoDateCtrl = TextEditingController(text: _displayMemoDate(h.memoDate));

    // Kick off background Gemini verification if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.ocrResult.needsGemini) {
        ref.read(geminiVerificationProvider.notifier).verify(
          allItems: _items,
          header: widget.ocrResult.header,
          rawOcrDump: widget.ocrResult.rawOcrDump,
          imageFile: widget.ocrResult.imagePath != null
              ? File(widget.ocrResult.imagePath!)
              : null,
        );
      }
    });
  }

  @override
  void dispose() {
    _customerNameCtrl.dispose();
    _areaCtrl.dispose();
    _memoNumberCtrl.dispose();
    _memoDateCtrl.dispose();
    super.dispose();
  }

  // Listen to Gemini verification updates and merge into local items list
  void _onGeminiUpdate(GeminiVerificationState state) {
    if (state.isCompleted && state.updatedItems.isNotEmpty) {
      if (mounted) {
        setState(() {
          _items = List.from(state.updatedItems);
        });
      }
    }
  }

  void _updateQty(int index, int delta) {
    final current = _items[index].qty;
    final newQty = (current + delta).clamp(1, 999);
    setState(() {
      _items[index] = _items[index].copyWith(qty: newQty);
    });
  }

  String _displayMemoDate(String? value) {
    if (value == null || value.isEmpty) return '';
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  Future<void> _editItem(int index) async {
    final updated = await showDialog<ExtractedMemoItem>(
      context: context,
      builder: (ctx) => _EditItemDialog(item: _items[index]),
    );
    if (updated != null && mounted) {
      setState(() => _items[index] = updated);
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
      final orderItems = _items.map((i) => i.toOrderItemMap()).toList();

      final localId = await repo.createLocalOrder(
        memoNumber: _memoNumberCtrl.text.trim(),
        customerName: _customerNameCtrl.text.trim(),
        customerLocation: _areaCtrl.text.trim(),
        memoDate: _memoDateCtrl.text.trim().isNotEmpty
            ? _memoDateCtrl.text.trim()
            : null,
        items: orderItems,
      );

      // Tell the background Gemini processor which order ID to update when finished
      ref.read(geminiVerificationProvider.notifier).attachOrderId(localId);

      if (!mounted) return;
      context.pop(); // dismiss loader
      context.go('/picking/$localId');
    } catch (e) {
      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate pickup list: $e')),
        );
      }
    }
  }

  void _showDebugDrawer() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          minChildSize: 0.4,
          expand: false,
          builder: (ctx2, scroll) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Developer Debug Panel',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(ctx2).pop()),
                  ],
                ),
                const Divider(),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    children: [
                      _DebugSection(
                          title: 'RAW ML Kit OCR Output',
                          content: widget.ocrResult.rawOcrDump),
                      const SizedBox(height: 24),
                      _DebugSection(
                          title: 'Gemini AI JSON Output',
                          content: ref.read(geminiVerificationProvider).rawJsonOutput ?? 'No AI data available.'),
                      const SizedBox(height: 24),
                      _DebugSection(
                          title: 'Extracted Items (${_items.length})',
                          content: _items
                              .map((i) =>
                                  '[${i.confidence.score}%] ${i.rawOcrPartNo} → ${i.correctedPartNo} (${i.confidence.label})')
                              .join('\n')),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Listen to Gemini updates
    ref.listen<GeminiVerificationState>(
      geminiVerificationProvider,
      (_, next) => _onGeminiUpdate(next),
    );

    final geminiState = ref.watch(geminiVerificationProvider);
    final verifiedCount = _items
        .where((i) => i.confidence != MatchConfidence.unmatched)
        .length;
    final unmatchedCount = _items.length - verifiedCount;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Review Pickup List',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text(
              '${_items.length} items · $verifiedCount verified · $unmatchedCount unmatched',
              style:
                  const TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.data_object),
            tooltip: 'Export JSON',
            onPressed: () {
              final jsonStr = const JsonEncoder.withIndent('  ').convert(widget.ocrResult.toJson());
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('AI Extracted JSON'),
                  content: SingleChildScrollView(
                    child: SelectableText(jsonStr, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: jsonStr));
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
                      },
                      child: const Text('Copy'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.bug_report_outlined),
            tooltip: 'Debug Panel',
            onPressed: _showDebugDrawer,
          ),
        ],
      ),
      body: Column(
        children: [
          // Gemini verification status banner (inline, not the global one)
          if (geminiState.isRunning)
            _GeminiStatusBar(
                label:
                    'Correcting with AI... (${geminiState.processedCount}/${geminiState.totalCount})',
                isRunning: true),
          if (geminiState.isCompleted && !geminiState.isRunning)
            _GeminiStatusBar(
                label:
                    '✅ AI verification complete',
                isRunning: false),
          if (geminiState.hasFailed)
            _GeminiStatusBar(
                label: '⚠️ AI verification failed — showing best local results',
                isRunning: false,
                isError: true),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppDimensions.md),
              children: [
                // Header fields
                _HeaderForm(
                  customerNameCtrl: _customerNameCtrl,
                  areaCtrl: _areaCtrl,
                  memoNumberCtrl: _memoNumberCtrl,
                  memoDateCtrl: _memoDateCtrl,
                ),
                const SizedBox(height: AppDimensions.md),

                // Item list
                ..._items.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final item = entry.value;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppDimensions.sm),
                    child: _OcrItemCard(
                      item: item,
                      onQtyIncrease: () => _updateQty(idx, 1),
                      onQtyDecrease: () => _updateQty(idx, -1),
                      onEdit: () => _editItem(idx),
                      onRemove: () => _removeItem(idx),
                    ),
                  );
                }),
                const SizedBox(height: 100), // space for bottom button
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: AppButton(
          label: 'Generate Pickup List',
          icon: Icons.shopping_cart_checkout_rounded,
          onPressed: _items.isEmpty ? null : _generatePickupList,
        ),
      ),
    );
  }
}

// =============================================================================
// HEADER FORM
// =============================================================================

class _HeaderForm extends StatelessWidget {
  final TextEditingController customerNameCtrl;
  final TextEditingController areaCtrl;
  final TextEditingController memoNumberCtrl;
  final TextEditingController memoDateCtrl;

  const _HeaderForm({
    required this.customerNameCtrl,
    required this.areaCtrl,
    required this.memoNumberCtrl,
    required this.memoDateCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Memo Header',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
          const SizedBox(height: 12),
          _field('Customer Name', customerNameCtrl, maxLines: 3),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _field('Area', areaCtrl)),
            const SizedBox(width: 8),
            Expanded(child: _field('Memo No.', memoNumberCtrl)),
          ]),
          const SizedBox(height: 8),
          _field('Memo Date', memoDateCtrl, hint: 'e.g. 2024-06-15'),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    String? hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: ctrl,
      minLines: 1,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.5)),
        labelStyle:
            const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}

// =============================================================================
// ITEM CARD
// =============================================================================

class _OcrItemCard extends StatelessWidget {
  final ExtractedMemoItem item;
  final VoidCallback onQtyIncrease;
  final VoidCallback onQtyDecrease;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _OcrItemCard({
    required this.item,
    required this.onQtyIncrease,
    required this.onQtyDecrease,
    required this.onEdit,
    required this.onRemove,
  });

  Color get _confidenceColor => switch (item.confidence) {
        MatchConfidence.exact => AppColors.success,
        MatchConfidence.normalized => AppColors.info,
        MatchConfidence.fuzzy => AppColors.warning,
        MatchConfidence.gemini => AppColors.primary,
        MatchConfidence.unmatched => AppColors.danger,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: AppColors.cardShadow,
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top bar: part number + confidence badge ──────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _confidenceColor.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppDimensions.radiusMd)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Corrected part number (bold, prominent)
                      Text(
                        item.correctedPartNo,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 0.5),
                        maxLines: 2,
                        softWrap: true,
                        overflow: TextOverflow.ellipsis,
                      ),
                      // If corrected ≠ raw OCR, show the raw OCR below
                      if (item.wasCorrected) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(Icons.auto_fix_high,
                                size: 12, color: AppColors.textSecondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                'OCR: ${item.rawOcrPartNo}',
                                style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    decoration: TextDecoration.lineThrough),
                                maxLines: 2,
                                softWrap: true,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // Confidence badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _confidenceColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: _confidenceColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${item.confidence.score}%',
                        style: TextStyle(
                            color: _confidenceColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        item.confidence.label,
                        style: TextStyle(
                            color: _confidenceColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Body: description + fields ───────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.description.isNotEmpty)
                  Text(
                    item.description,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 8),
                // Fields row
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _chip(Icons.location_on_outlined,
                        item.location.isEmpty ? 'No location' : item.location,
                        item.location.isEmpty
                            ? AppColors.danger
                            : AppColors.textSecondary),
                    _chip(Icons.currency_rupee,
                        item.mrp > 0 ? item.mrp.toStringAsFixed(2) : '—',
                        AppColors.textSecondary),
                    _chip(
                        Icons.inventory_2_outlined,
                        'Stock: ${item.stock}',
                        item.stock > 0
                            ? AppColors.success
                            : AppColors.danger),
                    if (item.pack > 0)
                      _chip(Icons.all_inbox_outlined, 'Pack: ${item.pack}',
                          AppColors.textSecondary),
                  ],
                ),
                const SizedBox(height: 10),
                // Qty stepper + action buttons
                Row(
                  children: [
                    _QtyStepper(
                        qty: item.qty,
                        onIncrease: onQtyIncrease,
                        onDecrease: onQtyDecrease),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          size: 20, color: AppColors.textSecondary),
                      onPressed: onEdit,
                      tooltip: 'Edit',
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 20, color: AppColors.danger),
                      onPressed: onRemove,
                      tooltip: 'Remove',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

// =============================================================================
// QTY STEPPER
// =============================================================================

class _QtyStepper extends StatelessWidget {
  final int qty;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  const _QtyStepper(
      {required this.qty,
      required this.onIncrease,
      required this.onDecrease});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _btn(Icons.remove, onDecrease),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('$qty',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15)),
          ),
          _btn(Icons.add, onIncrease),
        ],
      ),
    );
  }

  Widget _btn(IconData icon, VoidCallback fn) {
    return InkWell(
      onTap: fn,
      borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, size: 18, color: AppColors.primary),
      ),
    );
  }
}

// =============================================================================
// GEMINI STATUS BAR (inline, inside this screen)
// =============================================================================

class _GeminiStatusBar extends StatelessWidget {
  final String label;
  final bool isRunning;
  final bool isError;
  const _GeminiStatusBar(
      {required this.label,
      required this.isRunning,
      this.isError = false});

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? AppColors.warning
        : isRunning
            ? AppColors.primary
            : AppColors.success;
    return Container(
      color: color.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (isRunning)
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: color),
            )
          else
            Icon(
                isError ? Icons.warning_amber_rounded : Icons.check_circle,
                size: 16,
                color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// EDIT ITEM DIALOG
// =============================================================================

class _EditItemDialog extends StatefulWidget {
  final ExtractedMemoItem item;
  const _EditItemDialog({required this.item});

  @override
  State<_EditItemDialog> createState() => _EditItemDialogState();
}

class _EditItemDialogState extends State<_EditItemDialog> {
  late TextEditingController _partNoCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _locCtrl;
  late TextEditingController _qtyCtrl;
  late TextEditingController _mrpCtrl;
  late TextEditingController _packCtrl;
  late TextEditingController _stockCtrl;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _partNoCtrl = TextEditingController(text: i.correctedPartNo);
    _descCtrl = TextEditingController(text: i.description);
    _locCtrl = TextEditingController(text: i.location);
    _qtyCtrl = TextEditingController(text: '${i.qty}');
    _mrpCtrl = TextEditingController(text: i.mrp.toStringAsFixed(2));
    _packCtrl = TextEditingController(text: '${i.pack}');
    _stockCtrl = TextEditingController(text: '${i.stock}');
  }

  @override
  void dispose() {
    for (final c in [
      _partNoCtrl, _descCtrl, _locCtrl, _qtyCtrl,
      _mrpCtrl, _packCtrl, _stockCtrl
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Item',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tf('Part Number', _partNoCtrl,
                caps: TextCapitalization.characters),
            _tf('Description', _descCtrl),
            _tf('Location', _locCtrl,
                caps: TextCapitalization.characters),
            Row(children: [
              Expanded(child: _tf('Qty', _qtyCtrl, numeric: true)),
              const SizedBox(width: 8),
              Expanded(child: _tf('MRP', _mrpCtrl, decimal: true)),
            ]),
            Row(children: [
              Expanded(child: _tf('Pack', _packCtrl, numeric: true)),
              const SizedBox(width: 8),
              Expanded(child: _tf('Stock', _stockCtrl, numeric: true)),
            ]),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            Navigator.pop(
              context,
              widget.item.copyWith(
                correctedPartNo:
                    _partNoCtrl.text.trim().toUpperCase(),
                description: _descCtrl.text.trim(),
                location:
                    _locCtrl.text.trim().toUpperCase(),
                qty: int.tryParse(_qtyCtrl.text) ?? widget.item.qty,
                mrp: double.tryParse(_mrpCtrl.text) ?? widget.item.mrp,
                pack: int.tryParse(_packCtrl.text) ?? widget.item.pack,
                stock:
                    int.tryParse(_stockCtrl.text) ?? widget.item.stock,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  Widget _tf(
    String label,
    TextEditingController ctrl, {
    bool numeric = false,
    bool decimal = false,
    TextCapitalization caps = TextCapitalization.none,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        textCapitalization: caps,
        keyboardType: decimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : numeric
                ? TextInputType.number
                : TextInputType.text,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          labelStyle: const TextStyle(fontSize: 12),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        ),
      ),
    );
  }
}

// =============================================================================
// DEBUG SECTION WIDGET
// =============================================================================

class _DebugSection extends StatelessWidget {
  final String title;
  final String content;
  const _DebugSection({required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 14)),
            IconButton(
              icon: const Icon(Icons.copy, size: 18),
              tooltip: 'Copy',
              onPressed: () => Clipboard.setData(ClipboardData(text: content)),
            ),
          ],
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            content.isEmpty ? '(empty)' : content,
            style: const TextStyle(
                fontFamily: 'monospace',
                color: Color(0xFF9CDCFE),
                fontSize: 11),
          ),
        ),
      ],
    );
  }
}
