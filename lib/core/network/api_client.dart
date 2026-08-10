import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../constants/app_strings.dart';
import '../storage/secure_storage.dart';
import 'api_endpoints.dart';

part 'api_client.g.dart';

class ApiException implements Exception {
  final String message;
  final String errorCode;
  final int statusCode;
  final List<String> errors;

  ApiException({
    required this.message,
    required this.errorCode,
    required this.statusCode,
    this.errors = const [],
  });

  @override
  String toString() => message;
}

class ApiClient {
  final Dio _dio;
  final SecureStorage _storage;

  final void Function()? onUnauthenticated;

  ApiClient(this._storage, {this.onUnauthenticated})
      : _dio = Dio(
          BaseOptions(
            baseUrl: ApiEndpoints.baseUrl,
            connectTimeout: const Duration(seconds: 15),
            receiveTimeout: const Duration(seconds: 30),
            headers: {'Content-Type': 'application/json'},
          ),
        ) {
    _dio.interceptors.add(_authInterceptor());
    _dio.interceptors.add(_errorInterceptor());
  }

  InterceptorsWrapper _authInterceptor() {
    return InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await _storage.getToken();
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
    );
  }

  InterceptorsWrapper _errorInterceptor() {
    return InterceptorsWrapper(
      onError: (error, handler) {
        if (error.response != null) {
          final data = error.response!.data;
          if (error.response!.statusCode == 401 && onUnauthenticated != null) {
            onUnauthenticated!();
          }

          handler.reject(error.copyWith(
            error: ApiException(
              message: data is Map<String, dynamic> ? (data['message'] ?? AppStrings.error) : 'Unauthorized or Invalid Token',
              errorCode: data is Map<String, dynamic> ? (data['error_code'] ?? 'INTERNAL_ERROR') : 'UNAUTHORIZED',
              statusCode: error.response!.statusCode ?? 500,
              errors: data is Map<String, dynamic> ? List<String>.from(data['errors'] ?? []) : [],
            ),
          ));
          return;
        }
        handler.reject(error.copyWith(
          error: ApiException(
            message: 'No internet connection. Working offline.',
            errorCode: 'NETWORK_ERROR',
            statusCode: 0,
          ),
        ));
      },
    );
  }

  Future<Map<String, dynamic>> get(String path,
      {Map<String, dynamic>? queryParams}) async {
    try {
      final response = await _dio.get(path, queryParameters: queryParams);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.error is ApiException) throw e.error!;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> post(String path, {dynamic data}) async {
    try {
      final response = await _dio.post(path, data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.error is ApiException) throw e.error!;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> patch(String path, {dynamic data}) async {
    try {
      final response = await _dio.patch(path, data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.error is ApiException) throw e.error!;
      rethrow;
    }
  }

  Future<Map<String, dynamic>> put(String path, {dynamic data}) async {
    try {
      final response = await _dio.put(path, data: data);
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      if (e.error is ApiException) throw e.error!;
      rethrow;
    }
  }
}

final unauthenticatedEventProvider = StateProvider<bool>((ref) => false);

@riverpod
ApiClient apiClient(Ref ref) {
  final storage = ref.watch(secureStorageProvider);
  return ApiClient(storage, onUnauthenticated: () {
    ref.read(unauthenticatedEventProvider.notifier).state = true;
  });
}
