import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../models/user_model.dart';
import '../repositories/auth_repository.dart';

part 'auth_provider.g.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthState {
  final AuthStatus status;
  final UserModel? user;
  final bool isFirstLogin;
  final String? error;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.user,
    this.isFirstLogin = false,
    this.error,
    this.isLoading = false,
  });

  AuthState copyWith({
    AuthStatus? status,
    UserModel? user,
    bool? isFirstLogin,
    String? error,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      isFirstLogin: isFirstLogin ?? this.isFirstLogin,
      error: error,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  AuthState build() {
    _checkAuthStatus();
    return const AuthState();
  }

  Future<void> _checkAuthStatus() async {
    final storage = ref.read(secureStorageProvider);
    final isLoggedIn = await storage.isLoggedIn();
    if (isLoggedIn) {
      final cachedUser = await storage.getUser();
      if (cachedUser['id'] != null) {
        final user = UserModel(
          id: cachedUser['id']!,
          employeeId: cachedUser['employeeId'] ?? '',
          name: cachedUser['name'] ?? '',
          role: cachedUser['role'] ?? 'employee',
          email: '',
          mobile: '',
          status: 'active',
          isFirstLogin: false,
        );
        state = AuthState(
          status: AuthStatus.authenticated,
          user: user,
          isFirstLogin: false,
        );

        _updateUserFromServerQuietly();
        return;
      }
    }
    state = const AuthState(status: AuthStatus.unauthenticated);
  }

  Future<void> _updateUserFromServerQuietly() async {
    try {
      final user = await ref.read(authRepositoryProvider).getMe();
      state = AuthState(
        status: AuthStatus.authenticated,
        user: user,
        isFirstLogin: user.isFirstLogin,
      );
    } catch (_) {
      // Keep existing cached state on connection error
    }
  }

  Future<bool> login(String employeeId, String password) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final result = await ref
          .read(authRepositoryProvider)
          .login(employeeId, password);
      state = AuthState(
        status: AuthStatus.authenticated,
        user: result.user,
        isFirstLogin: result.isFirstLogin,
        isLoading: false,
      );
      return true;
    } catch (e) {
      String errorMessage = e.toString();
      if (e is ApiException) {
        errorMessage = e.message;
      } else if (e.runtimeType.toString() == 'DioException') {
        dynamic dioError = e;
        if (dioError.error is ApiException) {
          errorMessage = (dioError.error as ApiException).message;
        } else if (dioError.response?.data != null && dioError.response?.data['message'] != null) {
          errorMessage = dioError.response!.data['message'];
        }
      }
      state = state.copyWith(isLoading: false, error: errorMessage);
      return false;
    }
  }

  Future<bool> changePassword(
      String currentPassword, String newPassword) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await ref
          .read(authRepositoryProvider)
          .changePassword(currentPassword, newPassword);
      state = state.copyWith(isLoading: false, isFirstLogin: false);
      return true;
    } catch (e) {
      String errorMessage = e.toString();
      if (e is ApiException) {
        errorMessage = e.message;
      } else if (e.runtimeType.toString() == 'DioException') {
        dynamic dioError = e;
        if (dioError.error is ApiException) {
          errorMessage = (dioError.error as ApiException).message;
        } else if (dioError.response?.data != null && dioError.response?.data['message'] != null) {
          errorMessage = dioError.response!.data['message'];
        }
      }
      state = state.copyWith(isLoading: false, error: errorMessage);
      return false;
    }
  }

  Future<void> logout() async {
    await ref.read(authRepositoryProvider).logout();
    state = const AuthState(status: AuthStatus.unauthenticated);
  }
}
