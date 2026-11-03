import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';

void main() {
  late PlatformHarness h;
  late String tid;
  late String br;
  late String pid;

  setUp(() async {
    h = PlatformHarness();
    h.user('root', role: PlatformRole.superAdmin);
    tid = await h.createClinic('owner');
    br = await h.newBranch('owner');
    for (final e in {
      'recep': 'receptionist',
      'doc': 'doctor',
      'nurse': 'nurse',
      'admin': 'clinic_admin',
      'acct': 'accountant',
    }.entries) {
      h.member(e.key, tid, e.value);
    }
    pid = (await h.newPatient('recep', br))['patientId']! as String;
  });

  Future<Map<String, Object?>> post(
    String uid,
    String sub,
    Map<String, Object?> body,
  ) => h.okData(
    h.call('POST', '/patients/$pid/$sub', uid: uid, body: body),
    status: 201,
  );

  group('role access to clinical information', () {
    test(
      'receptionist, admin and accountant cannot read or write history, allergies or medications',
      () async {
        for (final uid in ['recep', 'admin', 'acct']) {
          for (final sub in ['medical-history', 'allergies', 'medications']) {
            expect(
              await h.status('GET', '/patients/$pid/$sub', uid: uid),
              403,
              reason: '$uid $sub',
            );
            expect(
              await h.status(
                'POST',
                '/patients/$pid/$sub',
                uid: uid,
                body: {'title': 'x'},
              ),
              403,
              reason: '$uid $sub',
            );
          }
          expect(
            await h.status('GET', '/patients/$pid/documents', uid: uid),
            403,
            reason: uid,
          );
        }
      },
    );

    test('doctors and nurses read; the owner has full access', () async {
      for (final uid in ['doc', 'nurse', 'owner']) {
        expect(
          await h.status('GET', '/patients/$pid/medical-history', uid: uid),
          200,
        );
        expect(
          await h.status('GET', '/patients/$pid/allergies', uid: uid),
          200,
        );
        expect(
          await h.status('GET', '/patients/$pid/medications', uid: uid),
          200,
        );
      }
      // nurses may record allergies and medications but not history
      expect(
        await h.status(
          'POST',
          '/patients/$pid/allergies',
          uid: 'nurse',
          body: {'allergen': 'Penicillin', 'category': 'drug'},
        ),
        201,
      );
      expect(
        await h.status(
          'POST',
          '/patients/$pid/medical-history',
          uid: 'nurse',
          body: {'category': 'condition', 'title': 'Asthma'},
        ),
        403,
      );
    });
  });

  group('medical history', () {
    test(
      'records a condition with source and verification; unverified by default',
      () async {
        final e = await post('doc', 'medical-history', {
          'category': 'chronic_condition',
          'title': 'Type 2 diabetes',
          'onsetDate': '2015-03-01',
          'source': 'patient_reported',
        });
        expect(e['entryId'], startsWith('he_'));
        expect(e['source'], 'patient_reported');
        expect(e['verificationStatus'], 'unverified');
        expect(e['recordedBy'], 'doc');
        expect(e['tenantId'], tid);
        expect(h.auditActions(pid), contains('history.created'));
      },
    );

    test('categories and validation', () async {
      expect(
        await h.status(
          'POST',
          '/patients/$pid/medical-history',
          uid: 'doc',
          body: {'category': 'family_history', 'title': 'Heart disease'},
        ),
        422,
      );
      expect(
        (await post('doc', 'medical-history', {
          'category': 'family_history',
          'title': 'Heart disease',
          'relative': 'father',
          'ageAtDiagnosis': 55,
        }))['relative'],
        'father',
      );
      expect(
        (await post('doc', 'medical-history', {
          'category': 'surgery',
          'title': 'Appendectomy',
          'eventDate': '2010-06-01',
          'provider': 'City Hospital',
        }))['category'],
        'surgery',
      );
      expect(
        (await post('doc', 'medical-history', {
          'category': 'immunization',
          'title': 'Hepatitis B',
          'eventDate': '2020-01-10',
        }))['category'],
        'immunization',
      );
      for (final bad in [
        {'category': 'unknown', 'title': 'x1'},
        {'category': 'condition', 'title': 'Cold', 'onsetDate': '2099-01-01'},
        {
          'category': 'condition',
          'title': 'Cold',
          'onsetDate': '2020-05-01',
          'resolvedDate': '2019-01-01',
        },
        {
          'category': 'condition',
          'title': 'Cold',
          'source': 'clinician_verified',
        },
        {'category': 'condition', 'title': 'Cold', 'patientId': 'pt_x'},
        {'category': 'condition', 'title': 'Cold', 'recordedBy': 'someone'},
      ]) {
        expect(
          await h.status(
            'POST',
            '/patients/$pid/medical-history',
            uid: 'doc',
            body: bad,
          ),
          422,
          reason: '$bad',
        );
      }
      final all = await h.list(
        await h.call(
          'GET',
          '/patients/$pid/medical-history?category=surgery',
          uid: 'doc',
        ),
      );
      expect(all, hasLength(1));
    });

    test(
      'only a doctor can verify; any content change resets verification and keeps the old version',
      () async {
        final e = await post('doc', 'medical-history', {
          'category': 'condition',
          'title': 'Hypertension',
        });
        final id = e['entryId']! as String;
        expect(
          await h.status(
            'PATCH',
            '/patients/$pid/medical-history/$id',
            uid: 'owner',
            body: {'verify': true},
          ),
          422,
        );
        final v = await h.okData(
          h.call(
            'PATCH',
            '/patients/$pid/medical-history/$id',
            uid: 'doc',
            body: {'verify': true},
          ),
        );
        expect(v['verificationStatus'], 'verified');
        expect(v['source'], 'clinician_verified');
        expect(v['lastReviewedAt'], isNotNull);
        final changed = await h.okData(
          h.call(
            'PATCH',
            '/patients/$pid/medical-history/$id',
            uid: 'doc',
            body: {'title': 'Hypertension stage 2'},
          ),
        );
        expect(changed['verificationStatus'], 'unverified');
        final revisions = h
            .docsOf('patient_record_revisions')
            .where((r) => r['resourceId'] == id);
        expect(
          revisions.any(
            (r) => (r['snapshot']! as Map)['title'] == 'Hypertension',
          ),
          isTrue,
        );
        expect(
          await h.status(
            'PATCH',
            '/patients/$pid/medical-history/$id',
            uid: 'doc',
            body: {'category': 'surgery'},
          ),
          422,
        );
      },
    );

    test(
      'writes are refused after the patient revokes data-processing consent',
      () async {
        final consent = h.docsOf('patient_consents').single;
        await h.okData(
          h.call(
            'POST',
            '/patients/$pid/consents/${consent['consentId']}/revoke',
            uid: 'recep',
            body: {'reason': 'Patient request'},
          ),
        );
        expect(
          await h.status(
            'POST',
            '/patients/$pid/medical-history',
            uid: 'doc',
            body: {'category': 'condition', 'title': 'Cold'},
          ),
          409,
        );
        expect(
          await h.status(
            'POST',
            '/patients/$pid/allergies',
            uid: 'doc',
            body: {'allergen': 'Dust', 'category': 'environmental'},
          ),
          409,
        );
        expect(
          await h.status(
            'POST',
            '/patients/$pid/medications',
            uid: 'doc',
            body: {'name': 'Paracetamol'},
          ),
          409,
        );
        // existing information remains readable to authorized staff
        expect(
          await h.status('GET', '/patients/$pid/medical-history', uid: 'doc'),
          200,
        );
      },
    );

    test('record ids from another patient are not reachable', () async {
      final other =
          (await h.newPatient(
                'recep',
                br,
                name: 'Other Person',
                dob: '1980-01-01',
                phone: '9876500044',
              ))['patientId']!
              as String;
      final e = await post('doc', 'medical-history', {
        'category': 'condition',
        'title': 'Asthma',
      });
      expect(
        await h.status(
          'PATCH',
          '/patients/$other/medical-history/${e['entryId']}',
          uid: 'doc',
          body: {'notes': 'x'},
        ),
        404,
      );
    });
  });

  group('allergies', () {
    test(
      'new allergies are unverified, never "active" until a doctor verifies',
      () async {
        final a = await post('nurse', 'allergies', {
          'allergen': 'Penicillin',
          'category': 'drug',
          'severity': 'severe',
          'reaction': 'Rash',
          'status': 'active',
        });
        expect(a['status'], 'unverified');
        expect(a['verificationStatus'], 'unverified');
        final v = await h.okData(
          h.call(
            'PATCH',
            '/patients/$pid/allergies/${a['allergyId']}',
            uid: 'doc',
            body: {'verify': true, 'status': 'active'},
          ),
        );
        expect(v['status'], 'active');
        expect(v['source'], 'clinician_verified');
      },
    );

    test(
      'active allergies are shown in the patient detail, with their verification state',
      () async {
        await post('doc', 'allergies', {
          'allergen': 'Peanuts',
          'category': 'food',
          'severity': 'severe',
          'verify': true,
          'status': 'active',
        });
        await post('nurse', 'allergies', {
          'allergen': 'Latex',
          'category': 'latex',
        });
        final d = await h.okData(h.call('GET', '/patients/$pid', uid: 'doc'));
        final list = (d['activeAllergies']! as List)
            .cast<Map<String, Object?>>();
        expect(
          list.map((e) => e['allergen']),
          containsAll(['Peanuts', 'Latex']),
        );
        expect(
          list.firstWhere((e) => e['allergen'] == 'Latex')['status'],
          'unverified',
        );
        // receptionists see no allergy information
        final r = await h.okData(h.call('GET', '/patients/$pid', uid: 'recep'));
        expect(r.containsKey('activeAllergies'), isFalse);
      },
    );

    test('validation and previous versions are kept', () async {
      expect(
        await h.status(
          'POST',
          '/patients/$pid/allergies',
          uid: 'doc',
          body: {'allergen': 'x', 'category': 'drug'},
        ),
        422,
      );
      expect(
        await h.status(
          'POST',
          '/patients/$pid/allergies',
          uid: 'doc',
          body: {'allergen': 'Dust', 'category': 'alien'},
        ),
        422,
      );
      expect(
        await h.status(
          'POST',
          '/patients/$pid/allergies',
          uid: 'doc',
          body: {
            'allergen': 'Dust',
            'category': 'environmental',
            'severity': 'deadly',
          },
        ),
        422,
      );
      final a = await post('doc', 'allergies', {
        'allergen': 'Dust',
        'category': 'environmental',
      });
      await h.okData(
        h.call(
          'PATCH',
          '/patients/$pid/allergies/${a['allergyId']}',
          uid: 'doc',
          body: {'status': 'inactive', 'reaction': 'Sneezing'},
        ),
      );
      expect(
        h
            .docsOf('patient_record_revisions')
            .where((r) => r['resourceType'] == 'allergy'),
        isNotEmpty,
      );
    });
  });

  group('medications', () {
    test(
      'history is separate from prescriptions and keeps source and status',
      () async {
        final m = await post('doc', 'medications', {
          'name': 'Metformin',
          'strength': '500 mg',
          'frequency': 'twice daily',
          'startDate': '2020-01-01',
          'source': 'patient_reported',
        });
        expect(m['status'], 'unknown');
        expect(m['verificationStatus'], 'unverified');
        expect(m['source'], 'patient_reported');
        final u = await h.okData(
          h.call(
            'PATCH',
            '/patients/$pid/medications/${m['medicationId']}',
            uid: 'doc',
            body: {'status': 'discontinued', 'endDate': '2023-01-01'},
          ),
        );
        expect(u['status'], 'discontinued');
        expect(
          await h.status(
            'POST',
            '/patients/$pid/medications',
            uid: 'doc',
            body: {
              'name': 'X',
              'startDate': '2023-01-01',
              'endDate': '2022-01-01',
            },
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/patients/$pid/prescriptions',
            uid: 'doc',
            body: {},
          ),
          anyOf(404, 405),
        );
      },
    );
  });

  group('emergency contacts and alerts', () {
    test(
      'contacts are replaced as a set, validated, and previous version kept',
      () async {
        final c = {
          'name': 'Meera Patil',
          'relationship': 'mother',
          'phone': '9876500055',
          'preferred': true,
        };
        final r = await h.okData(
          h.call(
            'PUT',
            '/patients/$pid/emergency-contacts',
            uid: 'recep',
            body: {
              'contacts': [c],
            },
          ),
        );
        expect((r['contacts']! as List), hasLength(1));
        await h.okData(
          h.call(
            'PUT',
            '/patients/$pid/emergency-contacts',
            uid: 'recep',
            body: {
              'contacts': [
                c,
                {...c, 'name': 'Ravi Patil', 'preferred': false},
              ],
            },
          ),
        );
        expect(
          h
              .docsOf('patient_record_revisions')
              .where((x) => x['resourceType'] == 'emergency_contacts'),
          hasLength(1),
        );
        for (final bad in [
          <Object?>[],
          [
            c,
            {...c, 'name': 'Second Preferred'},
          ],
          [
            {...c, 'phone': '12'},
          ],
        ]) {
          expect(
            await h.status(
              'PUT',
              '/patients/$pid/emergency-contacts',
              uid: 'recep',
              body: {'contacts': bad},
            ),
            422,
          );
        }
        expect(
          await h.status(
            'PUT',
            '/patients/$pid/emergency-contacts',
            uid: 'acct',
            body: {
              'contacts': [c],
            },
          ),
          403,
        );
        expect(
          await h.status(
            'GET',
            '/patients/$pid/emergency-contacts',
            uid: 'recep',
          ),
          200,
        );
      },
    );

    test(
      'clinical alerts are restricted; administrative alerts are visible to the front desk',
      () async {
        final med = await post('doc', 'alerts', {
          'category': 'allergy',
          'title': 'Anaphylaxis risk',
          'message': 'Severe peanut allergy',
          'priority': 'critical',
        });
        await post('recep', 'alerts', {
          'category': 'special_assistance',
          'title': 'Wheelchair',
          'message': 'Needs wheelchair access',
        });
        expect(
          await h.status(
            'POST',
            '/patients/$pid/alerts',
            uid: 'recep',
            body: {
              'category': 'medical',
              'title': 'Fake alert',
              'message': 'Not allowed',
            },
          ),
          403,
        );
        final recepView = await h.list(
          await h.call('GET', '/patients/$pid/alerts', uid: 'recep'),
        );
        expect(recepView, hasLength(1));
        expect((recepView.single as Map)['category'], 'special_assistance');
        expect(
          await h.list(
            await h.call('GET', '/patients/$pid/alerts', uid: 'doc'),
          ),
          hasLength(2),
        );
        expect(
          await h.status(
            'PATCH',
            '/patients/$pid/alerts/${med['alertId']}',
            uid: 'recep',
            body: {'status': 'resolved'},
          ),
          403,
        );
        final resolved = await h.okData(
          h.call(
            'PATCH',
            '/patients/$pid/alerts/${med['alertId']}',
            uid: 'doc',
            body: {'status': 'resolved'},
          ),
        );
        expect(resolved['status'], 'resolved');
        // the alert is preserved, not deleted
        expect(
          await h.list(
            await h.call(
              'GET',
              '/patients/$pid/alerts?status=resolved',
              uid: 'doc',
            ),
          ),
          hasLength(1),
        );
      },
    );

    test(
      'the patient detail shows active alerts to the right roles only',
      () async {
        await post('doc', 'alerts', {
          'category': 'medical',
          'title': 'On anticoagulants',
          'message': 'Bleeding risk',
        });
        final doc = await h.okData(h.call('GET', '/patients/$pid', uid: 'doc'));
        expect(doc['alerts'], hasLength(1));
        final recep = await h.okData(
          h.call('GET', '/patients/$pid', uid: 'recep'),
        );
        expect(recep['alerts'], isEmpty);
      },
    );
  });

  test('reading clinical lists is audited', () async {
    await h.call('GET', '/patients/$pid/allergies', uid: 'doc');
    await h.call('GET', '/patients/$pid/medical-history', uid: 'doc');
    expect(
      h.auditActions(pid),
      containsAll(['allergy.listed', 'history.listed']),
    );
  });
}
