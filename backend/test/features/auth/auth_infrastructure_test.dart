import 'dart:convert';

import 'package:backend/config/app_config.dart';
import 'package:backend/core/security/rate_limiter.dart';
import 'package:backend/features/auth/data/firebase_auth_admin.dart';
import 'package:backend/features/auth/data/signing_key_provider.dart';
import 'package:common_models/common_models.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import '../../support/auth_fixtures.dart';

void main() {
  group('RateLimiter', () {
    test('allows up to the limit then blocks until the window resets', () {
      var now = DateTime(2026);
      final limiter = RateLimiter(
        maxRequests: 2,
        window: const Duration(seconds: 10),
        clock: () => now,
      );
      expect(limiter.hit('a'), isNull);
      expect(limiter.hit('a'), isNull);
      expect(limiter.hit('a'), isNotNull);
      expect(limiter.hit('b'), isNull, reason: 'keys are independent');
      now = now.add(const Duration(seconds: 11));
      expect(limiter.hit('a'), isNull);
    });
  });

  group('AccountStatus', () {
    test('only active may use protected features', () {
      expect(AccountStatus.values.where((s) => s.canAccessProtectedFeatures), [
        AccountStatus.active,
      ]);
    });
    test('transition rules', () {
      expect(AccountStatus.pending.canTransitionTo(AccountStatus.active), true);
      expect(
        AccountStatus.active.canTransitionTo(AccountStatus.pending),
        false,
      );
      expect(
        AccountStatus.suspended.canTransitionTo(AccountStatus.active),
        true,
      );
      for (final s in AccountStatus.values) {
        expect(AccountStatus.disabled.canTransitionTo(s), false);
      }
    });
    test('unknown wire value does not parse', () {
      expect(AccountStatus.tryParse('admin'), isNull);
    });
  });

  group('PermissionPolicy', () {
    test('unknown or absent roles have no permissions', () {
      expect(PermissionPolicy.forPlatformRole(null), isEmpty);
      expect(PermissionPolicy.forClinicRole(ClinicRole.clinicOwner), isEmpty);
      expect(PermissionPolicy.forPatientRole(PatientRole.patient), isEmpty);
    });
    test('only super admin may revoke other users sessions', () {
      expect(
        PermissionPolicy.platformRoleHas(
          PlatformRole.superAdmin,
          Permission.revokeUserSessions,
        ),
        true,
      );
      expect(
        PermissionPolicy.platformRoleHas(
          PlatformRole.platformSupportAdmin,
          Permission.revokeUserSessions,
        ),
        false,
      );
    });
  });

  group('AppConfig auth settings', () {
    test('revocation checks are mandatory outside dev', () {
      expect(
        () => AppConfig.fromEnvironment({
          'APP_ENV': 'production',
          'FIREBASE_PROJECT_ID': 'p',
          'AUTH_CHECK_REVOKED': 'false',
        }),
        throwsA(isA<Object>()),
      );
      final dev = AppConfig.fromEnvironment({
        'APP_ENV': 'dev',
        'AUTH_CHECK_REVOKED': 'false',
      });
      expect(dev.authCheckRevoked, false);
    });
    test('defaults: revocation on, forwarded-for untrusted', () {
      final c = AppConfig.fromEnvironment({'APP_ENV': 'dev'});
      expect(c.authCheckRevoked, true);
      expect(c.trustForwardedFor, false);
    });
  });

  group('IdentityToolkitAuthAdmin', () {
    test('lookup parses disabled and validSince', () async {
      final admin = IdentityToolkitAuthAdmin(
        projectId: 'proj',
        client: MockClient((r) async {
          expect(r.url.path, '/v1/projects/proj/accounts:lookup');
          return http.Response(
            jsonEncode({
              'users': [
                {'localId': 'u1', 'disabled': true, 'validSince': '1700000000'},
              ],
            }),
            200,
          );
        }),
      );
      final rec = await admin.lookup('u1');
      expect(rec!.disabled, true);
      expect(rec.validSince!.millisecondsSinceEpoch, 1700000000 * 1000);
    });

    test('lookup → null when the user is gone', () async {
      final admin = IdentityToolkitAuthAdmin(
        projectId: 'p',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(await admin.lookup('u1'), isNull);
    });

    test('revoke sets validSince to now (seconds)', () async {
      late Map<String, Object?> sent;
      final admin = IdentityToolkitAuthAdmin(
        projectId: 'p',
        clock: () => DateTime.fromMillisecondsSinceEpoch(1700000000500),
        client: MockClient((r) async {
          sent = jsonDecode(r.body) as Map<String, Object?>;
          return http.Response('{}', 200);
        }),
      );
      await admin.revokeRefreshTokens('u1');
      expect(sent, {'localId': 'u1', 'validSince': '1700000000'});
    });

    test('failures raise without echoing the response', () async {
      final admin = IdentityToolkitAuthAdmin(
        projectId: 'p',
        client: MockClient((_) async => http.Response('leak', 500)),
      );
      await expectLater(
        admin.lookup('u1'),
        throwsA(
          isA<AuthAdminException>().having(
            (e) => e.message,
            'm',
            isNot(contains('leak')),
          ),
        ),
      );
    });
  });

  group('GoogleSigningKeyProvider', () {
    test('unavailable endpoint → SigningKeysUnavailableException', () async {
      final p = GoogleSigningKeyProvider(
        client: MockClient((_) async => http.Response('', 500)),
      );
      expect(p.keyFor('k'), throwsA(isA<SigningKeysUnavailableException>()));
    });

    test('caches within max-age and limits refetch for unknown kids', () async {
      var calls = 0;
      var now = DateTime(2026);
      final p = GoogleSigningKeyProvider(
        clock: () => now,
        client: MockClient((_) async {
          calls++;
          return http.Response(
            '{}',
            200,
            headers: {'cache-control': 'public, max-age=300'},
          );
        }),
      );
      expect(await p.keyFor('a'), isNull);
      expect(await p.keyFor('b'), isNull);
      expect(calls, 1, reason: 'unknown kid within interval must not refetch');
      now = now.add(const Duration(minutes: 2));
      await p.keyFor('c');
      expect(calls, 2, reason: 'allowed after the minimum refresh interval');
      now = now.add(const Duration(minutes: 10));
      await p.keyFor('a');
      expect(calls, 3, reason: 'expired cache is refreshed');
    });
  });

  test('test harness constants are consistent', () {
    expect(testProjectId, isNotEmpty);
  });
}
