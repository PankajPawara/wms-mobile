import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/splash_screen.dart';
import '../../features/home/screens/home_screen.dart';
import '../../features/scan_to_find/screens/scan_to_find_screen.dart';
import '../../features/memo_ocr/screens/memo_capture_screen.dart';
import '../../features/memo_ocr/screens/ocr_review_screen.dart';
import '../../features/picking/screens/picking_screen.dart';
import '../../features/picking/screens/picking_summary_screen.dart';
import '../../features/checking/screens/checking_screen.dart';
import '../../features/checking/screens/checking_list_screen.dart';
import '../../features/history/screens/history_screen.dart';
import '../../features/history/screens/order_details_screen.dart';
import '../../features/history/screens/picked_items_screen.dart';
import '../../features/settings/screens/settings_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/settings/screens/diagnostics_screen.dart';
import '../../features/scan_to_find/screens/ai_vision_test_screen.dart';
import '../../shared/widgets/app_bottom_nav.dart';

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(AppRouterRef ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      final status = authState.status;
      final path = state.matchedLocation;
      final isLoginPage = path == '/login';
      final isChangePassword = path == '/change-password';
      final isSplashPage = path == '/';

      if (status == AuthStatus.unknown) return null;
      if (status == AuthStatus.unauthenticated) {
        if (!isLoginPage) return '/login';
      }
      if (status == AuthStatus.authenticated) {
        if (authState.isFirstLogin && !isChangePassword) return '/change-password';
        if (isLoginPage || isSplashPage) return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/change-password', builder: (_, __) => const ChangePasswordScreen()),
      
      ShellRoute(
        builder: (context, state, child) {
          int index = 0;
          final path = state.matchedLocation;
          if (path.startsWith('/memo-capture')) index = 1;
          else if (path.startsWith('/scan-to-find')) index = 2;
          else if (path.startsWith('/checking-list')) index = 3;
          else if (path.startsWith('/settings')) index = 4;
          return MainLayout(currentIndex: index, child: child);
        },
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/scan-to-find', builder: (_, __) => const ScanToFindScreen()),
          GoRoute(path: '/memo-capture', builder: (_, __) => const MemoCaptureScreen()),
          GoRoute(path: '/checking-list', builder: (_, __) => const CheckingListScreen()),
          GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        ],
      ),

      GoRoute(
        path: '/ocr-review',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return OcrReviewScreen(
            extractedItems: extra?['items'] ?? [],
            customerName: extra?['customerName'] as String?,
            customerLocation: extra?['customerLocation'] as String?,
            memoNumber: extra?['memoNumber'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/picking/:orderId',
        builder: (context, state) => PickingScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: '/picking-summary/:orderId',
        builder: (context, state) => PickingSummaryScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: '/checking/:orderId',
        builder: (context, state) => CheckingScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
      GoRoute(
        path: '/order/:orderId',
        builder: (context, state) => OrderDetailsScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: '/order/:orderId/items',
        builder: (context, state) => PickedItemsScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(path: '/diagnostics', builder: (_, __) => const DiagnosticsScreen()),
      GoRoute(path: '/ai-vision-test', builder: (_, __) => const AIVisionTestScreen()),
    ],
  );
}
