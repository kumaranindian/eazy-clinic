import 'dart:convert';

import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

void main() {
  late PlatformHarness h;

  setUp(() {
    h = PlatformHarness()
      ..user('root', role: PlatformRole.superAdmin)
      ..user('support', role: PlatformRole.platformSupportAdmin)
      ..user('alice');
  });

  Future<int> grant(
    String by,
    String who,
    String role, {
    String reason = 'New team member',
  }) => h.status(
    'POST',
    '/platform/admins',
    uid: by,
    body: {'email': '$who@example.test', 'role': role, 'reason': reason},
  );

  String? roleOf(String uid) =>
      h.store.docs['platform_users/$uid']!['platformRole'] as String?;

  test(
    'a super admin lists, grants and revokes; everything is audited',
    () async {
      final list = await h.list(
        await h.call('GET', '/platform/admins', uid: 'root'),
      );
      expect(
        list.map((e) => (e! as Map)['uid']),
        unorderedEquals(['root', 'support']),
      );
      expect(await grant('root', 'alice', 'platform_support_admin'), 200);
      expect(roleOf('alice'), 'platform_support_admin');
      // the new role works at once
      expect(await h.status('GET', '/platform/tenants', uid: 'alice'), 200);
      expect(
        await h.status(
          'POST',
          '/platform/admins/alice/revoke',
          uid: 'root',
          body: {'reason': 'Left the team'},
        ),
        200,
      );
      expect(roleOf('alice'), isNull);
      expect(await h.status('GET', '/platform/tenants', uid: 'alice'), 403);
      final audit = h.store.docs.entries
          .where((e) => e.key.startsWith('platform_audit_logs/'))
          .map((e) => e.value)
          .where((e) => '${e['action']}'.startsWith('platform_admin.'))
          .toList();
      expect(audit.map((e) => e['action']), [
        'platform_admin.granted',
        'platform_admin.revoked',
      ]);
      expect(
        jsonEncode(audit, toEncodable: (o) => '$o').contains('@'),
        isFalse,
        reason: 'no e-mail in audit',
      );
    },
  );

  test('only a super admin changes roles', () async {
    expect(await grant('support', 'alice', 'platform_support_admin'), 403);
    expect(await grant('alice', 'alice', 'super_admin'), 403);
    expect(
      await h.status(
        'POST',
        '/platform/admins/root/revoke',
        uid: 'support',
        body: {'reason': 'takeover'},
      ),
      403,
    );
    expect(await h.status('GET', '/platform/admins', uid: 'alice'), 403);
    expect(await h.status('GET', '/platform/admins'), 401);
    expect(
      await h.status('GET', '/platform/admins', uid: 'support'),
      200,
      reason: 'support may read',
    );
    expect(roleOf('alice'), isNull);
  });

  test(
    'nobody changes their own role, and the last super admin stays',
    () async {
      expect(await grant('root', 'root', 'platform_support_admin'), 409);
      expect(
        await h.status(
          'POST',
          '/platform/admins/root/revoke',
          uid: 'root',
          body: {'reason': 'stepping down'},
        ),
        409,
      );
      // with a second super admin, the first can be removed, but not both
      expect(await grant('root', 'alice', 'super_admin'), 200);
      expect(
        await h.status(
          'POST',
          '/platform/admins/root/revoke',
          uid: 'alice',
          body: {'reason': 'rotation'},
        ),
        200,
      );
      expect(
        await h.status(
          'POST',
          '/platform/admins/alice/revoke',
          uid: 'alice',
          body: {'reason': 'oops'},
        ),
        409,
      );
      expect(roleOf('alice'), 'super_admin');
    },
  );

  test('a suspended super admin does not count as a remaining one', () async {
    expect(await grant('root', 'alice', 'super_admin'), 200);
    h.store.docs['platform_users/root']!['accountStatus'] = 'suspended';
    // alice is now the only ACTIVE super admin: demoting her is refused
    h.user('bob', role: PlatformRole.superAdmin);
    h.store.docs['platform_users/bob']!['accountStatus'] = 'suspended';
    h.user('carol', role: PlatformRole.superAdmin);
    expect(
      await h.status(
        'POST',
        '/platform/admins/alice/revoke',
        uid: 'carol',
        body: {'reason': 'cleanup'},
      ),
      200,
    );
    expect(
      await grant('alice', 'carol', 'platform_support_admin'),
      403,
      reason: 'alice lost the role',
    );
  });

  test(
    'validation: unknown account, unverified account, bad role, missing reason',
    () async {
      expect(await grant('root', 'nobody', 'super_admin'), 404);
      expect(await grant('root', 'alice', 'god_mode'), 400);
      expect(
        await h.status(
          'POST',
          '/platform/admins',
          uid: 'root',
          body: {'email': 'alice@example.test', 'role': 'super_admin'},
        ),
        422,
      );
      expect(
        await h.status(
          'POST',
          '/platform/admins',
          uid: 'root',
          body: {
            'email': 'alice@example.test',
            'role': 'super_admin',
            'reason': 'ok ok',
            'uid': 'root',
          },
        ),
        422,
      );
      h.store.docs['platform_users/alice']!['emailVerified'] = false;
      expect(await grant('root', 'alice', 'super_admin'), 409);
      h.store.docs['platform_users/alice']!
        ..['emailVerified'] = true
        ..['accountStatus'] = 'suspended';
      expect(await grant('root', 'alice', 'super_admin'), 409);
      expect(
        await h.status(
          'POST',
          '/platform/admins/alice/revoke',
          uid: 'root',
          body: {'reason': 'not an admin'},
        ),
        404,
      );
    },
  );

  test('granting the same role twice is a replay', () async {
    expect(await grant('root', 'alice', 'platform_support_admin'), 200);
    final r = await h.okData(
      h.call(
        'POST',
        '/platform/admins',
        uid: 'root',
        body: {
          'email': 'alice@example.test',
          'role': 'platform_support_admin',
          'reason': 'again',
        },
      ),
    );
    expect(r['idempotentReplay'], true);
  });
}
