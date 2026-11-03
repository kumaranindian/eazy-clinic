import 'dart:convert';

import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/auth_fixtures.dart' show errorCode;
import '../../support/platform_http_fixtures.dart';
import 'doctor_test.dart' show doctorBody;

Map<String, Object?> staffBody({
  String name = 'Nina Nurse',
  String email = 'nina@example.test',
  String role = 'nurse',
  Object? branchIds,
  bool? allBranches,
  Map<String, Object?> extra = const {},
}) => {
  'fullName': name,
  'email': email,
  'phone': '9876500001',
  'designation': 'Staff nurse',
  'department': 'Nursing',
  'role': role,
  if (allBranches != null) 'allBranches': allBranches,
  if (branchIds != null) 'branchIds': branchIds,
  ...extra,
};

void main() {
  late PlatformHarness h;
  late String tid;
  late String b1;
  late String b2;

  Future<Map<String, Object?>> mkStaff(
    String uid,
    Map<String, Object?> body, {
    int status = 201,
  }) => h.okData(
    h.call('POST', '/staff', uid: uid, body: body),
    status: status,
  );

  /// Staff profile with an invitation; returns (staffId, token).
  Future<(String, String)> invited(
    String email, {
    String role = 'nurse',
    String? by,
  }) async {
    final res = await h.okData(
      h.call(
        'POST',
        '/staff',
        uid: by ?? 'owner',
        body: {
          ...staffBody(
            name: 'Person ${email.split('@').first}',
            email: email,
            role: role,
            branchIds: [b1],
          ),
          'invite': true,
        },
      ),
      status: 201,
    );
    return (
      res['staffId']! as String,
      (res['invitation']! as Map)['inviteToken']! as String,
    );
  }

  Future<int> accept(
    String uid,
    String token, [
    Map<String, Object?> extra = const {},
  ]) async => (await h.call(
    'POST',
    '/invitations/accept',
    uid: uid,
    body: {'token': token, ...extra},
  )).statusCode;

  setUp(() async {
    h = PlatformHarness();
    h.user('root', role: PlatformRole.superAdmin);
    tid = await h.createClinic('owner', maxStaff: 3, maxDoctors: 3);
    b1 =
        (await h.okData(
              h.call(
                'POST',
                '/branches',
                uid: 'owner',
                body: branchBody(name: 'One', code: 'ONE'),
              ),
              status: 201,
            ))['branchId']!
            as String;
    b2 =
        (await h.okData(
              h.call(
                'POST',
                '/branches',
                uid: 'owner',
                body: branchBody(name: 'Two', code: 'TWO'),
              ),
              status: 201,
            ))['branchId']!
            as String;
  });

  group('staff profiles', () {
    test(
      'owner creates a staff profile: backend ids, inactive, no login, no seat',
      () async {
        final s = await mkStaff('owner', staffBody(branchIds: [b1]));
        expect(s['staffId'], startsWith('stf_'));
        expect(s['status'], 'inactive');
        expect(s['uid'], isNull);
        expect(s['branchIds'], [b1]);
        expect(
          h.store.docs.keys.where((k) => k.contains('/seats/staff_')),
          isEmpty,
        );
      },
    );

    test(
      'client cannot set identity, status, uid, tenant or permission fields',
      () async {
        for (final extra in [
          {'staffId': 'stf_x'},
          {'tenantId': 'o'},
          {'status': 'active'},
          {'uid': 'attacker'},
          {
            'permissions': ['*'],
          },
          {'platformRole': 'super_admin'},
          {'invitationId': 'inv_x'},
        ]) {
          expect(
            (await h.call(
              'POST',
              '/staff',
              uid: 'owner',
              body: staffBody(branchIds: [b1], extra: extra),
            )).statusCode,
            422,
            reason: '$extra',
          );
        }
      },
    );

    test('validation and duplicates', () async {
      for (final bad in [
        staffBody(name: 'x', branchIds: [b1]),
        staffBody(email: 'nope', branchIds: [b1]),
        staffBody(role: 'clinic_owner', branchIds: [b1]),
        staffBody(role: 'super_admin', branchIds: [b1]),
        staffBody(role: 'platform_support_admin', branchIds: [b1]),
        staffBody(),
        staffBody(branchIds: <String>[]),
        staffBody(branchIds: [b1], allBranches: true),
      ]) {
        expect(
          (await h.call('POST', '/staff', uid: 'owner', body: bad)).statusCode,
          422,
          reason: '$bad',
        );
      }
      await mkStaff('owner', staffBody(branchIds: [b1]));
      expect(
        (await h.call(
          'POST',
          '/staff',
          uid: 'owner',
          body: staffBody(
            name: 'Other Nina',
            email: 'NINA@example.test',
            branchIds: [b1],
          ),
        )).statusCode,
        409,
      );
    });

    test('unknown or foreign branches are rejected', () async {
      await h.createClinic(
        'ownerB',
        name: 'Clinic B',
        city: 'Mumbai',
        pin: '400001',
      );
      final foreign =
          (await h.okData(
                h.call(
                  'POST',
                  '/branches',
                  uid: 'ownerB',
                  body: branchBody(name: 'Foreign', code: 'FFF'),
                ),
                status: 201,
              ))['branchId']!
              as String;
      expect(
        (await h.call(
          'POST',
          '/staff',
          uid: 'owner',
          body: staffBody(branchIds: [foreign]),
        )).statusCode,
        404,
      );
      expect(
        (await h.call(
          'POST',
          '/staff',
          uid: 'owner',
          body: staffBody(branchIds: ['br_missing']),
        )).statusCode,
        404,
      );
    });

    test('update, search, filter', () async {
      final s = await mkStaff('owner', staffBody(branchIds: [b1]));
      await mkStaff(
        'owner',
        staffBody(
          name: 'Ravi Recep',
          email: 'ravi@example.test',
          role: 'receptionist',
          branchIds: [b2],
        ),
      );
      final u = await h.okData(
        h.call(
          'PATCH',
          '/staff/${s['staffId']}',
          uid: 'owner',
          body: {'department': 'ICU', 'role': 'accountant'},
        ),
      );
      expect(u['department'], 'ICU');
      expect(
        u['role'],
        'accountant',
        reason: 'role of a not-yet-invited profile can be set',
      );
      expect(
        await h.list(await h.call('GET', '/staff?q=ravi', uid: 'owner')),
        hasLength(1),
      );
      expect(
        await h.list(
          await h.call('GET', '/staff?role=receptionist', uid: 'owner'),
        ),
        hasLength(1),
      );
      expect(
        await h.list(await h.call('GET', '/staff?branchId=$b2', uid: 'owner')),
        hasLength(1),
      );
      expect(
        (await h.call('GET', '/staff?status=weird', uid: 'owner')).statusCode,
        400,
      );
      expect(
        (await h.call(
          'PATCH',
          '/staff/${s['staffId']}',
          uid: 'owner',
          body: {'uid': 'x'},
        )).statusCode,
        422,
      );
      expect(
        (await h.call(
          'PATCH',
          '/staff/${s['staffId']}',
          uid: 'owner',
          body: {'status': 'active'},
        )).statusCode,
        422,
      );
    });
  });

  group('invitation lifecycle', () {
    test(
      'invite: single-use secret shown once, only its hash is stored, delivery is not faked',
      () async {
        final (sid, token) = await invited('nina@example.test');
        expect(token, startsWith('ecinv_'));
        expect(token.length, greaterThan(40));
        final inv = h.store.docs.entries
            .firstWhere((e) => RegExp(r'/invitations/').hasMatch(e.key))
            .value;
        expect(inv['tokenHash'], isNot(token));
        expect(inv['tokenHash'], hasLength(64));
        expect(
          jsonEncode(
            h.store.docs.values
                .map(
                  (d) => d.map(
                    (k, v) =>
                        MapEntry(k, v is DateTime ? v.toIso8601String() : v),
                  ),
                )
                .toList(),
          ),
          isNot(contains(token)),
          reason: 'the raw secret is never persisted',
        );
        expect(
          (await h.call('POST', '/staff/$sid/invite', uid: 'owner')).statusCode,
          409,
          reason: 'already invited',
        );
        final list = await h.call('GET', '/invitations', uid: 'owner');
        final text = await list.readAsString();
        expect(text, isNot(contains(token)));
        expect(text, isNot(contains('tokenHash')));
        final created = await h.okData(
          h.call(
            'POST',
            '/staff',
            uid: 'owner',
            body: {
              ...staffBody(
                name: 'Second Person',
                email: 'second@example.test',
                branchIds: [b1],
              ),
              'invite': true,
            },
          ),
          status: 201,
        );
        expect(
          ((created['invitation']! as Map)['delivery']! as Map)['status'],
          'not_configured',
        );
      },
    );

    test(
      'the invitee accepts: membership has exactly the invited role and scope',
      () async {
        final (sid, token) = await invited(
          'nina@example.test',
          role: 'receptionist',
        );
        h.user('nina');
        expect(await accept('nina', token), 200);
        final m = h.store.docs['tenants/$tid/members/nina']!;
        expect(m['role'], 'receptionist');
        expect(m['branchIds'], [b1]);
        expect(m['allBranches'], false);
        expect(m['status'], 'active');
        expect(m['staffId'], sid);
        final staff = h.store.docs['tenants/$tid/staff/$sid']!;
        expect(staff['status'], 'active');
        expect(staff['uid'], 'nina');
        final session = await h.data(
          await h.call('GET', '/auth/session', uid: 'nina'),
        );
        expect(
          ((session['memberships']! as List).single as Map)['tenantId'],
          tid,
        );
        final perms = await h.okData(
          h.call('GET', '/members/current/permissions', uid: 'nina'),
        );
        expect(perms['role'], 'receptionist');
        expect((perms['branches']! as List).map((b) => (b as Map)['name']), [
          'One',
        ]);
        expect(
          h.store.docs.values.any((d) => d['action'] == 'invitation.accepted'),
          isTrue,
        );
      },
    );

    test('replay of a used invitation fails', () async {
      final (_, token) = await invited('nina@example.test');
      h.user('nina');
      expect(await accept('nina', token), 200);
      expect(await accept('nina', token), 400);
      h.user('mallory');
      expect(await accept('mallory', token), 400);
    });

    test(
      'a different person (email mismatch) cannot accept — and learns nothing',
      () async {
        final (_, token) = await invited('nina@example.test');
        h.user('mallory');
        final r = await h.call(
          'POST',
          '/invitations/accept',
          uid: 'mallory',
          body: {'token': token},
        );
        expect(r.statusCode, 400);
        final wrongToken = await h.call(
          'POST',
          '/invitations/accept',
          uid: 'mallory',
          body: {'token': 'ecinv_${'A' * 43}'},
        );
        expect(await r.readAsString(), contains('invalid or has expired'));
        expect(wrongToken.statusCode, 400);
        expect(
          h.store.docs.containsKey('tenants/$tid/members/mallory'),
          isFalse,
        );
        expect(
          h.store.docs.values.any(
            (d) =>
                d['action'] == 'invitation.accept_denied' &&
                d['reason'] == 'identity_mismatch',
          ),
          isTrue,
        );
        // the real invitee can still accept afterwards
        h.user('nina');
        expect(await accept('nina', token), 200);
      },
    );

    test('an unverified e-mail cannot accept', () async {
      final (_, token) = await invited('nina@example.test');
      h.user('nina', status: AccountStatus.pending);
      final r = await h.call(
        'POST',
        '/invitations/accept',
        uid: 'nina',
        body: {'token': token},
        emailVerified: false,
      );
      expect(r.statusCode, 403);
      expect(await errorCode(r), 'account_pending');
    });

    test('invitations expire', () async {
      final (sid, token) = await invited('nina@example.test');
      h.user('nina');
      h.clock.now = h.clock.now.add(const Duration(days: 8));
      expect(await accept('nina', token), 400);
      final staff = await h.okData(h.call('GET', '/staff/$sid', uid: 'owner'));
      expect(staff['status'], 'invitation_expired');
    });

    test('resend gives a new secret and kills the old one', () async {
      final (sid, oldToken) = await invited('nina@example.test');
      final invId =
          (await h.list(
                await h.call('GET', '/invitations', uid: 'owner'),
              )).cast<Map<String, Object?>>().single['invitationId']!
              as String;
      h.clock.now = h.clock.now.add(const Duration(days: 8));
      final resent = await h.okData(
        h.call('POST', '/invitations/$invId/resend', uid: 'owner'),
      );
      final newToken = resent['inviteToken']! as String;
      expect(newToken, isNot(oldToken));
      h.user('nina');
      expect(await accept('nina', oldToken), 400);
      expect(
        (await h.okData(h.call('GET', '/staff/$sid', uid: 'owner')))['status'],
        'invited',
      );
      expect(await accept('nina', newToken), 200);
      expect(
        (await h.call(
          'POST',
          '/invitations/$invId/resend',
          uid: 'owner',
        )).statusCode,
        409,
      );
    });

    test('revoked invitations cannot be accepted; the seat is freed', () async {
      final (sid, token) = await invited('nina@example.test');
      expect(
        h.store.docs.keys.where((k) => k.contains('/seats/staff_')),
        hasLength(1),
      );
      final invId =
          (await h.list(
                await h.call('GET', '/invitations', uid: 'owner'),
              )).cast<Map<String, Object?>>().single['invitationId']!
              as String;
      await h.okData(
        h.call('POST', '/invitations/$invId/revoke', uid: 'owner'),
      );
      h.user('nina');
      expect(await accept('nina', token), 400);
      expect(
        (await h.okData(h.call('GET', '/staff/$sid', uid: 'owner')))['status'],
        'inactive',
      );
      expect(
        h.store.docs.keys.where((k) => k.contains('/seats/staff_')),
        isEmpty,
      );
      expect(
        (await h.call(
          'POST',
          '/invitations/$invId/revoke',
          uid: 'owner',
        )).statusCode,
        409,
      );
      // and a fresh invitation can be created again
      await h.okData(
        h.call('POST', '/staff/$sid/invite', uid: 'owner'),
        status: 201,
      );
    });

    test(
      'the invitee cannot change role, branches, tenant or send extra fields',
      () async {
        final (_, token) = await invited('nina@example.test');
        h.user('nina');
        for (final extra in [
          {'role': 'clinic_admin'},
          {
            'branchIds': [b2],
          },
          {'allBranches': true},
          {'tenantId': 'x'},
          {'email': 'x@y.co'},
        ]) {
          expect(await accept('nina', token, extra), 400, reason: '$extra');
        }
        expect(h.store.docs.containsKey('tenants/$tid/members/nina'), isFalse);
        expect(await accept('nina', token), 200);
        expect(h.store.docs['tenants/$tid/members/nina']!['role'], 'nurse');
      },
    );

    test('garbage tokens are refused', () async {
      h.user('nina');
      for (final t in ['', 'abc', 'ecinv_', 'x' * 500]) {
        expect(await accept('nina', t), 400, reason: t);
      }
      expect(
        (await h.call(
          'POST',
          '/invitations/accept',
          uid: 'nina',
          body: {},
        )).statusCode,
        400,
      );
      expect(
        (await h.call(
          'POST',
          '/invitations/accept',
          body: {'token': 'ecinv_x'},
        )).statusCode,
        401,
      );
    });

    test('accept is rate limited per user', () async {
      h.user('nina');
      var last = 0;
      for (var i = 0; i < 11; i++) {
        last = await accept('nina', 'ecinv_${'B' * 43}');
      }
      expect(last, 429);
    });

    test(
      'existing members cannot accept again; one account can join several clinics',
      () async {
        final (_, token) = await invited('nina@example.test');
        h.user('nina');
        await accept('nina', token);
        final other = await h.createClinic(
          'ownerB',
          name: 'Clinic B',
          city: 'Mumbai',
          pin: '400001',
        );
        final bb =
            (await h.okData(
                  h.call(
                    'POST',
                    '/branches',
                    uid: 'ownerB',
                    body: branchBody(name: 'BB', code: 'BB1'),
                  ),
                  status: 201,
                ))['branchId']!
                as String;
        final res = await h.okData(
          h.call(
            'POST',
            '/staff',
            uid: 'ownerB',
            body: {
              ...staffBody(
                email: 'nina@example.test',
                role: 'accountant',
                branchIds: [bb],
              ),
              'invite': true,
            },
          ),
          status: 201,
        );
        expect(
          await accept(
            'nina',
            (res['invitation']! as Map)['inviteToken']! as String,
          ),
          200,
        );
        expect(
          h.store.docs['tenants/$other/members/nina']!['role'],
          'accountant',
        );
        expect(h.store.docs['tenants/$tid/members/nina']!['role'], 'nurse');
        // with two clinics a selector is required, and it only selects among own memberships
        expect(
          (await h.call('GET', '/clinics/current', uid: 'nina')).statusCode,
          409,
        );
        expect(
          (await h.call(
            'GET',
            '/clinics/current',
            uid: 'nina',
            headers: {'x-tenant-id': tid},
          )).statusCode,
          200,
        );
      },
    );
  });

  group('seats', () {
    test(
      'max_staff counts invited + active people; concurrent invitations cannot exceed it',
      () async {
        final ids = <String>[];
        for (var i = 0; i < 5; i++) {
          ids.add(
            (await mkStaff(
                  'owner',
                  staffBody(
                    name: 'Person $i',
                    email: 'p$i@example.test',
                    branchIds: [b1],
                  ),
                ))['staffId']!
                as String,
          );
        }
        final rs = await Future.wait([
          for (final id in ids)
            h.call('POST', '/staff/$id/invite', uid: 'owner'),
        ]);
        expect(rs.where((r) => r.statusCode == 201), hasLength(3));
        expect(rs.where((r) => r.statusCode == 403), hasLength(2));
        expect(
          h.store.docs.keys.where((k) => k.contains('/seats/staff_')),
          hasLength(3),
        );
      },
    );

    test('deactivating releases a seat; reactivating needs one', () async {
      final (sid, token) = await invited('a@example.test');
      h.user('a');
      await accept('a', token);
      await invited('b@example.test');
      await invited('c@example.test');
      await h.okData(h.call('POST', '/staff/$sid/deactivate', uid: 'owner'));
      final extra = await mkStaff(
        'owner',
        staffBody(
          name: 'Late Joiner',
          email: 'late@example.test',
          branchIds: [b1],
        ),
      );
      await h.okData(
        h.call('POST', '/staff/${extra['staffId']}/invite', uid: 'owner'),
        status: 201,
      );
      expect(
        (await h.call('POST', '/staff/$sid/activate', uid: 'owner')).statusCode,
        403,
      );
    });
  });

  group('status lifecycle and account separation', () {
    late String sid;
    setUp(() async {
      final r = await invited('nina@example.test');
      sid = r.$1;
      h.user('nina');
      await accept('nina', r.$2);
    });

    test('suspend / deactivate / reactivate follow the membership', () async {
      expect(
        (await h.call('GET', '/clinics/current', uid: 'nina')).statusCode,
        200,
      );
      await h.okData(h.call('POST', '/staff/$sid/suspend', uid: 'owner'));
      expect(h.store.docs['tenants/$tid/members/nina']!['status'], 'suspended');
      expect(
        (await h.call('GET', '/clinics/current', uid: 'nina')).statusCode,
        403,
      );
      await h.okData(h.call('POST', '/staff/$sid/activate', uid: 'owner'));
      expect(
        (await h.call('GET', '/clinics/current', uid: 'nina')).statusCode,
        200,
      );
      await h.okData(h.call('POST', '/staff/$sid/deactivate', uid: 'owner'));
      expect(
        h.store.docs['tenants/$tid/members/nina']!['status'],
        'deactivated',
      );
      expect(
        (await h.call('GET', '/clinics/current', uid: 'nina')).statusCode,
        403,
      );
      expect(
        (await h.call(
          'POST',
          '/staff/$sid/deactivate',
          uid: 'owner',
        )).statusCode,
        409,
      );
    });

    test(
      'deactivation does not delete the Firebase account or other clinics',
      () async {
        await h.createClinic(
          'ownerB',
          name: 'Clinic B',
          city: 'Mumbai',
          pin: '400001',
        );
        final other = h.store.docs.keys
            .firstWhere(
              (k) =>
                  RegExp(r'^tenants/[^/]+$').hasMatch(k) && k != 'tenants/$tid',
            )
            .split('/')[1];
        h.member('nina', other, 'accountant');
        await h.okData(h.call('POST', '/staff/$sid/deactivate', uid: 'owner'));
        expect(
          h.authAdmin.records.containsKey('nina'),
          isTrue,
          reason: 'Firebase account untouched',
        );
        expect(h.authAdmin.revoked, isEmpty);
        expect(h.store.docs.containsKey('platform_users/nina'), isTrue);
        expect(
          (await h.call(
            'GET',
            '/clinics/current',
            uid: 'nina',
            headers: {'x-tenant-id': tid},
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'GET',
            '/clinics/current',
            uid: 'nina',
            headers: {'x-tenant-id': other},
          )).statusCode,
          200,
        );
      },
    );

    test('a person cannot deactivate, suspend or re-role themselves', () async {
      h.member('adm', tid, 'clinic_admin');
      h.store.docs['tenants/$tid/staff/stf_adm'] = {
        'staffId': 'stf_adm',
        'uid': 'adm',
        'role': 'clinic_admin',
        'status': 'active',
        'allBranches': true,
        'branchIds': <String>[],
        'email': 'adm@example.test',
        'fullName': 'Adm',
      };
      expect(
        (await h.call(
          'POST',
          '/staff/stf_adm/deactivate',
          uid: 'adm',
        )).statusCode,
        403,
      );
      expect(
        (await h.call(
          'PATCH',
          '/members/adm/role',
          uid: 'adm',
          body: {'role': 'doctor'},
        )).statusCode,
        403,
      );
      expect(
        (await h.call(
          'PATCH',
          '/members/nina/role',
          uid: 'nina',
          body: {'role': 'clinic_admin'},
        )).statusCode,
        403,
      );
      expect(
        (await h.call(
          'PATCH',
          '/members/nina/branches',
          uid: 'nina',
          body: {'allBranches': true},
        )).statusCode,
        403,
      );
    });
  });

  group('roles, permissions and authority', () {
    late String nurseStaff;
    setUp(() async {
      final r = await invited('nina@example.test');
      nurseStaff = r.$1;
      h.user('nina');
      await accept('nina', r.$2);
    });

    test(
      'role catalogue and permission matrix come from the backend',
      () async {
        final roles = (await h.list(
          await h.call('GET', '/roles', uid: 'owner'),
        )).cast<Map<String, Object?>>();
        expect(
          roles.map((r) => r['role']),
          containsAll([
            'clinic_owner',
            'clinic_admin',
            'doctor',
            'receptionist',
            'nurse',
            'accountant',
            'lab_technician',
            'pharmacist',
          ]),
        );
        final admin = roles.firstWhere((r) => r['role'] == 'clinic_admin');
        expect(
          (admin['permissions']! as List),
          isNot(contains('roles.manage')),
        );
        expect(
          roles.every(
            (r) => !(r['permissions']! as List).any(
              (p) => '$p'.startsWith('platform.'),
            ),
          ),
          isTrue,
        );
        final catalog = await h.okData(
          h.call('GET', '/permissions', uid: 'owner'),
        );
        expect(catalog['customRoles'], 'deferred');
        expect(
          (await h.call('GET', '/roles', uid: 'nina')).statusCode,
          403,
          reason: 'nurses cannot browse roles',
        );
      },
    );

    test('current permissions reflect the stored role and scope', () async {
      final p = await h.okData(
        h.call('GET', '/members/current/permissions', uid: 'nina'),
      );
      expect(p['role'], 'nurse');
      expect(p['permissions'], isNot(contains('staff.assign_role')));
      expect(p['allBranches'], false);
      expect(p['branchIds'], [b1]);
      final o = await h.okData(
        h.call('GET', '/members/current/permissions', uid: 'owner'),
      );
      expect(o['allBranches'], true);
      expect(o['permissions'], contains('roles.manage'));
    });

    test('owner changes a role; the effect is immediate', () async {
      final r = await h.okData(
        h.call(
          'PATCH',
          '/members/nina/role',
          uid: 'owner',
          body: {'role': 'receptionist'},
        ),
      );
      expect(r['role'], 'receptionist');
      expect(
        h.store.docs['tenants/$tid/staff/$nurseStaff']!['role'],
        'receptionist',
      );
      expect(
        (await h.okData(
          h.call('GET', '/members/current/permissions', uid: 'nina'),
        ))['role'],
        'receptionist',
      );
      expect(
        h.store.docs.values.any(
          (d) =>
              d['action'] == 'member.role_changed' &&
              (d['before'] as Map?)?['role'] == 'nurse',
        ),
        isTrue,
      );
      expect(
        (await h.call(
          'PATCH',
          '/members/nina/role',
          uid: 'owner',
          body: {'role': 'receptionist'},
        )).statusCode,
        409,
      );
    });

    test(
      'only an owner can create admins; admins manage ordinary roles',
      () async {
        h.member('adm', tid, 'clinic_admin');
        expect(
          (await h.call(
            'PATCH',
            '/members/nina/role',
            uid: 'adm',
            body: {'role': 'clinic_admin'},
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'PATCH',
            '/members/nina/role',
            uid: 'adm',
            body: {'role': 'accountant'},
          )).statusCode,
          200,
        );
        expect(
          (await h.call(
            'PATCH',
            '/members/nina/role',
            uid: 'owner',
            body: {'role': 'clinic_admin'},
          )).statusCode,
          200,
        );
        // an admin cannot touch another admin or the owner
        h.member('adm2', tid, 'clinic_admin');
        expect(
          (await h.call(
            'PATCH',
            '/members/adm2/role',
            uid: 'adm',
            body: {'role': 'nurse'},
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'PATCH',
            '/members/owner/role',
            uid: 'adm',
            body: {'role': 'nurse'},
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'PATCH',
            '/members/owner/branches',
            uid: 'adm',
            body: {
              'branchIds': [b1],
            },
          )).statusCode,
          403,
        );
      },
    );

    test(
      'nobody can assign platform roles or permissions through the clinic API',
      () async {
        for (final role in [
          'super_admin',
          'platform_support_admin',
          'clinic_owner',
          'wizard',
        ]) {
          expect(
            (await h.call(
              'PATCH',
              '/members/nina/role',
              uid: 'owner',
              body: {'role': role},
            )).statusCode,
            422,
            reason: role,
          );
        }
        for (final extra in [
          {
            'permissions': ['platform.tenants.manage'],
          },
          {'platformRole': 'super_admin'},
          {
            'permissionOverrides': {'x': true},
          },
        ]) {
          expect(
            (await h.call(
              'PATCH',
              '/members/nina/role',
              uid: 'owner',
              body: {'role': 'nurse', ...extra},
            )).statusCode,
            422,
            reason: '$extra',
          );
        }
        expect(h.store.docs['platform_users/nina']!['platformRole'], isNull);
      },
    );

    test(
      'doctors, nurses and receptionists cannot grant themselves anything',
      () async {
        for (final role in [
          'doctor',
          'receptionist',
          'nurse',
          'accountant',
          'lab_technician',
          'pharmacist',
        ]) {
          h.member('u_$role', tid, role);
          expect(
            (await h.call(
              'PATCH',
              '/members/u_$role/role',
              uid: 'u_$role',
              body: {'role': 'clinic_admin'},
            )).statusCode,
            403,
            reason: role,
          );
          expect(
            (await h.call(
              'PATCH',
              '/members/nina/role',
              uid: 'u_$role',
              body: {'role': 'clinic_admin'},
            )).statusCode,
            403,
            reason: role,
          );
          expect(
            (await h.call(
              'PATCH',
              '/members/u_$role/branches',
              uid: 'u_$role',
              body: {'allBranches': true},
            )).statusCode,
            403,
            reason: role,
          );
          expect(
            (await h.call(
              'PATCH',
              '/clinics/current/settings',
              uid: 'u_$role',
              body: {'timezone': 'Asia/Kolkata'},
            )).statusCode,
            403,
            reason: role,
          );
          expect(
            (await h.call(
              'POST',
              '/staff',
              uid: 'u_$role',
              body: staffBody(email: '$role@x.co', branchIds: [b1]),
            )).statusCode,
            403,
            reason: role,
          );
          expect(
            (await h.call(
              'POST',
              '/invitations',
              uid: 'u_$role',
              body: {'staffId': nurseStaff},
            )).statusCode,
            403,
            reason: role,
          );
        }
      },
    );

    test(
      'branch access can be reassigned within the actor\'s own authority',
      () async {
        final r = await h.okData(
          h.call(
            'PATCH',
            '/members/nina/branches',
            uid: 'owner',
            body: {
              'branchIds': [b1, b2],
            },
          ),
        );
        expect(r['branchIds'], [b1, b2]);
        expect(h.store.docs['tenants/$tid/staff/$nurseStaff']!['branchIds'], [
          b1,
          b2,
        ]);
        final all = await h.okData(
          h.call(
            'PATCH',
            '/members/nina/branches',
            uid: 'owner',
            body: {'allBranches': true},
          ),
        );
        expect(all['allBranches'], true);
        expect(all['branchIds'], isEmpty);
        for (final bad in [
          {'branchIds': <String>[]},
          <String, Object?>{},
          {
            'allBranches': true,
            'branchIds': [b1],
          },
          {
            'branchIds': ['br_missing'],
          },
          {
            'tenantId': 'x',
            'branchIds': [b1],
          },
        ]) {
          final code = (await h.call(
            'PATCH',
            '/members/nina/branches',
            uid: 'owner',
            body: bad,
          )).statusCode;
          expect(code, anyOf(404, 422), reason: '$bad');
        }
      },
    );

    test(
      'a branch-scoped admin cannot widen scope or touch people outside it',
      () async {
        h.member(
          'scoped',
          tid,
          'clinic_admin',
          allBranches: false,
          branchIds: [b1],
        );
        // nina belongs to b1 only → manageable
        expect(
          (await h.call(
            'PATCH',
            '/members/nina/branches',
            uid: 'scoped',
            body: {'allBranches': true},
          )).statusCode,
          403,
          reason: 'cannot grant all-branch access',
        );
        expect(
          (await h.call(
            'PATCH',
            '/members/nina/branches',
            uid: 'scoped',
            body: {
              'branchIds': [b1, b2],
            },
          )).statusCode,
          404,
          reason: 'cannot grant branches they do not have',
        );
        expect(
          (await h.call(
            'PATCH',
            '/members/nina/role',
            uid: 'scoped',
            body: {'role': 'accountant'},
          )).statusCode,
          200,
        );
        // a member who also works in b2 is not fully inside their scope
        h.member('wide', tid, 'nurse', allBranches: false, branchIds: [b1, b2]);
        expect(
          (await h.call(
            'PATCH',
            '/members/wide/role',
            uid: 'scoped',
            body: {'role': 'pharmacist'},
          )).statusCode,
          403,
        );
        h.member(
          'elsewhere',
          tid,
          'nurse',
          allBranches: false,
          branchIds: [b2],
        );
        expect(
          (await h.call(
            'PATCH',
            '/members/elsewhere/role',
            uid: 'scoped',
            body: {'role': 'pharmacist'},
          )).statusCode,
          404,
        );
        expect(
          (await h.list(
            await h.call('GET', '/members', uid: 'scoped'),
          )).cast<Map<String, Object?>>().map((m) => m['memberId']),
          isNot(contains('elsewhere')),
        );
      },
    );

    test(
      'the owner cannot be demoted, deactivated or re-scoped — the last owner is protected',
      () async {
        expect(
          (await h.call(
            'PATCH',
            '/members/owner/role',
            uid: 'owner',
            body: {'role': 'nurse'},
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'PATCH',
            '/members/owner/branches',
            uid: 'owner',
            body: {
              'branchIds': [b1],
            },
          )).statusCode,
          403,
        );
        h.member('adm', tid, 'clinic_admin');
        // staff-status endpoints cannot reach the owner (no staff profile exists for them)
        expect(
          (await h.call(
            'POST',
            '/staff/stf_owner/deactivate',
            uid: 'adm',
          )).statusCode,
          404,
        );
        expect(
          h.store.docs['tenants/$tid/members/owner']!['role'],
          'clinic_owner',
        );
        expect(h.store.docs['tenants/$tid/members/owner']!['status'], 'active');
      },
    );

    test('member list shows names and flags the caller', () async {
      final rows = (await h.list(
        await h.call('GET', '/members', uid: 'owner'),
      )).cast<Map<String, Object?>>();
      expect(rows.map((r) => r['memberId']), containsAll(['owner', 'nina']));
      expect(rows.firstWhere((r) => r['memberId'] == 'owner')['isYou'], true);
      expect((await h.call('GET', '/members', uid: 'nina')).statusCode, 403);
    });
  });

  group('doctor login association', () {
    late String docId;
    setUp(() async {
      docId =
          (await h.okData(
                h.call(
                  'POST',
                  '/doctors',
                  uid: 'owner',
                  body: doctorBody(extra: {'email': 'asha@example.test'}),
                ),
                status: 201,
              ))['doctorId']!
              as String;
    });

    test(
      'needs a branch assignment first; invitation goes to the profile e-mail only',
      () async {
        expect(
          (await h.call(
            'POST',
            '/invitations',
            uid: 'owner',
            body: {'doctorId': docId},
          )).statusCode,
          409,
        );
        await h.call(
          'POST',
          '/doctors/$docId/branches',
          uid: 'owner',
          body: {'branchId': b1},
        );
        final inv = await h.okData(
          h.call(
            'POST',
            '/invitations',
            uid: 'owner',
            body: {'doctorId': docId},
          ),
          status: 201,
        );
        expect(inv['email'], 'asha@example.test');
        expect(inv['role'], 'doctor');
        expect(
          h.store.docs['tenants/$tid/doctors/$docId']!['accountStatus'],
          'invited',
        );
        expect(
          (await h.call(
            'POST',
            '/invitations',
            uid: 'owner',
            body: {'doctorId': docId, 'email': 'attacker@evil.co'},
          )).statusCode,
          422,
          reason: 'admins cannot aim the invitation elsewhere',
        );
        expect(
          (await h.call(
            'POST',
            '/invitations',
            uid: 'owner',
            body: {'doctorId': docId},
          )).statusCode,
          409,
        );
      },
    );

    test(
      'only the real doctor can link; admins cannot attach arbitrary accounts',
      () async {
        await h.call(
          'POST',
          '/doctors/$docId/branches',
          uid: 'owner',
          body: {'branchId': b1},
        );
        final token =
            (await h.okData(
                  h.call(
                    'POST',
                    '/invitations',
                    uid: 'owner',
                    body: {'doctorId': docId},
                  ),
                  status: 201,
                ))['inviteToken']!
                as String;
        expect(
          (await h.call(
            'PATCH',
            '/doctors/$docId',
            uid: 'owner',
            body: {'uid': 'attacker'},
          )).statusCode,
          422,
        );
        h.user('attacker');
        expect(await accept('attacker', token), 400);
        expect(h.store.docs['tenants/$tid/doctors/$docId']!['uid'], isNull);
        h.user('asha');
        expect(await accept('asha', token), 200);
        expect(h.store.docs['tenants/$tid/doctors/$docId']!['uid'], 'asha');
        expect(
          h.store.docs['tenants/$tid/doctors/$docId']!['accountStatus'],
          'linked',
        );
        final m = h.store.docs['tenants/$tid/members/asha']!;
        expect(m['role'], 'doctor');
        expect(m['doctorId'], docId);
        expect(m['branchIds'], [b1]);
      },
    );

    test('doctor branch assignments keep the linked login in step', () async {
      await h.call(
        'POST',
        '/doctors/$docId/branches',
        uid: 'owner',
        body: {'branchId': b1},
      );
      final token =
          (await h.okData(
                h.call(
                  'POST',
                  '/invitations',
                  uid: 'owner',
                  body: {'doctorId': docId},
                ),
                status: 201,
              ))['inviteToken']!
              as String;
      h.user('asha');
      await accept('asha', token);
      await h.call(
        'POST',
        '/doctors/$docId/branches',
        uid: 'owner',
        body: {'branchId': b2},
      );
      expect(
        h.store.docs['tenants/$tid/members/asha']!['branchIds'],
        containsAll([b1, b2]),
      );
      await h.call('DELETE', '/doctors/$docId/branches/$b1', uid: 'owner');
      expect(h.store.docs['tenants/$tid/members/asha']!['branchIds'], [b2]);
      expect(
        (await h.call(
          'PATCH',
          '/members/asha/branches',
          uid: 'owner',
          body: {
            'branchIds': [b1],
          },
        )).statusCode,
        409,
        reason: 'follows assignments',
      );
    });

    test('revoking a doctor invitation leaves the profile untouched', () async {
      await h.call(
        'POST',
        '/doctors/$docId/branches',
        uid: 'owner',
        body: {'branchId': b1},
      );
      final inv = await h.okData(
        h.call('POST', '/invitations', uid: 'owner', body: {'doctorId': docId}),
        status: 201,
      );
      await h.okData(
        h.call(
          'POST',
          '/invitations/${inv['invitationId']}/revoke',
          uid: 'owner',
        ),
      );
      expect(
        h.store.docs['tenants/$tid/doctors/$docId']!['accountStatus'],
        'none',
      );
      expect(h.store.docs['tenants/$tid/doctors/$docId']!['status'], 'active');
    });
  });

  group('tenant isolation', () {
    test(
      'Clinic B cannot see or act on Clinic A staff, invitations or members',
      () async {
        final (sid, token) = await invited('nina@example.test');
        h.user('nina');
        await accept('nina', token);
        await h.createClinic(
          'ownerB',
          name: 'Clinic B',
          city: 'Mumbai',
          pin: '400001',
        );
        expect(
          await h.list(await h.call('GET', '/staff', uid: 'ownerB')),
          isEmpty,
        );
        expect(
          await h.list(await h.call('GET', '/members', uid: 'ownerB')),
          hasLength(1),
        );
        expect(
          (await h.call('GET', '/staff/$sid', uid: 'ownerB')).statusCode,
          404,
        );
        expect(
          (await h.call(
            'PATCH',
            '/staff/$sid',
            uid: 'ownerB',
            body: {'department': 'x'},
          )).statusCode,
          404,
        );
        expect(
          (await h.call(
            'POST',
            '/staff/$sid/deactivate',
            uid: 'ownerB',
          )).statusCode,
          404,
        );
        expect(
          (await h.call(
            'POST',
            '/staff/$sid/invite',
            uid: 'ownerB',
          )).statusCode,
          404,
        );
        expect(
          (await h.call(
            'PATCH',
            '/members/nina/role',
            uid: 'ownerB',
            body: {'role': 'accountant'},
          )).statusCode,
          404,
        );
        expect(
          (await h.call(
            'PATCH',
            '/members/nina/branches',
            uid: 'ownerB',
            body: {'allBranches': true},
          )).statusCode,
          404,
        );
        expect(
          (await h.call(
            'GET',
            '/staff/$sid',
            uid: 'ownerB',
            headers: {'x-tenant-id': tid},
          )).statusCode,
          403,
        );
        expect(h.store.docs['tenants/$tid/members/nina']!['role'], 'nurse');
      },
    );

    test(
      'suspended tenants cannot administer anything; past-due is read-only',
      () async {
        final (sid, _) = await invited('nina@example.test');
        final subId =
            h.store.docs['tenants/$tid']!['subscriptionId']! as String;
        await h.call(
          'POST',
          '/platform/subscriptions/$subId/mark-past-due',
          uid: 'root',
        );
        expect((await h.call('GET', '/staff', uid: 'owner')).statusCode, 200);
        expect(
          (await h.call('POST', '/staff/$sid/invite', uid: 'owner')).statusCode,
          403,
        );
        expect(
          (await h.call(
            'POST',
            '/staff',
            uid: 'owner',
            body: staffBody(email: 'x@example.test', branchIds: [b1]),
          )).statusCode,
          403,
        );
        await h.call(
          'POST',
          '/platform/tenants/$tid/suspend',
          uid: 'root',
          body: {'reason': 'Policy review'},
        );
        expect((await h.call('GET', '/staff', uid: 'owner')).statusCode, 403);
      },
    );
  });

  group('audit and secrecy', () {
    test(
      'every sensitive action is audited with actor and tenant; secrets never reach logs',
      () async {
        final (sid, token) = await invited('nina@example.test');
        h.user('nina');
        await accept('nina', token);
        await h.call(
          'PATCH',
          '/members/nina/role',
          uid: 'owner',
          body: {'role': 'accountant'},
        );
        await h.call('POST', '/staff/$sid/deactivate', uid: 'owner');
        final actions = h.store.docs.values
            .where((d) => d['tenantId'] == tid)
            .map((d) => d['action'])
            .toSet();
        expect(
          actions,
          containsAll([
            'staff.created',
            'invitation.created',
            'invitation.accepted',
            'member.role_changed',
            'staff.inactive',
            'branch.created',
          ]),
        );
        final entry = h.store.docs.values.firstWhere(
          (d) => d['action'] == 'member.role_changed',
        );
        expect(entry['actorUid'], 'owner');
        expect(entry['tenantId'], tid);
        expect(entry['requestId'], isNotNull);
        final logs = h.logs.join('\n');
        expect(logs, isNot(contains(token)));
        expect(logs, isNot(contains('nina@example.test')));
        expect(
          h.store.docs.values.every((d) => !d.values.any((v) => v == token)),
          isTrue,
        );
      },
    );
  });
}
