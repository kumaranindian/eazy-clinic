import 'package:api_contracts/api_contracts.dart';
import 'package:dio/dio.dart';

import '../domain/auth_api.dart';
import '../domain/auth_repository.dart';

/// Backend client built on Dio. The bearer token is read from the identity
/// provider for every request (the SDK refreshes it when needed) and is never
/// stored here. Nothing in this class logs requests, headers or bodies.
class DioAuthApi implements AuthApi {
  DioAuthApi({required String baseUrl, required AuthRepository auth, Dio? dio})
    : _auth = auth,
      _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: '$baseUrl$apiV1Prefix',
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              headers: {'accept': 'application/json'},
              validateStatus: (_) => true, // errors are parsed from envelope
            ),
          );

  final AuthRepository _auth;
  final Dio _dio;

  @override
  Future<AuthSessionDto> getSession() async =>
      AuthSessionDto.fromJson(await _send('GET', '/auth/session'));

  @override
  Future<AuthSessionDto> provision() async =>
      AuthSessionDto.fromJson(await _send('POST', '/auth/provision'));

  @override
  Future<void> logout({bool allDevices = false}) async {
    await _send('POST', '/auth/logout', body: {'allDevices': allDevices});
  }

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Object? body,
  }) async {
    var response = await _request(method, path, body, forceRefresh: false);
    // An expired token is refreshed once by the SDK and retried.
    if (_errorCode(response) == ApiErrorCode.tokenExpired) {
      response = await _request(method, path, body, forceRefresh: true);
    }
    final status = response.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      final data = (response.data as Map?)?['data'];
      return (data as Map?)?.cast<String, Object?>() ?? const {};
    }
    throw AuthApiException(code: _errorCode(response));
  }

  Future<Response<Object?>> _request(
    String method,
    String path,
    Object? body, {
    required bool forceRefresh,
  }) async {
    final token = await _auth.idToken(forceRefresh: forceRefresh);
    if (token == null) {
      throw const AuthApiException(code: ApiErrorCode.unauthenticated);
    }
    try {
      return await _dio.request<Object?>(
        path,
        data: body,
        options: Options(
          method: method,
          headers: {'authorization': 'Bearer $token'},
        ),
      );
    } on DioException {
      throw const AuthApiException(isNetwork: true);
    }
  }

  ApiErrorCode? _errorCode(Response<Object?> r) {
    final data = r.data;
    if (data is! Map) return null;
    final error = data['error'];
    return error is Map
        ? ApiErrorCode.tryParse(error['code'] as String?)
        : null;
  }
}
