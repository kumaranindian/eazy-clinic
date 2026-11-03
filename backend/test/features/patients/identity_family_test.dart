import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

void main() {
  late PlatformHarness h;
  late String tidA;
  late String brA;
  late String pidA;

  setUp(() async {
    h = PlatformHarness();
    h.user('root', role: PlatformRole.superAdmin);
    tidA = await h.createClinic('ownerA', name: 'Clinic A');
    brA = await h.newBranch('ownerA');
    h.member('recepA', tidA, 'receptionist');
    h.member('docA', tidA, 'doctor');
    h.member('acctA', tidA, 'accountant');
    pidA = (await h.newPatient('recepA', brA))['patientId']! as String;
    h.user('asha'); // a person with a patient account
    h.user('mallory');
  });

  Future<Map<String, Object?>> account(String uid, {String? name}) => h.okData(
    h.call(
      'POST',
      '/patient-accounts',
      uid: uid,
      body: {if (name != null) 'displayName': name},
    ),
    status: 201,
  );

  Future<String> issueCode(String staff, String pid) async =>
      (await h.okData(
            h.call(
              'POST',
              '/patients/$pid/link-account',
              uid: staff,
              body: {
                'verificationMethod': 'government_id_sighted',
                'identityConfirmed': true,
              },
            ),
            status: 201,
          ))['code']!
          as String;

  group('patient account', () {
    test(
      'one account per sign-in, created by the user, no clinic access',
      () async {
        final a = await account('asha', name: 'Asha Patil');
        expect(a['accountId'], startsWith('pa_'));
        expect(a['kind'], 'self');
        expect(a['identityVerification'], 'email_verified');
        expect(a.containsKey('uid'), isFalse);
        expect(
          await h.status('POST', '/patient-accounts', uid: 'asha', body: {}),
          409,
        );
        final me = await h.okData(
          h.call('GET', '/patient-accounts/me', uid: 'asha'),
        );
        expect(me['accountId'], a['accountId']);
        expect(
          await h.status('GET', '/patient-accounts/me', uid: 'mallory'),
          404,
        );
        expect(await h.status('GET', '/patient-accounts/me'), 401);
        // having an account does not give any access to a clinic
        expect(await h.status('GET', '/patients', uid: 'asha'), 403);
        expect(await h.status('GET', '/patients/$pidA', uid: 'asha'), 403);
      },
    );

    test(
      'the account cannot be created with client-chosen identity fields',
      () async {
        for (final extra in [
          {'uid': 'someone-else'},
          {'accountId': 'pa_x'},
          {'status': 'verified'},
          {'kind': 'dependent'},
        ]) {
          expect(
            await h.status(
              'POST',
              '/patient-accounts',
              uid: 'asha',
              body: extra,
            ),
            422,
            reason: '$extra',
          );
        }
      },
    );
  });

  group('linking a clinic record', () {
    test(
      'clinic issues a one-time code after identifying the patient; the patient claims it',
      () async {
        final a = await account('asha');
        expect(
          await h.status(
            'POST',
            '/patients/$pidA/link-account',
            uid: 'recepA',
            body: {'verificationMethod': 'government_id_sighted'},
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/patients/$pidA/link-account',
            uid: 'acctA',
            body: {
              'verificationMethod': 'government_id_sighted',
              'identityConfirmed': true,
            },
          ),
          403,
        );
        final code = await issueCode('recepA', pidA);
        expect(code, startsWith('ECL-'));
        // only a hash is stored
        expect(
          h.docsOf('patient_link_codes').single.toString(),
          isNot(contains(code)),
        );
        final link = await h.okData(
          h.call(
            'POST',
            '/patient-accounts/me/link-clinic-record',
            uid: 'asha',
            body: {'code': code},
          ),
          status: 201,
        );
        expect(link['tenantId'], tidA);
        expect(link['patientId'], pidA);
        expect(link['accountId'], a['accountId']);
        final text = link.toString();
        expect(text, isNot(contains('Asha Patil')));
        expect(text, isNot(contains('dateOfBirth')));
        // record now knows its account; consent to link recorded; audited
        final p = await h.okData(
          h.call('GET', '/patients/$pidA', uid: 'recepA'),
        );
        expect(p['patientAccountId'], a['accountId']);
        expect(
          h
              .docsOf('patient_consents')
              .any(
                (c) =>
                    c['type'] == 'account_linking' && c['status'] == 'granted',
              ),
          isTrue,
        );
        expect(
          h.auditActions(pidA),
          containsAll(['patient.link_code_created', 'patient.account_linked']),
        );
        final links = await h.list(
          await h.call('GET', '/patient-accounts/me/clinic-links', uid: 'asha'),
        );
        expect(links, hasLength(1));
      },
    );

    test('a code is single use and the record cannot be taken over', () async {
      await account('asha');
      await account('mallory');
      final code = await issueCode('recepA', pidA);
      expect(
        await h.status(
          'POST',
          '/patient-accounts/me/link-clinic-record',
          uid: 'asha',
          body: {'code': code},
        ),
        201,
      );
      expect(
        await h.status(
          'POST',
          '/patient-accounts/me/link-clinic-record',
          uid: 'mallory',
          body: {'code': code},
        ),
        400,
      );
      // a second code cannot be issued while linked
      expect(
        await h.status(
          'POST',
          '/patients/$pidA/link-account',
          uid: 'recepA',
          body: {
            'verificationMethod': 'government_id_sighted',
            'identityConfirmed': true,
          },
        ),
        409,
      );
    });

    test(
      'wrong, malformed, expired and replaced codes all fail the same way',
      () async {
        await account('asha');
        final first = await issueCode('recepA', pidA);
        final second = await issueCode('recepA', pidA); // replaces the first
        final bodies = <String>[];
        for (final c in ['ECL-AAAA-BBBB-CCCC', 'short', first]) {
          final r = await h.call(
            'POST',
            '/patient-accounts/me/link-clinic-record',
            uid: 'asha',
            body: {'code': c},
          );
          expect(r.statusCode, anyOf(400, 422), reason: c);
          bodies.add(
            r.statusCode == 400
                ? await r.readAsString().then(
                    (s) => s.replaceAll(RegExp(r'"requestId":"[^"]+"'), ''),
                  )
                : '422',
          );
        }
        h.clock.now = h.clock.now.add(const Duration(hours: 25));
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/link-clinic-record',
            uid: 'asha',
            body: {'code': second},
          ),
          400,
        );
        expect(bodies.where((b) => b != '422').toSet(), hasLength(1));
      },
    );

    test(
      'an unverified e-mail cannot link, and a user without an account cannot link',
      () async {
        await account('asha');
        final code = await issueCode('recepA', pidA);
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/link-clinic-record',
            uid: 'asha',
            body: {'code': code},
            emailVerified: false,
          ),
          403,
        );
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/link-clinic-record',
            uid: 'mallory',
            body: {'code': code},
          ),
          403,
        );
      },
    );

    test('a matching phone or e-mail never links or merges anything', () async {
      await account('asha');
      final other = await h.newPatient(
        'recepA',
        brA,
        name: 'Asha Patil',
        dob: '1990-05-14',
        phone: '9876500001',
        extra: {
          'duplicateReview': {
            'decision': 'confirmed_distinct',
            'reason': 'Same phone, other person',
            'reviewedPatientIds': [pidA],
          },
        },
      );
      final p = await h.okData(
        h.call('GET', '/patients/${other['patientId']}', uid: 'recepA'),
      );
      expect(p['patientAccountId'], isNull);
      expect(
        await h.list(
          await h.call('GET', '/patient-accounts/me/clinic-links', uid: 'asha'),
        ),
        isEmpty,
      );
      expect(
        await h.status(
          'POST',
          '/patient-accounts/me/link-clinic-record',
          uid: 'asha',
          body: {'code': pidA},
        ),
        anyOf(400, 422),
      );
      expect(
        await h.status(
          'POST',
          '/patients/$pidA/link-account',
          uid: 'asha',
          body: {
            'verificationMethod': 'government_id_sighted',
            'identityConfirmed': true,
          },
        ),
        403,
      );
    });

    test('one person, two independent clinics', () async {
      final tidB = await h.createClinic('ownerB', name: 'Clinic B');
      final brB = await h.newBranch('ownerB');
      final pidB = (await h.newPatient('ownerB', brB))['patientId']! as String;
      await account('asha');
      await h.okData(
        h.call(
          'POST',
          '/patient-accounts/me/link-clinic-record',
          uid: 'asha',
          body: {'code': await issueCode('recepA', pidA)},
        ),
        status: 201,
      );
      await h.okData(
        h.call(
          'POST',
          '/patient-accounts/me/link-clinic-record',
          uid: 'asha',
          body: {'code': await issueCode('ownerB', pidB)},
        ),
        status: 201,
      );
      final links = await h.list(
        await h.call('GET', '/patient-accounts/me/clinic-links', uid: 'asha'),
      );
      expect(
        links.map((l) => (l! as Map)['tenantId']),
        unorderedEquals([tidA, tidB]),
      );
      // each clinic sees only its own record and nothing of the other
      expect(await h.status('GET', '/patients/$pidB', uid: 'recepA'), 404);
      expect(await h.status('GET', '/patients/$pidA', uid: 'ownerB'), 404);
      expect(
        await h.status('GET', '/patients/$pidB/medical-history', uid: 'docA'),
        404,
      );
      // a second record at the same clinic cannot be linked to the same account
      final p2 =
          (await h.newPatient(
                'recepA',
                brA,
                name: 'Different Person',
                dob: '1970-01-01',
                phone: '9876500077',
              ))['patientId']!
              as String;
      expect(
        await h.status(
          'POST',
          '/patient-accounts/me/link-clinic-record',
          uid: 'asha',
          body: {'code': await issueCode('recepA', p2)},
        ),
        409,
      );
    });

    test(
      'unlinking by the clinic needs a reason; by the patient needs ownership; both are audited',
      () async {
        await account('asha');
        await account('mallory');
        final link = await h.okData(
          h.call(
            'POST',
            '/patient-accounts/me/link-clinic-record',
            uid: 'asha',
            body: {'code': await issueCode('recepA', pidA)},
          ),
          status: 201,
        );
        expect(
          await h.status(
            'POST',
            '/patients/$pidA/unlink-account',
            uid: 'recepA',
            body: {},
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/clinic-links/${link['linkId']}/unlink',
            uid: 'mallory',
            body: {},
          ),
          404,
        );
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/clinic-links/${link['linkId']}/unlink',
            uid: 'asha',
            body: {},
          ),
          200,
        );
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/clinic-links/${link['linkId']}/unlink',
            uid: 'asha',
            body: {},
          ),
          404,
        );
        final p = await h.okData(
          h.call('GET', '/patients/$pidA', uid: 'recepA'),
        );
        expect(p['patientAccountId'], isNull);
        expect(h.auditActions(pidA), contains('patient.account_unlinked'));
        // the clinic keeps its record; it can be re-linked, and clinic-side unlink works
        await h.okData(
          h.call(
            'POST',
            '/patient-accounts/me/link-clinic-record',
            uid: 'asha',
            body: {'code': await issueCode('recepA', pidA)},
          ),
          status: 201,
        );
        expect(
          await h.status(
            'POST',
            '/patients/$pidA/unlink-account',
            uid: 'recepA',
            body: {'reason': 'Patient left the clinic'},
          ),
          200,
        );
        expect(
          await h.list(
            await h.call(
              'GET',
              '/patient-accounts/me/clinic-links',
              uid: 'asha',
            ),
          ),
          isEmpty,
        );
      },
    );

    test(
      'a branch-scoped member cannot issue a code for another branch\'s patient',
      () async {
        final br2 = await h.newBranch('ownerA', code: 'NORTH');
        h.member(
          'north',
          tidA,
          'receptionist',
          allBranches: false,
          branchIds: [br2],
        );
        expect(
          await h.status(
            'POST',
            '/patients/$pidA/link-account',
            uid: 'north',
            body: {
              'verificationMethod': 'government_id_sighted',
              'identityConfirmed': true,
            },
          ),
          404,
        );
      },
    );
  });

  group('family and dependents', () {
    late String ashaAcc;
    late String ravi;
    setUp(() async {
      ashaAcc = (await account('asha'))['accountId']! as String;
      h.user('ravi');
      ravi = (await account('ravi'))['accountId']! as String;
    });

    Future<Map<String, Object?>> request(
      String uid,
      Map<String, Object?> body,
    ) => h.okData(
      h.call('POST', '/patient-accounts/me/family', uid: uid, body: body),
      status: 201,
    );

    test(
      'an adult relationship grants nothing until the other person approves',
      () async {
        final rel = await request('ravi', {
          'relationshipType': 'spouse',
          'subjectAccountId': ashaAcc,
          'permissionScope': ['view_clinic_links'],
        });
        expect(rel['status'], 'pending');
        expect(rel['verificationStatus'], 'pending');
        // pending: Ravi cannot see Asha's clinic links
        expect(
          await h.status(
            'GET',
            '/patient-accounts/me/clinic-links?accountId=$ashaAcc',
            uid: 'ravi',
          ),
          404,
        );
        // Ravi cannot approve his own request; a stranger cannot see it
        expect(
          await h.status(
            'POST',
            '/family-relationships/${rel['relationshipId']}/verify',
            uid: 'ravi',
            body: {'decision': 'approve'},
          ),
          403,
        );
        expect(
          await h.status(
            'GET',
            '/family-relationships/${rel['relationshipId']}',
            uid: 'mallory',
          ),
          403,
        );
        await account('mallory');
        expect(
          await h.status(
            'GET',
            '/family-relationships/${rel['relationshipId']}',
            uid: 'mallory',
          ),
          404,
        );
        final ok = await h.okData(
          h.call(
            'POST',
            '/family-relationships/${rel['relationshipId']}/verify',
            uid: 'asha',
            body: {'decision': 'approve'},
          ),
        );
        expect(ok['status'], 'active');
        expect(ok['verificationStatus'], 'verified');
        expect(
          await h.status(
            'GET',
            '/patient-accounts/me/clinic-links?accountId=$ashaAcc',
            uid: 'ravi',
          ),
          200,
        );
      },
    );

    test(
      'scope is exact: no scope, no access; links only expose pointers, never records',
      () async {
        final rel = await request('ravi', {
          'relationshipType': 'caregiver',
          'subjectAccountId': ashaAcc,
          'permissionScope': ['manage_appointments'],
        });
        await h.okData(
          h.call(
            'POST',
            '/family-relationships/${rel['relationshipId']}/verify',
            uid: 'asha',
            body: {'decision': 'approve'},
          ),
        );
        // verified, but the scope does not include view_clinic_links
        expect(
          await h.status(
            'GET',
            '/patient-accounts/me/clinic-links?accountId=$ashaAcc',
            uid: 'ravi',
          ),
          404,
        );
        // and no relationship ever gives access to a clinic API
        expect(await h.status('GET', '/patients', uid: 'ravi'), 403);
        expect(await h.status('GET', '/patients/$pidA', uid: 'ravi'), 403);
      },
    );

    test(
      'revoking ends access immediately; either side can revoke; strangers cannot',
      () async {
        final rel = await request('ravi', {
          'relationshipType': 'caregiver',
          'subjectAccountId': ashaAcc,
          'permissionScope': ['view_clinic_links'],
        });
        final id = rel['relationshipId']! as String;
        await h.okData(
          h.call(
            'POST',
            '/family-relationships/$id/verify',
            uid: 'asha',
            body: {'decision': 'approve'},
          ),
        );
        expect(
          await h.status(
            'GET',
            '/patient-accounts/me/clinic-links?accountId=$ashaAcc',
            uid: 'ravi',
          ),
          200,
        );
        await account('mallory');
        expect(
          await h.status(
            'POST',
            '/family-relationships/$id/revoke',
            uid: 'mallory',
            body: {},
          ),
          404,
        );
        final r = await h.okData(
          h.call(
            'POST',
            '/family-relationships/$id/revoke',
            uid: 'asha',
            body: {'reason': 'No longer needed'},
          ),
        );
        expect(r['status'], 'revoked');
        expect(
          await h.status(
            'GET',
            '/patient-accounts/me/clinic-links?accountId=$ashaAcc',
            uid: 'ravi',
          ),
          404,
        );
        expect(
          await h.status(
            'POST',
            '/family-relationships/$id/revoke',
            uid: 'asha',
            body: {},
          ),
          409,
        );
        expect(
          await h.status(
            'POST',
            '/family-relationships/$id/verify',
            uid: 'asha',
            body: {'decision': 'approve'},
          ),
          409,
        );
      },
    );

    test(
      'a rejected request, an expired one and a widened scope grant nothing',
      () async {
        final rel = await request('ravi', {
          'relationshipType': 'spouse',
          'subjectAccountId': ashaAcc,
          'permissionScope': ['view_clinic_links'],
        });
        final id = rel['relationshipId']! as String;
        await h.okData(
          h.call(
            'POST',
            '/family-relationships/$id/verify',
            uid: 'asha',
            body: {'decision': 'reject'},
          ),
        );
        expect(
          await h.status(
            'GET',
            '/patient-accounts/me/clinic-links?accountId=$ashaAcc',
            uid: 'ravi',
          ),
          404,
        );

        final until = h.clock.now
            .add(const Duration(days: 1))
            .toUtc()
            .toIso8601String();
        final r2 = await request('ravi', {
          'relationshipType': 'caregiver',
          'subjectAccountId': ashaAcc,
          'permissionScope': ['view_clinic_links'],
          'validUntil': until,
        });
        await h.okData(
          h.call(
            'POST',
            '/family-relationships/${r2['relationshipId']}/verify',
            uid: 'asha',
            body: {'decision': 'approve'},
          ),
        );
        expect(
          await h.status(
            'GET',
            '/patient-accounts/me/clinic-links?accountId=$ashaAcc',
            uid: 'ravi',
          ),
          200,
        );
        // narrowing is allowed, widening is not
        expect(
          await h.status(
            'PATCH',
            '/family-relationships/${r2['relationshipId']}',
            uid: 'ravi',
            body: {
              'permissionScope': ['view_clinic_links', 'view_records'],
            },
          ),
          409,
        );
        h.clock.now = h.clock.now.add(const Duration(days: 2));
        expect(
          await h.status(
            'GET',
            '/patient-accounts/me/clinic-links?accountId=$ashaAcc',
            uid: 'ravi',
          ),
          404,
        );
        final shown = await h.okData(
          h.call(
            'GET',
            '/family-relationships/${r2['relationshipId']}',
            uid: 'ravi',
          ),
        );
        expect(shown['status'], 'expired');
      },
    );

    test(
      'validation: guardianship cannot be claimed over an adult; unknown scopes; self; duplicates',
      () async {
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/family',
            uid: 'ravi',
            body: {
              'relationshipType': 'parent',
              'isGuardian': true,
              'subjectAccountId': ashaAcc,
              'permissionScope': ['view_clinic_links'],
            },
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/family',
            uid: 'ravi',
            body: {
              'relationshipType': 'spouse',
              'subjectAccountId': ashaAcc,
              'permissionScope': ['everything'],
            },
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/family',
            uid: 'ravi',
            body: {
              'relationshipType': 'spouse',
              'subjectAccountId': ravi,
              'permissionScope': ['view_clinic_links'],
            },
          ),
          404,
        );
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/family',
            uid: 'ravi',
            body: {
              'relationshipType': 'spouse',
              'subjectAccountId': 'pa_missing',
              'permissionScope': ['view_clinic_links'],
            },
          ),
          404,
        );
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/family',
            uid: 'ravi',
            body: {
              'relationshipType': 'spouse',
              'permissionScope': ['view_clinic_links'],
            },
          ),
          422,
        );
        await request('ravi', {
          'relationshipType': 'spouse',
          'subjectAccountId': ashaAcc,
          'permissionScope': ['view_clinic_links'],
        });
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/family',
            uid: 'ravi',
            body: {
              'relationshipType': 'spouse',
              'subjectAccountId': ashaAcc,
              'permissionScope': ['view_clinic_links'],
            },
          ),
          409,
        );
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/family',
            uid: 'mallory',
            body: {
              'relationshipType': 'spouse',
              'subjectAccountId': ashaAcc,
              'permissionScope': ['view_clinic_links'],
            },
          ),
          403,
        );
      },
    );

    test(
      'a dependent is verified only by the clinic when its record is linked',
      () async {
        final kid = await h.newPatient(
          'recepA',
          brA,
          name: 'Kid Patil',
          dob: '2018-03-03',
          phone: '9876500061',
          guardian: {
            'name': 'Asha Patil',
            'relationship': 'mother',
            'phone': '9876500001',
            'verificationMethod': 'government_id_sighted',
          },
          consent: consentBody(grantedBy: {'type': 'guardian'}),
        );
        final kidId = kid['patientId']! as String;
        final rel = await request('asha', {
          'relationshipType': 'parent',
          'isGuardian': true,
          'permissionScope': ['view_clinic_links', 'link_clinic_records'],
          'dependent': {
            'displayName': 'Kid Patil',
            'dateOfBirth': '2018-03-03',
          },
        });
        expect(rel['status'], 'pending');
        final depId = rel['subjectAccountId']! as String;
        // the guardian cannot approve their own claim, and there is no account to approve it
        expect(
          await h.status(
            'POST',
            '/family-relationships/${rel['relationshipId']}/verify',
            uid: 'asha',
            body: {'decision': 'approve'},
          ),
          403,
        );
        expect(
          await h.status(
            'GET',
            '/patient-accounts/me/clinic-links?accountId=$depId',
            uid: 'asha',
          ),
          404,
        );
        // an adult record's code cannot be used for a dependent, nor a minor's for the guardian herself
        final adultCode = await issueCode('recepA', pidA);
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/link-clinic-record',
            uid: 'asha',
            body: {'code': adultCode, 'forAccountId': depId},
          ),
          400,
        );
        final kidCode = await issueCode('recepA', kidId);
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/link-clinic-record',
            uid: 'asha',
            body: {'code': kidCode},
          ),
          400,
        );
        // someone else's dependent cannot be targeted
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/link-clinic-record',
            uid: 'ravi',
            body: {'code': kidCode, 'forAccountId': depId},
          ),
          404,
        );
        final link = await h.okData(
          h.call(
            'POST',
            '/patient-accounts/me/link-clinic-record',
            uid: 'asha',
            body: {'code': kidCode, 'forAccountId': depId},
          ),
          status: 201,
        );
        expect(link['accountId'], depId);
        final rel2 = await h.okData(
          h.call(
            'GET',
            '/family-relationships/${rel['relationshipId']}',
            uid: 'asha',
          ),
        );
        expect(rel2['status'], 'active');
        expect(rel2['verificationStatus'], 'verified');
        expect(rel2['scopeTenantId'], tidA);
        expect(((rel2['verifiedBy']! as Map)['type']), 'clinic');
        // the verified guardian can now see the dependent's clinic link, and nothing else
        expect(
          await h.list(
            await h.call(
              'GET',
              '/patient-accounts/me/clinic-links?accountId=$depId',
              uid: 'asha',
            ),
          ),
          hasLength(1),
        );
        expect(await h.status('GET', '/patients/$kidId', uid: 'asha'), 403);
        // revoked guardian loses access
        await h.call(
          'POST',
          '/family-relationships/${rel['relationshipId']}/revoke',
          uid: 'asha',
          body: {},
        );
        expect(
          await h.status(
            'GET',
            '/patient-accounts/me/clinic-links?accountId=$depId',
            uid: 'asha',
          ),
          404,
        );
      },
    );

    test(
      'a dependent cannot be created without guardianship, and a minor record needs a verified guardian to link',
      () async {
        expect(
          await h.status(
            'POST',
            '/patient-accounts/me/family',
            uid: 'asha',
            body: {
              'relationshipType': 'caregiver',
              'permissionScope': ['view_clinic_links'],
              'dependent': {'displayName': 'Kid', 'dateOfBirth': '2018-03-03'},
            },
          ),
          422,
        );
        // a minor whose guardian was never verified cannot get a link code
        final kid = await h.newPatient(
          'recepA',
          brA,
          name: 'Kid Two',
          dob: '2019-01-01',
          phone: '9876500062',
          guardian: {
            'name': 'Asha Patil',
            'relationship': 'mother',
            'phone': '9876500001',
            'verificationMethod': 'government_id_sighted',
          },
          consent: consentBody(grantedBy: {'type': 'guardian'}),
        );
        // changing the guardian's details drops the verification
        await h.okData(
          h.call(
            'PATCH',
            '/patients/${kid['patientId']}',
            uid: 'docA',
            body: {
              'guardian': {
                'name': 'Someone Else',
                'relationship': 'uncle',
                'phone': '9876500088',
              },
            },
          ),
        );
        expect(
          await h.status(
            'POST',
            '/patients/${kid['patientId']}/link-account',
            uid: 'recepA',
            body: {
              'verificationMethod': 'government_id_sighted',
              'identityConfirmed': true,
            },
          ),
          409,
        );
      },
    );

    test('listing shows only your own relationships', () async {
      await request('ravi', {
        'relationshipType': 'spouse',
        'subjectAccountId': ashaAcc,
        'permissionScope': ['view_clinic_links'],
      });
      expect(
        await h.list(
          await h.call('GET', '/patient-accounts/me/family', uid: 'ravi'),
        ),
        hasLength(1),
      );
      expect(
        await h.list(
          await h.call('GET', '/patient-accounts/me/family', uid: 'asha'),
        ),
        hasLength(1),
      );
      await account('mallory');
      expect(
        await h.list(
          await h.call('GET', '/patient-accounts/me/family', uid: 'mallory'),
        ),
        isEmpty,
      );
    });
  });
}
