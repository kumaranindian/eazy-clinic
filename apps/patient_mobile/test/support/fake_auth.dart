import 'dart:async';

import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:common_models/common_models.dart';

/// Test doubles for the identity provider and backend (tests only).
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({this.signedIn = false});

  bool signedIn;
  final _controller = StreamController<AuthUser?>.broadcast();

  static const AuthUser user = AuthUser(
    uid: 'u1',
    email: 'user@example.test',
    displayName: 'Test User',
    emailVerified: true,
  );

  @override
  Stream<AuthUser?> authStateChanges() async* {
    yield signedIn ? user : null;
    yield* _controller.stream;
  }

  @override
  Future<AuthUser> signIn({required String email, required String password}) =>
      throw UnimplementedError();

  @override
  Future<AuthUser> register({
    required String displayName,
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> sendEmailVerification() async {}

  @override
  Future<AuthUser?> reload() async => signedIn ? user : null;

  @override
  Future<void> signOut() async {
    signedIn = false;
    _controller.add(null);
  }

  @override
  Future<String?> idToken({bool forceRefresh = false}) async => 't';
}

class FakeAuthApi implements AuthApi {
  FakeAuthApi(this.session);

  final AuthSessionDto session;

  @override
  Future<AuthSessionDto> getSession() async => session;

  @override
  Future<AuthSessionDto> provision() async => session;

  @override
  Future<void> logout({bool allDevices = false}) async {}
}

AuthSessionDto sessionWith({
  PlatformRole? platformRole,
  List<MembershipSummaryDto> memberships = const [],
}) => AuthSessionDto(
  uid: 'u1',
  accountStatus: AccountStatus.active,
  emailVerified: true,
  accessGranted: true,
  platformRole: platformRole,
  memberships: memberships,
);
