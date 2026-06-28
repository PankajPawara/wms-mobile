import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_strings.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/status_badge.dart';

class CheckingScreen extends ConsumerStatefulWidget {
  final String orderId;
  const CheckingScreen({super.key, required this.orderId});

  @override
  ConsumerState<CheckingScreen> createState() => _CheckingScreenState();
}

class _CheckingScreenState extends ConsumerState<CheckingScreen> {
  // Dummy items — replace with real provider
  final List<Map<String, dynamic>> _items = [
    {
      'part_no': '22201-KON-DU2',
      'description': 'DISK CLUTCH FRICTION',
      'location': 'A2-15',
      'required_qty': 10,
      'picked_qty': 10,
      'checked_qty': 0,
      'unit_price': 250.0,
      'status': 'pending',
    },
  ];

  bool get _allChecked =>
      _items.every((i) => i['status'] == 'checked');

  void _markChecked(int index, int qty) {
    setState(() {
      _items[index]['checked_qty'] = qty;
      _items[index]['status'] = qty > 0 ? 'checked' : 'missing';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Checking — ${widget.orderId}')),
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
                final picked = item['picked_qty'] as int;
                final checked = item['checked_qty'] as int;
                return Container(
                  padding: const EdgeInsets.all(AppDimensions.md),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusMd),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item['part_no'] as String,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                          ),
                          StatusBadge(
                              status: item['status'] as String),
                        ],
                      ),
                      Text(item['description'] as String,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 13)),
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
            color: Colors.white,
            padding: const EdgeInsets.all(AppDimensions.md),
            child: AppButton(
              label: AppStrings.completeChecking,
              icon: Icons.verified_rounded,
              onPressed: _allChecked ? () => context.go('/home') : null,
            ),
          ),
        ],
      ),
    );
  }
}
