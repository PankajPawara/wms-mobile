import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'secure_storage.g.dart';

class SecureStorage {
  static const _tokenKey = 'wms_auth_token';
  static const _userIdKey = 'wms_user_id';
  static const _employeeIdKey = 'wms_employee_id';
  static const _roleKey = 'wms_role';
  static const _userNameKey = 'wms_user_name';

  final FlutterSecureStorage _storage;

  SecureStorage()
      : _storage = const FlutterSecureStorage(
          aOptions: AndroidOptions(encryptedSharedPreferences: true),
        );

  Future<void> saveToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  Future<String?> getToken() => _storage.read(key: _tokenKey);

  Future<void> saveUser({
    required String id,
    required String employeeId,
    required String name,
    required String role,
  }) async {
    await Future.wait([
      _storage.write(key: _userIdKey, value: id),
      _storage.write(key: _employeeIdKey, value: employeeId),
      _storage.write(key: _userNameKey, value: name),
      _storage.write(key: _roleKey, value: role),
    ]);
  }

  Future<Map<String, String?>> getUser() async {
    final results = await Future.wait([
      _storage.read(key: _userIdKey),
      _storage.read(key: _employeeIdKey),
      _storage.read(key: _userNameKey),
      _storage.read(key: _roleKey),
    ]);
    return {
      'id': results[0],
      'employeeId': results[1],
      'name': results[2],
      'role': results[3],
    };
  }

  Future<void> clearAll() => _storage.deleteAll();

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }
}

@riverpod
SecureStorage secureStorage(Ref ref) => SecureStorage();
