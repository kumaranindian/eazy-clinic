import 'package:backend/features/auth/data/firebase_auth_admin.dart';
import 'package:common_models/common_models.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:test/test.dart';

import '../../support/auth_fixtures.dart';

void main() {
  late AuthHarness h;
  setUp(() {
    h = AuthHarness()..seedUser();
  });

  group('Authorization header', () {
    test('missing header → 401', () async {
      final r = await h.call('GET', '/auth/me');
      expect(r.statusCode, 401);
      expect(await errorCode(r), 'unauthenticated');
    });

    for (final bad in [
      'Basic abc',
      'Bearer',
      'Bearer ',
      'bearer-token',
      'Bearer a b',
      'Token abc.def.ghi',
    ]) {
      test('malformed header "$bad" → 401', () async {
        final r = await h.call('GET', '/auth/me', authorization: bad);
        expect(r.statusCode, 401);
      });
    }

    test('garbage bearer token → 401 without detail', () async {
      final r = await h.call('GET', '/auth/me', token: 'not.a.jwt');
      expect(r.statusCode, 401);
      final body = await r.readAsString();
      expect(body, isNot(contains('signature')));
      expect(body, isNot(contains('Exception')));
    });
  });

  group('token verification', () {
    test('valid token → 200', () async {
      final r = await h.call('GET', '/auth/me', token: h.keys.token());
      expect(r.statusCode, 200);
    });

    test('expired token → 401 token_expired', () async {
      final t = h.keys.token(
        expiresIn: const Duration(minutes: -10),
        issuedAgo: const Duration(hours: 2),
      );
      final r = await h.call('GET', '/auth/me', token: t);
      expect(r.statusCode, 401);
      expect(await errorCode(r), 'token_expired');
    });

    test('signed with a different key → 401', () async {
      final other = TestKeys.generate();
      final r = await h.call('GET', '/auth/me', token: other.token());
      expect(r.statusCode, 401);
    });

    test('unknown kid → 401', () async {
      final r = await h.call('GET', '/auth/me', token: h.keys.token(kid: 'x'));
      expect(r.statusCode, 401);
    });

    test('wrong audience (other Firebase project) → 401', () async {
      final r = await h.call(
        'GET',
        '/auth/me',
        token: h.keys.token(audience: 'other-project'),
      );
      expect(r.statusCode, 401);
    });

    test('wrong issuer → 401', () async {
      final r = await h.call(
        'GET',
        '/auth/me',
        token: h.keys.token(issuer: 'https://evil.example/'),
      );
      expect(r.statusCode, 401);
    });

    test('HS256 key-confusion token → 401', () async {
      final t = h.keys.token(
        signWith: SecretKey('anything'),
        algorithm: JWTAlgorithm.HS256,
      );
      final r = await h.call('GET', '/auth/me', token: t);
      expect(r.statusCode, 401);
    });

    test('alg=none token → 401', () async {
      // header {"alg":"none","kid":"test-key-1"}
      const t =
          'eyJhbGciOiJub25lIiwia2lkIjoidGVzdC1rZXktMSJ9.'
          'eyJzdWIiOiJ1c2VyLTEifQ.';
      final r = await h.call('GET', '/auth/me', token: t);
      expect(r.statusCode, 401);
    });

    test('anonymous Firebase identity → 401', () async {
      final r = await h.call(
        'GET',
        '/auth/me',
        token: h.keys.token(provider: 'anonymous'),
      );
      expect(r.statusCode, 401);
    });

    test('tampered payload → 401', () async {
      final parts = h.keys.token().split('.');
      // Swap in the payload of another user while keeping the signature.
      final forged = h.keys.token(uid: 'admin-1').split('.')[1];
      final r = await h.call(
        'GET',
        '/auth/me',
        token: '${parts[0]}.$forged.${parts[2]}',
      );
      expect(r.statusCode, 401);
    });
  });

  group('revocation', () {
    test('token issued before validSince → 401 session_revoked', () async {
      h.admin.records['user-1'] = AuthUserRecord(
        disabled: false,
        validSince: DateTime.now().toUtc(),
      );
      final r = await h.call(
        'GET',
        '/auth/me',
        token: h.keys.token(authAgo: const Duration(minutes: 5)),
      );
      expect(r.statusCode, 401);
      expect(await errorCode(r), 'session_revoked');
    });

    test('revoke-sessions then old token is rejected', () async {
      final token = h.keys.token(authAgo: const Duration(minutes: 5));
      expect((await h.call('GET', '/auth/me', token: token)).statusCode, 200);
      final revoke = await h.call(
        'POST',
        '/auth/revoke-sessions',
        token: token,
      );
      expect(revoke.statusCode, 200);
      final after = await h.call('GET', '/auth/me', token: token);
      expect(after.statusCode, 401);
      expect(await errorCode(after), 'session_revoked');
    });

    test('logout with allDevices revokes sessions', () async {
      final token = h.keys.token(authAgo: const Duration(minutes: 5));
      final r = await h.call(
        'POST',
        '/auth/logout',
        token: token,
        body: {'allDevices': true},
      );
      expect(r.statusCode, 200);
      expect(h.admin.revoked, ['user-1']);
      expect((await h.call('GET', '/auth/me', token: token)).statusCode, 401);
    });

    test('logout without allDevices does not revoke', () async {
      final r = await h.call('POST', '/auth/logout', token: h.keys.token());
      expect(r.statusCode, 200);
      expect(h.admin.revoked, isEmpty);
    });

    test('Firebase user disabled → 403 account_disabled', () async {
      h.admin.records['user-1'] = const AuthUserRecord(disabled: true);
      final r = await h.call('GET', '/auth/me', token: h.keys.token());
      expect(r.statusCode, 403);
      expect(await errorCode(r), 'account_disabled');
    });

    test('deleted Firebase user → 401', () async {
      h.admin.records.remove('user-1');
      final r = await h.call('GET', '/auth/me', token: h.keys.token());
      expect(r.statusCode, 401);
    });

    test('revocation lookup failure fails closed → 503', () async {
      h.admin.failLookup = true;
      final r = await h.call('GET', '/auth/me', token: h.keys.token());
      expect(r.statusCode, 503);
    });

    test('revocation checks can be disabled (dev only)', () async {
      final lax = AuthHarness(checkRevoked: false)..seedUser();
      lax.admin.records['user-1'] = const AuthUserRecord(disabled: true);
      final r = await lax.call('GET', '/auth/me', token: lax.keys.token());
      expect(r.statusCode, 200);
    });
  });

  group('account status', () {
    Future<void> expectStatus(
      AccountStatus status,
      int http,
      String code,
    ) async {
      final harness = AuthHarness()..seedUser(status: status);
      final r = await harness.call(
        'GET',
        '/auth/me',
        token: harness.keys.token(emailVerified: false),
      );
      if (status == AccountStatus.pending) {
        expect(r.statusCode, 200, reason: '/auth/me allows pending');
        return;
      }
      expect(r.statusCode, http);
      expect(await errorCode(r), code);
    }

    test('suspended → 403', () async {
      await expectStatus(AccountStatus.suspended, 403, 'account_suspended');
    });
    test('disabled → 403', () async {
      await expectStatus(AccountStatus.disabled, 403, 'account_disabled');
    });
    test('pending can read /auth/me', () async {
      await expectStatus(AccountStatus.pending, 200, '');
    });

    test('missing platform user → 403 account_not_provisioned', () async {
      final r = await h.call(
        'GET',
        '/auth/me',
        token: h.keys.token(uid: 'ghost'),
      );
      // Firebase user must exist for revocation check.
      expect(r.statusCode, 401);
      h.admin.records['ghost'] = const AuthUserRecord(disabled: false);
      final r2 = await h.call(
        'GET',
        '/auth/me',
        token: h.keys.token(uid: 'ghost'),
      );
      expect(r2.statusCode, 403);
      expect(await errorCode(r2), 'account_not_provisioned');
    });

    test(
      'pending account is activated once token proves verified email',
      () async {
        h.seedUser(
          uid: 'p1',
          status: AccountStatus.pending,
          emailVerified: false,
        );
        final r = await h.call(
          'GET',
          '/auth/session',
          token: h.keys.token(uid: 'p1'),
        );
        expect(r.statusCode, 200);
        final data = (await jsonBody(r))['data']! as Map;
        expect(data['accountStatus'], 'active');
        expect(h.store.users['p1']!.accountStatus, AccountStatus.active);
      },
    );

    test('pending account stays pending while email unverified', () async {
      h.seedUser(
        uid: 'p2',
        status: AccountStatus.pending,
        emailVerified: false,
      );
      final r = await h.call(
        'GET',
        '/auth/session',
        token: h.keys.token(uid: 'p2', emailVerified: false),
      );
      final data = (await jsonBody(r))['data']! as Map;
      expect(data['accountStatus'], 'pending');
      expect(data['accessGranted'], false);
    });
  });
}
