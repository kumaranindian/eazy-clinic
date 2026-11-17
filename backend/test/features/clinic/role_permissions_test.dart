import 'package:test/test.dart';

import '../../support/clinical_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

void main() {
  late PlatformHarness h;
  late ClinicalClinic k;

  setUp(() async {
    h = PlatformHarness();
    k = ClinicalClinic(h);
    await k.init();
  });

  Future<int> setRole(
    String role, {
    String by = 'owner',
    List<String> grant = const [],
    List<String> revoke = const [],
    String? reason = 'Clinic policy change',
  }) => h.status(
    'PUT',
    '/roles/$role/permissions',
    uid: by,
    body: {'grant': grant, 'revoke': revoke, 'reason': ?reason},
  );

  test(
    'defaults apply until the owner changes a role; changes apply at once',
    () async {
      expect(await h.status('GET', '/billing/invoices', uid: 'nurse'), 403);
      expect(await setRole('nurse', grant: ['billing.view']), 200);
      expect(await h.status('GET', '/billing/invoices', uid: 'nurse'), 200);
      final mine = await h.get('nurse', '/members/current/permissions');
      expect(mine['permissions'], contains('billing.view'));
      // taking a default permission away
      expect(await h.status('GET', '/appointments', uid: 'recep'), 200);
      expect(await setRole('receptionist', revoke: ['appointments.view']), 200);
      expect(await h.status('GET', '/appointments', uid: 'recep'), 403);
    },
  );

  test('reset returns a role to the defaults', () async {
    await setRole('nurse', grant: ['billing.view']);
    expect(
      await h.status(
        'POST',
        '/roles/nurse/permissions/reset',
        uid: 'owner',
        body: {'reason': 'Back to standard'},
      ),
      200,
    );
    expect(await h.status('GET', '/billing/invoices', uid: 'nurse'), 403);
    final r = await h.okData(
      h.call(
        'POST',
        '/roles/nurse/permissions/reset',
        uid: 'owner',
        body: {'reason': 'Back to standard'},
      ),
    );
    expect(r['idempotentReplay'], true);
  });

  test(
    'only the owner changes roles, and that power cannot be handed over',
    () async {
      for (final uid in ['admin', 'recep', 'nurse', 'docuser', 'acct']) {
        expect(
          await setRole('nurse', by: uid, grant: ['billing.view']),
          403,
          reason: uid,
        );
      }
      expect(await setRole('clinic_admin', grant: ['roles.manage']), 422);
      // an admin granted everything else still cannot edit roles
      expect(
        await setRole(
          'clinic_admin',
          grant: ['lab.results.view', 'consultations.view'],
        ),
        200,
      );
      expect(await setRole('nurse', by: 'admin', grant: ['billing.view']), 403);
      expect(
        await h.status(
          'POST',
          '/roles/nurse/permissions/reset',
          uid: 'admin',
          body: {'reason': 'try it'},
        ),
        403,
      );
    },
  );

  test('the owner role cannot be edited or weakened', () async {
    expect(await setRole('clinic_owner', revoke: ['billing.view']), 409);
    expect(await h.status('GET', '/billing/invoices', uid: 'owner'), 200);
    // even a stored document for the owner is ignored
    h.store.docs['tenants/${k.tid}/role_permissions/clinic_owner'] = {
      'grant': <String>[],
      'revoke': ['billing.view', 'roles.manage'],
    };
    expect(await h.status('GET', '/billing/invoices', uid: 'owner'), 200);
    expect(await setRole('nurse', grant: ['billing.view']), 200);
  });

  test('validation', () async {
    expect(await setRole('nurse', grant: ['platform.tenants.manage']), 422);
    expect(await setRole('nurse', grant: ['made.up']), 422);
    expect(
      await setRole('nurse', grant: ['billing.view'], revoke: ['billing.view']),
      422,
    );
    expect(await setRole('nurse', grant: ['billing.view'], reason: null), 422);
    expect(await setRole('wizard', grant: ['billing.view']), 404);
    expect(
      await h.status(
        'PUT',
        '/roles/nurse/permissions',
        uid: 'owner',
        body: {
          'grant': ['billing.view'],
          'reason': 'fine reason',
          'tenantId': 'x',
        },
      ),
      422,
    );
    expect(
      await h.status(
        'PUT',
        '/roles/nurse/permissions',
        body: {'grant': <String>[], 'reason': 'anon'},
      ),
      401,
    );
  });

  test(
    'a stored grant of an owner-only or unknown permission is ignored',
    () async {
      h.store.docs['tenants/${k.tid}/role_permissions/nurse'] = {
        'grant': ['roles.manage', 'not.a.permission', 'billing.view'],
        'revoke': <String>[],
      };
      expect(
        await setRole('receptionist', by: 'nurse', grant: ['billing.view']),
        403,
      );
      expect(await h.status('GET', '/billing/invoices', uid: 'nurse'), 200);
      final perms =
          (await h.get('nurse', '/members/current/permissions'))['permissions']!
              as List;
      expect(perms.contains('roles.manage'), isFalse);
      expect(perms.contains('not.a.permission'), isFalse);
    },
  );

  test(
    'granting clinical permissions does not let a non-doctor author records',
    () async {
      expect(
        await setRole(
          'receptionist',
          grant: ['consultations.manage', 'consultations.view'],
        ),
        200,
      );
      expect(
        await h.status(
          'POST',
          '/consultations',
          uid: 'recep',
          body: k.consult(),
        ),
        isNot(201),
      );
    },
  );

  test('one clinic\'s changes never affect another', () async {
    await setRole('nurse', grant: ['billing.view']);
    final other = await h.createClinic(
      'ownerB',
      name: 'Other Clinic',
      city: 'Nagpur',
      pin: '440001',
    );
    h.member('nurseB', other, 'nurse');
    expect(await h.status('GET', '/billing/invoices', uid: 'nurseB'), 403);
    // and clinic B's owner cannot edit clinic A's roles (the path has no tenant)
    expect(
      await setRole('nurse', by: 'ownerB', revoke: ['patients.view']),
      200,
    );
    expect(await h.status('GET', '/billing/invoices', uid: 'nurse'), 200);
    expect(await h.status('GET', '/patients', uid: 'nurse'), 200);
  });

  test('the role list shows adjustments and every change is audited', () async {
    await setRole('nurse', grant: ['billing.view'], revoke: ['patients.view']);
    final roles = await h.list(await h.call('GET', '/roles', uid: 'owner'));
    final nurse =
        roles.firstWhere((r) => (r! as Map)['role'] == 'nurse')! as Map;
    expect(nurse['custom'], true);
    expect(nurse['grant'], ['billing.view']);
    expect(nurse['revoke'], ['patients.view']);
    final owner =
        roles.firstWhere((r) => (r! as Map)['role'] == 'clinic_owner')! as Map;
    expect(owner['editable'], false);
    final audit = h.store.docs.entries
        .where((e) => e.key.startsWith('platform_audit_logs/'))
        .map((e) => e.value)
        .where((e) => e['action'] == 'role.permissions_changed');
    expect(audit, hasLength(1));
    expect(audit.single['reason'], 'Clinic policy change');
    expect(audit.single['tenantId'], k.tid);
  });
}
