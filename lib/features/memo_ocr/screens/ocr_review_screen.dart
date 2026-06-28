import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/status_badge.dart';

class OcrReviewScreen extends ConsumerStatefulWidget {
  final List<Map<String, dynamic>> extractedItems;
  const OcrReviewScreen({super.key, required this.extractedItems});

  @override
  ConsumerState<OcrReviewScreen> createState() => _OcrReviewScreenState();
}

class _OcrReviewScreenState extends ConsumerState<OcrReviewScreen> {
  late List<Map<String, dynamic>> _items;

  @override
  void initState() {
    super.initState();
    _items = widget.extractedItems
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  void _updateQty(int index, int qty) {
    setState(() => _items[index]['required_qty'] = qty.clamp(1, 999));
  }

  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  void _generatePickupList() {
    if (_items.isEmpty) return;
    // Navigate to picking with these items as a new order
    // TODO: Create order from items then navigate to picking
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Creating pickup list...'),
          backgroundColor: AppColors.primary),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.reviewItems),
        actions: [
          Padding(
            padding:
                const EdgeInsets.only(right: AppDimensions.md),
            child: Center(
              child: Text(
                '${_items.length} item${_items.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _items.isEmpty
                ? const Center(
                    child: Text(AppStrings.noItemsExtracted,
                        style:
                            TextStyle(color: AppColors.textSecondary)))
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
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(AppDimensions.md),
            child: AppButton(
              label: AppStrings.generatePickupList,
              icon: Icons.check_rounded,
              onPressed: _items.isEmpty ? null : _generatePickupList,
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

    return Container(
      padding: const EdgeInsets.all(AppDimensions.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  partNo,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.textPrimary),
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
          if (location.isNotEmpty) ...
            [
              const SizedBox(height: AppDimensions.xs),
              Row(
                children: [
                  const Icon(Icons.location_on_outlined,
                      size: 14, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text(
                    location,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.primary),
                  ),
                ],
              ),
            ],
          if (description.isNotEmpty) ...
            [
              const SizedBox(height: AppDimensions.xs),
              Text(
                description,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          const SizedBox(height: AppDimensions.sm),
          Row(
            children: [
              const Text('Qty:',
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary)),
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
    );
  }
}
