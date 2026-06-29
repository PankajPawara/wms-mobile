import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_colors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../repositories/inventory_repository.dart';
import '../../picking/repositories/order_repository.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).user;
    final name = user?.name ?? 'User';
    final role = user?.role == 'admin' ? 'Admin' : 'Picker';
    final empId = user?.employeeId ?? 'EMP000';

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF3F4F6),
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: const Text(
          'Settings',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Color(0xFF111827),
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: () async {
                await ref.read(authNotifierProvider.notifier).logout();
                if (context.mounted) context.go('/login');
              },
              icon: const Icon(Icons.logout_rounded, size: 18,
                  color: Color(0xFF16A34A)),
              label: const Text('Logout',
                  style: TextStyle(
                      color: Color(0xFF16A34A), fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Profile card ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(
                    color: Color(0xFF16A34A),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person_rounded,
                      color: Colors.white, size: 30),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name,
                          style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF111827))),
                      Text('$role • $empId',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
                Column(
                  children: [
                    const Icon(Icons.chevron_right_rounded,
                        color: Color(0xFF9CA3AF)),
                    const SizedBox(height: 4),
                    Text('View Profile',
                        style: TextStyle(
                            fontSize: 11, color: AppColors.primary)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── DATA MANAGEMENT ─────────────────────────────────────────────
          _SectionLabel('DATA MANAGEMENT'),
          const SizedBox(height: 8),
          _SettingsGroup(items: [
            _SettingsItem(
                icon: Icons.file_upload_outlined,
                iconBg: const Color(0xFFDCFCE7),
                iconColor: const Color(0xFF16A34A),
                title: 'Import Excel File',
                subtitle: 'Import or update inventory data',
                onTap: () {}),
            _SettingsItem(
                icon: Icons.storage_rounded,
                iconBg: const Color(0xFFDCFCE7),
                iconColor: const Color(0xFF16A34A),
                title: 'Database Summary',
                subtitle: 'View database information',
                onTap: () => _showDatabaseSummary(context, ref)),
            _SettingsItem(
                icon: Icons.refresh_rounded,
                iconBg: const Color(0xFFDCFCE7),
                iconColor: const Color(0xFF16A34A),
                title: 'Re-import Database',
                subtitle: 'Replace existing data',
                onTap: () => _runManualSync(context, ref),
                showDivider: false),
          ]),
          const SizedBox(height: 16),

          // ── TOOLS ───────────────────────────────────────────────────────
          _SectionLabel('TOOLS'),
          const SizedBox(height: 8),
          _SettingsGroup(items: [
            _SettingsItem(
                icon: Icons.qr_code_scanner_rounded,
                iconBg: const Color(0xFFDBEAFE),
                iconColor: const Color(0xFF1D4ED8),
                title: 'Scanner Test (Diagnostic)',
                subtitle: 'Test camera, barcode, OCR etc.',
                onTap: () {}),
            _SettingsItem(
                icon: Icons.history_rounded,
                iconBg: const Color(0xFFFEF3C7),
                iconColor: const Color(0xFFD97706),
                title: 'History',
                subtitle: 'View all orders and status',
                onTap: () => context.push('/history'),
                showDivider: false),
          ]),
          const SizedBox(height: 16),

          // ── SCANNER SETTINGS ─────────────────────────────────────────────
          _SectionLabel('SCANNER SETTINGS'),
          const SizedBox(height: 8),
          _SettingsGroup(items: [
            _SettingsItem(
                icon: Icons.document_scanner_rounded,
                iconBg: const Color(0xFFDBEAFE),
                iconColor: const Color(0xFF1D4ED8),
                title: 'Scanner Settings',
                subtitle: 'Configure scanner preferences',
                onTap: () {}),
            _SettingsItem(
                icon: Icons.text_fields_rounded,
                iconBg: const Color(0xFFDCFCE7),
                iconColor: const Color(0xFF16A34A),
                title: 'OCR Settings',
                subtitle: 'Configure OCR preferences',
                onTap: () {},
                showDivider: false),
          ]),
          const SizedBox(height: 16),

          // ── OTHERS ──────────────────────────────────────────────────────
          _SectionLabel('OTHERS'),
          const SizedBox(height: 8),
          _SettingsGroup(items: [
            _SettingsItem(
                icon: Icons.help_outline_rounded,
                iconBg: const Color(0xFFDBEAFE),
                iconColor: const Color(0xFF1D4ED8),
                title: 'Help & Support',
                subtitle: 'User guide and contact admin',
                onTap: () {}),
            _SettingsItem(
                icon: Icons.info_outline_rounded,
                iconBg: const Color(0xFFF3F4F6),
                iconColor: const Color(0xFF6B7280),
                title: 'About',
                subtitle: 'App information and version',
                onTap: () {},
                showDivider: false),
          ]),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _showDatabaseSummary(BuildContext context, WidgetRef ref) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final summary = await ref.read(inventoryRepositoryProvider).getDatabaseSummary();
    if (!context.mounted) return;
    context.pop(); // dismiss loader

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Database Summary'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Inventory Records: ${summary['inventory']}'),
            const SizedBox(height: 6),
            Text('Sync Queue Items: ${summary['sync_queue']}'),
            const SizedBox(height: 6),
            Text('Orders Cache Count: ${summary['orders']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _runManualSync(BuildContext context, WidgetRef ref) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Synchronising data with WMS Server...'), duration: Duration(seconds: 1)),
    );

    final updated = await ref.read(inventoryRepositoryProvider).syncInventory(force: true);
    await ref.read(orderRepositoryProvider).syncOrdersFromServer();

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(updated ? 'Sync complete. Inventory updated!' : 'Sync complete. Local database up to date!')),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel(this.label);

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Color(0xFF9CA3AF),
        letterSpacing: 0.8,
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  final List<_SettingsItem> items;
  const _SettingsGroup({required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: items,
      ),
    );
  }
}

class _SettingsItem extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  const _SettingsItem({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: iconColor, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF111827))),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6B7280))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFF9CA3AF), size: 20),
              ],
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, indent: 66, endIndent: 14),
      ],
    );
  }
}
