import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/patient_fixtures.dart';
import '../../support/platform_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

void main() {
  late PlatformHarness h;
  late String tid;
  late String br;

  setUp(() async {
    h = PlatformHarness();
    h.user('root', role: PlatformRole.superAdmin);
    tid = await h.createClinic('owner');
    br = await h.newBranch('owner');
    h.member('recep', tid, 'receptionist');
    h.member('doc', tid, 'doctor');
    h.member('acct', tid, 'accountant');
    h.member('admin', tid, 'clinic_admin');
  });

  group('registration', () {
    test(
      'backend assigns id, MRN and tenant; consent and audit written',
      () async {
        final p = await h.newPatient('recep', br);
        expect(p['patientId'], startsWith('pt_'));
        expect(p['mrn'], 'MRN-000001');
        expect(p['tenantId'], tid);
        expect(p['status'], 'active');
        expect(p['patientAccountId'], isNull);
        expect(p.containsKey('phoneNorm'), isFalse);
        expect(p.containsKey('seatSlot'), isFalse);
        final second = await h.newPatient(
          'recep',
          br,
          name: 'Ravi Kulkarni',
          dob: '1985-01-02',
          phone: '9876500002',
        );
        expect(second['mrn'], 'MRN-000002');
        expect(
          h.auditActions(p['patientId']! as String),
          contains('patient.created'),
        );
        final consents = h
            .docsOf('patient_consents')
            .where((c) => c['patientId'] == p['patientId']);
        expect(consents.single['type'], 'data_processing');
        expect(consents.single['status'], 'granted');
      },
    );

    test(
      'client cannot choose id, tenant, mrn, status, account or creator',
      () async {
        for (final extra in [
          {'patientId': 'pt_x'},
          {'tenantId': 'other'},
          {'mrn': 'MRN-999999'},
          {'status': 'archived'},
          {'patientAccountId': 'pa_x'},
          {'createdBy': 'x'},
        ]) {
          expect(
            await h.status(
              'POST',
              '/patients',
              uid: 'recep',
              body: patientBody(br, extra: extra),
            ),
            422,
            reason: '$extra',
          );
        }
      },
    );

    test('validation: dob, phone, name, consent, branch', () async {
      for (final bad in [
        patientBody(br, dob: '2999-01-01'),
        patientBody(br, dob: '1990-13-40'),
        patientBody(br, phone: '123'),
        patientBody(br, name: 'x'),
        patientBody(br, gender: 'robot'),
        patientBody(br, consent: {...consentBody(), 'granted': false}),
        patientBody(br, consent: {...consentBody(), 'textVersion': '0.1'}),
        {...patientBody(br)}..remove('consent'),
      ]) {
        expect(
          await h.status('POST', '/patients', uid: 'recep', body: bad),
          422,
          reason: '$bad',
        );
      }
      expect(
        await h.status(
          'POST',
          '/patients',
          uid: 'recep',
          body: patientBody('br_missing'),
        ),
        anyOf(403, 404, 422),
      );
    });

    test(
      'roles: receptionist and doctor register; accountant cannot',
      () async {
        expect(
          await h.status(
            'POST',
            '/patients',
            uid: 'doc',
            body: patientBody(br, phone: '9876500009', name: 'Doc Patient'),
          ),
          201,
        );
        expect(
          await h.status(
            'POST',
            '/patients',
            uid: 'acct',
            body: patientBody(br),
          ),
          403,
        );
        expect(await h.status('POST', '/patients', body: patientBody(br)), 401);
      },
    );

    test('a minor needs a guardian and guardian consent', () async {
      final minor = patientBody(br, name: 'Kid Patil', dob: '2018-03-03');
      expect(
        await h.status('POST', '/patients', uid: 'recep', body: minor),
        422,
      );
      final guardian = {
        'name': 'Meera Patil',
        'relationship': 'mother',
        'phone': '9876500055',
      };
      // unverified guardian cannot consent
      expect(
        await h.status(
          'POST',
          '/patients',
          uid: 'recep',
          body: patientBody(
            br,
            name: 'Kid Patil',
            dob: '2018-03-03',
            guardian: guardian,
            consent: consentBody(grantedBy: {'type': 'guardian'}),
          ),
        ),
        422,
      );
      // the patient cannot consent for themselves
      expect(
        await h.status(
          'POST',
          '/patients',
          uid: 'recep',
          body: patientBody(
            br,
            name: 'Kid Patil',
            dob: '2018-03-03',
            guardian: {
              ...guardian,
              'verificationMethod': 'government_id_sighted',
            },
            consent: consentBody(grantedBy: {'type': 'patient'}),
          ),
        ),
        422,
      );
      final ok = await h.newPatient(
        'recep',
        br,
        name: 'Kid Patil',
        dob: '2018-03-03',
        guardian: {...guardian, 'verificationMethod': 'government_id_sighted'},
        consent: consentBody(grantedBy: {'type': 'guardian'}),
      );
      expect((ok['guardian']! as Map)['verified'], true);
      final c = h.docsOf('patient_consents').single;
      expect((c['grantedBy']! as Map)['type'], 'guardian');
    });

    test('an adult cannot be registered with guardian consent', () async {
      expect(
        await h.status(
          'POST',
          '/patients',
          uid: 'recep',
          body: patientBody(
            br,
            consent: consentBody(grantedBy: {'type': 'guardian'}),
          ),
        ),
        422,
      );
    });

    test('the minor age is a clinic setting', () async {
      expect(
        await h.status(
          'PATCH',
          '/clinics/current/settings',
          uid: 'owner',
          body: {'minorAgeYears': 21},
        ),
        200,
      );
      // 19 years old is now a minor
      final y = DateTime.now().year - 19;
      expect(
        await h.status(
          'POST',
          '/patients',
          uid: 'recep',
          body: patientBody(br, dob: '$y-01-01'),
        ),
        422,
      );
    });
  });

  group('directory', () {
    late Map<String, Object?> asha;
    setUp(() async {
      asha = await h.newPatient('recep', br, email: 'asha@example.test');
      await h.newPatient(
        'recep',
        br,
        name: 'Ashok Rao',
        dob: '1970-02-02',
        phone: '9876500003',
      );
      await h.newPatient(
        'recep',
        br,
        name: 'Bhavna Shah',
        dob: '1999-09-09',
        phone: '9876500004',
      );
    });

    test('search by name prefix, MRN, phone, email and id', () async {
      Future<List<Object?>> q(String s) async => h.list(
        await h.call(
          'GET',
          '/patients?q=${Uri.encodeQueryComponent(s)}',
          uid: 'recep',
        ),
      );
      expect(await q('as'), hasLength(2));
      expect(await q('asha'), hasLength(1));
      expect(await q('MRN-000003'), hasLength(1));
      expect(await q('9876500003'), hasLength(1));
      expect(await q('asha@example.test'), hasLength(1));
      expect(await q(asha['patientId']! as String), hasLength(1));
      expect(await q('zzz'), isEmpty);
    });

    test('list is paginated, masked and free of clinical data', () async {
      final r = await h.call('GET', '/patients?limit=2', uid: 'recep');
      final body = await r.readAsString();
      expect(body, contains('"hasMore":true'));
      expect(body, isNot(contains('98765000')));
      expect(body, contains('XXXXXX000'));
      expect(body, isNot(contains('restrictedNotes')));
      expect(await h.status('GET', '/patients?limit=0', uid: 'recep'), 400);
    });

    test('filters: status, gender, branch', () async {
      expect(
        await h.list(
          await h.call('GET', '/patients?gender=male', uid: 'recep'),
        ),
        isEmpty,
      );
      expect(
        await h.list(
          await h.call('GET', '/patients?branchId=$br', uid: 'recep'),
        ),
        hasLength(3),
      );
      expect(
        await h.status('GET', '/patients?status=bogus', uid: 'recep'),
        400,
      );
    });

    test(
      'detail audits the access and hides restricted notes from receptionists',
      () async {
        final id = asha['patientId']! as String;
        await h.okData(
          h.call(
            'PATCH',
            '/patients/$id',
            uid: 'doc',
            body: {'restrictedNotes': 'Anxious about needles'},
          ),
        );
        final recep = await h.okData(
          h.call('GET', '/patients/$id', uid: 'recep'),
        );
        expect(recep.containsKey('restrictedNotes'), isFalse);
        final doc = await h.okData(h.call('GET', '/patients/$id', uid: 'doc'));
        expect(doc['restrictedNotes'], 'Anxious about needles');
        expect(h.auditActions(id), contains('patient.viewed'));
      },
    );

    test('accountants cannot read patients', () async {
      expect(await h.status('GET', '/patients', uid: 'acct'), 403);
      expect(
        await h.status('GET', '/patients/${asha['patientId']}', uid: 'acct'),
        403,
      );
    });
  });

  group('update and status', () {
    late String id;
    setUp(
      () async =>
          id = (await h.newPatient('recep', br))['patientId']! as String,
    );

    test(
      'updates demographics, keeps a revision, cannot change identity',
      () async {
        final u = await h.okData(
          h.call(
            'PATCH',
            '/patients/$id',
            uid: 'recep',
            body: {'fullName': 'Asha P. Patil', 'phone': '9876500077'},
          ),
        );
        expect(u['fullName'], 'Asha P. Patil');
        expect(h.docsOf('patient_record_revisions'), isNotEmpty);
        for (final bad in [
          {'mrn': 'MRN-1'},
          {'tenantId': 'x'},
          {'branchId': 'br_other'},
          {'patientAccountId': 'pa_x'},
          {'status': 'archived'},
        ]) {
          expect(
            await h.status('PATCH', '/patients/$id', uid: 'recep', body: bad),
            422,
            reason: '$bad',
          );
        }
        expect(
          await h.status('PATCH', '/patients/$id', uid: 'recep', body: {}),
          400,
        );
      },
    );

    test(
      'deactivate, activate, archive need the right role and a reason',
      () async {
        expect(
          await h.status(
            'POST',
            '/patients/$id/deactivate',
            uid: 'recep',
            body: {'reason': 'moved away'},
          ),
          403,
        );
        expect(
          await h.status(
            'POST',
            '/patients/$id/deactivate',
            uid: 'admin',
            body: {},
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/patients/$id/deactivate',
            uid: 'admin',
            body: {'reason': 'moved away'},
          ),
          200,
        );
        expect(
          await h.status(
            'POST',
            '/patients/$id/deactivate',
            uid: 'admin',
            body: {'reason': 'moved away'},
          ),
          409,
        );
        expect(
          await h.status('POST', '/patients/$id/activate', uid: 'admin'),
          200,
        );
        expect(
          await h.status(
            'POST',
            '/patients/$id/archive',
            uid: 'admin',
            body: {'reason': 'duplicate file'},
          ),
          200,
        );
        // archived: no changes, no reactivation, history preserved
        expect(
          await h.status(
            'PATCH',
            '/patients/$id',
            uid: 'recep',
            body: {'occupation': 'x'},
          ),
          409,
        );
        expect(
          await h.status('POST', '/patients/$id/activate', uid: 'admin'),
          409,
        );
        expect(await h.status('GET', '/patients/$id', uid: 'recep'), 200);
        expect(
          h.auditActions(id),
          containsAll([
            'patient.inactive',
            'patient.active',
            'patient.archived',
          ]),
        );
      },
    );

    test('there is no delete', () async {
      expect(
        await h.status('DELETE', '/patients/$id', uid: 'owner'),
        anyOf(404, 405),
      );
    });
  });

  group('branch and tenant isolation', () {
    late String br2;
    late String id1;
    late String id2;
    setUp(() async {
      br2 = await h.newBranch('owner', code: 'NORTH');
      h.member(
        'north',
        tid,
        'receptionist',
        allBranches: false,
        branchIds: [br2],
      );
      id1 = (await h.newPatient('owner', br))['patientId']! as String;
      id2 =
          (await h.newPatient(
                'owner',
                br2,
                name: 'Nisha Rao',
                dob: '1991-01-01',
                phone: '9876500011',
              ))['patientId']!
              as String;
    });

    test('a branch-scoped user only sees their branch', () async {
      expect(await h.status('GET', '/patients/$id2', uid: 'north'), 200);
      expect(await h.status('GET', '/patients/$id1', uid: 'north'), 404);
      expect(
        await h.status(
          'PATCH',
          '/patients/$id1',
          uid: 'north',
          body: {'occupation': 'x'},
        ),
        404,
      );
      expect(
        await h.list(await h.call('GET', '/patients', uid: 'north')),
        hasLength(1),
      );
      expect(
        await h.status('GET', '/patients?branchId=$br', uid: 'north'),
        404,
      );
      expect(
        await h.status(
          'POST',
          '/patients',
          uid: 'north',
          body: patientBody(
            br,
            name: 'Other Branch',
            phone: '9876500020',
            dob: '1980-01-01',
          ),
        ),
        404,
      );
    });

    test('clinic A cannot read clinic B patients or sub-resources', () async {
      final tidB = await h.createClinic('ownerB', name: 'Other Clinic');
      expect(tidB, isNot(tid));
      expect(await h.status('GET', '/patients/$id1', uid: 'ownerB'), 404);
      expect(
        await h.status(
          'PATCH',
          '/patients/$id1',
          uid: 'ownerB',
          body: {'occupation': 'x'},
        ),
        404,
      );
      for (final sub in [
        'medical-history',
        'allergies',
        'medications',
        'alerts',
        'consents',
        'documents',
        'emergency-contacts',
        'audit-logs',
      ]) {
        expect(
          await h.status('GET', '/patients/$id1/$sub', uid: 'ownerB'),
          404,
          reason: sub,
        );
      }
      expect(
        await h.list(await h.call('GET', '/patients', uid: 'ownerB')),
        isEmpty,
      );
      // a spoofed tenant selector is refused, not honoured
      expect(
        await h.status(
          'GET',
          '/patients/$id1',
          uid: 'ownerB',
          headers: {'x-tenant-id': tid},
        ),
        403,
      );
    });
  });

  group('duplicate detection', () {
    late String id;
    setUp(
      () async =>
          id = (await h.newPatient('recep', br))['patientId']! as String,
    );

    test(
      'same name and birth date must be reviewed; nothing is merged',
      () async {
        final dup = await h.call(
          'POST',
          '/patients',
          uid: 'recep',
          body: patientBody(br, phone: '9876500099'),
        );
        expect(dup.statusCode, 409);
        expect(await dup.readAsString(), contains('duplicate_review_required'));
        final ok = await h.okData(
          h.call(
            'POST',
            '/patients',
            uid: 'recep',
            body: patientBody(
              br,
              phone: '9876500099',
              extra: {
                'duplicateReview': {
                  'decision': 'confirmed_distinct',
                  'reason': 'Different person, same name',
                  'reviewedPatientIds': [id],
                },
              },
            ),
          ),
          status: 201,
        );
        expect(ok['patientId'], isNot(id));
        expect(h.docsOf('patient_duplicate_reviews'), hasLength(1));
        expect(
          h.auditActions(ok['patientId']! as String),
          contains('patient.duplicate_reviewed'),
        );
        // both records still exist, unchanged
        expect(await h.status('GET', '/patients/$id', uid: 'recep'), 200);
      },
    );

    test('a review that omits a candidate is not enough', () async {
      expect(
        await h.status(
          'POST',
          '/patients',
          uid: 'recep',
          body: patientBody(
            br,
            phone: '9876500099',
            extra: {
              'duplicateReview': {
                'decision': 'confirmed_distinct',
                'reason': 'Different person',
                'reviewedPatientIds': ['pt_other'],
              },
            },
          ),
        ),
        409,
      );
    });

    test(
      'similar names with different birth dates are not duplicates',
      () async {
        expect(
          await h.status(
            'POST',
            '/patients',
            uid: 'recep',
            body: patientBody(br, dob: '1991-05-14', phone: '9876500098'),
          ),
          201,
        );
      },
    );

    test(
      'a shared phone alone is a low match and never blocks or merges',
      () async {
        final check = await h.okData(
          h.call(
            'POST',
            '/patients/duplicate-check',
            uid: 'recep',
            body: {
              'fullName': 'Totally Different',
              'dateOfBirth': '1960-01-01',
              'phone': '9876500001',
            },
          ),
        );
        final matches = check['matches']! as List;
        expect((matches.single as Map)['level'], 'low');
        expect(check['requiresReview'], false);
        expect(
          await h.status(
            'POST',
            '/patients',
            uid: 'recep',
            body: patientBody(br, name: 'Totally Different', dob: '1960-01-01'),
          ),
          201,
        );
      },
    );

    test(
      'suggestions expose no clinical data and respect branch scope',
      () async {
        final check = await h.call(
          'POST',
          '/patients/duplicate-check',
          uid: 'recep',
          body: {'fullName': 'Asha Patil', 'dateOfBirth': '1990-05-14'},
        );
        final text = await check.readAsString();
        expect(text, contains('XXXXXX0001'));
        expect(text, isNot(contains('9876500001')));
        final br2 = await h.newBranch('owner', code: 'EAST');
        h.member(
          'east',
          tid,
          'receptionist',
          allBranches: false,
          branchIds: [br2],
        );
        final other = await h.okData(
          h.call(
            'POST',
            '/patients/duplicate-check',
            uid: 'east',
            body: {'fullName': 'Asha Patil', 'dateOfBirth': '1990-05-14'},
          ),
        );
        expect(other['matches'], isEmpty);
      },
    );

    test(
      'possible-duplicates lists matches for an existing record; merge does not exist',
      () async {
        final ok = await h.okData(
          h.call(
            'POST',
            '/patients',
            uid: 'recep',
            body: patientBody(
              br,
              phone: '9876500099',
              extra: {
                'duplicateReview': {
                  'decision': 'confirmed_distinct',
                  'reason': 'Different person',
                  'reviewedPatientIds': [id],
                },
              },
            ),
          ),
          status: 201,
        );
        final m = await h.okData(
          h.call(
            'GET',
            '/patients/${ok['patientId']}/possible-duplicates',
            uid: 'recep',
          ),
        );
        expect((m['matches']! as List).single['patientId'], id);
        expect(
          await h.status('POST', '/patients/$id/merge', uid: 'owner', body: {}),
          anyOf(404, 405),
        );
      },
    );
  });

  group('limits', () {
    test(
      'the patient seat limit is enforced and released on archive',
      () async {
        final h2 = PlatformHarness();
        h2.user('root', role: PlatformRole.superAdmin);
        // plan with max_patients = 1
        final planRes = await h2.okData(
          h2.call(
            'POST',
            '/platform/subscription-plans',
            uid: 'root',
            body: planBody(
              name: 'Tiny',
              limits: {
                'max_branches': 2,
                'max_doctors': 2,
                'max_staff': 2,
                'max_patients': 1,
              },
              features: {
                'appointments': true,
                'patient_management': true,
                'doctor_workspace': true,
                'multiple_branches': true,
              },
            ),
          ),
          status: 201,
        );
        final planId = planRes['planId']! as String;
        await h2.call(
          'POST',
          '/platform/subscription-plans/$planId/activate',
          uid: 'root',
        );
        h2.user('o2');
        final app = await h2.apply('o2');
        final t2 = await h2.approve(app, planId: planId);
        final b2 = await h2.newBranch('o2');
        final first = await h2.newPatient('o2', b2);
        expect(
          await h2.status(
            'POST',
            '/patients',
            uid: 'o2',
            body: patientBody(
              b2,
              name: 'Second One',
              dob: '1980-01-01',
              phone: '9876500012',
            ),
          ),
          403,
        );
        await h2.call(
          'POST',
          '/patients/${first['patientId']}/archive',
          uid: 'o2',
          body: {'reason': 'left the clinic'},
        );
        expect(
          await h2.status(
            'POST',
            '/patients',
            uid: 'o2',
            body: patientBody(
              b2,
              name: 'Second One',
              dob: '1980-01-01',
              phone: '9876500012',
            ),
          ),
          201,
        );
        expect(t2, isNotEmpty);
      },
    );
  });
}
