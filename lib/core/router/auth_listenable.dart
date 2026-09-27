import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../features/auth/providers/auth_provider.dart';

/// A [ChangeNotifier] that listens to the Riverpod [AuthNotifier] and
/// notifies GoRouter's [refreshListenable] whenever auth state changes.
/// This avoids rebuilding the entire GoRouter instance on every auth change,
/// which was causing the login-page flicker.
class AuthListenable extends ChangeNotifier {
  AuthListenable(Ref ref) {
    // Only notify on status changes — not on loading/error sub-states
    ref.listen<AuthState>(
      authNotifierProvider,
      (previous, next) {
        if (previous?.status != next.status) {
          notifyListeners();
        }
      },
    );
    // Also react to mid-session 401 events
    ref.listen<bool>(
      unauthenticatedEventProvider,
      (previous, next) {
        if (next == true) notifyListeners();
      },
    );
  }
}
