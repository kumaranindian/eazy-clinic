import 'package:test/test.dart';

import '../../support/lab_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/portal_fixtures.dart';
import '../../support/scheduling_fixtures.dart';

void main() {
  late PlatformHarness h;
  late PortalClinic p;

  setUp(() async {
    h = PlatformHarness();
    p = PortalClinic(h);
    await p.init();
  });

  Iterable<String> cats(String account) => h
      .docsOf('patient_notifications')
      .where((n) => n['accountId'] == account)
      .map((n) => '${n['category']}');

  group('staff actions notify the patient through the pipeline', () {
    test('confirm, move and cancel', () async {
      final booked = await p.book();
      final id = booked['appointmentId']! as String;
      expect(cats(p.accountId), ['appointment_booked']);
      await h.actOk('recep', '/appointments/$id/confirm');
      expect(cats(p.accountId), contains('appointment_confirmed'));
      await h.actOk(
        'recep',
        '/appointments/$id/cancel',
        body: {'reason': 'Doctor unavailable'},
      );
      expect(cats(p.accountId), contains('appointment_cancelled'));
      // every one went through an event and has a tracked delivery
      expect(h.docsOf('notification_events').length, greaterThanOrEqualTo(3));
      expect(
        h
            .docsOf('notification_deliveries')
            .where(
              (d) => d['channel'] == 'in_app' && d['status'] == 'delivered',
            )
            .length,
        greaterThanOrEqualTo(3),
      );
    });

    test('check-in and the call to the room', () async {
      final id = await p.k.checkedInVisit();
      expect(id, isNotEmpty);
      expect(cats(p.accountId), contains('token_generated'));
      final qid = h.docsOf('queue_entries').first['queueId']! as String;
      await h.actOk('recep', '/queues/$qid/call-next');
      expect(cats(p.accountId), contains('doctor_calling'));
      final msg = h
          .docsOf('patient_notifications')
          .firstWhere((n) => n['category'] == 'doctor_calling');
      expect('${msg['title']} ${msg['body']}'.contains('MRN'), isFalse);
    });

    test('nobody else is told about this patient\'s visit', () async {
      await p.createAccount('ravi');
      final other = await p.k.c.morePatient(3);
      await p.link('ravi', other);
      final booked = await p.book();
      await h.actOk(
        'recep',
        '/appointments/${booked['appointmentId']}/confirm',
      );
      final ravi =
          (await h.okData(
                h.call('GET', '/patient-accounts/me', uid: 'ravi'),
              ))['accountId']!
              as String;
      expect(cats(ravi), isEmpty);
      expect(
        (await p.get('/patient/notifications', uid: 'ravi'))['items'],
        isEmpty,
      );
    });

    test('a patient without an app account is simply not notified', () async {
      final a = await h.bookOk(
        'recep',
        p.k.c.body(patientId: await p.k.c.morePatient(4)),
      );
      await h.actOk(
        'recep',
        '/appointments/${a['appointmentId']}/cancel',
        body: {'reason': 'Closed that day'},
      );
      expect(
        h
            .docsOf('patient_notifications')
            .where((n) => n['category'] == 'appointment_cancelled'),
        isEmpty,
      );
      expect(h.docsOf('notification_deliveries'), isEmpty);
    });

    test('a failing notification never undoes the business action', () async {
      final booked = await p.book();
      final id = booked['appointmentId']! as String;
      // break the pipeline: it cannot write events any more
      h.store.docs['tenants/${p.tid}/notification_events/ev_blocker'] = {};
      h.clinic.scheduling.onEvent = (t, type, d) async =>
          throw StateError('boom');
      final r = await h.okData(
        h.call('POST', '/appointments/$id/confirm', uid: 'recep'),
      );
      expect(r['status'], 'confirmed');
    });
  });

  group('laboratory events', () {
    test(
      'a rejected sample tells the requesting doctor, without the reason',
      () async {
        final lab = LabClinic.on(h, p.k.c);
        final t = (await lab.test())['testId']! as String;
        final cid =
            (await h.okData(
                  h.call(
                    'POST',
                    '/consultations',
                    uid: 'docuser',
                    body: {
                      'patientId': p.patientId,
                      'branchId': p.br,
                      'chiefComplaint': {'reason': 'Tiredness'},
                    },
                  ),
                  status: 201,
                ))['consultationId']!
                as String;
        await h.actOk('docuser', '/consultations/$cid/start');
        final o = await lab.post('docuser', '/consultations/$cid/lab-orders', {
          'tests': [
            {'testId': t},
          ],
        }, 201);
        final id = o['orderId']! as String;
        await lab.post('labtech', '/laboratory/orders/$id/accept', {});
        final s = await lab.post(
          'nurse',
          '/laboratory/orders/$id/samples',
          {},
          201,
        );
        await lab.post('nurse', '/laboratory/samples/${s['sampleId']}/reject', {
          'reason': 'Haemolysed, glucose looks odd',
        });
        final inbox = await h.list(
          await h.call('GET', '/notifications', uid: 'docuser'),
        );
        final n =
            inbox.firstWhere(
                  (x) => (x! as Map)['category'] == 'lab_sample_rejected',
                )!
                as Map;
        expect('${n['title']} ${n['body']}'.contains('Haemolysed'), isFalse);
        expect(n['resourceType'], 'lab_order');
        // another doctor is not told
        expect(
          await h.list(await h.call('GET', '/notifications', uid: 'doc2user')),
          isEmpty,
        );
      },
    );

    test(
      'publishing a report reaches the patient and the doctor, not other staff',
      () async {
        final lab = LabClinic.on(h, p.k.c);
        final t = (await lab.test())['testId']! as String;
        final cid =
            (await h.okData(
                  h.call(
                    'POST',
                    '/consultations',
                    uid: 'docuser',
                    body: {
                      'patientId': p.patientId,
                      'branchId': p.br,
                      'chiefComplaint': {'reason': 'Tiredness'},
                    },
                  ),
                  status: 201,
                ))['consultationId']!
                as String;
        await h.actOk('docuser', '/consultations/$cid/start');
        final o = await lab.post('docuser', '/consultations/$cid/lab-orders', {
          'tests': [
            {'testId': t},
          ],
        }, 201);
        final id = o['orderId']! as String;
        await lab.post('labtech', '/laboratory/orders/$id/accept', {});
        final s = await lab.post(
          'nurse',
          '/laboratory/orders/$id/samples',
          {},
          201,
        );
        await lab.post(
          'nurse',
          '/laboratory/samples/${s['sampleId']}/collect',
          {'identifier': 'EV-0001', 'confirmedMrn': await lab.mrn()},
        );
        await lab.enter(
          id,
          ((o['items']! as List).first as Map)['itemId']! as String,
          13.5,
        );
        await lab.post('labtech', '/laboratory/orders/$id/submit-verification');
        await lab.post('labtech2', '/laboratory/orders/$id/verify');
        await lab.post('labtech2', '/laboratory/orders/$id/publish');
        expect(cats(p.accountId), contains('report_available'));
        final doc = await h.list(
          await h.call('GET', '/notifications', uid: 'docuser'),
        );
        expect(
          doc.any((x) => (x! as Map)['category'] == 'report_available'),
          isTrue,
        );
        expect(
          await h.list(await h.call('GET', '/notifications', uid: 'recep')),
          isEmpty,
        );
      },
    );
  });

  group('follow-ups', () {
    test('recommending one tells the patient, with generic text', () async {
      final cid = await p.k.readyConsultation();
      await h.actOk('docuser', '/consultations/$cid/finalize');
      await h.actOk(
        'docuser',
        '/consultations/$cid/followups',
        status: 201,
        body: {
          'recommendedDate': '2026-06-20',
          'reason': 'Review of the lump',
          'instructions': 'Bring the scan',
        },
      );
      final n = h
          .docsOf('patient_notifications')
          .firstWhere((x) => x['category'] == 'followup_reminder');
      expect('${n['title']} ${n['body']}'.contains('lump'), isFalse);
      expect('${n['title']} ${n['body']}'.contains('scan'), isFalse);
    });
  });
}
