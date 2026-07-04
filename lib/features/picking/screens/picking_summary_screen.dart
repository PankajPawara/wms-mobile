import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../shared/widgets/app_button.dart';
import '../repositories/order_repository.dart';

class PickingSummaryScreen extends ConsumerWidget {
  final String orderId;
  const PickingSummaryScreen({super.key, required this.orderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Picking Summary', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primary,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppDimensions.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(AppDimensions.lg),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
              ),
              child: const Column(
                children: [
                  Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 56),
                  SizedBox(height: AppDimensions.sm),
                  Text(
                    'Picking Complete!',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.success),
                  ),
                  Text(
                    'All items have been picked.',
                    style: TextStyle(color: AppColors.success),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppDimensions.xl),
            AppButton(
              label: 'Submit for Checking',
              icon: Icons.verified_outlined,
              onPressed: () async {
                final id = int.tryParse(orderId);
                if (id != null) {
                  await ref.read(orderRepositoryProvider).updateOrderStatus(id, 'pending_checking');
                }
                if (context.mounted) {
                  context.go('/home');
                }
              },
            ),
            const SizedBox(height: AppDimensions.sm),
            AppButton(
              label: 'Back to Home',
              variant: AppButtonVariant.outline,
              onPressed: () => context.go('/home'),
            ),
          ],
        ),
      ),
    );
  }
}
