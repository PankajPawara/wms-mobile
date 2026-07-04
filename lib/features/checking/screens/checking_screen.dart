import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/status_badge.dart';
import '../../picking/repositories/order_repository.dart';
import '../../../core/database/app_database.dart';

class CheckingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const CheckingScreen({super.key, required this.orderId});

  @override
  ConsumerState<CheckingScreen> createState() => _CheckingScreenState();
}

class _CheckingScreenState extends ConsumerState<CheckingScreen> {
  List<OrderItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final id = int.tryParse(widget.orderId);
    if (id == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final items =
        await ref.read(orderRepositoryProvider).getLocalOrderItems(id);
    if (mounted) {
      setState(() {
        _items = items;
        _isLoading = false;
      });
    }
  }

  bool get _allChecked =>
      _items.isNotEmpty &&
      _items.every((i) => i.status == 'checked' || i.status == 'missing');

  /// Fixed status logic: 0 qty → missing, qty >= picked → checked, else pending
  void _markChecked(int index, int qty) async {
    final item = _items[index];
    final status =
        qty == 0 ? 'missing' : (qty >= item.pickedQty ? 'checked' : 'pending');

    await ref.read(orderRepositoryProvider).updateOrderItemQty(
          itemId: item.id,
          checkedQty: qty,
          status: status,
        );
    // Guard mounted before calling setState inside _loadItems
    if (mounted) await _loadItems();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('Checking — ${widget.orderId}'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 17,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(AppDimensions.md),
              itemCount: _items.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: AppDimensions.sm),
              itemBuilder: (context, index) {
                final item = _items[index];
                final picked = item.pickedQty;
                final checked = item.checkedQty;
                return Container(
                  padding: const EdgeInsets.all(AppDimensions.md),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusMd),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.partNo,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          StatusBadge(status: item.status),
                        ],
                      ),
                      Text(item.description ?? '',
                          style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 13)),
                      const SizedBox(height: AppDimensions.sm),
                      Row(
                        children: [
                          Text(
                              'Picked: $picked | Checked: $checked',
                              style: const TextStyle(fontSize: 13)),
                          const Spacer(),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    color: AppColors.primary, size: 22),
                                onPressed: checked > 0
                                    ? () => _markChecked(index, checked - 1)
                                    : null,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: AppDimensions.sm),
                                child: Text('$checked',
                                    style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline,
                                    color: AppColors.primary, size: 22),
                                onPressed: checked < picked
                                    ? () => _markChecked(index, checked + 1)
                                    : null,
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
              },
            ),
          ),
          Container(
            color: colorScheme.surface,
            padding: EdgeInsets.fromLTRB(
              AppDimensions.md,
              AppDimensions.md,
              AppDimensions.md,
              AppDimensions.md + MediaQuery.of(context).padding.bottom,
            ),
            child: AppButton(
              label: AppStrings.completeChecking,
              icon: Icons.verified_rounded,
              onPressed: _allChecked
                  ? () async {
                      final id = int.tryParse(widget.orderId);
                      if (id != null) {
                        await ref
                            .read(orderRepositoryProvider)
                            .updateOrderStatus(id, 'checked');
                      }
                      // Navigate back to checking list (not home) to preserve navigation stack
                      if (context.mounted) {
                        context.go('/checking-list');
                      }
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
