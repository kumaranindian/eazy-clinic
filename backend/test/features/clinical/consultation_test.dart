import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/clinical_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/scheduling_fixtures.dart';

void main() {
  late PlatformHarness h;
  late ClinicalClinic k;

  setUp(() async {
    h = PlatformHarness();
    k = ClinicalClinic(h);
    await k.init();
  });

  group('access control', () {
    test(
      'unauthenticated, invalid-token and suspended callers are rejected',
      () async {
        expect(await h.status('GET', '/doctor/dashboard'), 401);
        expect(
          (await h.call(
            'GET',
            '/doctor/dashboard',
            headers: {'authorization': 'Bearer not-a-token'},
          )).statusCode,
          401,
        );
        h.user('sus', status: AccountStatus.suspended);
        h.member('sus', k.tid, 'doctor');
        expect(
          await h.status('GET', '/doctor/dashboard', uid: 'sus'),
          anyOf(401, 403),
        );
        expect(
          await h.status('POST', '/consultations', body: k.consult()),
          401,
        );
      },
    );

    test(
      'only the treating doctor can author; reception, nurses, admins, accountants and the owner cannot',
      () async {
        for (final uid in ['recep', 'nurse', 'admin', 'acct', 'owner']) {
          expect(
            await h.status(
              'POST',
              '/consultations',
              uid: uid,
              body: k.consult(),
            ),
            403,
            reason: uid,
          );
        }
        final cid = (await k.newConsultation())['consultationId']! as String;
        for (final uid in ['recep', 'nurse', 'admin', 'acct']) {
          expect(
            await h.status('GET', '/consultations/$cid', uid: uid),
            403,
            reason: uid,
          );
        }
        for (final action in ['start', 'finalize']) {
          expect(
            await h.act('owner', '/consultations/$cid/$action'),
            403,
            reason: 'owner $action',
          );
          expect(
            await h.act('recep', '/consultations/$cid/$action'),
            403,
            reason: 'recep $action',
          );
        }
      },
    );

    test(
      'another doctor cannot see or change a doctor\'s consultation; the owner can read it',
      () async {
        final cid = (await k.newConsultation())['consultationId']! as String;
        expect(
          await h.status('GET', '/consultations/$cid', uid: 'doc2user'),
          404,
        );
        expect(
          await h.status(
            'PATCH',
            '/consultations/$cid',
            uid: 'doc2user',
            body: {
              'assessment': {'notes': 'x'},
            },
          ),
          404,
        );
        expect(await h.act('doc2user', '/consultations/$cid/start'), 404);
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/diagnoses',
            uid: 'doc2user',
            body: {
              'kind': 'primary',
              'certainty': 'provisional',
              'label': 'Fever',
            },
          ),
          404,
        );
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/prescriptions',
            uid: 'doc2user',
            body: {'medicines': <Object?>[]},
          ),
          404,
        );
        expect(await h.status('GET', '/consultations/$cid', uid: 'owner'), 200);
      },
    );

    test(
      'another clinic and another branch never reach the consultation',
      () async {
        final cid = (await k.newConsultation())['consultationId']! as String;
        await h.createClinic('ownerB', name: 'Other Clinic');
        for (final path in [
          '/consultations/$cid',
          '/consultations/$cid/amendments',
          '/consultations/$cid/investigations',
        ]) {
          expect(
            await h.status('GET', path, uid: 'ownerB'),
            anyOf(403, 404),
            reason: path,
          );
        }
        final b2 = await h.newBranch('owner', code: 'EAST');
        h.member(
          'eastdoc',
          k.tid,
          'doctor',
          allBranches: false,
          branchIds: [b2],
        );
        final eastDoc = await h.newDoctor(
          'owner',
          branchIds: [b2],
          name: 'Dr East',
          n: '5',
        );
        h.store.docs['tenants/${k.tid}/members/eastdoc']!['doctorId'] = eastDoc;
        expect(
          await h.status('GET', '/consultations/$cid', uid: 'eastdoc'),
          404,
        );
        expect(
          await h.status(
            'POST',
            '/consultations',
            uid: 'eastdoc',
            body: k.consult(),
          ),
          404,
          reason: 'patient of another branch',
        );
      },
    );

    test(
      'a client cannot choose tenant, doctor, status or ownership',
      () async {
        for (final extra in [
          {'tenantId': 'x'},
          {'doctorId': 'dr_other'},
          {'status': 'finalized'},
          {'consultationId': 'con_x'},
          {'createdBy': 'x'},
          {'finalizedAt': '2026-01-01'},
        ]) {
          expect(
            await h.status(
              'POST',
              '/consultations',
              uid: 'docuser',
              body: k.consult(extra: extra),
            ),
            422,
            reason: '$extra',
          );
        }
        final cid = (await k.newConsultation())['consultationId']! as String;
        for (final bad in [
          {'status': 'finalized'},
          {'doctorId': 'dr_x'},
          {'branchId': 'br_x'},
          {'patientId': 'pt_x'},
          {'revision': 4},
        ]) {
          expect(
            await h.status(
              'PATCH',
              '/consultations/$cid',
              uid: 'docuser',
              body: bad,
            ),
            422,
            reason: '$bad',
          );
        }
      },
    );

    test('the plan must include the doctor workspace', () async {
      final h2 = PlatformHarness();
      h2.user('root', role: PlatformRole.superAdmin);
      final plan = await h2.okData(
        h2.call(
          'POST',
          '/platform/subscription-plans',
          uid: 'root',
          body: {
            'name': 'No workspace',
            'billingInterval': 'monthly',
            'priceMinor': 0,
            'currency': 'INR',
            'trialDays': 0,
            'limits': {
              'max_branches': 2,
              'max_doctors': 2,
              'max_staff': 2,
              'max_patients': null,
            },
            'features': {
              'patient_management': true,
              'appointments': true,
              'doctor_workspace': false,
            },
          },
        ),
        status: 201,
      );
      await h2.call(
        'POST',
        '/platform/subscription-plans/${plan['planId']}/activate',
        uid: 'root',
      );
      h2.user('o2');
      await h2.approve(await h2.apply('o2'), planId: plan['planId']! as String);
      expect(await h2.status('GET', '/clinical/templates', uid: 'o2'), 403);
      expect(
        await h2.status('POST', '/consultations', uid: 'o2', body: {}),
        403,
      );
    });

    test('a suspended clinic cannot use the clinical workspace', () async {
      await h.call(
        'POST',
        '/platform/tenants/${k.tid}/suspend',
        uid: 'root',
        body: {'reason': 'Policy review'},
      );
      expect(await h.status('GET', '/doctor/dashboard', uid: 'docuser'), 403);
    });
  });

  group('draft and in-progress', () {
    test(
      'creates a draft with sections, saves, resumes and detects stale edits',
      () async {
        final c = await k.newConsultation(
          extra: {
            'chiefComplaint': {
              'reason': 'Fever for three days',
              'symptoms': [
                {'name': 'Fever', 'duration': '3 days', 'severity': 'moderate'},
                {'name': 'Cough', 'onset': 'gradual'},
              ],
            },
            'observations': {
              'examination': 'Throat congested',
              'negativeFindings': ['No rash'],
            },
          },
        );
        expect(c['status'], 'draft');
        expect(c['consultationId'], startsWith('con_'));
        expect(c['tenantId'], k.tid);
        expect(c['doctorId'], k.c.doc);
        expect(c['version'], 1);
        expect(c['patientName'], 'Asha Patil');
        final id = c['consultationId']! as String;
        final u = await h.actOk(
          'docuser',
          '/consultations/$id',
          method: 'PATCH',
          body: {
            'expectedVersion': 1,
            'assessment': {'notes': 'Likely viral'},
            'treatmentPlan': {'recommendations': 'Rest and fluids'},
          },
        );
        expect(u['version'], 2);
        expect((u['assessment']! as Map)['notes'], 'Likely viral');
        // sections merge field by field; others are untouched
        final u2 = await h.actOk(
          'docuser',
          '/consultations/$id',
          method: 'PATCH',
          body: {
            'chiefComplaint': {'notes': 'Worse at night'},
          },
        );
        expect(
          (u2['chiefComplaint']! as Map)['reason'],
          'Fever for three days',
        );
        expect((u2['chiefComplaint']! as Map)['notes'], 'Worse at night');
        expect(
          await h.status(
            'PATCH',
            '/consultations/$id',
            uid: 'docuser',
            body: {
              'expectedVersion': 1,
              'assessment': {'notes': 'stale'},
            },
          ),
          409,
        );
        final d = await h.get('docuser', '/consultations/$id');
        expect((d['assessment']! as Map)['notes'], 'Likely viral');
      },
    );

    test('section validation', () async {
      for (final bad in [
        {
          'chiefComplaint': {
            'symptoms': [
              {'name': 'x'},
            ],
          },
        },
        {
          'chiefComplaint': {
            'symptoms': [
              {'name': 'Fever', 'severity': 'extreme'},
            ],
          },
        },
        {
          'chiefComplaint': {'unknown': 'x'},
        },
        {
          'followUp': {'recommendedDate': 'tomorrow'},
        },
        {
          'observations': {'positiveFindings': List.filled(30, 'x1')},
        },
        {'unknownSection': <String, Object?>{}},
      ]) {
        expect(
          await h.status(
            'POST',
            '/consultations',
            uid: 'docuser',
            body: k.consult(extra: bad),
          ),
          422,
          reason: '$bad',
        );
      }
    });

    test(
      'a consultation needs an active patient, consent and an assigned branch',
      () async {
        expect(
          await h.status(
            'POST',
            '/consultations',
            uid: 'docuser',
            body: {'patientId': 'pt_missing0', 'branchId': k.br},
          ),
          404,
        );
        final consent = h.docsOf('patient_consents').single;
        await h.okData(
          h.call(
            'POST',
            '/patients/${k.patient}/consents/${consent['consentId']}/revoke',
            uid: 'recep',
            body: {'reason': 'Patient request'},
          ),
        );
        expect(
          await h.status(
            'POST',
            '/consultations',
            uid: 'docuser',
            body: k.consult(),
          ),
          409,
        );
        final b2 = await h.newBranch('owner', code: 'EAST');
        final p2 =
            (await h.newPatient(
                  'owner',
                  b2,
                  name: 'East Patient',
                  dob: '1980-01-01',
                  phone: '9876500077',
                ))['patientId']!
                as String;
        expect(
          await h.status(
            'POST',
            '/consultations',
            uid: 'docuser',
            body: {'patientId': p2, 'branchId': b2},
          ),
          403,
          reason: 'doctor not assigned to that branch',
        );
      },
    );

    test(
      'a template pre-fills a draft but never finalizes it; unusable templates are refused',
      () async {
        final tpl = await h.actOk(
          'docuser',
          '/clinical/templates',
          status: 201,
          body: {
            'name': 'Fever',
            'scope': 'doctor',
            'content': {
              'chiefComplaint': {'reason': 'Fever'},
              'treatmentPlan': {
                'recommendations': 'Rest, fluids',
                'patientInstructions': 'Return if fever persists',
              },
            },
          },
        );
        final c = await h.okData(
          h.call(
            'POST',
            '/consultations',
            uid: 'docuser',
            body: {
              'patientId': k.patient,
              'branchId': k.br,
              'templateId': tpl['templateId'],
            },
          ),
          status: 201,
        );
        expect(c['status'], 'draft');
        expect((c['treatmentPlan']! as Map)['recommendations'], 'Rest, fluids');
        expect(c['templateId'], tpl['templateId']);
        // another doctor's private template, an inactive one and a made-up id
        expect(
          await h.status(
            'POST',
            '/consultations',
            uid: 'doc2user',
            body: {
              'patientId': k.patient,
              'branchId': k.br,
              'templateId': tpl['templateId'],
            },
          ),
          422,
        );
        await h.actOk(
          'docuser',
          '/clinical/templates/${tpl['templateId']}',
          method: 'PATCH',
          body: {'status': 'inactive'},
        );
        expect(
          await h.status(
            'POST',
            '/consultations',
            uid: 'docuser',
            body: {
              'patientId': k.patient,
              'branchId': k.br,
              'templateId': tpl['templateId'],
            },
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/consultations',
            uid: 'docuser',
            body: {
              'patientId': k.patient,
              'branchId': k.br,
              'templateId': 'tpl_nope',
            },
          ),
          422,
        );
      },
    );

    test('start moves a draft to in progress and is repeatable', () async {
      final id = (await k.newConsultation())['consultationId']! as String;
      final s = await h.actOk('docuser', '/consultations/$id/start');
      expect(s['status'], 'in_progress');
      expect(s['startedAt'], isNotNull);
      final again = await h.actOk('docuser', '/consultations/$id/start');
      expect(again['idempotentReplay'], true);
      expect(
        h
            .clinicalActions(consultationId: id)
            .where((a) => a == 'consultation.started'),
        hasLength(1),
      );
    });
  });

  group('appointment and queue integration', () {
    test(
      'a checked-in visit: the consultation starts the queue entry and finalizing completes the visit',
      () async {
        final apt = await k.checkedInVisit();
        final cid =
            (await k.newConsultation(appointmentId: apt))['consultationId']!
                as String;
        expect(
          await h.status(
            'POST',
            '/consultations',
            uid: 'docuser',
            body: k.consult(appointmentId: apt),
          ),
          409,
          reason: 'one consultation per appointment',
        );
        final s = await h.actOk('docuser', '/consultations/$cid/start');
        expect(s['status'], 'in_progress');
        final a1 = await h.get('recep', '/appointments/$apt');
        expect(a1['status'], 'in_progress');
        await k.primaryDx(cid);
        final f = await h.actOk('docuser', '/consultations/$cid/finalize');
        expect(f['status'], 'finalized');
        final a2 = await h.get('recep', '/appointments/$apt');
        expect(a2['status'], 'completed');
        final q = await h.actOk(
          'recep',
          '/queues/current?branchId=${k.br}&doctorId=${k.c.doc}',
          method: 'GET',
        );
        expect(q['completed'], 1);
      },
    );

    test(
      'a patient who has not checked in cannot be started; others\' appointments are refused',
      () async {
        final a = await h.bookOk('recep', k.c.body());
        expect(
          await h.status(
            'POST',
            '/consultations',
            uid: 'docuser',
            body: k.consult(appointmentId: a['appointmentId']! as String),
          ),
          201,
          reason: 'a draft may be prepared for a confirmed visit',
        );
        final cid =
            h.docsOf('consultations').single['consultationId']! as String;
        expect(await h.act('docuser', '/consultations/$cid/start'), 409);
        // an appointment of the other doctor
        final p2 = await k.c.morePatient(1);
        final b = await h.bookOk(
          'recep',
          h.bookBody(
            patientId: p2,
            doctorId: k.doc2,
            branchId: k.br,
            typeId: k.c.type,
            startTime: '10:00',
          ),
        );
        expect(
          await h.status(
            'POST',
            '/consultations',
            uid: 'docuser',
            body: k.consult(
              patientId: p2,
              appointmentId: b['appointmentId']! as String,
            ),
          ),
          403,
        );
        expect(
          await h.status(
            'POST',
            '/consultations',
            uid: 'docuser',
            body: k.consult(
              patientId: p2,
              appointmentId: a['appointmentId']! as String,
            ),
          ),
          403,
          reason: 'wrong patient for the appointment',
        );
      },
    );

    test('a cancelled appointment cannot start a consultation', () async {
      final a = await h.bookOk('recep', k.c.body());
      await h.actOk(
        'recep',
        '/appointments/${a['appointmentId']}/cancel',
        body: {'reason': 'Patient called'},
      );
      expect(
        await h.status(
          'POST',
          '/consultations',
          uid: 'docuser',
          body: k.consult(appointmentId: a['appointmentId']! as String),
        ),
        409,
      );
    });
  });

  group('finalization and amendments', () {
    test(
      'finalizing needs the reason for the visit and a primary diagnosis',
      () async {
        final cid =
            (await h.okData(
                  h.call(
                    'POST',
                    '/consultations',
                    uid: 'docuser',
                    body: {'patientId': k.patient, 'branchId': k.br},
                  ),
                  status: 201,
                ))['consultationId']!
                as String;
        expect(
          await h.act('docuser', '/consultations/$cid/finalize'),
          409,
          reason: 'not started',
        );
        await h.actOk('docuser', '/consultations/$cid/start');
        final r = await h.call(
          'POST',
          '/consultations/$cid/finalize',
          uid: 'docuser',
          body: <String, Object?>{},
        );
        expect(r.statusCode, 422);
        final text = await r.readAsString();
        expect(text, contains('chiefComplaint.reason'));
        expect(text, contains('primary_required'));
      },
    );

    test(
      'finalizing locks the record, keeps the original and is idempotent',
      () async {
        final cid = await k.readyConsultation();
        await h.actOk(
          'docuser',
          '/consultations/$cid',
          method: 'PATCH',
          body: {
            'assessment': {'notes': 'Likely viral'},
          },
        );
        final f = await h.actOk('docuser', '/consultations/$cid/finalize');
        expect(f['status'], 'finalized');
        expect(f['finalizedBy'], 'docuser');
        expect(f['revision'], 0);
        final again = await h.actOk('docuser', '/consultations/$cid/finalize');
        expect(again['idempotentReplay'], true);
        expect(again['finalizedAt'], f['finalizedAt']);
        expect(
          h
              .clinicalActions(consultationId: cid)
              .where((a) => a == 'consultation.finalized'),
          hasLength(1),
        );
        expect(
          h
              .docsOf('consultation_versions')
              .where((v) => v['consultationId'] == cid),
          hasLength(1),
        );
        // read-only
        expect(
          await h.status(
            'PATCH',
            '/consultations/$cid',
            uid: 'docuser',
            body: {
              'assessment': {'notes': 'silent edit'},
            },
          ),
          409,
        );
        expect(await h.act('docuser', '/consultations/$cid/start'), 409);
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/diagnoses',
            uid: 'docuser',
            body: {
              'kind': 'secondary',
              'certainty': 'provisional',
              'label': 'Late addition',
            },
          ),
          409,
        );
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/investigations',
            uid: 'docuser',
            body: {'testName': 'CBC', 'indication': 'Fever'},
          ),
          409,
        );
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/prescriptions',
            uid: 'docuser',
            body: {'medicines': <Object?>[]},
          ),
          409,
        );
        expect(await h.act('doc2user', '/consultations/$cid/finalize'), 404);
      },
    );

    test('concurrent finalize requests produce one finalization', () async {
      final cid = await k.readyConsultation();
      final results = await Future.wait([
        for (var i = 0; i < 4; i++)
          h.call(
            'POST',
            '/consultations/$cid/finalize',
            uid: 'docuser',
            body: <String, Object?>{},
          ),
      ]);
      expect(results.map((r) => r.statusCode), everyElement(200));
      expect(
        h
            .clinicalActions(consultationId: cid)
            .where((a) => a == 'consultation.finalized'),
        hasLength(1),
      );
    });

    test(
      'an amendment needs a reason and a real change, keeps the original and records who and what',
      () async {
        final cid = await k.readyConsultation();
        await h.actOk(
          'docuser',
          '/consultations/$cid',
          method: 'PATCH',
          body: {
            'assessment': {'notes': 'Likely viral'},
          },
        );
        await h.actOk('docuser', '/consultations/$cid/finalize');
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/amend',
            uid: 'docuser',
            body: {
              'assessment': {'notes': 'x1y2z3'},
            },
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/amend',
            uid: 'docuser',
            body: {'reason': 'Typo fix'},
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/amend',
            uid: 'docuser',
            body: {
              'reason': 'No change',
              'assessment': {'notes': 'Likely viral'},
            },
          ),
          422,
        );
        final a = await h.actOk(
          'docuser',
          '/consultations/$cid/amend',
          body: {
            'reason': 'Correct the assessment',
            'assessment': {'notes': 'Viral fever, rule out dengue'},
          },
        );
        expect(a['status'], 'amended');
        expect(a['revision'], 1);
        expect(
          (a['assessment']! as Map)['notes'],
          'Viral fever, rule out dengue',
        );
        final list = await h.get('docuser', '/consultations/$cid/amendments');
        final amendment =
            (list['amendments']! as List).single as Map<String, Object?>;
        expect(amendment['reason'], 'Correct the assessment');
        expect(amendment['amendedBy'], 'docuser');
        expect(amendment['changedSections'], ['assessment']);
        expect((amendment['before']! as Map)['assessment'], {
          'notes': 'Likely viral',
        });
        final versions = (list['versions']! as List)
            .cast<Map<String, Object?>>();
        expect(versions.map((v) => v['revision']), [0, 1]);
        expect(
          ((versions.first['content']! as Map)['assessment']! as Map)['notes'],
          'Likely viral',
          reason: 'the original is preserved',
        );
        expect(
          k.clinicalActions(consultationId: cid),
          contains('consultation.amended'),
        );
        // amend again: revision 2, original still intact
        await h.actOk(
          'docuser',
          '/consultations/$cid/amend',
          body: {
            'reason': 'Add advice',
            'treatmentPlan': {'lifestyle': 'Rest'},
          },
        );
        final again = await h.get('docuser', '/consultations/$cid/amendments');
        expect((again['versions']! as List), hasLength(3));
      },
    );

    test(
      'only the author amends; drafts cannot be amended; diagnoses change through amendments',
      () async {
        final draft = (await k.newConsultation())['consultationId']! as String;
        expect(
          await h.status(
            'POST',
            '/consultations/$draft/amend',
            uid: 'docuser',
            body: {
              'reason': 'x1y2z3',
              'assessment': {'notes': 'a1'},
            },
          ),
          409,
        );
        final cid = await k.readyConsultation();
        await h.actOk('docuser', '/consultations/$cid/finalize');
        for (final uid in ['recep', 'nurse', 'owner', 'admin']) {
          expect(
            await h.status(
              'POST',
              '/consultations/$cid/amend',
              uid: uid,
              body: {
                'reason': 'Correct it',
                'assessment': {'notes': 'a1'},
              },
            ),
            403,
            reason: uid,
          );
        }
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/amend',
            uid: 'doc2user',
            body: {
              'reason': 'Correct it',
              'assessment': {'notes': 'a1'},
            },
          ),
          404,
        );
        final dx =
            (await h.get('docuser', '/consultations/$cid'))['diagnoses']!
                as List;
        final dxId = (dx.single as Map)['diagnosisId'];
        final a = await h.actOk(
          'docuser',
          '/consultations/$cid/amend',
          body: {
            'reason': 'Diagnosis confirmed by results',
            'diagnosisChanges': [
              {'op': 'update', 'diagnosisId': dxId, 'certainty': 'confirmed'},
              {
                'op': 'add',
                'kind': 'secondary',
                'certainty': 'provisional',
                'label': 'Dehydration',
              },
            ],
          },
        );
        expect(a['status'], 'amended');
        final detail = await h.get('docuser', '/consultations/$cid');
        final labels = (detail['diagnoses']! as List).map(
          (d) => '${(d as Map)['label']}:${d['certainty']}',
        );
        expect(
          labels,
          unorderedEquals(['Viral fever:confirmed', 'Dehydration:provisional']),
        );
        final v =
            (await h.get(
                  'docuser',
                  '/consultations/$cid/amendments',
                ))['versions']!
                as List;
        final original = ((v.first as Map)['diagnoses']! as List).single as Map;
        expect(
          original['certainty'],
          'provisional',
          reason: 'the original diagnosis is preserved',
        );
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/amend',
            uid: 'docuser',
            body: {
              'reason': 'Remove the only primary',
              'diagnosisChanges': [
                {'op': 'remove', 'diagnosisId': dxId},
              ],
            },
          ),
          422,
        );
      },
    );
  });

  group('diagnoses', () {
    late String cid;
    setUp(
      () async =>
          cid = (await k.newConsultation())['consultationId']! as String,
    );

    Future<int> addDx(String uid, Map<String, Object?> body) =>
        h.status('POST', '/consultations/$cid/diagnoses', uid: uid, body: body);

    test('several diagnoses, one primary, provisional or confirmed', () async {
      await k.primaryDx(cid);
      expect(
        await addDx('docuser', {
          'kind': 'primary',
          'certainty': 'provisional',
          'label': 'Second primary',
        }),
        409,
      );
      expect(
        await addDx('docuser', {
          'kind': 'secondary',
          'certainty': 'confirmed',
          'label': 'Anaemia',
          'notes': 'Mild',
        }),
        201,
      );
      expect(
        await addDx('docuser', {
          'kind': 'differential',
          'certainty': 'provisional',
          'label': 'Dengue',
        }),
        201,
      );
      final dx =
          ((await h.get('docuser', '/consultations/$cid'))['diagnoses']!
                  as List)
              .cast<Map<String, Object?>>();
      expect(dx.map((d) => d['kind']), [
        'primary',
        'secondary',
        'differential',
      ]);
      expect(dx.first['createdBy'], 'docuser');
      expect(
        h
            .clinicalActions(consultationId: cid)
            .where((a) => a == 'diagnosis.added'),
        hasLength(3),
      );
    });

    test(
      'validation: label or catalogue entry, kinds, certainty, code needs its system, unknown fields',
      () async {
        for (final bad in [
          {'kind': 'primary', 'certainty': 'provisional'},
          {'kind': 'primary', 'certainty': 'maybe', 'label': 'Fever'},
          {'kind': 'tertiary', 'certainty': 'provisional', 'label': 'Fever'},
          {
            'kind': 'primary',
            'certainty': 'provisional',
            'label': 'Fever',
            'code': 'X1',
          },
          {
            'kind': 'primary',
            'certainty': 'provisional',
            'label': 'Fever',
            'status': 'removed',
          },
          {
            'kind': 'primary',
            'certainty': 'provisional',
            'label': 'Fever',
            'doctorId': 'x',
          },
        ]) {
          expect(await addDx('docuser', bad), anyOf(422), reason: '$bad');
        }
        expect(
          await addDx('docuser', {
            'kind': 'primary',
            'certainty': 'provisional',
            'label': 'Fever',
            'code': 'R50.9',
            'codeSystem': 'ICD-10',
          }),
          201,
          reason: 'a code the doctor supplies with its system',
        );
      },
    );

    test(
      'catalogue entries come from the clinic; invalid entries are refused; labels and codes are not invented',
      () async {
        expect(
          await h.status('GET', '/diagnoses/catalogue?q=fe', uid: 'docuser'),
          200,
        );
        expect(
          await h.list(
            await h.call('GET', '/diagnoses/catalogue?q=fe', uid: 'docuser'),
          ),
          isEmpty,
          reason: 'ships empty',
        );
        expect(
          await h.status(
            'POST',
            '/diagnoses/catalogue',
            uid: 'docuser',
            body: {'name': 'Fever'},
          ),
          403,
        );
        expect(
          await h.status(
            'POST',
            '/diagnoses/catalogue',
            uid: 'admin',
            body: {'name': 'Fever', 'code': 'R50.9'},
          ),
          422,
          reason: 'code without a system',
        );
        final e = await h.actOk(
          'admin',
          '/diagnoses/catalogue',
          status: 201,
          body: {
            'name': 'Fever, unspecified',
            'code': 'R50.9',
            'codeSystem': 'ICD-10',
          },
        );
        expect(
          await h.list(
            await h.call('GET', '/diagnoses/catalogue?q=fev', uid: 'docuser'),
          ),
          hasLength(1),
        );
        final dx = await h.okData(
          h.call(
            'POST',
            '/consultations/$cid/diagnoses',
            uid: 'docuser',
            body: {
              'kind': 'primary',
              'certainty': 'provisional',
              'catalogueId': e['entryId'],
              'label': 'ignored text',
            },
          ),
          status: 201,
        );
        expect(dx['label'], 'Fever, unspecified');
        expect(dx['code'], 'R50.9');
        expect(dx['codeSystem'], 'ICD-10');
        expect(
          await addDx('docuser', {
            'kind': 'secondary',
            'certainty': 'provisional',
            'catalogueId': 'dc_missing',
          }),
          422,
        );
        await h.actOk(
          'admin',
          '/diagnoses/catalogue/${e['entryId']}',
          method: 'PATCH',
          body: {'status': 'inactive'},
        );
        expect(
          await addDx('docuser', {
            'kind': 'secondary',
            'certainty': 'provisional',
            'catalogueId': e['entryId'],
          }),
          422,
        );
      },
    );

    test('changing and removing; unauthorized users cannot modify', () async {
      final dx = await k.primaryDx(cid);
      final id = dx['diagnosisId'];
      final up = await h.actOk(
        'docuser',
        '/consultations/$cid/diagnoses/$id',
        method: 'PATCH',
        body: {'certainty': 'confirmed', 'notes': 'Confirmed on review'},
      );
      expect(up['certainty'], 'confirmed');
      expect(up['version'], 2);
      for (final uid in ['recep', 'nurse', 'admin']) {
        expect(
          await h.status(
            'PATCH',
            '/consultations/$cid/diagnoses/$id',
            uid: uid,
            body: {'certainty': 'provisional'},
          ),
          403,
          reason: uid,
        );
      }
      expect(
        await h.status(
          'PATCH',
          '/consultations/$cid/diagnoses/$id',
          uid: 'doc2user',
          body: {'certainty': 'provisional'},
        ),
        404,
      );
      expect(
        await h.status(
          'PATCH',
          '/consultations/$cid/diagnoses/dx_other',
          uid: 'docuser',
          body: {'certainty': 'provisional'},
        ),
        404,
      );
      await h.actOk(
        'docuser',
        '/consultations/$cid/diagnoses/$id',
        method: 'PATCH',
        body: {'status': 'removed'},
      );
      expect(
        await h.status(
          'PATCH',
          '/consultations/$cid/diagnoses/$id',
          uid: 'docuser',
          body: {'notes': 'x1'},
        ),
        404,
      );
      expect(
        k.clinicalActions(consultationId: cid),
        containsAll([
          'diagnosis.added',
          'diagnosis.updated',
          'diagnosis.removed',
        ]),
      );
    });
  });

  group('investigation requests', () {
    test(
      'are saved against the consultation and clearly not processed',
      () async {
        final cid = (await k.newConsultation())['consultationId']! as String;
        final r = await h.actOk(
          'docuser',
          '/consultations/$cid/investigations',
          status: 201,
          body: {
            'testName': 'Complete blood count',
            'indication': 'Persistent fever',
            'priority': 'urgent',
            'instructions': 'Fasting not required',
          },
        );
        expect(r['status'], 'requested');
        expect(r['processing'], 'not_available');
        expect(r['priority'], 'urgent');
        final list = await h.list(
          await h.call(
            'GET',
            '/consultations/$cid/investigations',
            uid: 'docuser',
          ),
        );
        expect(list, hasLength(1));
        for (final bad in [
          {'testName': 'x', 'indication': 'Fever'},
          {'testName': 'CBC'},
          {'testName': 'CBC', 'indication': 'Fever', 'priority': 'whenever'},
          {'testName': 'CBC', 'indication': 'Fever', 'status': 'completed'},
        ]) {
          expect(
            await h.status(
              'POST',
              '/consultations/$cid/investigations',
              uid: 'docuser',
              body: bad,
            ),
            422,
            reason: '$bad',
          );
        }
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/investigations',
            uid: 'recep',
            body: {'testName': 'CBC', 'indication': 'Fever'},
          ),
          403,
        );
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/investigations',
            uid: 'doc2user',
            body: {'testName': 'CBC', 'indication': 'Fever'},
          ),
          404,
        );
        expect(
          k.clinicalActions(consultationId: cid),
          contains('investigation.requested'),
        );
      },
    );
  });

  group('audit', () {
    test(
      'every step is audited with actor and tenant, without clinical text',
      () async {
        final cid =
            (await k.newConsultation(
                  extra: {
                    'chiefComplaint': {'reason': 'Secret symptom text'},
                  },
                ))['consultationId']!
                as String;
        await h.actOk('docuser', '/consultations/$cid/start');
        await k.primaryDx(cid);
        await h.actOk('docuser', '/consultations/$cid/finalize');
        expect(
          k.clinicalActions(consultationId: cid),
          containsAll([
            'consultation.created',
            'consultation.started',
            'diagnosis.added',
            'consultation.finalized',
          ]),
        );
        for (final d in h.docsOf('clinical_audit_logs')) {
          expect(d['tenantId'], k.tid);
          expect(d['actorUid'], isNotNull);
          expect(d['actorRole'], isNotNull);
        }
        final all = h.docsOf('clinical_audit_logs').toString();
        expect(all, isNot(contains('Secret symptom text')));
        expect(all, isNot(contains('Viral fever')));
        // audit trail can be read by the owner only; nobody can write it
        expect(
          await h.status('GET', '/consultations/$cid/audit-logs', uid: 'owner'),
          200,
        );
        expect(
          await h.status(
            'GET',
            '/consultations/$cid/audit-logs',
            uid: 'docuser',
          ),
          403,
        );
        for (final m in ['POST', 'PATCH', 'DELETE']) {
          expect(
            await h.status(
              m,
              '/consultations/$cid/audit-logs',
              uid: 'owner',
              body: {},
            ),
            anyOf(404, 405),
          );
        }
        expect(consentBody(), isNotEmpty);
        expect(tuesday, isNotEmpty);
      },
    );
  });
}
