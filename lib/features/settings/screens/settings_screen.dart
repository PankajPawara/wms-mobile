import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:drift/drift.dart' hide Column;

import '../../../core/constants/app_colors.dart';
import '../../../features/auth/providers/auth_provider.dart';
import '../repositories/inventory_repository.dart';
import '../../picking/repositories/order_repository.dart';
import '../../../core/database/app_database.dart';
import '../../../core/providers/theme_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authNotifierProvider).user;
    final name = user?.name ?? 'User';
    final role = user?.role == 'admin' ? 'Admin' : 'Picker';
    final empId = user?.employeeId ?? 'EMP000';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/home');
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
        body: Builder(builder: (context) {
          final colorScheme = Theme.of(context).colorScheme;
          return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Profile card ────────────────────────────────────────────────
            GestureDetector(
              onTap: () => context.push('/profile'),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: AppColors.success,
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
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface)),
                          Text('$role • $empId',
                              style: TextStyle(
                                  fontSize: 12, color: colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        Icon(Icons.chevron_right_rounded,
                            color: colorScheme.outline),
                        const SizedBox(height: 4),
                        Text('View Profile',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.primary)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── DATA MANAGEMENT ─────────────────────────────────────────────
            _SectionLabel('DATA MANAGEMENT'),
            const SizedBox(height: 8),
            _SettingsGroup(items: [
              _SettingsItem(
                  icon: Icons.file_upload_outlined,
                  iconColor: const Color(0xFF16A34A),
                  title: 'Import Excel File',
                  subtitle: 'Import or update inventory data',
                  onTap: () => _showImportExcelDialog(context)),
              _SettingsItem(
                  icon: Icons.storage_rounded,
                  iconColor: const Color(0xFF16A34A),
                  title: 'Database & Sync Diagnostics',
                  subtitle: 'Sync logs and SQLite catalog viewer',
                  onTap: () => context.push('/diagnostics')),
              _SettingsItem(
                  icon: Icons.refresh_rounded,
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
                  iconColor: const Color(0xFF1D4ED8),
                  title: 'Scanner Test (Diagnostic)',
                  subtitle: 'Test camera, barcode, OCR etc.',
                  onTap: () => context.push('/scan-to-find')),
              _SettingsItem(
                  icon: Icons.history_rounded,
                  iconColor: const Color(0xFFD97706),
                  title: 'History',
                  subtitle: 'View all orders and status',
                  onTap: () => context.push('/history')),
              _SettingsItem(
                  icon: Icons.auto_awesome_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: 'AI Vision Sandbox',
                  subtitle: 'Test Gemini image extraction',
                  onTap: () => context.push('/ai-vision-test'),
                  showDivider: false),
            ]),
            const SizedBox(height: 16),

            // ── SCANNER SETTINGS ─────────────────────────────────────────────
            _SectionLabel('SCANNER SETTINGS'),
            const SizedBox(height: 8),
            _SettingsGroup(items: [
              _SettingsItem(
                  icon: Icons.document_scanner_rounded,
                  iconColor: const Color(0xFF1D4ED8),
                  title: 'Scanner Settings',
                  subtitle: 'Configure scanner preferences',
                  onTap: () => _showScannerSettingsSheet(context, ref)),
              _SettingsItem(
                  icon: Icons.text_fields_rounded,
                  iconColor: const Color(0xFF16A34A),
                  title: 'OCR Settings',
                  subtitle: 'Configure OCR preferences',
                  onTap: () => _showOcrSettingsSheet(context, ref),
                  showDivider: false),
            ]),
            const SizedBox(height: 16),

            // ── THEME SETTINGS ───────────────────────────────────────────────
            _SectionLabel('THEME SETTINGS'),
            const SizedBox(height: 8),
            _SettingsGroup(items: [
              _SettingsItem(
                  icon: Icons.palette_outlined,
                  iconColor: AppColors.primary,
                  title: 'App Theme',
                  subtitle: 'Switch between Light and Dark mode',
                  onTap: () => _showThemeSettingsSheet(context, ref),
                  showDivider: false),
            ]),
            const SizedBox(height: 16),

            // ── OTHERS ──────────────────────────────────────────────────────
            _SectionLabel('OTHERS'),
            const SizedBox(height: 8),
            _SettingsGroup(items: [
              _SettingsItem(
                  icon: Icons.help_outline_rounded,
                  iconColor: const Color(0xFF1D4ED8),
                  title: 'Help & Support',
                  subtitle: 'User guide and contact admin',
                  onTap: () => _showHelpSupportDialog(context)),
              _SettingsItem(
                  icon: Icons.info_outline_rounded,
                  iconColor: const Color(0xFF6B7280),
                  title: 'About',
                  subtitle: 'App information and version',
                  onTap: () => _showAboutDialog(context),
                  showDivider: false),
            ]),
            const SizedBox(height: 20),
            _SettingsGroup(items: [
              _SettingsItem(
                icon: Icons.logout_rounded,
                iconColor: const Color(0xFFDC2626),
                title: 'Log Out',
                subtitle: 'Sign out of your account on this device',
                onTap: () async {
                  await ref.read(authNotifierProvider.notifier).logout();
                  if (context.mounted) context.go('/login');
                },
                showDivider: false,
              ),
            ]),
            const SizedBox(height: 84),
          ],
        );
        }),
      ),
    );
  }

  void _showImportExcelDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Excel Master Import'),
        content: const Text(
          'To import a new Excel inventory master file:\n\n'
          '1. Log in to the WMS Web Admin Dashboard on your computer.\n'
          '2. Click "Import Excel File" and select your spreadsheet.\n'
          '3. Once complete, tap "Re-import Database" under Settings in this app to pull all new data onto your phone.\n\n'
          'This ensures catalog consistency across all scanner terminals.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Understood', style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showHelpSupportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Help & Support'),
        content: const Text(
          'For technical issues, database resets, or password unlocks:\n\n'
          '• Contact System Administrator:\n  admin@warehouse-wms.com\n\n'
          '• Hot-key guide:\n'
          '  Swipe left on order items to mark missing. Tap items in history to view coordinates.',
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Close', style: TextStyle(color: AppColors.textSecondary)),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('About WMS'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Warehouse Management System (WMS)', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Version: 1.0.0'),
            const Text('Build: v2.0-stable'),
            const Text('Engine: SQLite (drift) + MongoDB Sync'),
            const SizedBox(height: 12),
            Text('© 2026 Honda Spare Parts Warehouse', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('OK'),
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

  void _showScannerSettingsSheet(BuildContext context, WidgetRef ref) {
    final db = ref.read(appDatabaseProvider);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return FutureBuilder<List<AppSetting>>(
              future: db.select(db.appSettings).get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final settings = snapshot.data!;
                final vibrate = settings.firstWhere((e) => e.key == 'vibrate_on_scan', orElse: () => const AppSetting(key: 'vibrate_on_scan', value: 'true')).value == 'true';
                final beep = settings.firstWhere((e) => e.key == 'beep_on_scan', orElse: () => const AppSetting(key: 'beep_on_scan', value: 'true')).value == 'true';

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Scanner Preferences',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Vibrate on successful scan'),
                        value: vibrate,
                        activeColor: AppColors.primary,
                        onChanged: (val) async {
                          await db.into(db.appSettings).insertOnConflictUpdate(
                            AppSettingsCompanion(
                              key: const Value('vibrate_on_scan'),
                              value: Value(val.toString()),
                            ),
                          );
                          setModalState(() {});
                        },
                      ),
                      SwitchListTile(
                        title: const Text('Beep on successful scan'),
                        value: beep,
                        activeColor: AppColors.primary,
                        onChanged: (val) async {
                          await db.into(db.appSettings).insertOnConflictUpdate(
                            AppSettingsCompanion(
                              key: const Value('beep_on_scan'),
                              value: Value(val.toString()),
                            ),
                          );
                          setModalState(() {});
                        },
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _showThemeSettingsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final currentMode = ref.watch(themeModeProvider);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'App Theme Preference',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              RadioListTile<ThemeMode>(
                title: const Text('Light Mode'),
                subtitle: const Text('Sleek high contrast light layout'),
                value: ThemeMode.light,
                groupValue: currentMode,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  if (val != null) {
                    ref.read(themeModeProvider.notifier).setThemeMode(val);
                    Navigator.pop(context);
                  }
                },
              ),
              RadioListTile<ThemeMode>(
                title: const Text('Dark Mode'),
                subtitle: const Text('Eye-friendly slate theme layout'),
                value: ThemeMode.dark,
                groupValue: currentMode,
                activeColor: AppColors.primary,
                onChanged: (val) {
                  if (val != null) {
                    ref.read(themeModeProvider.notifier).setThemeMode(val);
                    Navigator.pop(context);
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  void _showOcrSettingsSheet(BuildContext context, WidgetRef ref) {
    final db = ref.read(appDatabaseProvider);
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return FutureBuilder<List<AppSetting>>(
              future: db.select(db.appSettings).get(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final settings = snapshot.data!;
                final autoTrigger = settings.firstWhere((e) => e.key == 'ocr_auto_trigger', orElse: () => const AppSetting(key: 'ocr_auto_trigger', value: 'false')).value == 'true';
                final defaultQty = int.tryParse(settings.firstWhere((e) => e.key == 'ocr_default_qty', orElse: () => const AppSetting(key: 'ocr_default_qty', value: '1')).value) ?? 1;

                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'OCR Settings',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 16),
                      SwitchListTile(
                        title: const Text('Auto-process image after selection'),
                        value: autoTrigger,
                        activeColor: AppColors.primary,
                        onChanged: (val) async {
                          await db.into(db.appSettings).insertOnConflictUpdate(
                            AppSettingsCompanion(
                              key: const Value('ocr_auto_trigger'),
                              value: Value(val.toString()),
                            ),
                          );
                          setModalState(() {});
                        },
                      ),
                      ListTile(
                        title: const Text('Default Extracted Quantity'),
                        trailing: DropdownButton<int>(
                          value: defaultQty,
                          items: [1, 2, 5, 10, 20].map((int value) {
                            return DropdownMenuItem<int>(
                              value: value,
                              child: Text(value.toString()),
                            );
                          }).toList(),
                          onChanged: (val) async {
                            if (val != null) {
                              await db.into(db.appSettings).insertOnConflictUpdate(
                                AppSettingsCompanion(
                                  key: const Value('ocr_default_qty'),
                                  value: Value(val.toString()),
                                ),
                              );
                              setModalState(() {});
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
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
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.outline,
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
        color: Theme.of(context).colorScheme.surface,
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
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  const _SettingsItem({
    required this.icon,
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
                    color: iconColor.withValues(alpha: 0.12),
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
                            style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Theme.of(context).colorScheme.onSurface)),
                        Text(subtitle,
                            style: TextStyle(
                                fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      color: Theme.of(context).colorScheme.outline, size: 20),
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
