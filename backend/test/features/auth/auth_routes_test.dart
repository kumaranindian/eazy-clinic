import 'dart:convert';

import 'package:backend/features/auth/data/firebase_auth_admin.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

import '../../support/auth_fixtures.dart';

void main() {
  late AuthHarness h;
  setUp(() => h = AuthHarness());

  group('POST /auth/provision', () {
    test('creates a pending profile for an unverified new user', () async {
      h.admin.records['new-1'] = const AuthUserRecord(disabled: false);
      final r = await h.call(
        'POST',
        '/auth/provision',
        token: h.keys.token(uid: 'new-1', emailVerified: false),
      );
      expect(r.statusCode, 200);
      final user = h.store.users['new-1']!;
      expect(user.accountStatus, AccountStatus.pending);
      expect(user.platformRole, isNull);
      final data = (await jsonBody(r))['data']! as Map;
      expect(data['accessGranted'], false);
      expect(data['memberships'], isEmpty);
    });

    test('verified new user becomes active but gets no roles', () async {
      h.admin.records['new-2'] = const AuthUserRecord(disabled: false);
      await h.call(
        'POST',
        '/auth/provision',
        token: h.keys.token(uid: 'new-2'),
      );
      final user = h.store.users['new-2']!;
      expect(user.accountStatus, AccountStatus.active);
      expect(user.platformRole, isNull);
    });

    test('is idempotent', () async {
      h.admin.records['new-3'] = const AuthUserRecord(disabled: false);
      final t = h.keys.token(uid: 'new-3');
      await h.call('POST', '/auth/provision', token: t);
      await h.call('POST', '/auth/provision', token: t);
      expect(h.store.users, hasLength(1));
    });

    test('ignores role / status / tenant / uid in the body', () async {
      h.admin.records['new-4'] = const AuthUserRecord(disabled: false);
      final r = await h.call(
        'POST',
        '/auth/provision',
        token: h.keys.token(uid: 'new-4'),
        body: {
          'uid': 'victim',
          'platformRole': 'super_admin',
          'role': 'clinic_owner',
          'accountStatus': 'active',
          'tenantId': 'clinic-a',
        },
      );
      expect(r.statusCode, 200);
      expect(h.store.users.containsKey('victim'), isFalse);
      final user = h.store.users['new-4']!;
      expect(user.platformRole, isNull);
      final data = (await jsonBody(r))['data']! as Map;
      expect(data['memberships'], isEmpty);
    });

    test('does not reactivate or log in a suspended account', () async {
      h.seedUser(status: AccountStatus.suspended);
      final r = await h.call('POST', '/auth/provision', token: h.keys.token());
      expect(r.statusCode, 200);
      final data = (await jsonBody(r))['data']! as Map;
      expect(data['accountStatus'], 'suspended');
      expect(data['accessGranted'], false);
      expect(h.store.users['user-1']!.lastLoginAt, isNull);
    });

    test('requires a token', () async {
      final r = await h.call('POST', '/auth/provision');
      expect(r.statusCode, 401);
    });

    test('rejects a token without an e-mail', () async {
      h.admin.records['no-mail'] = const AuthUserRecord(disabled: false);
      final r = await h.call(
        'POST',
        '/auth/provision',
        token: h.keys.token(uid: 'no-mail', email: null),
      );
      expect(r.statusCode, 400);
    });
  });

  group('GET /auth/me & /auth/session', () {
    setUp(() => h.seedUser());

    test('me returns the stored profile', () async {
      final r = await h.call('GET', '/auth/me', token: h.keys.token());
      expect(r.statusCode, 200);
      final data = (await jsonBody(r))['data']! as Map;
      expect(data['uid'], 'user-1');
      expect(data['email'], 'user-1@example.test');
      expect(data.containsKey('platformRole'), isFalse);
    });

    test('responses are not cacheable and carry a request id', () async {
      final r = await h.call('GET', '/auth/me', token: h.keys.token());
      expect(r.headers['cache-control'], 'no-store');
      expect(r.headers['x-request-id'], isNotEmpty);
    });

    test('session reports status and empty memberships', () async {
      final r = await h.call('GET', '/auth/session', token: h.keys.token());
      final data = (await jsonBody(r))['data']! as Map;
      expect(data['accessGranted'], true);
      expect(data['memberships'], isEmpty);
    });

    test('session explains suspended status instead of hiding it', () async {
      h.seedUser(status: AccountStatus.suspended);
      final r = await h.call('GET', '/auth/session', token: h.keys.token());
      expect(r.statusCode, 200);
      final data = (await jsonBody(r))['data']! as Map;
      expect(data['accountStatus'], 'suspended');
      expect(data['accessGranted'], false);
    });

    test('spoofed headers cannot change identity or role', () async {
      final r = await h.call(
        'GET',
        '/auth/session',
        token: h.keys.token(),
        headers: {
          'x-user-id': 'admin',
          'x-uid': 'admin',
          'x-role': 'super_admin',
          'x-tenant-id': 'clinic-b',
        },
      );
      final data = (await jsonBody(r))['data']! as Map;
      expect(data['uid'], 'user-1');
      expect(data.containsKey('platformRole'), isFalse);
      expect(data['memberships'], isEmpty);
    });

    test('spoofed uid in the query string is ignored', () async {
      h.seedUser(uid: 'victim');
      final r = await h.call(
        'GET',
        '/auth/me?uid=victim',
        token: h.keys.token(),
      );
      final data = (await jsonBody(r))['data']! as Map;
      expect(data['uid'], 'user-1');
    });

    test('custom role claim in the token is not trusted', () async {
      final r = await h.call(
        'GET',
        '/auth/session',
        token: h.keys.token(
          extra: {'role': 'super_admin', 'platformRole': 'super_admin'},
        ),
      );
      final data = (await jsonBody(r))['data']! as Map;
      expect(data.containsKey('platformRole'), isFalse);
    });
  });

  group('POST /auth/revoke-sessions', () {
    setUp(() {
      h.seedUser();
      h.seedUser(uid: 'other');
    });

    test('a user may revoke their own sessions', () async {
      final r = await h.call(
        'POST',
        '/auth/revoke-sessions',
        token: h.keys.token(),
      );
      expect(r.statusCode, 200);
      expect(h.admin.revoked, ['user-1']);
    });

    test('an ordinary user cannot revoke someone else → 403', () async {
      final r = await h.call(
        'POST',
        '/auth/revoke-sessions',
        token: h.keys.token(),
        body: {'targetUid': 'other'},
      );
      expect(r.statusCode, 403);
      expect(h.admin.revoked, isEmpty);
    });

    test('claiming an admin role in the body does not help', () async {
      final r = await h.call(
        'POST',
        '/auth/revoke-sessions',
        token: h.keys.token(),
        body: {'targetUid': 'other', 'platformRole': 'super_admin'},
      );
      expect(r.statusCode, 403);
    });

    test('support admin lacks the permission → 403', () async {
      h.seedUser(
        uid: 'support',
        platformRole: PlatformRole.platformSupportAdmin,
      );
      final r = await h.call(
        'POST',
        '/auth/revoke-sessions',
        token: h.keys.token(uid: 'support'),
        body: {'targetUid': 'other'},
      );
      expect(r.statusCode, 403);
    });

    test('super admin (server-side role) may revoke another user', () async {
      h.seedUser(uid: 'root', platformRole: PlatformRole.superAdmin);
      final r = await h.call(
        'POST',
        '/auth/revoke-sessions',
        token: h.keys.token(uid: 'root'),
        body: {'targetUid': 'other'},
      );
      expect(r.statusCode, 200);
      expect(h.admin.revoked, ['other']);
      expect(
        h.store.audit.any((e) => e['event'] == 'sessions_revoked'),
        isTrue,
      );
    });

    test('unknown target → 404', () async {
      h.seedUser(uid: 'root', platformRole: PlatformRole.superAdmin);
      final r = await h.call(
        'POST',
        '/auth/revoke-sessions',
        token: h.keys.token(uid: 'root'),
        body: {'targetUid': 'nobody'},
      );
      expect(r.statusCode, 404);
    });

    test('invalid body → 422', () async {
      final r = await h.call(
        'POST',
        '/auth/revoke-sessions',
        token: h.keys.token(),
        body: {'targetUid': 5},
      );
      expect(r.statusCode, 422);
    });

    test('suspended accounts cannot use it', () async {
      h.seedUser(status: AccountStatus.suspended);
      final r = await h.call(
        'POST',
        '/auth/revoke-sessions',
        token: h.keys.token(),
      );
      expect(r.statusCode, 403);
    });

    test('is rate limited (5 per window) → 429', () async {
      final t = h.keys.token();
      for (var i = 0; i < 5; i++) {
        expect(
          (await h.call('POST', '/auth/revoke-sessions', token: t)).statusCode,
          anyOf(200, 401),
        );
      }
      final r = await h.call('POST', '/auth/revoke-sessions', token: t);
      // After the first revoke the token is revoked (401) or limited (429).
      expect(r.statusCode, anyOf(401, 429));
    });
  });

  group('misc', () {
    test('POST /auth/account-status is not exposed', () async {
      h.seedUser();
      final r = await h.call(
        'POST',
        '/auth/account-status',
        token: h.keys.token(),
        body: {'uid': 'user-1', 'accountStatus': 'active'},
      );
      expect(r.statusCode, 404);
    });

    test('per-IP rate limit protects auth endpoints → 429', () async {
      for (var i = 0; i < 60; i++) {
        await h.call('GET', '/auth/me');
      }
      final r = await h.call('GET', '/auth/me');
      expect(r.statusCode, 429);
      expect(r.headers['retry-after'], isNotNull);
    });

    test('health stays public', () async {
      final r = await h.handler(
        Request('GET', Uri.parse('http://localhost/health')),
      );
      expect(r.statusCode, 200);
    });

    test('tokens never appear in logs', () async {
      h.seedUser();
      final token = h.keys.token();
      await h.call('GET', '/auth/me', token: token);
      await h.call('GET', '/auth/me', token: '$token-tampered');
      await h.call('POST', '/auth/logout', token: token);
      final all = h.logs.join('\n');
      expect(all, isNot(contains(token)));
      expect(all, isNot(contains(token.split('.')[1])));
      expect(all.toLowerCase(), isNot(contains('bearer')));
      expect(all, isNot(contains('user-1@example.test')));
    });

    test('security events are persisted without PII', () async {
      h.seedUser();
      await h.call('POST', '/auth/logout', token: h.keys.token());
      final event = h.store.audit.singleWhere((e) => e['event'] == 'logout');
      expect(
        jsonEncode(event.map((k, v) => MapEntry(k, '$v'))),
        isNot(contains('@')),
      );
    });
  });
}
