import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/platform_http_fixtures.dart';

void main() {
  late PlatformHarness h;
  late String tid;

  Future<Map<String, Object?>> mk(
    String uid,
    Map<String, Object?> body, {
    int status = 201,
  }) => h.okData(
    h.call('POST', '/branches', uid: uid, body: body),
    status: status,
  );

  setUp(() async {
    h = PlatformHarness();
    h.user('root', role: PlatformRole.superAdmin);
    tid = await h.createClinic('owner', maxBranches: 2);
  });

  group('create / read / update', () {
    test(
      'owner creates a branch: backend id, tenant stamped, audit written',
      () async {
        final b = await mk('owner', branchBody());
        expect(b['branchId'], startsWith('br_'));
        expect(b['tenantId'], tid);
        expect(b['status'], 'active');
        expect(b['createdBy'], 'owner');
        expect(
          b.containsKey('seatSlot'),
          isFalse,
          reason: 'internal fields are not exposed',
        );
        expect(
          h.store.docs.values.any(
            (d) => d['action'] == 'branch.created' && d['tenantId'] == tid,
          ),
          isTrue,
        );
      },
    );

    test('client cannot choose id, tenant, status or creator', () async {
      for (final extra in [
        {'branchId': 'br_custom'},
        {'tenantId': 'other'},
        {'status': 'inactive'},
        {'createdBy': 'x'},
        {'seatSlot': 9},
      ]) {
        final r = await h.call(
          'POST',
          '/branches',
          uid: 'owner',
          body: {...branchBody(), ...extra},
        );
        expect(r.statusCode, 422, reason: '$extra');
      }
    });

    test(
      'validation: required fields, code format, phone, PIN, type',
      () async {
        for (final bad in [
          {...branchBody(), 'name': 'x'},
          {...branchBody(), 'code': 'a b'},
          {...branchBody(), 'phone': '12'},
          {...branchBody(), 'type': 'castle'},
          {...branchBody()}..remove('address'),
          {
            ...branchBody(),
            'weeklyHours': {'1': day('10:00', '10:00')},
          },
        ]) {
          expect(
            (await h.call(
              'POST',
              '/branches',
              uid: 'owner',
              body: bad,
            )).statusCode,
            422,
            reason: '$bad',
          );
        }
      },
    );

    test(
      'duplicate code → 409 (codes are unique per clinic, case-insensitive)',
      () async {
        await mk('owner', branchBody(code: 'MAIN'));
        expect(
          (await h.call(
            'POST',
            '/branches',
            uid: 'owner',
            body: branchBody(name: 'Second', code: 'main'),
          )).statusCode,
          409,
        );
      },
    );

    test('list, search, status filter and detail', () async {
      final a = await mk('owner', branchBody(name: 'Central', code: 'CEN'));
      await mk('owner', branchBody(name: 'North Wing', code: 'NOR'));
      expect(
        await h.list(await h.call('GET', '/branches', uid: 'owner')),
        hasLength(2),
      );
      expect(
        await h.list(await h.call('GET', '/branches?q=north', uid: 'owner')),
        hasLength(1),
      );
      expect(
        await h.list(
          await h.call('GET', '/branches?status=inactive', uid: 'owner'),
        ),
        isEmpty,
      );
      expect(
        (await h.call(
          'GET',
          '/branches?status=weird',
          uid: 'owner',
        )).statusCode,
        400,
      );
      final d = await h.okData(
        h.call('GET', '/branches/${a['branchId']}', uid: 'owner'),
      );
      expect(d['name'], 'Central');
      expect(d['doctors'], isEmpty);
    });

    test('update changes permitted fields only; code is immutable', () async {
      final b = await mk('owner', branchBody());
      final id = b['branchId']! as String;
      final u = await h.okData(
        h.call(
          'PATCH',
          '/branches/$id',
          uid: 'owner',
          body: {
            'name': 'Main Branch (Pune)',
            'weeklyHours': {'1': day('08:00', '16:00')},
          },
        ),
      );
      expect(u['name'], 'Main Branch (Pune)');
      expect((u['weeklyHours']! as Map)['1'], isNotNull);
      expect(
        (await h.call(
          'PATCH',
          '/branches/$id',
          uid: 'owner',
          body: {'code': 'NEW'},
        )).statusCode,
        422,
      );
      expect(
        (await h.call(
          'PATCH',
          '/branches/$id',
          uid: 'owner',
          body: {'status': 'inactive'},
        )).statusCode,
        422,
      );
      expect(
        (await h.call(
          'PATCH',
          '/branches/$id',
          uid: 'owner',
          body: {'tenantId': 'x'},
        )).statusCode,
        422,
      );
      expect(
        (await h.call(
          'PATCH',
          '/branches/$id',
          uid: 'owner',
          body: <String, Object?>{},
        )).statusCode,
        400,
      );
      final reset = await h.okData(
        h.call(
          'PATCH',
          '/branches/$id',
          uid: 'owner',
          body: {'weeklyHours': null},
        ),
      );
      expect(
        reset['weeklyHours'],
        isNull,
        reason: 'null = inherit clinic hours',
      );
    });
  });

  group('subscription limits and entitlements', () {
    test('max_branches is enforced', () async {
      await mk('owner', branchBody(name: 'One', code: 'ONE'));
      await mk('owner', branchBody(name: 'Two', code: 'TWO'));
      final r = await h.call(
        'POST',
        '/branches',
        uid: 'owner',
        body: branchBody(name: 'Three', code: 'THR'),
      );
      expect(r.statusCode, 403);
      expect(await r.readAsString(), contains('limit'));
    });

    test('concurrent creates cannot exceed the limit', () async {
      final results = await Future.wait([
        for (var i = 0; i < 6; i++)
          h.call(
            'POST',
            '/branches',
            uid: 'owner',
            body: branchBody(name: 'Branch $i', code: 'B$i'),
          ),
      ]);
      expect(results.where((r) => r.statusCode == 201), hasLength(2));
      expect(
        results
            .where((r) => r.statusCode != 201)
            .every((r) => r.statusCode == 403),
        isTrue,
      );
      expect(
        h.store.docs.keys.where(
          (k) => RegExp(r'^tenants/[^/]+/branches/').hasMatch(k),
        ),
        hasLength(2),
      );
      expect(
        h.store.docs.keys.where((k) => k.contains('/seats/branches_')),
        hasLength(2),
      );
    });

    test('the second branch needs the multiple_branches feature', () async {
      final single = await h.createClinic(
        'solo',
        name: 'Solo Clinic',
        city: 'Nashik',
        pin: '422001',
        multipleBranches: false,
      );
      await mk('solo', branchBody(name: 'Only', code: 'ONLY'));
      expect(
        (await h.call(
          'POST',
          '/branches',
          uid: 'solo',
          body: branchBody(name: 'Extra', code: 'EXT'),
        )).statusCode,
        403,
      );
      expect(single, isNot(tid));
    });

    test('unlimited plans need no seats', () async {
      await h.createClinic(
        'big',
        name: 'Big Clinic',
        city: 'Delhi',
        pin: '110001',
        maxBranches: null,
      );
      for (var i = 0; i < 4; i++) {
        await mk('big', branchBody(name: 'Br $i', code: 'U$i'));
      }
      expect(
        h.store.docs.keys.where((k) => k.contains('/seats/branches_')),
        isEmpty,
      );
    });

    test(
      'deactivating frees a seat; activating needs a free seat again',
      () async {
        final a = await mk('owner', branchBody(name: 'One', code: 'ONE'));
        final b = await mk('owner', branchBody(name: 'Two', code: 'TWO'));
        await h.okData(
          h.call('POST', '/branches/${b['branchId']}/deactivate', uid: 'owner'),
        );
        final c = await mk('owner', branchBody(name: 'Three', code: 'THR'));
        expect(
          (await h.call(
            'POST',
            '/branches/${b['branchId']}/activate',
            uid: 'owner',
          )).statusCode,
          403,
          reason: 'no seat left',
        );
        await h.okData(
          h.call('POST', '/branches/${a['branchId']}/deactivate', uid: 'owner'),
        );
        final re = await h.okData(
          h.call('POST', '/branches/${b['branchId']}/activate', uid: 'owner'),
        );
        expect(re['status'], 'active');
        expect(c['status'], 'active');
      },
    );

    test('suspended or expired tenants cannot create branches', () async {
      await h.call(
        'POST',
        '/platform/tenants/$tid/suspend',
        uid: 'root',
        body: {'reason': 'Policy review'},
      );
      expect(
        (await h.call(
          'POST',
          '/branches',
          uid: 'owner',
          body: branchBody(),
        )).statusCode,
        403,
      );
    });
  });

  group('deactivation rules', () {
    test('the last active branch cannot be deactivated', () async {
      final a = await mk('owner', branchBody(name: 'One', code: 'ONE'));
      expect(
        (await h.call(
          'POST',
          '/branches/${a['branchId']}/deactivate',
          uid: 'owner',
        )).statusCode,
        409,
      );
    });

    test(
      'deactivation keeps the record and its history; no delete endpoint',
      () async {
        final a = await mk('owner', branchBody(name: 'One', code: 'ONE'));
        final b = await mk('owner', branchBody(name: 'Two', code: 'TWO'));
        final id = a['branchId']! as String;
        final d = await h.okData(
          h.call('POST', '/branches/$id/deactivate', uid: 'owner'),
        );
        expect(d['status'], 'inactive');
        expect(h.store.docs['tenants/$tid/branches/$id'], isNotNull);
        expect(
          (await h.call('DELETE', '/branches/$id', uid: 'owner')).statusCode,
          anyOf(404, 405),
        );
        expect(
          (await h.call(
            'POST',
            '/branches/$id/deactivate',
            uid: 'owner',
          )).statusCode,
          409,
        );
        expect(b['status'], 'active');
        final actions = h.store.docs.values.map((x) => x['action']).toSet();
        expect(actions, containsAll(['branch.created', 'branch.deactivated']));
      },
    );
  });

  group('authorization and isolation', () {
    test(
      'role permissions: receptionist can view but not create/update/deactivate',
      () async {
        final b = await mk('owner', branchBody());
        h.member('rec', tid, 'receptionist');
        expect((await h.call('GET', '/branches', uid: 'rec')).statusCode, 200);
        expect(
          (await h.call(
            'POST',
            '/branches',
            uid: 'rec',
            body: branchBody(name: 'Rogue', code: 'RG'),
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'PATCH',
            '/branches/${b['branchId']}',
            uid: 'rec',
            body: {'name': 'Hacked'},
          )).statusCode,
          403,
        );
        expect(
          (await h.call(
            'POST',
            '/branches/${b['branchId']}/deactivate',
            uid: 'rec',
          )).statusCode,
          403,
        );
      },
    );

    test('clinic admin can manage branches', () async {
      h.member('adm', tid, 'clinic_admin');
      expect(
        (await h.call(
          'POST',
          '/branches',
          uid: 'adm',
          body: branchBody(name: 'By Admin', code: 'ADM'),
        )).statusCode,
        201,
      );
    });

    test('Clinic A cannot read or modify Clinic B branches', () async {
      final a = await mk('owner', branchBody(name: 'A Branch', code: 'AAA'));
      await h.createClinic(
        'ownerB',
        name: 'Clinic B',
        city: 'Mumbai',
        pin: '400001',
      );
      final b = await mk('ownerB', branchBody(name: 'B Branch', code: 'BBB'));
      // B lists only its own
      final list = (await h.list(
        await h.call('GET', '/branches', uid: 'ownerB'),
      )).cast<Map<String, Object?>>();
      expect(list.map((x) => x['name']), ['B Branch']);
      // B cannot see/modify A's branch by id (existence hidden)
      final aid = a['branchId']! as String;
      expect(
        (await h.call('GET', '/branches/$aid', uid: 'ownerB')).statusCode,
        404,
      );
      expect(
        (await h.call(
          'PATCH',
          '/branches/$aid',
          uid: 'ownerB',
          body: {'name': 'Pwned'},
        )).statusCode,
        404,
      );
      expect(
        (await h.call(
          'POST',
          '/branches/$aid/deactivate',
          uid: 'ownerB',
        )).statusCode,
        404,
      );
      expect(h.store.docs['tenants/$tid/branches/$aid']!['name'], 'A Branch');
      // spoofing the tenant via header/query/body does nothing
      expect(
        (await h.call(
          'GET',
          '/branches/$aid',
          uid: 'ownerB',
          headers: {'x-tenant-id': tid},
        )).statusCode,
        403,
      );
      expect(
        (await h.call(
          'GET',
          '/branches?tenantId=$tid',
          uid: 'ownerB',
        )).statusCode,
        200,
      );
      expect(b['tenantId'], isNot(tid));
    });

    test('branch-scoped users see and change only their branches', () async {
      final a = await mk('owner', branchBody(name: 'One', code: 'ONE'));
      final b = await mk('owner', branchBody(name: 'Two', code: 'TWO'));
      h.member(
        'scoped',
        tid,
        'clinic_admin',
        allBranches: false,
        branchIds: [a['branchId']! as String],
      );
      final list = (await h.list(
        await h.call('GET', '/branches', uid: 'scoped'),
      )).cast<Map<String, Object?>>();
      expect(list.map((x) => x['name']), ['One']);
      final bid = b['branchId']! as String;
      expect(
        (await h.call('GET', '/branches/$bid', uid: 'scoped')).statusCode,
        404,
      );
      expect(
        (await h.call(
          'PATCH',
          '/branches/$bid',
          uid: 'scoped',
          body: {'name': 'Mine now'},
        )).statusCode,
        404,
      );
      expect(
        (await h.call(
          'POST',
          '/branches/$bid/deactivate',
          uid: 'scoped',
        )).statusCode,
        404,
      );
      expect(
        (await h.call(
          'PATCH',
          '/branches/${a['branchId']}',
          uid: 'scoped',
          body: {'name': 'One (renamed)'},
        )).statusCode,
        200,
      );
      // creating clinic-wide branches needs all-branch access
      expect(
        (await h.call(
          'POST',
          '/branches',
          uid: 'scoped',
          body: branchBody(name: 'New', code: 'NEW'),
        )).statusCode,
        403,
      );
      // request parameters cannot widen the scope
      expect(
        await h.list(
          await h.call('GET', '/branches?branchId=$bid&q=two', uid: 'scoped'),
        ),
        isEmpty,
      );
    });

    test('malformed ids are not found', () async {
      expect(
        (await h.call('GET', '/branches/..%2fx', uid: 'owner')).statusCode,
        404,
      );
      expect(
        (await h.call('GET', '/branches/x', uid: 'owner')).statusCode,
        404,
      );
    });
  });
}
