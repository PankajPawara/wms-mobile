import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_endpoints.dart';
import '../../../core/storage/secure_storage.dart';
import '../models/user_model.dart';

part 'auth_repository.g.dart';

class AuthRepository {
  final ApiClient _api;
  final SecureStorage _storage;
  final AppDatabase _db;

  AuthRepository(this._api, this._storage, this._db);

  Future<({UserModel user, bool isFirstLogin})> login(
      String employeeId, String password) async {
    final res = await _api.post(ApiEndpoints.login, data: {
      'employee_id': employeeId,
      'password': password,
    });
    final data = res['data'] as Map<String, dynamic>;
    final user = UserModel.fromJson(data['user'] as Map<String, dynamic>);
    final token = data['token'] as String;
    final isFirstLogin = data['is_first_login'] as bool? ?? false;

    await _storage.saveToken(token);
    await _storage.saveUser(
      id: user.id,
      employeeId: user.employeeId,
      name: user.name,
      role: user.role,
    );

    // Save user in SQLite
    await _db.delete(_db.currentUsers).go();
    await _db.into(_db.currentUsers).insert(CurrentUsersCompanion.insert(
      mongoId: user.id,
      employeeId: user.employeeId,
      name: user.name,
      mobile: user.mobile,
      email: user.email,
      role: user.role,
      token: token,
      tokenExpiry: DateTime.now().add(const Duration(hours: 8)).toIso8601String(),
    ));

    return (user: user, isFirstLogin: isFirstLogin);
  }

  Future<void> changePassword(
      String currentPassword, String newPassword) async {
    await _api.post(ApiEndpoints.changePassword, data: {
      'current_password': currentPassword,
      'new_password': newPassword,
      'confirm_password': newPassword,
    });
  }

  Future<UserModel> getMe() async {
    final res = await _api.get(ApiEndpoints.me);
    return UserModel.fromJson(
        res['data']['user'] as Map<String, dynamic>);
  }

  Future<void> logout() async {
    await _storage.clearAll();
    await _db.delete(_db.currentUsers).go();
    await _db.delete(_db.orders).go();
    await _db.delete(_db.orderItems).go();
    await _db.delete(_db.syncQueues).go();
  }
}

@riverpod
AuthRepository authRepository(AuthRepositoryRef ref) {
  return AuthRepository(
    ref.watch(apiClientProvider),
    ref.watch(secureStorageProvider),
    ref.watch(appDatabaseProvider),
  );
}
