import 'dart:async';
import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';
import 'package:dio/dio.dart';

/// Test double for the identity provider. Lives in `test/` only.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AuthUser? initial}) : _current = initial;

  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? _current;

  AuthFailure? signInFailure;
  AuthFailure? registerFailure;
  AuthFailure? resetFailure;
  AuthFailure? signOutFailure;
  final List<String> resetRequests = [];
  int signOutCalls = 0;
  int verificationEmails = 0;
  AuthUser? reloadResult;

  void emit(AuthUser? user) {
    _current = user;
    _controller.add(user);
  }

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    if (signInFailure != null) throw signInFailure!;
    final user = AuthUser(uid: 'u1', email: email, emailVerified: true);
    emit(user);
    return user;
  }

  @override
  Future<AuthUser> register({
    required String displayName,
    required String email,
    required String password,
  }) async {
    if (registerFailure != null) throw registerFailure!;
    final user = AuthUser(
      uid: 'u2',
      email: email,
      displayName: displayName,
      emailVerified: false,
    );
    emit(user);
    return user;
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    if (resetFailure != null) throw resetFailure!;
    resetRequests.add(email);
  }

  @override
  Future<void> sendEmailVerification() async => verificationEmails++;

  @override
  Future<AuthUser?> reload() async => reloadResult ?? _current;

  @override
  Future<void> signOut() async {
    signOutCalls++;
    if (signOutFailure != null) throw signOutFailure!;
    emit(null);
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async =>
      _current == null ? null : 'test-token';
}

class FakeAuthApi implements AuthApi {
  /// Responses are consumed in order; the last one repeats.
  List<Object> sessions = [];
  Object? provisionResult;
  int sessionCalls = 0;
  int provisionCalls = 0;
  int logoutCalls = 0;
  bool logoutAllDevices = false;
  bool logoutFails = false;

  Future<AuthSessionDto> _next(List<Object> queue, int index) async {
    final item = queue[index < queue.length ? index : queue.length - 1];
    if (item is Exception) throw item;
    return item as AuthSessionDto;
  }

  @override
  Future<AuthSessionDto> getSession() => _next(sessions, sessionCalls++);

  @override
  Future<AuthSessionDto> provision() {
    provisionCalls++;
    final r = provisionResult;
    if (r is Exception) throw r;
    return Future.value(r as AuthSessionDto? ?? activeSession());
  }

  @override
  Future<void> logout({bool allDevices = false}) async {
    logoutCalls++;
    logoutAllDevices = allDevices;
    if (logoutFails) throw const AuthApiException(isNetwork: true);
  }
}

AuthSessionDto activeSession({
  PlatformRole? platformRole,
  List<MembershipSummaryDto> memberships = const [],
  AccountStatus status = AccountStatus.active,
}) => AuthSessionDto(
  uid: 'u1',
  accountStatus: status,
  emailVerified: status != AccountStatus.pending,
  accessGranted: status.canAccessProtectedFeatures,
  platformRole: platformRole,
  memberships: memberships,
);

const AuthUser testUser = AuthUser(
  uid: 'u1',
  email: 'user@example.test',
  displayName: 'Test User',
  emailVerified: true,
);

/// Dio adapter returning scripted responses.
class ScriptedAdapter implements HttpClientAdapter {
  ScriptedAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}
