import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/constants/app_colors.dart';

class AppBottomNav extends StatelessWidget {
  final int currentIndex;
  const AppBottomNav({super.key, required this.currentIndex});

  static const _routes = [
    '/home',
    '/scan-to-find',
    '/memo-capture',
    '/checking-list',
    '/history',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, -2)),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _NavItem(icon: Icons.home_rounded, label: 'Home', active: currentIndex == 0,
                  onTap: () => context.go(_routes[0])),
              _NavItem(icon: Icons.qr_code_scanner_rounded, label: 'Scan To Find', active: currentIndex == 1,
                  onTap: () => context.go(_routes[1])),
              _NavItem(icon: Icons.list_alt_rounded, label: 'Pickup List', active: currentIndex == 2,
                  onTap: () => context.go(_routes[2])),
              _NavItem(icon: Icons.verified_rounded, label: 'Verification', active: currentIndex == 3,
                  onTap: () => context.go(_routes[3])),
              _NavItem(icon: Icons.history_rounded, label: 'History', active: currentIndex == 4,
                  onTap: () => context.go(_routes[4])),
            ],
          ),
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
            Icon(icon, color: active ? AppColors.primary : AppColors.textSecondary, size: 22),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? AppColors.primary : AppColors.textSecondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
