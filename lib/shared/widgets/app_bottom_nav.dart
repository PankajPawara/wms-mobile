import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../features/notifications/providers/notification_provider.dart';
import '../utils/notifications_helper.dart';

class MainLayout extends ConsumerWidget {
  final Widget child;
  final int currentIndex;

  const MainLayout({super.key, required this.child, required this.currentIndex});

  static const _titles = [
    'WMS Dashboard',
    'Capture Memo',
    'Scan to Find',
    'Checking List',
    'Settings',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (currentIndex == 0) {
          final shouldExit = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Exit App'),
              content: const Text('Are you sure you want to exit the WMS application?'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: Text('Exit', style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
          if (shouldExit == true) {
            SystemNavigator.pop();
          }
        } else {
          context.go('/home');
        }
      },
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          _titles[currentIndex],
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: AppColors.primary,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: 0.15),
        centerTitle: false,
        leading: currentIndex == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                onPressed: () => context.go('/home'),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 24),
            onPressed: () => context.push('/history'),
            tooltip: 'Orders',
          ),
          const NotificationBell(),
        ],
      ),
      body: child, // Screens will have their own safeareas if needed
      bottomNavigationBar: AppBottomNav(currentIndex: currentIndex),
    ),
  );
}
}

class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifState = ref.watch(notificationNotifierProvider);

    return notifState.maybeWhen(
      data: (items) {
        final unreadCount = items.where((i) => !i.isRead).length;
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 24),
              onPressed: () => showNotificationsDialog(context, ref),
            ),
            if (unreadCount > 0)
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 8,
                    minHeight: 8,
                  ),
                ),
              ),
          ],
        );
      },
      orElse: () => IconButton(
        icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 24),
        onPressed: () => showNotificationsDialog(context, ref),
      ),
    );
  }
}

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  const AppBottomNav({super.key, required this.currentIndex});

  static const _routes = [
    '/home',
    '/memo-capture',
    '/scan-to-find',
    '/checking-list',
    '/settings',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: AppColors.primary, // Purple background
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            spreadRadius: 4,
            offset: const Offset(0, -6),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 24,
            spreadRadius: 8,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _NavItem(
              icon: Icons.home_rounded,
              label: 'Home',
              active: currentIndex == 0,
              onTap: () => context.go(_routes[0]),
            ),
            _NavItem(
              icon: Icons.list_alt_rounded,
              label: 'Pickup List',
              active: currentIndex == 1,
              onTap: () => context.go(_routes[1]),
            ),
            _NavItem(
              icon: Icons.qr_code_scanner_rounded,
              label: 'Scan to Find',
              active: currentIndex == 2,
              onTap: () => context.go(_routes[2]),
            ),
            _NavItem(
              icon: Icons.verified_rounded,
              label: 'Checking',
              active: currentIndex == 3,
              onTap: () => context.go(_routes[3]),
            ),
            _NavItem(
              icon: Icons.settings_rounded,
              label: 'Settings',
              active: currentIndex == 4,
              onTap: () => context.go(_routes[4]),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavItem({required this.icon, required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 6),
            Icon(
              icon,
              color: active ? Colors.white : Colors.white60,
              size: 22,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: active ? FontWeight.bold : FontWeight.w400,
                color: active ? Colors.white : Colors.white60,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // White underline indicator for active tab
            Container(
              height: 2,
              width: 20,
              color: active ? Colors.white : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}
