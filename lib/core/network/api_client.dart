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

  ApiClient(this._storage)
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
          throw ApiException(
            message: data['message'] ?? AppStrings.error,
            errorCode: data['error_code'] ?? 'INTERNAL_ERROR',
            statusCode: error.response!.statusCode ?? 500,
            errors: List<String>.from(data['errors'] ?? []),
          );
        }
        throw ApiException(
          message: 'No internet connection. Working offline.',
          errorCode: 'NETWORK_ERROR',
          statusCode: 0,
        );
      },
    );
  }

  Future<Map<String, dynamic>> get(String path,
      {Map<String, dynamic>? queryParams}) async {
    final response = await _dio.get(path, queryParameters: queryParams);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> post(String path, {dynamic data}) async {
    final response = await _dio.post(path, data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> patch(String path, {dynamic data}) async {
    final response = await _dio.patch(path, data: data);
    return response.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> put(String path, {dynamic data}) async {
    final response = await _dio.put(path, data: data);
    return response.data as Map<String, dynamic>;
  }
}

@riverpod
ApiClient apiClient(Ref ref) {
  final storage = ref.watch(secureStorageProvider);
  return ApiClient(storage);
}
