import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/app_bottom_nav.dart';

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

  // Mock data
  final _orders = [
    {
      'id': '6389', 'customer': 'Tirupati Auto Spare Parts',
      'area': 'Mandsaur', 'status': 'completed',
      'pickedBy': 'Pankaj Pawara (EMP001)', 'verifiedBy': 'Rakesh Sharma (EMP002)',
      'totalItems': 20, 'pickedItems': 18, 'notFound': 2,
      'date': '18 Jun 2026, 12:15 PM',
    },
    {
      'id': '6390', 'customer': 'Kausar Auto Parts',
      'area': 'Ratlam', 'status': 'in_progress',
      'pickedBy': 'Ramesh Parmar (EMP003)', 'verifiedBy': '-',
      'totalItems': 20, 'pickedItems': 15, 'notFound': 5,
      'date': '18 Jun 2026, 10:15 AM',
    },
    {
      'id': '6388', 'customer': 'Prince Auto Center',
      'area': 'Ujjain', 'status': 'completed',
      'pickedBy': 'Mahesh Chouhan (EMP004)', 'verifiedBy': 'Ajay Verma (EMP005)',
      'totalItems': 20, 'pickedItems': 20, 'notFound': 0,
      'date': '17 Jun 2026, 05:30 PM',
    },
    {
      'id': '6387', 'customer': 'Shree Sai Motors',
      'area': 'Neemuch', 'status': 'cancelled',
      'pickedBy': 'Pankaj Pawara (EMP001)', 'verifiedBy': '-',
      'totalItems': 18, 'pickedItems': 0, 'notFound': 18,
      'date': '17 Jun 2026, 11:20 AM',
    },
  ];

  List<Map<String, dynamic>> get _filtered {
    final tab = _tabController.index;
    return _orders.where((o) {
      if (tab == 1 && o['status'] != 'in_progress') return false;
      if (tab == 2 && o['status'] != 'completed') return false;
      final q = _searchController.text.toLowerCase();
      if (q.isNotEmpty) {
        return o['customer'].toString().toLowerCase().contains(q) ||
            o['id'].toString().contains(q);
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
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
                          icon: const Icon(Icons.menu_rounded, color: Colors.white),
                          onPressed: () {},
                        ),
                        const Expanded(
                          child: Text('History',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.search_rounded, color: Colors.white),
                          onPressed: () {},
                        ),
                        IconButton(
                          icon: const Icon(Icons.filter_list_rounded, color: Colors.white),
                          onPressed: () {},
                        ),
                      ],
                    ),
                  ),
                  // Tabs
                  TabBar(
                    controller: _tabController,
                    labelColor: Colors.white,
                    unselectedLabelColor: Colors.white60,
                    indicatorColor: Colors.white,
                    indicatorWeight: 3,
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

          // Search bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search by memo no, customer, picker...',
                hintStyle:
                    const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF9CA3AF), size: 20),
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Sort row
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Row(
              children: [
                _SortChip(
                  prefix: 'Sort By:',
                  value: _sortBy,
                  icon: Icons.sort_rounded,
                  onTap: () {},
                ),
                const SizedBox(width: 8),
                _SortChip(
                  prefix: '',
                  value: _sortDir,
                  icon: Icons.arrow_downward_rounded,
                  onTap: () {
                    setState(() => _sortDir =
                        _sortDir == 'Descending' ? 'Ascending' : 'Descending');
                  },
                ),
              ],
            ),
          ),

          // Order list
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: _filtered.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final order = _filtered[i];
                return _OrderCard(
                  order: order,
                  onTap: () => context.push('/order/${order['id']}'),
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
  final Map<String, dynamic> order;
  final VoidCallback onTap;
  const _OrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String;
    final notFound = order['notFound'] as int;

    final (statusLabel, statusColor, statusBg) = switch (status) {
      'completed' => ('Completed', AppColors.success, AppColors.successLight),
      'in_progress' => ('In Progress', AppColors.warning, AppColors.warningLight),
      'cancelled' => ('Cancelled', AppColors.danger, AppColors.dangerLight),
      _ => ('Unknown', AppColors.textSecondary, AppColors.border),
    };

    final avatarColor = switch (status) {
      'completed' => AppColors.success,
      'in_progress' => AppColors.warning,
      'cancelled' => AppColors.danger,
      _ => AppColors.textSecondary,
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
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
                    (order['customer'] as String)[0],
                    style: TextStyle(
                        color: avatarColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    order['customer'] as String,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text('#${order['id']}',
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
                Text(order['area'] as String,
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

            // Picked by + Verified by
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Picked By',
                          style: TextStyle(
                              fontSize: 10, color: Color(0xFF9CA3AF))),
                      Text(order['pickedBy'] as String,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF374151)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Verified By',
                          style: TextStyle(
                              fontSize: 10, color: Color(0xFF9CA3AF))),
                      Text(order['verifiedBy'] as String,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF374151)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Items row
            Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 14, color: Color(0xFF9CA3AF)),
                const SizedBox(width: 4),
                Text(
                  '${order['pickedItems']}/${order['totalItems']} Items',
                  style: const TextStyle(
                      fontSize: 12, color: Color(0xFF6B7280)),
                ),
                if (notFound > 0) ...[  
                  const SizedBox(width: 8),
                  Text(
                    '$notFound Not Found',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600),
                  ),
                ],
                const Spacer(),
                Text(order['date'] as String,
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
