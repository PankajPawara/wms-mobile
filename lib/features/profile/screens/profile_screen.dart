import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../features/auth/providers/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final user = ref.watch(authNotifierProvider).user;
    final name = user?.name ?? 'User';
    final role = user?.role == 'admin' ? 'Administrator' : 'Warehouse Assistant';
    final empId = user?.employeeId ?? 'EMP000';
    final email = user?.email ?? 'Not Provided';
    final mobile = user?.mobile ?? 'Not Provided';
    final status = user?.status ?? 'active';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/settings');
      },
      child: Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        appBar: AppBar(
          title: Text('My Profile', style: TextStyle(color: colorScheme.onSurface)),
          backgroundColor: colorScheme.surface,
          foregroundColor: colorScheme.onSurface,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => context.go('/settings'),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(AppDimensions.md),
          children: [
            // Avatar Header card
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              ),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_rounded, color: Colors.white, size: 48),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    name,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                    ),
                    child: Text(
                      role,
                      style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Profile info card
            _buildSectionLabel(context, 'ACCOUNT INFORMATION'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              ),
              child: Column(
                children: [
                  _buildProfileItem(context, Icons.badge_outlined, 'Employee ID', empId),
                  Divider(height: 1, indent: 56, color: colorScheme.outlineVariant),
                  _buildProfileItem(context, Icons.email_outlined, 'Email Address', email),
                  Divider(height: 1, indent: 56, color: colorScheme.outlineVariant),
                  _buildProfileItem(context, Icons.phone_outlined, 'Mobile Number', mobile),
                  Divider(height: 1, indent: 56, color: colorScheme.outlineVariant),
                  _buildProfileItem(
                    context,
                    Icons.check_circle_outline_rounded,
                    'Account Status',
                    status.toUpperCase(),
                    valueColor: status.toLowerCase() == 'active' ? AppColors.success : AppColors.danger,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Security card
            _buildSectionLabel(context, 'SECURITY'),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              ),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.lock_reset_outlined, color: AppColors.warning, size: 20),
                ),
                title: Text('Change Account Password', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: colorScheme.onSurface)),
                subtitle: Text('Update login security key', style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11)),
                trailing: Icon(Icons.chevron_right_rounded, color: colorScheme.outline),
                onTap: () => context.push('/change-password'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.outline,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _buildProfileItem(BuildContext context, IconData icon, String label, String value, {Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11)),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? colorScheme.onSurface,
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
