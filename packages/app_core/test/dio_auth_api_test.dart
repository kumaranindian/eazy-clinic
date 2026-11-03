import 'dart:convert';

import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fakes.dart';

ResponseBody json(int status, Object body) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: {
    Headers.contentTypeHeader: [Headers.jsonContentType],
  },
);

void main() {
  final okSession = {
    'data': {
      'uid': 'u1',
      'accountStatus': 'active',
      'emailVerified': true,
      'accessGranted': true,
      'memberships': <Object>[],
    },
  };

  DioAuthApi build(ScriptedAdapter adapter, FakeAuthRepository repo) {
    final dio = Dio(
      BaseOptions(baseUrl: 'http://x/api/v1', validateStatus: (_) => true),
    )..httpClientAdapter = adapter;
    return DioAuthApi(baseUrl: 'http://x', auth: repo, dio: dio);
  }

  test('sends the bearer token and parses the session', () async {
    final adapter = ScriptedAdapter((_) => json(200, okSession));
    final api = build(adapter, FakeAuthRepository(initial: testUser));
    final session = await api.getSession();
    expect(session.accessGranted, isTrue);
    expect(
      adapter.requests.single.headers['authorization'],
      'Bearer test-token',
    );
    expect(adapter.requests.single.path, '/auth/session');
  });

  test('never sends identity or role in the request body', () async {
    final adapter = ScriptedAdapter((_) => json(200, okSession));
    final api = build(adapter, FakeAuthRepository(initial: testUser));
    await api.provision();
    expect(adapter.requests.single.data, isNull);
  });

  test('no token → unauthenticated without calling the network', () async {
    final adapter = ScriptedAdapter((_) => json(200, okSession));
    final api = build(adapter, FakeAuthRepository());
    await expectLater(
      api.getSession(),
      throwsA(
        isA<AuthApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.unauthenticated,
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test('maps error envelopes to error codes', () async {
    final adapter = ScriptedAdapter(
      (_) => json(403, {
        'error': {'code': 'account_suspended', 'message': 'x'},
      }),
    );
    final api = build(adapter, FakeAuthRepository(initial: testUser));
    await expectLater(
      api.getSession(),
      throwsA(
        isA<AuthApiException>().having(
          (e) => e.code,
          'code',
          ApiErrorCode.accountSuspended,
        ),
      ),
    );
  });

  test('retries once after token_expired with a refreshed token', () async {
    var calls = 0;
    final adapter = ScriptedAdapter(
      (_) => ++calls == 1
          ? json(401, {
              'error': {'code': 'token_expired', 'message': 'x'},
            })
          : json(200, okSession),
    );
    final api = build(adapter, FakeAuthRepository(initial: testUser));
    expect((await api.getSession()).uid, 'u1');
    expect(adapter.requests, hasLength(2));
  });

  test('transport failure is reported as a network error', () async {
    final adapter = ScriptedAdapter(
      (o) => throw DioException(
        requestOptions: o,
        type: DioExceptionType.connectionError,
      ),
    );
    final api = build(adapter, FakeAuthRepository(initial: testUser));
    await expectLater(
      api.getSession(),
      throwsA(isA<AuthApiException>().having((e) => e.isNetwork, 'net', true)),
    );
  });

  test('logout sends allDevices', () async {
    final adapter = ScriptedAdapter(
      (_) => json(200, {'data': <String, Object?>{}}),
    );
    final api = build(adapter, FakeAuthRepository(initial: testUser));
    await api.logout(allDevices: true);
    expect(adapter.requests.single.data, <String, Object?>{'allDevices': true});
  });

  group('Firebase error mapping', () {
    test('credential errors share one message (no account enumeration)', () {
      for (final code in [
        'wrong-password',
        'user-not-found',
        'invalid-credential',
      ]) {
        expect(
          FirebaseAuthRepository.mapCode(code),
          AuthFailureCode.invalidCredentials,
        );
      }
    });
    test('other codes', () {
      expect(
        FirebaseAuthRepository.mapCode('user-disabled'),
        AuthFailureCode.accountDisabled,
      );
      expect(
        FirebaseAuthRepository.mapCode('too-many-requests'),
        AuthFailureCode.tooManyRequests,
      );
      expect(
        FirebaseAuthRepository.mapCode('network-request-failed'),
        AuthFailureCode.network,
      );
      expect(
        FirebaseAuthRepository.mapCode('email-already-in-use'),
        AuthFailureCode.emailInUse,
      );
      expect(
        FirebaseAuthRepository.mapCode('weak-password'),
        AuthFailureCode.weakPassword,
      );
      expect(
        FirebaseAuthRepository.mapCode('invalid-email'),
        AuthFailureCode.invalidEmail,
      );
      expect(FirebaseAuthRepository.mapCode('???'), AuthFailureCode.unknown);
    });
  });
}
