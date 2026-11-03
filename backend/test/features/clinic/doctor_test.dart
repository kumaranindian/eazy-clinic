import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/platform_http_fixtures.dart';

Map<String, Object?> doctorBody({
  String name = 'Dr Asha Rao',
  String reg = 'MH/2010/12345',
  String specialty = 'Paediatrics',
  Object? extra,
}) => {
  'fullName': name,
  'email': 'asha@gv.test',
  'phone': '9876543211',
  'designation': 'Consultant',
  'qualifications': ['MBBS', 'MD Paediatrics'],
  'registrationNumber': reg,
  'registrationCouncil': 'Maharashtra Medical Council',
  'specialty': specialty,
  'yearsOfExperience': 12,
  'languages': ['English', 'Hindi'],
  'consultationFeeMinor': 50000,
  'dateOfBirth': '1982-04-01',
  if (extra is Map<String, Object?>) ...extra,
};

void main() {
  late PlatformHarness h;
  late String tid;
  late String b1;
  late String b2;

  Future<Map<String, Object?>> mk(
    String uid,
    Map<String, Object?> body, {
    int status = 201,
  }) => h.okData(
    h.call('POST', '/doctors', uid: uid, body: body),
    status: status,
  );

  setUp(() async {
    h = PlatformHarness();
    h.user('root', role: PlatformRole.superAdmin);
    tid = await h.createClinic('owner', maxDoctors: 2);
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

  group('profiles', () {
    test('owner creates a doctor; one profile, no login yet', () async {
      final d = await mk('owner', doctorBody());
      expect(d['doctorId'], startsWith('doc_'));
      expect(d['tenantId'], tid);
      expect(d['status'], 'active');
      expect(d['uid'], isNull);
      expect(d['accountStatus'], 'none');
      expect(d.containsKey('seatSlot'), isFalse);
      expect(d.containsKey('fullNameLower'), isFalse);
      expect(
        h.store.docs.values.any((x) => x['action'] == 'doctor.created'),
        isTrue,
      );
    });

    test(
      'client cannot set identity, status, login or tenant fields',
      () async {
        for (final extra in [
          {'doctorId': 'doc_x'},
          {'tenantId': 'other'},
          {'status': 'inactive'},
          {'uid': 'attacker'},
          {'accountStatus': 'linked'},
          {'role': 'clinic_admin'},
          {'createdBy': 'x'},
          {
            'permissions': ['*'],
          },
        ]) {
          final r = await h.call(
            'POST',
            '/doctors',
            uid: 'owner',
            body: doctorBody(extra: extra),
          );
          expect(r.statusCode, 422, reason: '$extra');
        }
      },
    );

    test('validation', () async {
      for (final bad in [
        doctorBody(name: 'x'),
        doctorBody(extra: {'email': 'nope'}),
        doctorBody(extra: {'phone': '123'}),
        doctorBody(extra: {'gender': 'robot'}),
        doctorBody(extra: {'dateOfBirth': '1982-13-40'}),
        doctorBody(extra: {'yearsOfExperience': 99}),
        doctorBody(extra: {'consultationFeeMinor': -1}),
        doctorBody(extra: {'qualifications': List.filled(11, 'MBBS')}),
        doctorBody(reg: '!!'),
        {...doctorBody()}..remove('registrationNumber'),
      ]) {
        expect(
          (await h.call(
            'POST',
            '/doctors',
            uid: 'owner',
            body: bad,
          )).statusCode,
          422,
          reason: '$bad',
        );
      }
    });

    test(
      'registration number is unique per clinic (format-insensitive) and policy can relax it',
      () async {
        await mk('owner', doctorBody());
        expect(
          (await h.call(
            'POST',
            '/doctors',
            uid: 'owner',
            body: doctorBody(name: 'Dr Other', reg: 'mh 2010 12345'),
          )).statusCode,
          409,
        );
        await h.okData(
          h.call(
            'PATCH',
            '/clinics/current/settings',
            uid: 'owner',
            body: {'doctorRegistrationRequired': false},
          ),
        );
        final d = await mk(
          'owner',
          {...doctorBody(name: 'Dr No Reg')}..remove('registrationNumber'),
        );
        expect(d['registrationNumber'], isNull);
      },
    );

    test(
      'the same registration number is allowed in a different clinic',
      () async {
        await mk('owner', doctorBody());
        await h.createClinic(
          'owner2',
          name: 'Other',
          city: 'Mumbai',
          pin: '400001',
        );
        expect(
          (await h.call(
            'POST',
            '/doctors',
            uid: 'owner2',
            body: doctorBody(),
          )).statusCode,
          201,
        );
      },
    );

    test('update, search, filter, detail', () async {
      final a = await mk('owner', doctorBody());
      await mk(
        'owner',
        doctorBody(
          name: 'Dr Bose',
          reg: 'WB/2001/777',
          specialty: 'Dermatology',
        ),
      );
      final id = a['doctorId']! as String;
      final u = await h.okData(
        h.call(
          'PATCH',
          '/doctors/$id',
          uid: 'owner',
          body: {
            'designation': 'Senior Consultant',
            'registrationNumber': 'MH/2010/99999',
          },
        ),
      );
      expect(u['designation'], 'Senior Consultant');
      // old registration number is free again, new one reserved
      expect(
        (await h.call(
          'POST',
          '/doctors',
          uid: 'owner',
          body: doctorBody(name: 'Third', reg: 'MH/2010/12345'),
        )).statusCode,
        403,
        reason: 'limit of 2 reached, not a conflict',
      );
      expect(
        await h.list(await h.call('GET', '/doctors?q=dr%20a', uid: 'owner')),
        hasLength(1),
      );
      expect(
        await h.list(
          await h.call('GET', '/doctors?specialty=Dermatology', uid: 'owner'),
        ),
        hasLength(1),
      );
      expect(
        await h.list(
          await h.call('GET', '/doctors?status=inactive', uid: 'owner'),
        ),
        isEmpty,
      );
      expect(
        (await h.call('GET', '/doctors?status=weird', uid: 'owner')).statusCode,
        400,
      );
      expect(
        (await h.call(
          'PATCH',
          '/doctors/$id',
          uid: 'owner',
          body: {'uid': 'x'},
        )).statusCode,
        422,
      );
      expect(
        (await h.call(
          'PATCH',
          '/doctors/$id',
          uid: 'owner',
          body: <String, Object?>{},
        )).statusCode,
        400,
      );
    });

    test(
      'date of birth is shown only to people who maintain profiles',
      () async {
        final d = await mk('owner', doctorBody());
        h.member('rec', tid, 'receptionist');
        final asRec = await h.okData(
          h.call('GET', '/doctors/${d['doctorId']}', uid: 'rec'),
        );
        expect(asRec.containsKey('dateOfBirth'), isFalse);
        final asOwner = await h.okData(
          h.call('GET', '/doctors/${d['doctorId']}', uid: 'owner'),
        );
        expect(asOwner['dateOfBirth'], '1982-04-01');
      },
    );
  });

  group('limits and activation', () {
    test('max_doctors enforced, including concurrent creates', () async {
      final results = await Future.wait([
        for (var i = 0; i < 5; i++)
          h.call(
            'POST',
            '/doctors',
            uid: 'owner',
            body: doctorBody(name: 'Dr $i Test', reg: 'REG/$i/000'),
          ),
      ]);
      expect(results.where((r) => r.statusCode == 201), hasLength(2));
      expect(
        h.store.docs.keys.where((k) => k.contains('/seats/doctors_')),
        hasLength(2),
      );
    });

    test(
      'deactivate frees a seat; activate needs one; history stays',
      () async {
        final a = await mk(
          'owner',
          doctorBody(name: 'Dr A One', reg: 'A/1/111'),
        );
        await mk('owner', doctorBody(name: 'Dr B Two', reg: 'B/2/222'));
        final id = a['doctorId']! as String;
        await h.call(
          'POST',
          '/doctors/$id/branches',
          uid: 'owner',
          body: {'branchId': b1},
        );
        await h.okData(h.call('POST', '/doctors/$id/deactivate', uid: 'owner'));
        final c = await mk(
          'owner',
          doctorBody(name: 'Dr C Three', reg: 'C/3/333'),
        );
        expect(
          (await h.call(
            'POST',
            '/doctors/$id/activate',
            uid: 'owner',
          )).statusCode,
          403,
        );
        expect(c['status'], 'active');
        expect(h.store.docs['tenants/$tid/doctors/$id'], isNotNull);
        expect(
          (await h.call(
            'POST',
            '/doctors/$id/deactivate',
            uid: 'owner',
          )).statusCode,
          409,
        );
        expect(
          h.store.docs.values.where(
            (x) => x['doctorId'] == id && x['branchId'] == b1,
          ),
          isNotEmpty,
          reason: 'assignment history preserved',
        );
      },
    );
  });

  group('branch assignments', () {
    late String doc;
    setUp(
      () async =>
          doc = (await mk('owner', doctorBody()))['doctorId']! as String,
    );

    test('a doctor works at several branches with one profile', () async {
      final a1 = await h.okData(
        h.call(
          'POST',
          '/doctors/$doc/branches',
          uid: 'owner',
          body: {'branchId': b1, 'consultationFeeMinor': 60000},
        ),
        status: 201,
      );
      await h.okData(
        h.call(
          'POST',
          '/doctors/$doc/branches',
          uid: 'owner',
          body: {'branchId': b2},
        ),
        status: 201,
      );
      expect(a1['consultationFeeMinor'], 60000);
      expect(
        h.store.docs.keys.where(
          (k) => RegExp(r'/doctors/').hasMatch(k) && !k.contains('assign'),
        ),
        hasLength(1),
      );
      final list = (await h.list(
        await h.call('GET', '/doctors/$doc/branches', uid: 'owner'),
      )).cast<Map<String, Object?>>();
      expect(list.map((x) => x['branchName']).toSet(), {'One', 'Two'});
      final byBranch = await h.list(
        await h.call('GET', '/doctors?branchId=$b1', uid: 'owner'),
      );
      expect(byBranch, hasLength(1));
    });

    test('duplicate active assignment is refused, even concurrently', () async {
      final rs = await Future.wait([
        for (var i = 0; i < 4; i++)
          h.call(
            'POST',
            '/doctors/$doc/branches',
            uid: 'owner',
            body: {'branchId': b1},
          ),
      ]);
      expect(rs.where((r) => r.statusCode == 201), hasLength(1));
      expect(rs.where((r) => r.statusCode == 409), hasLength(3));
    });

    test(
      'ending an assignment keeps history and allows re-assigning',
      () async {
        await h.call(
          'POST',
          '/doctors/$doc/branches',
          uid: 'owner',
          body: {'branchId': b1},
        );
        expect(
          (await h.call(
            'DELETE',
            '/doctors/$doc/branches/$b1',
            uid: 'owner',
          )).statusCode,
          200,
        );
        expect(
          (await h.call(
            'DELETE',
            '/doctors/$doc/branches/$b1',
            uid: 'owner',
          )).statusCode,
          404,
        );
        await h.okData(
          h.call(
            'POST',
            '/doctors/$doc/branches',
            uid: 'owner',
            body: {'branchId': b1},
          ),
          status: 201,
        );
        final all = (await h.list(
          await h.call('GET', '/doctors/$doc/branches', uid: 'owner'),
        )).cast<Map<String, Object?>>();
        expect(all.map((x) => x['status']).toList()..sort(), [
          'active',
          'ended',
        ]);
      },
    );

    test('cross-tenant, unknown and inactive branches are refused', () async {
      await h.createClinic(
        'owner2',
        name: 'Other',
        city: 'Mumbai',
        pin: '400001',
      );
      final foreign =
          (await h.okData(
                h.call(
                  'POST',
                  '/branches',
                  uid: 'owner2',
                  body: branchBody(name: 'Foreign', code: 'FOR'),
                ),
                status: 201,
              ))['branchId']!
              as String;
      expect(
        (await h.call(
          'POST',
          '/doctors/$doc/branches',
          uid: 'owner',
          body: {'branchId': foreign},
        )).statusCode,
        404,
      );
      expect(
        (await h.call(
          'POST',
          '/doctors/$doc/branches',
          uid: 'owner',
          body: {'branchId': 'br_nonexistent'},
        )).statusCode,
        404,
      );
      await h.call('POST', '/branches/$b2/deactivate', uid: 'owner');
      expect(
        (await h.call(
          'POST',
          '/doctors/$doc/branches',
          uid: 'owner',
          body: {'branchId': b2},
        )).statusCode,
        409,
      );
      expect(
        (await h.call(
          'POST',
          '/doctors/$doc/branches',
          uid: 'owner',
          body: {
            'branchId': b1,
            'effectiveFrom': '2026-05-02',
            'effectiveTo': '2026-05-01',
          },
        )).statusCode,
        422,
      );
      expect(
        (await h.call(
          'POST',
          '/doctors/$doc/branches',
          uid: 'owner',
          body: {'branchId': b1, 'tenantId': 'x'},
        )).statusCode,
        422,
      );
    });

    test('inactive doctors cannot be assigned', () async {
      await h.call('POST', '/doctors/$doc/deactivate', uid: 'owner');
      expect(
        (await h.call(
          'POST',
          '/doctors/$doc/branches',
          uid: 'owner',
          body: {'branchId': b1},
        )).statusCode,
        409,
      );
    });
  });

  group('authorization and isolation', () {
    test('Clinic A cannot read or modify Clinic B doctors', () async {
      final a = await mk('owner', doctorBody());
      await h.createClinic(
        'ownerB',
        name: 'Clinic B',
        city: 'Mumbai',
        pin: '400001',
      );
      final id = a['doctorId']! as String;
      expect(
        (await h.call('GET', '/doctors/$id', uid: 'ownerB')).statusCode,
        404,
      );
      expect(
        (await h.call(
          'PATCH',
          '/doctors/$id',
          uid: 'ownerB',
          body: {'designation': 'x'},
        )).statusCode,
        404,
      );
      expect(
        (await h.call(
          'POST',
          '/doctors/$id/deactivate',
          uid: 'ownerB',
        )).statusCode,
        404,
      );
      expect(
        (await h.call(
          'POST',
          '/doctors/$id/branches',
          uid: 'ownerB',
          body: {'branchId': b1},
        )).statusCode,
        anyOf(404),
      );
      expect(
        await h.list(await h.call('GET', '/doctors', uid: 'ownerB')),
        isEmpty,
      );
    });

    test(
      'roles: receptionist views only; doctor cannot edit or assign themselves',
      () async {
        final d = await mk('owner', doctorBody());
        final id = d['doctorId']! as String;
        h.member('rec', tid, 'receptionist');
        h.member('docUser', tid, 'doctor');
        expect((await h.call('GET', '/doctors', uid: 'rec')).statusCode, 200);
        for (final u in ['rec', 'docUser']) {
          expect(
            (await h.call(
              'POST',
              '/doctors',
              uid: u,
              body: doctorBody(name: 'Rogue Doc', reg: 'R/1/1'),
            )).statusCode,
            403,
            reason: u,
          );
          expect(
            (await h.call(
              'PATCH',
              '/doctors/$id',
              uid: u,
              body: {'designation': 'CEO'},
            )).statusCode,
            403,
            reason: u,
          );
          expect(
            (await h.call(
              'POST',
              '/doctors/$id/deactivate',
              uid: u,
            )).statusCode,
            403,
            reason: u,
          );
          expect(
            (await h.call(
              'POST',
              '/doctors/$id/branches',
              uid: u,
              body: {'branchId': b1},
            )).statusCode,
            403,
            reason: u,
          );
        }
      },
    );

    test(
      'branch-scoped admin sees only doctors of their branches and cannot reach others',
      () async {
        final d1 = await mk(
          'owner',
          doctorBody(name: 'Dr One One', reg: 'X/1/1'),
        );
        final d2 = await mk(
          'owner',
          doctorBody(name: 'Dr Two Two', reg: 'X/2/2'),
        );
        await h.call(
          'POST',
          '/doctors/${d1['doctorId']}/branches',
          uid: 'owner',
          body: {'branchId': b1},
        );
        await h.call(
          'POST',
          '/doctors/${d2['doctorId']}/branches',
          uid: 'owner',
          body: {'branchId': b2},
        );
        h.member(
          'scoped',
          tid,
          'clinic_admin',
          allBranches: false,
          branchIds: [b1],
        );
        final names = (await h.list(
          await h.call('GET', '/doctors', uid: 'scoped'),
        )).cast<Map<String, Object?>>().map((x) => x['fullName']);
        expect(names, ['Dr One One']);
        expect(
          (await h.call(
            'GET',
            '/doctors/${d2['doctorId']}',
            uid: 'scoped',
          )).statusCode,
          404,
        );
        expect(
          (await h.call(
            'PATCH',
            '/doctors/${d2['doctorId']}',
            uid: 'scoped',
            body: {'designation': 'x'},
          )).statusCode,
          404,
        );
        expect(
          (await h.call(
            'POST',
            '/doctors/${d1['doctorId']}/branches',
            uid: 'scoped',
            body: {'branchId': b2},
          )).statusCode,
          404,
          reason: 'cannot assign into a branch outside the scope',
        );
        expect(
          (await h.call(
            'GET',
            '/doctors?branchId=$b2',
            uid: 'scoped',
          )).statusCode,
          404,
          reason: 'branchId query cannot widen scope',
        );
        expect(
          (await h.call(
            'DELETE',
            '/doctors/${d2['doctorId']}/branches/$b2',
            uid: 'scoped',
          )).statusCode,
          404,
        );
        // creating needs branches inside the scope
        expect(
          (await h.call(
            'POST',
            '/doctors',
            uid: 'scoped',
            body: doctorBody(name: 'No Branch', reg: 'N/1/1'),
          )).statusCode,
          422,
        );
        expect(
          (await h.call(
            'POST',
            '/doctors',
            uid: 'scoped',
            body: {
              ...doctorBody(name: 'Out Scope', reg: 'N/2/2'),
              'branchIds': [b2],
            },
          )).statusCode,
          404,
        );
        // free a seat so the limit does not mask the scope checks
        await h.call(
          'POST',
          '/doctors/${d2['doctorId']}/deactivate',
          uid: 'owner',
        );
        expect(
          (await h.call(
            'POST',
            '/doctors',
            uid: 'scoped',
            body: {
              ...doctorBody(name: 'In Scope', reg: 'N/3/3'),
              'branchIds': [b1],
            },
          )).statusCode,
          201,
        );
      },
    );
  });
}
