import 'dart:convert';

import 'package:test/test.dart';

import '../../support/clinical_fixtures.dart';
import '../../support/lab_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/scheduling_fixtures.dart';

void main() {
  late PlatformHarness h;
  late LabClinic k;
  late String testId;

  setUp(() async {
    h = PlatformHarness();
    k = LabClinic(h);
    await k.init();
    testId = (await k.test())['testId']! as String;
  });

  String itemOf(Map<String, Object?> order) =>
      ((order['items']! as List).first as Map)['itemId']! as String;

  group('catalogue', () {
    test('a test is created with versioning and a unique code', () async {
      final t = await k.test(code: 'GLU', name: 'Glucose');
      expect(t['version'], 1);
      expect(
        await h.status(
          'POST',
          '/laboratory/tests',
          uid: 'owner',
          body: k.testBody(code: 'glu', name: 'Other'),
        ),
        409,
      );
    });

    test('search matches the start of a name', () async {
      await k.test(code: 'GLU', name: 'Glucose fasting');
      final res = await h.call('GET', '/laboratory/tests?q=gluc', uid: 'nurse');
      final rows =
          (jsonDecode(await res.readAsString()) as Map)['data'] as List;
      expect(rows.length, 1);
      expect((rows.first as Map)['code'], 'GLU');
      final none = await h.call('GET', '/laboratory/tests?q=zzz', uid: 'nurse');
      expect((jsonDecode(await none.readAsString()) as Map)['data'], isEmpty);
    });

    test('ranges need a source and sensible limits', () async {
      final body = k.testBody(code: 'BAD', name: 'Bad range');
      final p = (body['parameters']! as List).first as Map;
      ((p['referenceRanges']! as List).first as Map)
        ..['low'] = 20
        ..['high'] = 10;
      expect(
        await h.status('POST', '/laboratory/tests', uid: 'owner', body: body),
        422,
      );
      final noSource = k.testBody(code: 'NOS', name: 'No source');
      (((noSource['parameters']! as List).first as Map)['referenceRanges']!
              as List)
          .cast<Map<String, Object?>>()
          .first
          .remove('source');
      expect(
        await h.status(
          'POST',
          '/laboratory/tests',
          uid: 'owner',
          body: noSource,
        ),
        422,
      );
    });

    test('only permitted roles manage the catalogue', () async {
      expect(
        await h.status(
          'POST',
          '/laboratory/tests',
          uid: 'recep',
          body: k.testBody(code: 'X1', name: 'X'),
        ),
        403,
      );
      expect(await h.status('GET', '/laboratory/tests', uid: 'nurse'), 200);
      expect(await h.status('GET', '/laboratory/tests', uid: 'acct'), 403);
    });

    test('a plan without the laboratory blocks every route', () async {
      final tid = await h.createClinic(
        'other',
        name: 'No Lab Clinic',
        city: 'Nashik',
        pin: '422001',
        laboratory: false,
      );
      expect(tid, isNotEmpty);
      expect(await h.status('GET', '/laboratory/tests', uid: 'other'), 403);
    });
  });

  group('order lifecycle', () {
    test('requested to published with a stored, versioned report', () async {
      final o = await k.order(testId);
      final id = o['orderId']! as String;
      expect(o['orderNumber'], 'LAB-000001');
      expect(o['status'], 'requested');
      await k.post('labtech', '/laboratory/orders/$id/accept', {});
      final s = await k.post(
        'nurse',
        '/laboratory/orders/$id/samples',
        {},
        201,
      );
      final sid = s['sampleId']! as String;
      await k.post('nurse', '/laboratory/samples/$sid/collect', {
        'identifier': 'smp-9001',
        'confirmedMrn': await k.mrn(),
      });
      await k.enter(id, itemOf(o), 13.5);
      await k.post('labtech', '/laboratory/orders/$id/submit-verification');
      await k.post('labtech2', '/laboratory/orders/$id/verify');
      final pub = await k.post('labtech2', '/laboratory/orders/$id/publish');
      expect(pub['version'], 1);
      expect(pub['status'], 'published');
      expect(pub.containsKey('storagePath'), isTrue); // staff projection only
      final d = await h.get('labtech', '/laboratory/orders/$id');
      expect(d['status'], 'published');
      final hist = [
        for (final e in d['history']! as List) (e as Map)['status'],
      ];
      expect(
        hist,
        containsAllInOrder([
          'requested',
          'accepted',
          'sample_pending',
          'sample_collected',
          'processing',
          'result_entered',
          'verification_pending',
          'verified',
          'published',
        ]),
      );
      final dl = await h.call(
        'GET',
        '/laboratory/reports/${pub['reportId']}/download',
        uid: 'labtech',
      );
      expect(dl.statusCode, 200);
      expect(dl.headers['content-type'], 'application/pdf');
      expect(dl.headers['cache-control'], contains('no-store'));
      final bytes = await dl.read().expand((e) => e).toList();
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(
        k.actions(),
        containsAll([
          'lab_order.created',
          'lab_order.accepted',
          'lab_sample.collected',
          'lab_result.saved',
          'lab_result.submitted',
          'lab_result.verified',
          'lab_report.published',
          'lab_report.downloaded',
        ]),
      );
    });

    test('invalid transitions are refused', () async {
      final o = await k.order(testId);
      final id = o['orderId']! as String;
      expect(
        await h.status(
          'POST',
          '/laboratory/orders/$id/verify',
          uid: 'labtech2',
        ),
        409,
      );
      expect(
        await h.status(
          'POST',
          '/laboratory/orders/$id/publish',
          uid: 'labtech',
        ),
        409,
      );
      expect(
        await h.status(
          'POST',
          '/laboratory/orders/$id/samples',
          uid: 'nurse',
          body: {},
        ),
        409,
      );
      await k.post('labtech', '/laboratory/orders/$id/reject', {
        'reason': 'Duplicate request',
      });
      expect(
        await h.status(
          'POST',
          '/laboratory/orders/$id/accept',
          uid: 'labtech',
          body: {},
        ),
        409,
      );
    });

    test('manual orders replay safely with the same Idempotency-Key', () async {
      final body = {
        'patientId': k.patient,
        'branchId': k.br,
        'tests': [
          {'testId': testId},
        ],
      };
      final headers = {'idempotency-key': 'idem-key-0001'};
      final a = await h.okData(
        h.call(
          'POST',
          '/laboratory/orders',
          uid: 'labtech',
          body: body,
          headers: headers,
        ),
        status: 201,
      );
      final b = await h.okData(
        h.call(
          'POST',
          '/laboratory/orders',
          uid: 'labtech',
          body: body,
          headers: headers,
        ),
        status: 201,
      );
      expect(b['orderId'], a['orderId']);
      expect(b['idempotentReplay'], true);
      expect(
        await h.status(
          'POST',
          '/laboratory/orders',
          uid: 'labtech',
          body: {...body, 'priority': 'urgent'},
          headers: headers,
        ),
        409,
      );
      expect(
        await h.status(
          'POST',
          '/laboratory/orders',
          uid: 'labtech',
          body: body,
        ),
        400,
      );
    });
  });

  group('samples', () {
    test('identity must match and identifiers are unique', () async {
      final o = await k.order(testId);
      final id = o['orderId']! as String;
      await k.post('labtech', '/laboratory/orders/$id/accept', {});
      final s = await k.post(
        'nurse',
        '/laboratory/orders/$id/samples',
        {},
        201,
      );
      final sid = s['sampleId']! as String;
      expect(
        await h.status(
          'POST',
          '/laboratory/samples/$sid/collect',
          uid: 'nurse',
          body: {'identifier': 'SMP-1', 'confirmedMrn': 'WRONG-1'},
        ),
        422,
      );
      await k.post('nurse', '/laboratory/samples/$sid/collect', {
        'identifier': 'SMP-1',
        'confirmedMrn': await k.mrn(),
      });
      final o2 = await k.order(testId);
      final id2 = o2['orderId']! as String;
      await k.post('labtech', '/laboratory/orders/$id2/accept', {});
      final s2 = await k.post(
        'nurse',
        '/laboratory/orders/$id2/samples',
        {},
        201,
      );
      expect(
        await h.status(
          'POST',
          '/laboratory/samples/${s2['sampleId']}/collect',
          uid: 'nurse',
          body: {'identifier': 'smp-1', 'confirmedMrn': await k.mrn()},
        ),
        409,
      );
    });

    test('a rejected sample forces recollection', () async {
      final o = await k.collected(testId);
      final id = o['orderId']! as String;
      await k.post('nurse', '/laboratory/samples/${o['sampleId']}/reject', {
        'reason': 'Haemolysed sample',
      });
      var d = await h.get('labtech', '/laboratory/orders/$id');
      expect(d['status'], 'recollection_required');
      final again = await k.post(
        'nurse',
        '/laboratory/samples/${o['sampleId']}/recollect',
        null,
        201,
      );
      expect(again['recollectOf'], o['sampleId']);
      d = await h.get('labtech', '/laboratory/orders/$id');
      expect(d['status'], 'sample_pending');
      expect(
        await h.status(
          'POST',
          '/laboratory/samples/${o['sampleId']}/recollect',
          uid: 'nurse',
        ),
        409,
      );
    });

    test('the same identifier cannot be claimed twice at once', () async {
      final ids = <String>[];
      for (var i = 0; i < 2; i++) {
        final o = await k.order(testId);
        final id = o['orderId']! as String;
        await k.post('labtech', '/laboratory/orders/$id/accept', {});
        final s = await k.post(
          'nurse',
          '/laboratory/orders/$id/samples',
          {},
          201,
        );
        ids.add(s['sampleId']! as String);
      }
      final mrn = await k.mrn();
      final codes = await Future.wait([
        for (final sid in ids)
          h.status(
            'POST',
            '/laboratory/samples/$sid/collect',
            uid: 'nurse',
            body: {'identifier': 'RACE-001', 'confirmedMrn': mrn},
          ),
      ]);
      expect(codes.where((c) => c == 200).length, 1);
      expect(codes.where((c) => c == 409).length, 1);
    });
  });

  group('results and flags', () {
    Future<Map<String, Object?>> flagged(num v, {String? tid}) async {
      final o = await k.collected(
        tid ?? testId,
        identifier: 'FLAG-${'$v'.replaceAll('.', '_')}',
      );
      return k.enter(o['orderId']! as String, itemOf(o), v);
    }

    test('flags come from the clinic configuration only', () async {
      // the fixture patient is female: configured range 12-15, critical low 7
      Map<Object?, Object?> obs(Map<String, Object?> r) =>
          ((r['observations']! as List).first as Map);
      expect(obs(await flagged(13.5))['flag'], 'normal');
      expect(obs(await flagged(10.2))['flag'], 'low');
      expect(obs(await flagged(16))['flag'], 'high');
      final crit = obs(await flagged(6));
      expect(crit['flag'], 'critical_low');
      expect((crit['range']! as Map)['source'], 'Clinic lab SOP 2026');
    });

    test('no configured range means not assessed, never a guess', () async {
      final t2 =
          (await k.test(
                code: 'NR',
                name: 'No ranges',
                ranges: false,
              ))['testId']!
              as String;
      final r = await flagged(99, tid: t2);
      expect(
        ((r['observations']! as List).first as Map)['flag'],
        'not_assessed',
      );
    });

    test('values are validated against the parameter type', () async {
      final o = await k.collected(testId);
      final id = o['orderId']! as String;
      for (final bad in [
        {'code': 'HGB', 'value': 'high'},
        {'code': 'NOPE', 'value': 1},
      ]) {
        expect(
          await h.status(
            'PUT',
            '/laboratory/orders/$id/results/${itemOf(o)}',
            uid: 'labtech',
            body: {
              'observations': [bad],
            },
          ),
          422,
        );
      }
    });

    test('incomplete results cannot be submitted', () async {
      final o = await k.collected(testId);
      final id = o['orderId']! as String;
      // processing needs a first save
      expect(
        await h.status(
          'POST',
          '/laboratory/orders/$id/submit-verification',
          uid: 'labtech',
        ),
        409,
      );
      await k.enter(id, itemOf(o), 13);
      expect(
        await h.status(
          'POST',
          '/laboratory/orders/$id/submit-verification',
          uid: 'labtech',
        ),
        200,
      );
    });
  });

  group('verification', () {
    test('the person who entered results cannot verify them', () async {
      final o = await k.collected(testId);
      final id = o['orderId']! as String;
      await k.enter(id, itemOf(o), 13);
      await k.post('labtech', '/laboratory/orders/$id/submit-verification');
      expect(
        await h.status('POST', '/laboratory/orders/$id/verify', uid: 'labtech'),
        409,
      );
      expect(
        await h.status(
          'POST',
          '/laboratory/orders/$id/verify',
          uid: 'labtech2',
        ),
        200,
      );
    });

    test('returned results are edited and resubmitted', () async {
      final o = await k.collected(testId);
      final id = o['orderId']! as String;
      await k.enter(id, itemOf(o), 13);
      await k.post('labtech', '/laboratory/orders/$id/submit-verification');
      await k.post('labtech2', '/laboratory/orders/$id/return', {
        'reason': 'Value looks transposed',
      });
      var d = await h.get('labtech', '/laboratory/orders/$id');
      expect(d['status'], 'processing');
      final r = await k.enter(id, itemOf(o), 14);
      expect(r['status'], 'returned');
      await k.post('labtech', '/laboratory/orders/$id/submit-verification');
      await k.post('labtech2', '/laboratory/orders/$id/verify');
      d = await h.get('labtech', '/laboratory/orders/$id');
      expect(d['status'], 'verified');
    });

    test('verifying and publishing replay safely', () async {
      final id = await k.verified(testId);
      final again = await k.post('labtech2', '/laboratory/orders/$id/verify');
      expect(again['idempotentReplay'], true);
      final p1 = await k.post('labtech2', '/laboratory/orders/$id/publish');
      final p2 = await k.post('labtech2', '/laboratory/orders/$id/publish');
      expect(p2['reportId'], p1['reportId']);
      expect(p2['idempotentReplay'], true);
      expect(h.docsOf('lab_reports').length, 1);
    });

    test('only roles with the permission verify or publish', () async {
      final o = await k.collected(testId);
      final id = o['orderId']! as String;
      await k.enter(id, itemOf(o), 13);
      await k.post('labtech', '/laboratory/orders/$id/submit-verification');
      for (final u in ['nurse', 'recep', 'acct', 'admin']) {
        expect(
          await h.status('POST', '/laboratory/orders/$id/verify', uid: u),
          403,
          reason: u,
        );
      }
    });
  });

  group('amendment', () {
    test('an amended published report becomes a new version', () async {
      final id = await k.verified(testId);
      final v1 = await k.post('labtech2', '/laboratory/orders/$id/publish');
      final item = itemOf(await h.get('labtech', '/laboratory/orders/$id'));
      final am = await k.post(
        'labtech',
        '/laboratory/orders/$id/results/$item/amend',
        {
          'reason': 'Analyser recalibrated, value corrected',
          'observations': [
            {'code': 'HGB', 'value': 11.0},
          ],
        },
        201,
      );
      expect(am['revision'], 2);
      expect((am['revisions']! as List).length, 1);
      // not yet republished: the old report is still the current one
      final d = await h.get('labtech', '/laboratory/orders/$id');
      expect(d['status'], 'verification_pending');
      expect(
        await h.status(
          'POST',
          '/laboratory/orders/$id/publish',
          uid: 'labtech2',
        ),
        409,
      );
      // the amender cannot verify their own amendment
      expect(
        await h.status('POST', '/laboratory/orders/$id/verify', uid: 'labtech'),
        409,
      );
      await k.post('labtech2', '/laboratory/orders/$id/verify');
      final v2 = await k.post('labtech2', '/laboratory/orders/$id/publish');
      expect(v2['version'], 2);
      expect(v2['reportId'], isNot(v1['reportId']));
      final old = await h.get(
        'labtech',
        '/laboratory/reports/${v1['reportId']}',
      );
      expect(old['status'], 'superseded');
      expect(old['current'], false);
      expect(k.actions(), contains('lab_result.amended'));
    });

    test('an amendment needs a reason and a verified result', () async {
      final o = await k.collected(testId);
      final id = o['orderId']! as String;
      await k.enter(id, itemOf(o), 13);
      expect(
        await h.status(
          'POST',
          '/laboratory/orders/$id/results/${itemOf(o)}/amend',
          uid: 'labtech',
          body: {
            'reason': 'Fix it please',
            'observations': [
              {'code': 'HGB', 'value': 12},
            ],
          },
        ),
        409,
      );
      final vid = await k.verified(testId);
      final item = itemOf(await h.get('labtech', '/laboratory/orders/$vid'));
      expect(
        await h.status(
          'POST',
          '/laboratory/orders/$vid/results/$item/amend',
          uid: 'labtech',
          body: {
            'observations': [
              {'code': 'HGB', 'value': 12},
            ],
          },
        ),
        422,
      );
    });
  });

  group('doctor requests', () {
    late String cid;

    test('a catalogue request is linked, not duplicated', () async {
      cid =
          (await h.okData(
                h.call(
                  'POST',
                  '/consultations',
                  uid: 'docuser',
                  body: {
                    'patientId': k.patient,
                    'branchId': k.br,
                    'chiefComplaint': {'reason': 'Tiredness'},
                  },
                ),
                status: 201,
              ))['consultationId']!
              as String;
      await h.actOk('docuser', '/consultations/$cid/start');
      final o = await k.post('docuser', '/consultations/$cid/lab-orders', {
        'priority': 'urgent',
        'tests': [
          {'testId': testId, 'indication': 'Suspected anaemia'},
        ],
      }, 201);
      expect(o['source'], 'doctor');
      expect(o['priority'], 'urgent');
      final linked = h
          .docsOf('investigation_requests')
          .where((d) => d['labOrderId'] == o['orderId']);
      expect(linked.length, 1);
      expect(linked.first['status'], 'ordered');
      expect(
        await h.status(
          'POST',
          '/consultations/$cid/lab-orders',
          uid: 'docuser',
          body: {
            'tests': [
              {'testId': testId},
            ],
          },
        ),
        409,
        reason: 'one active request per consultation and test',
      );
      // cancelling frees the test again
      await k.post('docuser', '/laboratory/orders/${o['orderId']}/cancel', {
        'reason': 'Ordered by mistake',
      });
      expect(
        await h.status(
          'POST',
          '/consultations/$cid/lab-orders',
          uid: 'docuser',
          body: {
            'tests': [
              {'testId': testId},
            ],
          },
        ),
        201,
      );
      expect(
        await h.status('GET', '/consultations/$cid/lab-orders', uid: 'docuser'),
        200,
      );
    });

    test(
      'the doctor sees the order, then only verified results and reports',
      () async {
        cid =
            (await h.okData(
                  h.call(
                    'POST',
                    '/consultations',
                    uid: 'docuser',
                    body: {
                      'patientId': k.patient,
                      'branchId': k.br,
                      'chiefComplaint': {'reason': 'Tiredness'},
                    },
                  ),
                  status: 201,
                ))['consultationId']!
                as String;
        await h.actOk('docuser', '/consultations/$cid/start');
        final o = await k.post('docuser', '/consultations/$cid/lab-orders', {
          'tests': [
            {'testId': testId},
          ],
        }, 201);
        final id = o['orderId']! as String;
        await k.post('labtech', '/laboratory/orders/$id/accept', {});
        final s = await k.post(
          'nurse',
          '/laboratory/orders/$id/samples',
          {},
          201,
        );
        await k.post('nurse', '/laboratory/samples/${s['sampleId']}/collect', {
          'identifier': 'DOC-0001',
          'confirmedMrn': await k.mrn(),
        });
        await k.enter(id, itemOf(o), 9.5);
        await k.post('labtech', '/laboratory/orders/$id/submit-verification');
        // unverified values are invisible to the doctor
        var res = await h.get('docuser', '/laboratory/orders/$id/results');
        expect(res['results'], isEmpty);
        var hist = await h.get(
          'docuser',
          '/clinical/patients/${k.patient}/history',
        );
        expect(((hist['laboratory']! as Map)['reports']! as List), isEmpty);
        await k.post('labtech2', '/laboratory/orders/$id/verify');
        res = await h.get('docuser', '/laboratory/orders/$id/results');
        final obs =
            (((res['results']! as List).first as Map)['observations']! as List)
                    .first
                as Map;
        expect(obs['flag'], 'low');
        expect(
          ((res['results']! as List).first as Map).containsKey(
            'internalComment',
          ),
          isFalse,
        );
        expect(
          ((res['results']! as List).first as Map).containsKey('enteredBy'),
          isFalse,
        );
        final pub = await k.post('labtech2', '/laboratory/orders/$id/publish');
        hist = await h.get(
          'docuser',
          '/clinical/patients/${k.patient}/history',
        );
        final reps = (hist['laboratory']! as Map)['reports']! as List;
        expect(reps.single['reportId'], pub['reportId']);
        // the finalized consultation is never touched by lab activity
        final con = await h.get('docuser', '/consultations/$cid');
        expect(con['status'], 'in_progress');
      },
    );

    test('doctors see only their own orders and verified results', () async {
      final mine = await k.verified(testId);
      // an order raised by the front desk for the same patient is not theirs
      expect(
        await h.status('GET', '/laboratory/orders/$mine', uid: 'docuser'),
        404,
      );
      h.member('doc2user', k.tid, 'doctor');
      expect(
        await h.status('GET', '/laboratory/orders/$mine', uid: 'doc2user'),
        404,
      );
    });
  });

  group('external laboratory', () {
    late String extTest;

    setUp(() async {
      final lab = await h.okData(
        h.call(
          'POST',
          '/laboratory/external-labs',
          uid: 'labtech',
          body: {'name': 'City Reference Lab'},
        ),
        status: 201,
      );
      extTest =
          (await k.test(
                code: 'EXT1',
                name: 'Send-out marker',
                ranges: false,
                extra: {
                  'designation': 'external',
                  'externalLabId': lab['labId'],
                },
              ))['testId']!
              as String;
    });

    List<int> pdf() => ascii.encode('%PDF-1.4 external report body');

    test('upload, clinic review, publish — clearly labelled', () async {
      final o = await k.collected(extTest, identifier: 'EXT-001');
      final id = o['orderId']! as String;
      expect(o['external'], true);
      // internal result entry is not for external tests
      expect(
        await h.status(
          'PUT',
          '/laboratory/orders/$id/results/${itemIdOf(o)}',
          uid: 'labtech',
          body: {
            'observations': [
              {'code': 'HGB', 'value': 1},
            ],
          },
        ),
        409,
      );
      final up = await k
          .post('labtech', '/laboratory/orders/$id/external-report', {
            'fileName': 'ref-lab.pdf',
            'contentBase64': k.b64(pdf()),
            'externalReference': 'CRL-778',
          }, 201);
      expect(up['external'], true);
      expect(up['verifiedByClinic'], false);
      expect(up['label'], contains('External laboratory'));
      // not verifiable by the uploader, nor publishable before review
      expect(
        await h.status('POST', '/laboratory/orders/$id/verify', uid: 'labtech'),
        409,
      );
      await k.post('labtech2', '/laboratory/orders/$id/verify');
      final pub = await k.post('labtech2', '/laboratory/orders/$id/publish');
      expect(pub['external'], true);
      expect(pub['verifiedByClinic'], true);
      final dl = await h.call(
        'GET',
        '/laboratory/reports/${pub['reportId']}/download',
        uid: 'labtech',
      );
      expect(dl.statusCode, 200);
    });

    test(
      'files are checked by content, not by name or declared type',
      () async {
        final o = await k.collected(extTest, identifier: 'EXT-002');
        final id = o['orderId']! as String;
        expect(
          await h.status(
            'POST',
            '/laboratory/orders/$id/external-report',
            uid: 'labtech',
            body: {
              'fileName': 'report.pdf',
              'contentBase64': k.b64(ascii.encode('<html>not a pdf</html>')),
            },
          ),
          422,
        );
        expect(
          await h.status(
            'POST',
            '/laboratory/orders/$id/external-report',
            uid: 'labtech',
            body: {'fileName': 'a.pdf', 'contentBase64': '%%%'},
          ),
          422,
        );
      },
    );
  });

  group('isolation and access', () {
    test('another clinic cannot see orders, reports or tests', () async {
      final id = await k.verified(testId);
      final pub = await k.post('labtech2', '/laboratory/orders/$id/publish');
      await h.createClinic(
        'rival',
        name: 'Rival Clinic',
        city: 'Nagpur',
        pin: '440001',
      );
      expect(
        await h.status('GET', '/laboratory/orders/$id', uid: 'rival'),
        404,
      );
      expect(
        await h.status(
          'GET',
          '/laboratory/reports/${pub['reportId']}/download',
          uid: 'rival',
        ),
        404,
      );
      expect(
        await h.status('GET', '/laboratory/tests/$testId', uid: 'rival'),
        404,
      );
      final mine = await h.call('GET', '/laboratory/orders', uid: 'rival');
      expect(mine.statusCode, 200);
      expect((jsonDecode(await mine.readAsString()) as Map)['data'], isEmpty);
    });

    test('branch scope limits staff to their branches', () async {
      final id = await k.verified(testId);
      final other = await h.newBranch('owner', code: 'SECOND');
      h.member(
        'narrow',
        k.tid,
        'lab_technician',
        allBranches: false,
        branchIds: [other],
      );
      expect(
        await h.status('GET', '/laboratory/orders/$id', uid: 'narrow'),
        404,
      );
    });

    test('the audit trail holds no clinical values', () async {
      final id = await k.verified(testId, value: 13.5);
      await k.post('labtech2', '/laboratory/orders/$id/publish');
      final raw = jsonEncode(
        h.docsOf('lab_audit_logs').toList(),
        toEncodable: (e) => '$e',
      );
      expect(raw.contains('Haemoglobin'), isFalse);
      expect(raw.contains('13.5'), isFalse);
      final page = await h.call('GET', '/laboratory/audit', uid: 'owner');
      expect(page.statusCode, 200);
      expect(await h.status('GET', '/laboratory/audit', uid: 'recep'), 403);
    });
  });

  group('dashboard', () {
    test('counts come from real orders', () async {
      await k.order(testId, priority: 'urgent');
      await k.collected(testId);
      final d = await h.get('labtech', '/laboratory/dashboard');
      expect(d['pendingOrders'], greaterThanOrEqualTo(1));
      expect(d['definitions'], isA<Map<String, Object?>>());
      expect(await h.status('GET', '/laboratory/dashboard', uid: 'acct'), 403);
    });
  });
}

String itemIdOf(Map<String, Object?> order) =>
    ((order['items']! as List).first as Map)['itemId']! as String;
