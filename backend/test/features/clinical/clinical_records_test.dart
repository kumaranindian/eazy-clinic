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

  group('prescriptions', () {
    late String cid;
    setUp(
      () async =>
          cid = (await k.newConsultation())['consultationId']! as String,
    );

    Future<int> createRx(String uid, Object? body) => h.status(
      'POST',
      '/consultations/$cid/prescriptions',
      uid: uid,
      body: body,
    );

    test('several medicines with all their fields, saved as a draft', () async {
      final rx = await k.newRx(
        cid,
        meds: [
          k.medicine(
            extra: {
              'genericName': 'Acetaminophen',
              'brandName': 'Brand',
              'quantity': 15,
              'instructions': 'Do not exceed 4 a day',
              'warnings': 'Avoid alcohol',
            },
          ),
          k.medicine(
            name: 'ORS',
            extra: {
              'strength': '1 sachet',
              'dosage': '1 sachet in 200 ml water',
              'frequency': 'after each loose stool',
              'route': 'oral',
            },
          ),
        ],
      );
      expect(rx['status'], 'draft');
      expect(rx['version'], 1);
      expect(rx['number'], isNull);
      expect(rx['doctorId'], k.c.doc);
      expect(rx['tenantId'], k.tid);
      expect((rx['medicines']! as List), hasLength(2));
      expect(
        h.clinicalActions(consultationId: cid),
        contains('prescription.created'),
      );
    });

    test('invalid medicine entries are rejected', () async {
      for (final bad in <Map<String, Object?>>[
        {
          'name': 'Paracetamol',
          'dosage': '',
          'frequency': 'daily',
          'durationValue': 5,
          'durationUnit': 'days',
        },
        {
          'name': 'Paracetamol',
          'dosage': '???',
          'frequency': 'daily',
          'durationValue': 5,
          'durationUnit': 'days',
        },
        {
          'name': 'Paracetamol',
          'frequency': 'daily',
          'durationValue': 5,
          'durationUnit': 'days',
        },
        {
          'name': 'Paracetamol',
          'dosage': '1 tablet',
          'durationValue': 5,
          'durationUnit': 'days',
        },
        {
          'name': 'Paracetamol',
          'dosage': '1 tablet',
          'frequency': 'daily',
          'durationValue': 0,
          'durationUnit': 'days',
        },
        {
          'name': 'Paracetamol',
          'dosage': '1 tablet',
          'frequency': 'daily',
          'durationValue': 5,
          'durationUnit': 'years',
        },
        {
          'name': 'Paracetamol',
          'dosage': '1 tablet',
          'frequency': 'daily',
          'durationValue': 5,
          'durationUnit': 'days',
          'quantity': -1,
        },
        {
          'name': 'Paracetamol',
          'dosage': '1 tablet',
          'frequency': 'daily',
          'durationValue': 5,
          'durationUnit': 'days',
          'foodRelation': 'whenever',
        },
        {
          'name': 'P',
          'dosage': '1 tablet',
          'frequency': 'daily',
          'durationValue': 5,
          'durationUnit': 'days',
        },
        {...k.medicine(), 'price': 10},
      ]) {
        expect(
          await createRx('docuser', {
            'medicines': [bad],
          }),
          422,
          reason: '$bad',
        );
      }
      expect(
        await createRx('docuser', {'medicines': List.filled(31, k.medicine())}),
        422,
      );
      expect(
        await createRx('docuser', {
          'medicines': <Object?>[],
          'status': 'finalized',
        }),
        422,
      );
    });

    test(
      'draft editing: replace, add and remove medicines; stale edits are refused',
      () async {
        final rx = await k.newRx(
          cid,
          meds: [
            k.medicine(),
            k.medicine(name: 'ORS'),
          ],
        );
        final id = rx['prescriptionId']! as String;
        final u = await h.actOk(
          'docuser',
          '/prescriptions/$id',
          method: 'PATCH',
          body: {
            'expectedRev': 1,
            'medicines': [
              k.medicine(
                name: 'Paracetamol 650',
                extra: {'strength': '650 mg'},
              ),
              k.medicine(name: 'Cetirizine'),
              k.medicine(name: 'ORS'),
            ],
            'notes': 'Review in 5 days',
          },
        );
        expect((u['medicines']! as List), hasLength(3));
        expect(u['rev'], 2);
        final r = await h.actOk(
          'docuser',
          '/prescriptions/$id',
          method: 'PATCH',
          body: {
            'medicines': [k.medicine(name: 'Cetirizine')],
          },
        );
        expect((r['medicines']! as List), hasLength(1));
        expect(
          await h.status(
            'PATCH',
            '/prescriptions/$id',
            uid: 'docuser',
            body: {'expectedRev': 1, 'notes': 'stale'},
          ),
          409,
        );
        expect(
          await h.status(
            'PATCH',
            '/prescriptions/$id',
            uid: 'docuser',
            body: {},
          ),
          400,
        );
        expect(
          await h.status(
            'PATCH',
            '/prescriptions/$id',
            uid: 'docuser',
            body: {'status': 'finalized'},
          ),
          422,
        );
        expect(
          await h.status(
            'PATCH',
            '/prescriptions/$id',
            uid: 'docuser',
            body: {'doctorId': 'dr_x'},
          ),
          422,
        );
      },
    );

    test('only the doctor can create, edit, view or finalize', () async {
      for (final uid in ['recep', 'nurse', 'admin', 'acct', 'owner']) {
        expect(
          await createRx(uid, {
            'medicines': [k.medicine()],
          }),
          403,
          reason: uid,
        );
      }
      expect(
        await createRx('doc2user', {
          'medicines': [k.medicine()],
        }),
        404,
      );
      final id = (await k.newRx(cid))['prescriptionId']! as String;
      await h.actOk('docuser', '/consultations/$cid/start');
      for (final uid in ['recep', 'nurse', 'admin']) {
        expect(
          await h.act(uid, '/prescriptions/$id/finalize'),
          403,
          reason: uid,
        );
        expect(
          await h.status('GET', '/prescriptions/$id', uid: uid),
          403,
          reason: uid,
        );
      }
      expect(
        await h.act('owner', '/prescriptions/$id/finalize'),
        403,
        reason: 'the owner is not the prescriber',
      );
      expect(await h.act('doc2user', '/prescriptions/$id/finalize'), 404);
      expect(
        await h.status(
          'PATCH',
          '/prescriptions/$id',
          uid: 'doc2user',
          body: {'notes': 'hijack'},
        ),
        404,
      );
      expect(await h.status('GET', '/prescriptions/$id', uid: 'owner'), 200);
    });

    test(
      'finalizing needs a started consultation and a medicine, numbers it and is idempotent',
      () async {
        final id = (await k.newRx(cid))['prescriptionId']! as String;
        expect(
          await h.act('docuser', '/prescriptions/$id/finalize'),
          409,
          reason: 'consultation not started',
        );
        await h.actOk('docuser', '/consultations/$cid/start');
        final empty =
            (await k.newRx(
                  cid,
                  meds: <Map<String, Object?>>[],
                ))['prescriptionId']!
                as String;
        expect(await h.act('docuser', '/prescriptions/$empty/finalize'), 422);
        final f = await h.actOk('docuser', '/prescriptions/$id/finalize');
        expect(f['status'], 'finalized');
        expect(f['number'], 'RX-000001');
        expect(f['finalizedBy'], 'docuser');
        final again = await h.actOk('docuser', '/prescriptions/$id/finalize');
        expect(again['idempotentReplay'], true);
        expect(again['number'], 'RX-000001');
        expect(
          h
              .clinicalActions(consultationId: cid)
              .where((a) => a == 'prescription.finalized'),
          hasLength(1),
        );
        final second = (await k.newRx(cid))['prescriptionId']! as String;
        expect(
          (await h.actOk(
            'docuser',
            '/prescriptions/$second/finalize',
          ))['number'],
          'RX-000002',
        );
      },
    );

    test('concurrent finalize requests produce one number', () async {
      await h.actOk('docuser', '/consultations/$cid/start');
      final id = (await k.newRx(cid))['prescriptionId']! as String;
      final res = await Future.wait([
        for (var i = 0; i < 4; i++)
          h.call(
            'POST',
            '/prescriptions/$id/finalize',
            uid: 'docuser',
            body: <String, Object?>{},
          ),
      ]);
      expect(res.map((r) => r.statusCode), everyElement(200));
      expect(h.docsOf('prescription_numbers'), hasLength(1));
      expect(
        h
            .clinicalActions(consultationId: cid)
            .where((a) => a == 'prescription.finalized'),
        hasLength(1),
      );
    });

    test(
      'a finalized prescription is never edited; an amendment creates a replacement and keeps the original',
      () async {
        await h.actOk('docuser', '/consultations/$cid/start');
        final id =
            (await k.newRx(
                  cid,
                  meds: [
                    k.medicine(),
                    k.medicine(name: 'ORS'),
                  ],
                ))['prescriptionId']!
                as String;
        await h.actOk('docuser', '/prescriptions/$id/finalize');
        expect(
          await h.status(
            'PATCH',
            '/prescriptions/$id',
            uid: 'docuser',
            body: {'notes': 'silent edit'},
          ),
          409,
        );
        expect(
          await h.status(
            'POST',
            '/prescriptions/$id/amend',
            uid: 'docuser',
            body: {
              'medicines': [k.medicine()],
            },
          ),
          422,
          reason: 'a reason is required',
        );
        expect(
          await h.status(
            'POST',
            '/prescriptions/$id/amend',
            uid: 'recep',
            body: {'reason': 'Wrong dose'},
          ),
          403,
        );
        expect(
          await h.status(
            'POST',
            '/prescriptions/$id/amend',
            uid: 'doc2user',
            body: {'reason': 'Wrong dose'},
          ),
          404,
        );
        final rep = await h.actOk(
          'docuser',
          '/prescriptions/$id/amend',
          status: 201,
          body: {
            'reason': 'Wrong dose of paracetamol',
            'medicines': [
              k.medicine(extra: {'dosage': '2 tablets'}),
              k.medicine(name: 'ORS'),
            ],
          },
        );
        expect(rep['status'], 'draft');
        expect(rep['version'], 2);
        expect(rep['supersedesId'], id);
        expect(rep['rootId'], id);
        expect(
          await h.status(
            'POST',
            '/prescriptions/$id/amend',
            uid: 'docuser',
            body: {'reason': 'Second try'},
          ),
          409,
          reason: 'an amendment is already open',
        );
        // until the replacement is finalized the original stays current
        expect(
          (await h.get('docuser', '/prescriptions/$id'))['status'],
          'finalized',
        );
        final repId = rep['prescriptionId']! as String;
        final fin = await h.actOk('docuser', '/prescriptions/$repId/finalize');
        expect(fin['status'], 'finalized');
        expect(
          fin['number'],
          'RX-000001',
          reason: 'the number follows the prescription through its versions',
        );
        final orig = await h.get('docuser', '/prescriptions/$id');
        expect(orig['status'], 'amended');
        expect(orig['replacedById'], repId);
        expect(
          ((orig['medicines']! as List).first as Map)['dosage'],
          '1 tablet',
          reason: 'the original is preserved',
        );
        final chain =
            (await h.get('docuser', '/prescriptions/$repId'))['versions']!
                as List;
        expect(chain.map((v) => (v as Map)['version']), [1, 2]);
        expect(chain.map((v) => (v as Map)['status']), [
          'amended',
          'finalized',
        ]);
        expect(
          await h.status(
            'POST',
            '/prescriptions/$id/amend',
            uid: 'docuser',
            body: {'reason': 'Amend the old one'},
          ),
          409,
        );
        final actions = h.clinicalActions(consultationId: cid);
        expect(
          actions,
          containsAll([
            'prescription.finalized',
            'prescription.amendment_started',
            'prescription.amended',
          ]),
        );
        expect(
          h
              .docsOf('clinical_audit_logs')
              .any(
                (d) =>
                    d['action'] == 'prescription.amended' &&
                    d['reason'] == 'Wrong dose of paracetamol',
              ),
          isTrue,
        );
      },
    );

    test(
      'catalogue entries are only a lookup; unknown ids are refused; nothing is suggested',
      () async {
        expect(
          await h.list(
            await h.call('GET', '/medicines/catalogue?q=pa', uid: 'docuser'),
          ),
          isEmpty,
        );
        expect(
          await h.status(
            'POST',
            '/medicines/catalogue',
            uid: 'docuser',
            body: {'name': 'Paracetamol'},
          ),
          403,
        );
        final e = await h.actOk(
          'admin',
          '/medicines/catalogue',
          status: 201,
          body: {
            'name': 'Paracetamol 500 mg',
            'genericName': 'Paracetamol',
            'form': 'tablet',
          },
        );
        expect(
          await h.list(
            await h.call('GET', '/medicines/catalogue?q=para', uid: 'docuser'),
          ),
          hasLength(1),
        );
        expect(
          await h.status('GET', '/medicines/catalogue?q=para', uid: 'recep'),
          403,
        );
        expect(
          await createRx('docuser', {
            'medicines': [
              k.medicine(extra: {'catalogueId': e['entryId']}),
            ],
          }),
          201,
        );
        expect(
          await createRx('docuser', {
            'medicines': [
              k.medicine(extra: {'catalogueId': 'md_missing'}),
            ],
          }),
          422,
        );
        await h.actOk(
          'admin',
          '/medicines/catalogue/${e['entryId']}',
          method: 'PATCH',
          body: {'status': 'inactive'},
        );
        expect(
          await createRx('docuser', {
            'medicines': [
              k.medicine(extra: {'catalogueId': e['entryId']}),
            ],
          }),
          422,
        );
      },
    );

    test('another clinic cannot read or change it', () async {
      final id = (await k.newRx(cid))['prescriptionId']! as String;
      await h.createClinic('ownerB', name: 'Other Clinic');
      expect(
        await h.status('GET', '/prescriptions/$id', uid: 'ownerB'),
        anyOf(403, 404),
      );
      expect(
        await h.act('ownerB', '/prescriptions/$id/finalize'),
        anyOf(403, 404),
      );
    });
  });

  group('vitals', () {
    Future<Map<String, Object?>> record(
      String uid,
      Map<String, Object?> body, {
      int status = 201,
    }) => h.okData(
      h.call(
        'POST',
        '/clinical/patients/${k.patient}/vitals',
        uid: uid,
        body: body,
      ),
      status: status,
    );

    test(
      'valid measurements are stored with the person, time and originals; BMI is calculated and marked',
      () async {
        final v = await record('nurse', {
          'height': {'value': 175, 'unit': 'cm'},
          'weight': {'value': 70, 'unit': 'kg'},
          'systolic': 120,
          'diastolic': 80,
          'pulse': 72,
          'temperature': {'value': 98.6, 'unit': 'F'},
          'respiratoryRate': 16,
          'spo2': 98,
          'glucose': {'value': 5.5, 'unit': 'mmol/L'},
          'additional': [
            {'name': 'Pain score', 'value': '3', 'unit': '/10'},
          ],
        });
        expect(v['bmi'], 22.9);
        expect(v['bmiCalculated'], true);
        expect(v['recordedBy'], 'nurse');
        expect(v['recordedByRole'], 'nurse');
        expect(v['measuredAt'], isNotNull);
        expect(v['temperatureC'], 37.0);
        expect((v['original']! as Map)['temperature'], {
          'value': 98.6,
          'unit': 'F',
        });
        expect(v['glucoseMgDl'], closeTo(99.1, 0.1));
        expect(v['tenantId'], k.tid);
      },
    );

    test('unit conversion and BMI correctness', () async {
      final v = await record('docuser', {
        'height': {'value': 70, 'unit': 'in'},
        'weight': {'value': 154.32, 'unit': 'lb'},
      });
      expect(v['heightCm'], 177.8);
      expect(v['weightKg'], closeTo(70.0, 0.01));
      expect(v['bmi'], 22.1);
      final onlyWeight = await record('docuser', {
        'weight': {'value': 60, 'unit': 'kg'},
      });
      expect(onlyWeight.containsKey('bmi'), isFalse);
      expect(onlyWeight['bmiCalculated'], isNull);
    });

    test('implausible values, units and combinations are rejected', () async {
      for (final bad in <Map<String, Object?>>[
        {
          'temperature': {'value': 50, 'unit': 'C'},
        },
        {
          'temperature': {'value': 98.6, 'unit': 'K'},
        },
        {'spo2': 120},
        {'pulse': 5},
        {'respiratoryRate': 200},
        {'systolic': 120},
        {'systolic': 80, 'diastolic': 90},
        {
          'height': {'value': 1000, 'unit': 'cm'},
        },
        {
          'weight': {'value': -3, 'unit': 'kg'},
        },
        {
          'weight': {'value': 'heavy', 'unit': 'kg'},
        },
        {
          'glucose': {'value': 5000, 'unit': 'mg/dL'},
        },
        <String, Object?>{},
        {'pulse': 70, 'measuredAt': '2099-01-01T00:00:00Z'},
        {'pulse': 70, 'measuredAt': '2020-01-01T00:00:00Z'},
        {'pulse': 70, 'bmi': 22},
        {'pulse': 70, 'patientId': 'pt_x'},
        {
          'pulse': 70,
          'additional': List.filled(11, {'name': 'abc', 'value': '1'}),
        },
      ]) {
        expect(
          await h.status(
            'POST',
            '/clinical/patients/${k.patient}/vitals',
            uid: 'nurse',
            body: bad,
          ),
          422,
          reason: '$bad',
        );
      }
    });

    test(
      'history is preserved and never overwritten; corrections are new records',
      () async {
        final a = await record('nurse', {'pulse': 70});
        h.clock.now = h.clock.now.add(const Duration(minutes: 30));
        final b = await record('nurse', {
          'pulse': 98,
          'correctsVitalsId': a['vitalsId'],
        });
        final list = await h.list(
          await h.call(
            'GET',
            '/clinical/patients/${k.patient}/vitals',
            uid: 'docuser',
          ),
        );
        expect(list, hasLength(2));
        expect(
          (list.first! as Map)['vitalsId'],
          b['vitalsId'],
          reason: 'newest first, so the previous value can be compared',
        );
        expect((list.last! as Map)['pulse'], 70);
        for (final m in ['PATCH', 'PUT', 'DELETE']) {
          expect(
            await h.status(
              m,
              '/clinical/patients/${k.patient}/vitals/${a['vitalsId']}',
              uid: 'nurse',
              body: {'pulse': 1},
            ),
            anyOf(404, 405),
            reason: m,
          );
        }
        expect(
          await h.status(
            'POST',
            '/clinical/patients/${k.patient}/vitals',
            uid: 'nurse',
            body: {'pulse': 70, 'correctsVitalsId': 'vt_missing'},
          ),
          422,
        );
      },
    );

    test('who may record and read; tenant and branch isolation', () async {
      expect(
        await h.status(
          'POST',
          '/clinical/patients/${k.patient}/vitals',
          uid: 'recep',
          body: {'pulse': 70},
        ),
        403,
      );
      expect(
        await h.status(
          'POST',
          '/clinical/patients/${k.patient}/vitals',
          uid: 'acct',
          body: {'pulse': 70},
        ),
        403,
      );
      expect(
        await h.status(
          'GET',
          '/clinical/patients/${k.patient}/vitals',
          uid: 'recep',
        ),
        403,
      );
      expect(
        await h.status(
          'GET',
          '/clinical/patients/${k.patient}/vitals',
          uid: 'nurse',
        ),
        200,
      );
      await h.createClinic('ownerB', name: 'Other Clinic');
      expect(
        await h.status(
          'GET',
          '/clinical/patients/${k.patient}/vitals',
          uid: 'ownerB',
        ),
        anyOf(403, 404),
      );
      expect(
        await h.status(
          'POST',
          '/clinical/patients/${k.patient}/vitals',
          uid: 'ownerB',
          body: {'pulse': 70},
        ),
        anyOf(403, 404),
      );
      final b2 = await h.newBranch('owner', code: 'EAST');
      h.member(
        'eastnurse',
        k.tid,
        'nurse',
        allBranches: false,
        branchIds: [b2],
      );
      expect(
        await h.status(
          'POST',
          '/clinical/patients/${k.patient}/vitals',
          uid: 'eastnurse',
          body: {'pulse': 70},
        ),
        404,
      );
      expect(
        await h.status(
          'GET',
          '/clinical/patients/${k.patient}/vitals',
          uid: 'eastnurse',
        ),
        404,
      );
    });

    test(
      'vitals can be linked to the doctor\'s consultation of the same patient only',
      () async {
        final cid = (await k.newConsultation())['consultationId']! as String;
        final v = await record('docuser', {'pulse': 80, 'consultationId': cid});
        expect(v['consultationId'], cid);
        final other = await k.c.morePatient(1);
        expect(
          await h.status(
            'POST',
            '/clinical/patients/$other/vitals',
            uid: 'docuser',
            body: {'pulse': 80, 'consultationId': cid},
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/clinical/patients/${k.patient}/vitals',
            uid: 'nurse',
            body: {'pulse': 80, 'consultationId': cid},
          ),
          404,
          reason: 'a nurse cannot see a doctor\'s consultation',
        );
        expect(h.clinicalActions(), contains('vitals.recorded'));
      },
    );
  });

  group('follow-ups', () {
    late String cid;
    setUp(
      () async =>
          cid = (await k.newConsultation())['consultationId']! as String,
    );

    Map<String, Object?> fu({
      String date = '2026-06-10',
      Map<String, Object?>? extra,
    }) => {
      'recommendedDate': date,
      'reason': 'Review fever',
      'instructions': 'Bring reports',
      ...?extra,
    };

    test(
      'create, list upcoming and overdue, and move through the statuses',
      () async {
        final f = await h.actOk(
          'docuser',
          '/consultations/$cid/followups',
          status: 201,
          body: fu(),
        );
        expect(f['status'], 'scheduled');
        expect(
          f['appointmentId'],
          isNull,
          reason: 'a recommendation is not an appointment',
        );
        expect(f['doctorId'], k.c.doc);
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/followups',
            uid: 'docuser',
            body: fu(date: '2026-05-01'),
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/followups',
            uid: 'docuser',
            body: fu(extra: {'status': 'completed'}),
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/followups',
            uid: 'recep',
            body: fu(),
          ),
          403,
        );
        expect(
          await h.status(
            'POST',
            '/consultations/$cid/followups',
            uid: 'doc2user',
            body: fu(),
          ),
          404,
        );
        final up = await h.list(
          await h.call(
            'GET',
            '/doctor/followups?upcoming=true',
            uid: 'docuser',
          ),
        );
        expect(up, hasLength(1));
        expect(
          await h.list(
            await h.call(
              'GET',
              '/doctor/followups?overdue=true',
              uid: 'docuser',
            ),
          ),
          isEmpty,
        );
        h.clock.now = DateTime.utc(2026, 6, 20, 4, 30);
        final od = await h.list(
          await h.call('GET', '/doctor/followups?overdue=true', uid: 'docuser'),
        );
        expect(od, hasLength(1));
        expect((od.single! as Map)['overdue'], true);
        final id = f['followupId']! as String;
        expect(
          (await h.actOk(
            'docuser',
            '/followups/$id',
            method: 'PATCH',
            body: {'status': 'missed'},
          ))['status'],
          'missed',
        );
        expect(
          await h.status(
            'PATCH',
            '/followups/$id',
            uid: 'docuser',
            body: {'status': 'scheduled'},
          ),
          409,
        );
        expect(
          (await h.actOk(
            'docuser',
            '/followups/$id',
            method: 'PATCH',
            body: {'status': 'completed'},
          ))['status'],
          'completed',
        );
        expect(
          await h.status(
            'PATCH',
            '/followups/$id',
            uid: 'docuser',
            body: {'status': 'cancelled'},
          ),
          409,
        );
        expect(
          await h.list(
            await h.call(
              'GET',
              '/doctor/followups?overdue=true',
              uid: 'docuser',
            ),
          ),
          isEmpty,
        );
        expect(
          h.clinicalActions(consultationId: cid),
          containsAll(['followup.created', 'followup.updated']),
        );
      },
    );

    test(
      'editing is only for scheduled follow-ups; other doctors and roles cannot touch it',
      () async {
        final f = await h.actOk(
          'docuser',
          '/consultations/$cid/followups',
          status: 201,
          body: fu(),
        );
        final id = f['followupId']! as String;
        expect(
          (await h.actOk(
            'docuser',
            '/followups/$id',
            method: 'PATCH',
            body: {'recommendedDate': '2026-06-12', 'reason': 'Review again'},
          ))['recommendedDate'],
          '2026-06-12',
        );
        expect(
          await h.status(
            'PATCH',
            '/followups/$id',
            uid: 'doc2user',
            body: {'status': 'cancelled'},
          ),
          404,
        );
        expect(
          await h.status(
            'PATCH',
            '/followups/$id',
            uid: 'recep',
            body: {'status': 'cancelled'},
          ),
          403,
        );
        await h.actOk(
          'docuser',
          '/followups/$id',
          method: 'PATCH',
          body: {'status': 'cancelled'},
        );
        expect(
          await h.status(
            'PATCH',
            '/followups/$id',
            uid: 'docuser',
            body: {'reason': 'later'},
          ),
          409,
        );
        expect(
          await h.status('PATCH', '/followups/$id', uid: 'docuser', body: {}),
          400,
        );
      },
    );

    test(
      'reception sees follow-ups to book but not the clinical wording; another doctor does not see them',
      () async {
        await h.actOk(
          'docuser',
          '/consultations/$cid/followups',
          status: 201,
          body: fu(),
        );
        final r = await h.list(
          await h.call('GET', '/doctor/followups?upcoming=true', uid: 'recep'),
        );
        expect(r, hasLength(1));
        final row = r.single! as Map;
        expect(row['patientName'], 'Asha Patil');
        expect(row.containsKey('reason'), isFalse);
        expect(row.containsKey('instructions'), isFalse);
        expect(
          await h.list(
            await h.call(
              'GET',
              '/doctor/followups?upcoming=true',
              uid: 'doc2user',
            ),
          ),
          isEmpty,
        );
        expect(await h.status('GET', '/doctor/followups', uid: 'acct'), 403);
        await h.createClinic('ownerB', name: 'Other Clinic');
        expect(
          await h.list(
            await h.call(
              'GET',
              '/doctor/followups?upcoming=true',
              uid: 'ownerB',
            ),
          ),
          isEmpty,
        );
      },
    );

    test(
      'booking the follow-up uses the appointment service and cannot be duplicated',
      () async {
        final f = await h.actOk(
          'docuser',
          '/consultations/$cid/followups',
          status: 201,
          body: fu(date: '2026-06-02'),
        );
        final id = f['followupId']! as String;
        Future<int> book(
          String uid, {
          String? key = 'fu-book-0001',
          String start = '09:00',
        }) => h.status(
          'POST',
          '/followups/$id/appointment',
          uid: uid,
          body: {'typeId': k.c.type, 'date': tuesday, 'startTime': start},
          headers: {if (key != null) 'idempotency-key': key},
        );
        expect(await book('acct'), 403);
        expect(await book('recep', key: null), 400);
        final res = await h.okData(
          h.call(
            'POST',
            '/followups/$id/appointment',
            uid: 'recep',
            headers: {'idempotency-key': 'fu-book-0001'},
            body: {'typeId': k.c.type, 'date': tuesday, 'startTime': '09:00'},
          ),
          status: 201,
        );
        final appt = res['appointment']! as Map<String, Object?>;
        expect(appt['doctorId'], k.c.doc);
        expect(appt['patientId'], k.patient);
        expect(appt['status'], 'confirmed');
        final done =
            (await h.list(
                  await h.call(
                    'GET',
                    '/doctor/followups?from=2026-06-01',
                    uid: 'docuser',
                  ),
                )).single!
                as Map;
        expect(done['appointmentId'], appt['appointmentId']);
        expect(
          await book('recep', key: 'fu-book-0002', start: '10:00'),
          409,
          reason: 'already has an open appointment',
        );
        expect(h.apptDocs().where((a) => a['followupId'] == id), hasLength(1));
        await h.actOk(
          'recep',
          '/appointments/${appt['appointmentId']}/cancel',
          body: {'reason': 'Patient called'},
        );
        expect(
          await book('recep', key: 'fu-book-0003', start: '10:00'),
          201,
          reason: 'allowed again after the first was cancelled',
        );
        expect(
          h.clinicalActions(consultationId: cid),
          contains('followup.appointment_booked'),
        );
      },
    );
  });

  group('templates', () {
    Map<String, Object?> body({
      String scope = 'doctor',
      String name = 'Cold and cough',
    }) => {
      'name': name,
      'scope': scope,
      'description': 'Common cold',
      'content': {
        'chiefComplaint': {'reason': 'Cough and runny nose'},
        'treatmentPlan': {'lifestyle': 'Steam inhalation'},
      },
    };

    test(
      'doctors manage their own templates; the clinic manages shared ones; both can be used',
      () async {
        expect(
          await h.status(
            'POST',
            '/clinical/templates',
            uid: 'docuser',
            body: body(scope: 'clinic'),
          ),
          403,
        );
        expect(
          await h.status(
            'POST',
            '/clinical/templates',
            uid: 'recep',
            body: body(),
          ),
          403,
        );
        expect(
          await h.status(
            'POST',
            '/clinical/templates',
            uid: 'admin',
            body: body(),
          ),
          403,
          reason: 'admins are not doctors',
        );
        final mine = await h.actOk(
          'docuser',
          '/clinical/templates',
          status: 201,
          body: body(),
        );
        final shared = await h.actOk(
          'admin',
          '/clinical/templates',
          status: 201,
          body: body(scope: 'clinic', name: 'General consultation'),
        );
        expect(mine['doctorId'], k.c.doc);
        expect(shared['doctorId'], isNull);
        final listDoc = (await h.okDataList(
          'docuser',
          '/clinical/templates',
        )).map((t) => t['name']);
        expect(
          listDoc,
          unorderedEquals(['Cold and cough', 'General consultation']),
        );
        final listOther = (await h.okDataList(
          'doc2user',
          '/clinical/templates',
        )).map((t) => t['name']);
        expect(listOther, [
          'General consultation',
        ], reason: 'a private template is not visible to other doctors');
        expect(await h.status('GET', '/clinical/templates', uid: 'recep'), 403);
        expect(
          await h.status(
            'PATCH',
            '/clinical/templates/${mine['templateId']}',
            uid: 'doc2user',
            body: {'status': 'inactive'},
          ),
          404,
        );
        expect(
          await h.status(
            'PATCH',
            '/clinical/templates/${shared['templateId']}',
            uid: 'docuser',
            body: {'status': 'inactive'},
          ),
          403,
        );
        await h.actOk(
          'admin',
          '/clinical/templates/${shared['templateId']}',
          method: 'PATCH',
          body: {'status': 'inactive'},
        );
        expect(
          (await h.okDataList('doc2user', '/clinical/templates')),
          isEmpty,
        );
        expect(
          (await h.okDataList(
            'admin',
            '/clinical/templates',
          )).where((t) => t['status'] == 'inactive'),
          hasLength(1),
        );
      },
    );

    test(
      'invalid content is refused and the scope cannot be changed',
      () async {
        expect(
          await h.status(
            'POST',
            '/clinical/templates',
            uid: 'docuser',
            body: {
              ...body(),
              'content': {
                'chiefComplaint': {'unknown': 'x'},
              },
            },
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/clinical/templates',
            uid: 'docuser',
            body: {'name': 'x1', 'scope': 'doctor'},
          ),
          422,
        );
        final mine = await h.actOk(
          'docuser',
          '/clinical/templates',
          status: 201,
          body: body(),
        );
        expect(
          await h.status(
            'PATCH',
            '/clinical/templates/${mine['templateId']}',
            uid: 'docuser',
            body: {'scope': 'clinic'},
          ),
          422,
        );
        expect(
          await h.status(
            'PATCH',
            '/clinical/templates/${mine['templateId']}',
            uid: 'docuser',
            body: {},
          ),
          400,
        );
      },
    );
  });

  group('doctor workspace', () {
    test(
      'the dashboard counts only the doctor\'s own visits and shows the queue',
      () async {
        final a1 = await h.bookOk('recep', k.c.body());
        final p2 = await k.c.morePatient(1);
        final other = await h.bookOk(
          'recep',
          h.bookBody(
            patientId: p2,
            doctorId: k.doc2,
            branchId: k.br,
            typeId: k.c.type,
            startTime: '10:00',
          ),
        );
        expect(other['doctorId'], k.doc2);
        await h.bookOk(
          'recep',
          k.c.body(start: '11:00', patientId: await k.c.morePatient(2)),
        );
        final gone = await h.bookOk(
          'recep',
          k.c.body(start: '11:30', patientId: await k.c.morePatient(3)),
        );
        await h.actOk(
          'recep',
          '/appointments/${gone['appointmentId']}/cancel',
          body: {'reason': 'Patient called'},
        );
        h.clock.now = DateTime.utc(2026, 6, 2, 4, 30);
        await h.actOk('recep', '/appointments/${a1['appointmentId']}/check-in');
        final apt = a1['appointmentId']! as String;
        final d = await h.get('docuser', '/doctor/dashboard');
        final c = d['counts']! as Map;
        expect(c['scheduled'], 2);
        expect(c['checkedIn'], 1);
        expect(c['waiting'], 1);
        expect(c['cancelled'], 1);
        expect((d['upcoming']! as List), hasLength(1));
        final q = (d['queues']! as List).single as Map;
        expect((q['nextToken']! as Map)['displayToken'], 'A001');
        final today = (await h.okDataList(
          'docuser',
          '/doctor/appointments/today',
        ));
        expect(
          today.map((a) => a['doctorId'] ?? k.c.doc),
          everyElement(k.c.doc),
        );
        expect(today, hasLength(3));
        final queue = (await h.okDataList('docuser', '/doctor/queue')).single;
        expect((queue['entries']! as List), hasLength(1));
        expect(apt, isNotEmpty);
      },
    );

    test(
      'the doctor calls the next patient through the queue; others cannot',
      () async {
        await k.checkedInVisit();
        final qe =
            (await h.okDataList('docuser', '/doctor/queue')).single['entries']!
                as List;
        final entryId = (qe.single as Map)['entryId'];
        expect(await h.act('recep', '/doctor/queue/$entryId/call'), 403);
        expect(await h.act('doc2user', '/doctor/queue/$entryId/call'), 403);
        final called = await h.actOk('docuser', '/doctor/queue/$entryId/call');
        expect(called['status'], 'called');
        expect(await h.act('docuser', '/doctor/queue/$entryId/call'), 409);
      },
    );

    test(
      'the workspace is for doctors with a linked profile; the owner has no doctor queue',
      () async {
        for (final uid in ['recep', 'nurse', 'admin', 'acct']) {
          expect(
            await h.status('GET', '/doctor/dashboard', uid: uid),
            403,
            reason: uid,
          );
        }
        expect(await h.status('GET', '/doctor/dashboard', uid: 'owner'), 403);
        h.member('unlinked', k.tid, 'doctor');
        expect(
          await h.status('GET', '/doctor/dashboard', uid: 'unlinked'),
          403,
        );
        expect(
          await h.status(
            'GET',
            '/doctor/dashboard?branchId=br_other',
            uid: 'docuser',
          ),
          anyOf(403, 404),
        );
      },
    );
  });

  group('patient clinical profile', () {
    test(
      'overview shows the patient, alerts, allergies, medicines, history and documents, and is audited',
      () async {
        final p = k.patient;
        await h.actOk(
          'docuser',
          '/patients/$p/allergies',
          status: 201,
          body: {
            'allergen': 'Penicillin',
            'category': 'drug',
            'severity': 'severe',
          },
        );
        await h.actOk(
          'docuser',
          '/patients/$p/medications',
          status: 201,
          body: {'name': 'Metformin', 'status': 'current'},
        );
        await h.actOk(
          'docuser',
          '/patients/$p/medical-history',
          status: 201,
          body: {'category': 'condition', 'title': 'Type 2 diabetes'},
        );
        await h.actOk(
          'recep',
          '/patients/$p/alerts',
          status: 201,
          body: {
            'category': 'special_assistance',
            'title': 'Wheelchair',
            'message': 'Needs a wheelchair',
          },
        );
        await h.actOk(
          'recep',
          '/patients/$p/consents',
          status: 201,
          body: {
            'type': 'document_processing',
            'decision': 'granted',
            'textVersion': '1.0',
            'collectionMethod': 'in_person_signed',
            'grantedBy': {'type': 'patient'},
          },
        );
        final o = await h.get('docuser', '/clinical/patients/$p/overview');
        final patient = o['patient']! as Map;
        expect(patient['fullName'], 'Asha Patil');
        expect(patient['mrn'], startsWith('MRN-'));
        expect(patient['age'], isA<int>());
        expect(patient['gender'], 'female');
        expect((o['allergies']! as List).single['allergen'], 'Penicillin');
        expect((o['medications']! as List).single['name'], 'Metformin');
        expect(
          (o['medicalHistory']! as List).single['title'],
          'Type 2 diabetes',
        );
        expect((o['alerts']! as List).single['title'], 'Wheelchair');
        expect(o['documents'], isEmpty);
        expect(h.clinicalActions(), contains('clinical.overview_viewed'));
        expect(h.auditActions(p), contains('clinical.overview_viewed'));
      },
    );

    test(
      'non-clinical roles, other branches and other clinics are refused',
      () async {
        for (final uid in ['recep', 'nurse', 'admin', 'acct']) {
          expect(
            await h.status(
              'GET',
              '/clinical/patients/${k.patient}/overview',
              uid: uid,
            ),
            403,
            reason: uid,
          );
          expect(
            await h.status(
              'GET',
              '/clinical/patients/${k.patient}/history',
              uid: uid,
            ),
            403,
            reason: uid,
          );
        }
        await h.createClinic('ownerB', name: 'Other Clinic');
        expect(
          await h.status(
            'GET',
            '/clinical/patients/${k.patient}/overview',
            uid: 'ownerB',
          ),
          anyOf(403, 404),
        );
        final b2 = await h.newBranch('owner', code: 'EAST');
        final east = await h.newDoctor(
          'owner',
          branchIds: [b2],
          name: 'Dr East',
          n: '5',
        );
        h.member(
          'eastdoc',
          k.tid,
          'doctor',
          allBranches: false,
          branchIds: [b2],
        );
        h.store.docs['tenants/${k.tid}/members/eastdoc']!['doctorId'] = east;
        expect(
          await h.status(
            'GET',
            '/clinical/patients/${k.patient}/overview',
            uid: 'eastdoc',
          ),
          404,
        );
        expect(
          await h.status(
            'GET',
            '/clinical/patients/${k.patient}/history',
            uid: 'eastdoc',
          ),
          404,
        );
      },
    );

    test(
      'history lists the doctor\'s own consultations, prescriptions and follow-ups; laboratory is not available',
      () async {
        final cid = await k.readyConsultation();
        final rx = (await k.newRx(cid))['prescriptionId']! as String;
        await h.actOk('docuser', '/prescriptions/$rx/finalize');
        await h.actOk('docuser', '/consultations/$cid/finalize');
        await h.actOk(
          'docuser',
          '/consultations/$cid/followups',
          status: 201,
          body: {'recommendedDate': '2026-06-10', 'reason': 'Review'},
        );
        final other = await h.okData(
          h.call('POST', '/consultations', uid: 'doc2user', body: k.consult()),
          status: 201,
        );
        final r = await h.get(
          'docuser',
          '/clinical/patients/${k.patient}/history',
        );
        final cons = (r['consultations']! as List).cast<Map<String, Object?>>();
        expect(cons, hasLength(1));
        expect(cons.single['consultationId'], cid);
        expect(
          (cons.single['diagnoses']! as List).single['label'],
          'Viral fever',
        );
        expect((r['prescriptions']! as List).single['number'], 'RX-000001');
        expect((r['followups']! as List), hasLength(1));
        expect((r['laboratory']! as Map)['available'], false);
        // another doctor's draft is not shown to this doctor; the owner sees both
        expect(
          cons.map((c) => c['consultationId']),
          isNot(contains(other['consultationId'])),
        );
        final all = await h.get(
          'owner',
          '/clinical/patients/${k.patient}/history',
        );
        expect((all['consultations']! as List), hasLength(2));
        expect(h.clinicalActions(), contains('clinical.history_viewed'));
      },
    );
  });

  test('no clinical content ever reaches the logs or audit records', () async {
    final cid =
        (await k.newConsultation(
              extra: {
                'chiefComplaint': {'reason': 'Distinctive complaint text'},
              },
            ))['consultationId']!
            as String;
    await h.actOk('docuser', '/consultations/$cid/start');
    final rx = await k.newRx(
      cid,
      meds: [k.medicine(name: 'Distinctive medicine')],
    );
    await h.actOk('docuser', '/prescriptions/${rx['prescriptionId']}/finalize');
    expect(h.logs.join('\n'), isNot(contains('Distinctive')));
    expect(
      h.docsOf('clinical_audit_logs').toString(),
      isNot(contains('Distinctive')),
    );
    expect(
      h.docsOf('platform_audit_logs').toString(),
      isNot(contains('Distinctive')),
    );
    expect(consentBody(), isNotEmpty);
    expect(tuesday, isNotEmpty);
  });
}

extension on PlatformHarness {
  Future<List<Map<String, Object?>>> okDataList(
    String uid,
    String path,
  ) async => (await list(
    await call('GET', path, uid: uid),
  )).cast<Map<String, Object?>>();
}
