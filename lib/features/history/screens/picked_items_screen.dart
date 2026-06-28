import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';

class PickedItemsScreen extends StatelessWidget {
  final String orderId;
  const PickedItemsScreen({super.key, required this.orderId});

  static const _pickedItems = [
    {'partNo': '22201-KON-DU2', 'desc': 'Disk Clutch Friction', 'qty': 10, 'price': '₹176.00', 'found': true},
    {'partNo': '22355-KON-DU2', 'desc': 'Plate Clutch Pressure', 'qty': 5, 'price': '₹218.00', 'found': true},
    {'partNo': '17211-KSP-900', 'desc': 'Spring Clutch', 'qty': 1, 'price': '₹98.00', 'found': true},
  ];

  static const _notFoundItems = [
    {'partNo': '17920-KOV-B81', 'desc': 'Carburetor Assy', 'qty': 2, 'price': '₹165.00', 'found': false},
    {'partNo': '18381-KRJ-900', 'desc': 'Filter Comp Air Cleaner', 'qty': 1, 'price': '₹120.00', 'found': false},
  ];

  @override
  Widget build(BuildContext context) {
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
                      label: 'Memo No.', value: '#$orderId'),
                ),
                Expanded(
                  child: _HeaderField(
                      label: 'Customer',
                      value: 'Tirupati Auto Spare Parts'),
                ),
              ],
            ),
          ),

          // Items list
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                // Picked items section
                _SectionHeader(
                    label: 'Picked Items (${_pickedItems.length})',
                    color: AppColors.success),
                const SizedBox(height: 8),
                ..._pickedItems.map((item) => _ItemCard(item: item)),
                const SizedBox(height: 16),

                // Not found section
                _SectionHeader(
                    label: 'Not Found Items (${_notFoundItems.length})',
                    color: AppColors.danger),
                const SizedBox(height: 8),
                ..._notFoundItems.map((item) => _ItemCard(item: item)),
                const SizedBox(height: 16),

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
                              value: '20',
                              color: Colors.black)),
                      const VerticalDivider(width: 1),
                      Expanded(
                          child: _FooterStat(
                              label: 'Picked Items',
                              value: '${_pickedItems.length}',
                              color: AppColors.success)),
                      const VerticalDivider(width: 1),
                      Expanded(
                          child: _FooterStat(
                              label: 'Not Found',
                              value: '${_notFoundItems.length}',
                              color: AppColors.danger)),
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
            style: const TextStyle(
                fontSize: 10, color: Color(0xFF9CA3AF))),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: Color(0xFF111827))),
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
    return Text(label,
        style: TextStyle(
            fontSize: 14, fontWeight: FontWeight.bold, color: color));
  }
}

class _ItemCard extends StatelessWidget {
  final Map<String, Object> item;
  const _ItemCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final found = item['found'] as bool;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            found ? Icons.check_circle_rounded : Icons.cancel_rounded,
            color: found ? AppColors.success : AppColors.danger,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item['partNo'] as String,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827))),
                Text(item['desc'] as String,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF6B7280))),
                Text('Qty: ${item['qty']}   Price: ${item['price']}',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded,
              color: Color(0xFF9CA3AF), size: 18),
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
                fontSize: 22, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: Color(0xFF6B7280))),
      ],
    );
  }
}
