import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';
import '../../features/notifications/providers/notification_provider.dart';
import '../utils/notifications_helper.dart';

/// Canonical page-title map. Sub-pages not in the shell tabs
/// declare their title here; shell tabs also live here for the
/// notification-bell action in [MainLayout].
const _pageTitles = {
  '/home': 'WMS Dashboard',
  '/memo-capture': 'Capture Memo',
  '/scan-to-find': 'Scan to Find',
  '/checking-list': 'Checking List',
  '/settings': 'Settings',
  '/history': 'Orders',
  '/profile': 'My Profile',
  '/parts-master': 'Parts Master',
  '/red-label-scan': 'Red Label Scan',
  '/diagnostics': 'Database & Sync Diagnostics',
  '/settings/ocr-sandbox': 'OCR Sandbox Laboratory',
  '/settings/pipeline-sandbox': 'Pipeline Sandbox',
  '/ai-vision-test': 'AI Vision Sandbox',
};

/// Shell-tab routes that have a dedicated bottom-nav item.
const _shellTabs = [
  '/home',
  '/memo-capture',
  '/scan-to-find',
  '/checking-list',
  '/settings',
];

/// Returns the bottom-nav index for [path], or -1 if it is a sub-page.
int _tabIndexFor(String path) {
  for (int i = 0; i < _shellTabs.length; i++) {
    if (path.startsWith(_shellTabs[i])) return i;
  }
  return -1;
}

/// Resolves a human-readable page title for any route path.
String _titleFor(String path) {
  // Exact map look-up first
  if (_pageTitles.containsKey(path)) return _pageTitles[path]!;

  // Parameterised routes
  if (path.startsWith('/picking-summary/')) return 'Picking Summary';
  if (path.startsWith('/picking/')) return 'Picking';
  if (path.startsWith('/checking/')) return 'Checking';
  if (path.startsWith('/order/') && path.endsWith('/items')) return 'Picked Items';
  if (path.startsWith('/order/')) return 'Order Details';
  if (path.startsWith('/ocr-review')) return 'Review Pickup List';

  return 'WMS';
}

/// The global app shell. All routes inside the ShellRoute are
/// rendered here — both top-level tabs and contextual sub-pages.
class MainLayout extends ConsumerWidget {
  final Widget child;
  final String currentPath;

  const MainLayout({
    super.key,
    required this.child,
    required this.currentPath,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabIndex = _tabIndexFor(currentPath);
    final isShellTab = tabIndex != -1;
    final title = _titleFor(currentPath);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (!isShellTab) {
          // Sub-pages: go back
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
          return;
        }
        // Shell tab: only home shows exit dialog
        if (tabIndex == 0) {
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
          if (shouldExit == true) SystemNavigator.pop();
        } else {
          context.go('/home');
        }
      },
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          elevation: 6,
          shadowColor: Colors.black.withValues(alpha: 0.15),
          centerTitle: false,
          // Show back arrow on sub-pages; show nothing on home; show home icon on other tabs
          leading: !isShellTab
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/home');
                    }
                  },
                )
              : tabIndex == 0
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                      onPressed: () => context.go('/home'),
                    ),
          title: Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          actions: [
            // Orders history icon (shown on all pages except history itself)
            if (!currentPath.startsWith('/history'))
              IconButton(
                icon: const Icon(Icons.inventory_2_outlined, color: Colors.white, size: 24),
                onPressed: () => context.push('/history'),
                tooltip: 'Orders',
              ),
            const NotificationBell(),
          ],
        ),
        body: child,
        bottomNavigationBar: AppBottomNav(currentIndex: tabIndex < 0 ? 0 : tabIndex),
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
              tooltip: 'Notifications',
            ),
            if (unreadCount > 0)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );
      },
      orElse: () => IconButton(
        icon: const Icon(Icons.notifications_none_rounded, color: Colors.white, size: 24),
        onPressed: () => showNotificationsDialog(context, ref),
        tooltip: 'Notifications',
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
        color: AppColors.primary,
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
