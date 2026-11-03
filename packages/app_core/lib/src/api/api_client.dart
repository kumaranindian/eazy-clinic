import 'dart:convert';
import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/domain/auth_repository.dart';

/// A failed API call, already reduced to what the UI may show.
class ApiFailure implements Exception {
  const ApiFailure({
    this.code,
    this.message = 'Something went wrong. Please try again.',
    this.issues = const [],
    this.isNetwork = false,
  });

  final ApiErrorCode? code;
  final String message;
  final List<FieldIssue> issues;
  final bool isNetwork;

  /// The session is gone; the caller should sign the user out.
  bool get isSessionInvalid =>
      code == ApiErrorCode.sessionRevoked ||
      code == ApiErrorCode.tokenExpired ||
      code == ApiErrorCode.unauthenticated;

  String get displayMessage => isNetwork
      ? 'Cannot reach the server. Check your connection and try again.'
      : message;

  @override
  String toString() =>
      'ApiFailure(${code?.wireName ?? (isNetwork ? 'network' : 'unknown')})';
}

class ApiResult {
  const ApiResult(this.data, [this.page]);
  final Object? data;
  final PageMeta? page;

  Map<String, Object?> get map => (data as Map).cast<String, Object?>();
  List<Map<String, Object?>> get list =>
      (data as List).map((e) => (e as Map).cast<String, Object?>()).toList();
}

/// Authenticated JSON client for `/api/v1`. The bearer token is read from the
/// identity provider per request (the SDK refreshes it); an expired token is
/// refreshed once and retried. Requests, headers and bodies are never logged.
class ApiClient {
  ApiClient({
    required String baseUrl,
    required AuthRepository auth,
    this.onSessionInvalid,
    Dio? dio,
  }) : _auth = auth,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: '$baseUrl$apiV1Prefix',
               connectTimeout: const Duration(seconds: 15),
               receiveTimeout: const Duration(seconds: 30),
               headers: {'accept': 'application/json'},
               validateStatus: (_) => true,
             ),
           );

  final AuthRepository _auth;
  final Dio _dio;

  /// Called when the backend says the session is dead.
  final void Function()? onSessionInvalid;

  Future<ApiResult> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
  }) => _send('GET', path, query: query, headers: headers);

  Future<ApiResult> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<ApiResult> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  Future<ApiResult> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<ApiResult> delete(String path) => _send('DELETE', path);

  /// Binary download (e.g. the clinic logo). Errors use the normal envelope.
  Future<Uint8List> getBytes(String path) async {
    final token = await _auth.idToken();
    if (token == null) {
      throw const ApiFailure(
        code: ApiErrorCode.unauthenticated,
        message: 'Please sign in again.',
      );
    }
    final Response<List<int>> r;
    try {
      r = await _dio.get<List<int>>(
        path,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'authorization': 'Bearer $token'},
        ),
      );
    } on DioException {
      throw const ApiFailure(isNetwork: true);
    }
    final status = r.statusCode ?? 0;
    if (status >= 200 && status < 300) {
      return Uint8List.fromList(r.data ?? const []);
    }
    Map<String, Object?>? json;
    try {
      json = (jsonDecode(utf8.decode(r.data ?? const [])) as Map)
          .cast<String, Object?>();
    } on Object {
      json = null;
    }
    final failure = _failure(json);
    if (failure.isSessionInvalid) onSessionInvalid?.call();
    throw failure;
  }

  Future<ApiResult> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    var r = await _request(method, path, body, query, headers, false);
    if (_code(r) == ApiErrorCode.tokenExpired) {
      r = await _request(method, path, body, query, headers, true);
    }
    final status = r.statusCode ?? 0;
    final json = r.data is Map
        ? (r.data! as Map).cast<String, Object?>()
        : null;
    if (status >= 200 && status < 300 && json != null) {
      final meta = (json['meta'] as Map?)?['page'];
      return ApiResult(
        json['data'],
        meta is Map ? PageMeta.fromJson(meta.cast<String, Object?>()) : null,
      );
    }
    final failure = _failure(json);
    if (failure.isSessionInvalid) onSessionInvalid?.call();
    throw failure;
  }

  Future<Response<Object?>> _request(
    String method,
    String path,
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    bool forceRefresh,
  ) async {
    final token = await _auth.idToken(forceRefresh: forceRefresh);
    if (token == null) {
      throw const ApiFailure(
        code: ApiErrorCode.unauthenticated,
        message: 'Please sign in again.',
      );
    }
    try {
      return await _dio.request<Object?>(
        path,
        data: body,
        queryParameters: query,
        options: Options(
          method: method,
          headers: {'authorization': 'Bearer $token', ...?headers},
        ),
      );
    } on DioException {
      throw const ApiFailure(isNetwork: true);
    }
  }

  ApiErrorCode? _code(Response<Object?> r) {
    final data = r.data;
    final error = data is Map ? data['error'] : null;
    return error is Map
        ? ApiErrorCode.tryParse(error['code'] as String?)
        : null;
  }

  ApiFailure _failure(Map<String, Object?>? json) {
    final error = (json?['error'] as Map?)?.cast<String, Object?>();
    if (error == null) return const ApiFailure();
    return ApiFailure(
      code: ApiErrorCode.tryParse(error['code'] as String?),
      message:
          error['message'] as String? ??
          'Something went wrong. Please try again.',
      issues: ((error['issues'] as List?) ?? const [])
          .whereType<Map<Object?, Object?>>()
          .map((i) => FieldIssue.fromJson(i.cast<String, Object?>()))
          .toList(),
    );
  }
}

/// Overridden in each app's `main()`.
final apiClientProvider = Provider<ApiClient>(
  (ref) => throw StateError('apiClientProvider must be overridden.'),
);
