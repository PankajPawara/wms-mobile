import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
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

part 'app_router.g.dart';

@riverpod
GoRouter appRouter(AppRouterRef ref) {
  final authState = ref.watch(authNotifierProvider);

  return GoRouter(
    initialLocation: '/login',
    redirect: (context, state) {
      final status = authState.status;
      final path = state.matchedLocation;
      final isLoginPage = path == '/login';
      final isChangePassword = path == '/change-password';

      if (status == AuthStatus.unknown) return null;
      if (status == AuthStatus.unauthenticated && !isLoginPage) return '/login';
      if (status == AuthStatus.authenticated) {
        if (authState.isFirstLogin && !isChangePassword) return '/change-password';
        if (isLoginPage) return '/home';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/change-password', builder: (_, __) => const ChangePasswordScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
      GoRoute(path: '/scan-to-find', builder: (_, __) => const ScanToFindScreen()),
      GoRoute(path: '/memo-capture', builder: (_, __) => const MemoCaptureScreen()),
      GoRoute(
        path: '/ocr-review',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          return OcrReviewScreen(extractedItems: extra?['items'] ?? []);
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
      GoRoute(path: '/checking-list', builder: (_, __) => const CheckingListScreen()),
      GoRoute(path: '/history', builder: (_, __) => const HistoryScreen()),
      GoRoute(
        path: '/order/:orderId',
        builder: (context, state) => OrderDetailsScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(
        path: '/order/:orderId/items',
        builder: (context, state) => PickedItemsScreen(orderId: state.pathParameters['orderId']!),
      ),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
    ],
  );
}
