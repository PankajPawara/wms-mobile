import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../picking/repositories/order_repository.dart';
import '../../../core/database/app_database.dart';

class PickedItemsScreen extends ConsumerStatefulWidget {
  final String orderId;
  const PickedItemsScreen({super.key, required this.orderId});

  @override
  ConsumerState<PickedItemsScreen> createState() => _PickedItemsScreenState();
}

class _PickedItemsScreenState extends ConsumerState<PickedItemsScreen> {
  Order? _order;
  List<OrderItem> _items = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    final id = int.tryParse(widget.orderId);
    if (id != null) {
      final repo = ref.read(orderRepositoryProvider);
      final order = await repo.getLocalOrderById(id);
      final items = await repo.getLocalOrderItems(id);
      if (mounted) {
        setState(() {
          _order = order;
          _items = items;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Picked Items')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_order == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Picked Items')),
        body: const Center(child: Text('Order not found')),
      );
    }

    final order = _order!;
    final pickedItems = _items.where((i) => i.status == 'picked' || i.status == 'checked').toList();
    final notFoundItems = _items.where((i) => i.status == 'missing').toList();
    final pendingItems = _items.where((i) => i.status == 'pending').toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => context.pop(),
        ),
        title: const Text('Picked Items',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Summary header
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeaderField(
                      label: 'Memo No.', value: '#${order.memoNumber}'),
                ),
                Expanded(
                  child: _HeaderField(
                      label: 'Customer',
                      value: order.customerName ?? '-'),
                ),
              ],
            ),
          ),

          // Items list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                if (pickedItems.isNotEmpty) ...[
                  _SectionHeader(
                      label: 'Picked Items (${pickedItems.length})',
                      color: AppColors.success),
                  const SizedBox(height: 8),
                  ...pickedItems.map((item) => _ItemCard(item: item)),
                  const SizedBox(height: 16),
                ],

                if (notFoundItems.isNotEmpty) ...[
                  _SectionHeader(
                      label: 'Not Found Items (${notFoundItems.length})',
                      color: AppColors.danger),
                  const SizedBox(height: 8),
                  ...notFoundItems.map((item) => _ItemCard(item: item)),
                  const SizedBox(height: 16),
                ],

                if (pendingItems.isNotEmpty) ...[
                  _SectionHeader(
                      label: 'Pending Items (${pendingItems.length})',
                      color: AppColors.warning),
                  const SizedBox(height: 8),
                  ...pendingItems.map((item) => _ItemCard(item: item)),
                  const SizedBox(height: 16),
                ],

                if (_items.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Text('No items in this order',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),

                // Footer stats
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                          child: _FooterStat(
                              label: 'Total Items',
                              value: '${_items.length}',
                              color: Colors.black)),
                      const VerticalDivider(width: 1),
                      Expanded(
                          child: _FooterStat(
                              label: 'Picked Items',
                              value: '${pickedItems.length}',
                              color: AppColors.success)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderField extends StatelessWidget {
  final String label;
  final String value;
  const _HeaderField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionHeader({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 14,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.bold, color: color),
        ),
      ],
    );
  }
}

class _ItemCard extends StatelessWidget {
  final OrderItem item;
  const _ItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.partNo,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827))),
                const SizedBox(height: 2),
                Text(item.description ?? '',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6B7280)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 11, color: Color(0xFF9CA3AF)),
                    const SizedBox(width: 2),
                    Text(item.location,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF6B7280))),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹${item.unitPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151))),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF3F4F6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Qty: ${item.pickedQty}/${item.requiredQty}',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF374151)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FooterStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _FooterStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 10, color: Color(0xFF9CA3AF))),
      ],
    );
  }
}
