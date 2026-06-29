import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_bottom_nav.dart';
import '../../picking/repositories/order_repository.dart';
import '../../../core/database/app_database.dart';

class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _searchController = TextEditingController();
  String _sortBy = 'Date';
  String _sortDir = 'Descending';
  List<Order> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadOrdersAndSync();
  }

  Future<void> _loadOrdersAndSync() async {
    setState(() => _isLoading = true);
    final repo = ref.read(orderRepositoryProvider);
    // Try to sync with server first (swallows exceptions offline)
    await repo.syncOrdersFromServer();
    await _refreshLocalOrders();
  }

  Future<void> _refreshLocalOrders() async {
    final repo = ref.read(orderRepositoryProvider);
    final orders = await repo.getLocalOrders(search: _searchController.text);
    if (mounted) {
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    }
  }

  List<Order> get _filtered {
    final tab = _tabController.index;
    final filtered = _orders.where((o) {
      if (tab == 1 && o.status != 'picking' && o.status != 'draft') return false;
      if (tab == 2 && o.status != 'checked') return false;
      return true;
    }).toList();

    // Sort
    filtered.sort((a, b) {
      int cmp;
      if (_sortBy == 'Customer') {
        cmp = (a.customerName ?? '').compareTo(b.customerName ?? '');
      } else {
        cmp = a.createdAt.compareTo(b.createdAt);
      }
      return _sortDir == 'Descending' ? -cmp : cmp;
    });

    return filtered;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: Column(
        children: [
          // Purple App Bar
          Container(
            color: AppColors.primary,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: () => context.go('/home'),
                        ),
                        const Expanded(
                          child: Text(
                            'Order History',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh_rounded, color: Colors.white),
                          onPressed: _loadOrdersAndSync,
                        ),
                      ],
                    ),
                  ),

                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (_) => _refreshLocalOrders(),
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search customer name or memo...',
                        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        prefixIcon: const Icon(Icons.search_rounded,
                            color: Color(0xFF9CA3AF), size: 20),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchController.clear();
                                  _refreshLocalOrders();
                                },
                              )
                            : null,
                        fillColor: Colors.white,
                        filled: true,
                        isDense: true,
                        contentPadding: const EdgeInsets.all(10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),

                  // Tabs
                  TabBar(
                    controller: _tabController,
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white70,
                    labelStyle:
                        const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    tabs: const [
                      Tab(text: 'All Orders'),
                      Tab(text: 'In Progress'),
                      Tab(text: 'Completed'),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Chips area
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: Colors.white,
            child: Row(
              children: [
                _SortChip(
                  prefix: 'Sort by:',
                  value: _sortBy,
                  icon: Icons.sort_rounded,
                  onTap: () {
                    setState(() {
                      _sortBy = _sortBy == 'Date' ? 'Customer' : 'Date';
                    });
                  },
                ),
                const SizedBox(width: 8),
                _SortChip(
                  prefix: '',
                  value: _sortDir,
                  icon: Icons.swap_vert_rounded,
                  onTap: () {
                    setState(() {
                      _sortDir = _sortDir == 'Descending'
                          ? 'Ascending'
                          : 'Descending';
                    });
                  },
                ),
              ],
            ),
          ),

          // Orders List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(
                        child: Text(
                          'No orders found',
                          style: TextStyle(color: Color(0xFF6B7280)),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filtered.length,
                        itemBuilder: (context, index) {
                          final order = _filtered[index];
                          return _OrderCard(
                            order: order,
                            onTap: () => context.push('/order/${order.id}').then((_) => _refreshLocalOrders()),
                          );
                        },
                      ),
          ),

          const AppBottomNav(currentIndex: 4),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String prefix;
  final String value;
  final IconData icon;
  final VoidCallback onTap;
  const _SortChip(
      {required this.prefix,
      required this.value,
      required this.icon,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF6B7280)),
            const SizedBox(width: 4),
            Text(
              prefix.isNotEmpty ? '$prefix $value' : value,
              style:
                  const TextStyle(fontSize: 12, color: Color(0xFF374151)),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down_rounded,
                size: 16, color: Color(0xFF6B7280)),
          ],
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;
  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = order.status;

    final (statusLabel, statusColor, statusBg) = switch (status) {
      'checked' => ('Completed', AppColors.success, AppColors.successLight),
      'picking' || 'draft' => ('In Progress', AppColors.warning, AppColors.warningLight),
      'cancelled' => ('Cancelled', AppColors.danger, AppColors.dangerLight),
      _ => ('Pending', AppColors.textSecondary, AppColors.border),
    };

    final avatarColor = switch (status) {
      'checked' => AppColors.success,
      'picking' || 'draft' => AppColors.warning,
      'cancelled' => AppColors.danger,
      _ => AppColors.textSecondary,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0A000000), blurRadius: 6, offset: Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: avatar + customer name + order id + status badge
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: avatarColor.withValues(alpha: 0.15),
                  child: Text(
                    (order.customerName ?? 'C')[0],
                    style: TextStyle(
                        color: avatarColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    order.customerName ?? '-',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('#${order.memoNumber}',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151))),
              ],
            ),
            const SizedBox(height: 4),

            // Area + status badge row
            Row(
              children: [
                const SizedBox(width: 46),
                Text(order.customerLocation ?? '-',
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280))),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(statusLabel,
                      style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const Divider(height: 16),

            // Date
            Row(
              children: [
                const Icon(Icons.calendar_today_rounded,
                    size: 14, color: Color(0xFF9CA3AF)),
                const SizedBox(width: 4),
                Text(
                  order.createdAt.length > 16 ? order.createdAt.substring(0, 16).replaceAll('T', ' ') : order.createdAt,
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7280)),
                ),
                const Spacer(),
                Text(
                  '₹${order.finalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
