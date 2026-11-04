import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

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

  group('access', () {
    test('every portal route needs a signed-in patient account', () async {
      for (final path in [
        '/patient/clinics',
        '/patient/appointments',
        '/patient/medical-records',
        '/patient/invoices',
        '/patient/notifications',
        '/patient/profile',
      ]) {
        expect(await p.status('GET', path, uid: null), 401, reason: path);
        // signed in but without a patient account
        h.user('nobody');
        expect(
          await p.status('GET', path, uid: 'nobody'),
          anyOf(403, 404),
          reason: path,
        );
      }
    });

    test('clinic staff are not patients and patients are not staff', () async {
      expect(
        await p.status('GET', '/patient/appointments', uid: 'recep'),
        anyOf(403, 404),
      );
      expect(await p.status('GET', '/billing/invoices', uid: 'asha'), 403);
      expect(await p.status('GET', '/patients', uid: 'asha'), 403);
      expect(await p.status('GET', '/appointments', uid: 'asha'), 403);
    });
  });

  group('clinic and doctor discovery', () {
    test('shows approved, active clinics with public details only', () async {
      final clinics = await p.list('/patient/clinics');
      expect(clinics, hasLength(1));
      final c = clinics.single! as Map;
      expect(c['clinicId'], p.tid);
      expect(c['name'], isNotNull);
      final d = await p.get('/patient/clinics/${p.tid}');
      expect(d['clinicId'], p.tid);
      expect((d['branches']! as List), hasLength(1));
      expect((d['appointmentTypes']! as List), hasLength(1));
      expect(d['onlinePayments'], false);
      for (final leak in [
        'members',
        'staff',
        'subscription',
        'limits',
        'ownerUid',
      ]) {
        expect(d.containsKey(leak), isFalse, reason: leak);
      }
    });

    test('filters by name and hides clinics not on the patient app', () async {
      expect(await p.list('/patient/clinics?q=green'), hasLength(1));
      expect(await p.list('/patient/clinics?q=zzzz'), isEmpty);
      final h2 = PlatformHarness();
      final p2 = PortalClinic(h2);
      h2.user('root', role: PlatformRole.superAdmin);
      await h2.createClinic(
        'ownerHidden',
        name: 'Hidden Clinic',
        patientApp: false,
      );
      await p2.createAccount('visitor');
      expect(await p2.list('/patient/clinics', uid: 'visitor'), isEmpty);
      expect(
        await p2.status(
          'GET',
          '/patient/clinics/${(await h2.okData(h2.call('GET', '/tenants/current/entitlements', uid: 'ownerHidden')))['tenantId']}',
          uid: 'visitor',
        ),
        404,
      );
    });

    test('a suspended clinic disappears from discovery', () async {
      h.store.docs['tenants/${p.tid}']!['status'] = 'suspended';
      expect(await p.list('/patient/clinics'), isEmpty);
      expect(await p.status('GET', '/patient/clinics/${p.tid}'), 404);
    });

    test('discovering a clinic grants no access to any record', () async {
      final p2 = await p.createAccount('newcomer');
      expect(p2['accountId'], isNotNull);
      expect(await p.list('/patient/clinics', uid: 'newcomer'), hasLength(1));
      expect(await p.list('/patient/appointments', uid: 'newcomer'), isEmpty);
      expect(
        await p.list('/patient/medical-records', uid: 'newcomer'),
        isEmpty,
      );
      expect(await p.list('/patient/invoices', uid: 'newcomer'), isEmpty);
    });

    test(
      'doctors expose public profile fields, never contact or registration data',
      () async {
        final docs = await p.list('/patient/clinics/${p.tid}/doctors');
        expect(docs, hasLength(2));
        final d = docs.first! as Map;
        expect(d['fullName'], isNotNull);
        expect(d['consultationModes'], ['in_person']);
        for (final leak in [
          'email',
          'phone',
          'registrationNumber',
          'registrationCouncil',
          'dateOfBirth',
          'status',
        ]) {
          expect(d.containsKey(leak), isFalse, reason: leak);
        }
        expect(
          await p.list('/patient/clinics/${p.tid}/doctors?q=second'),
          hasLength(1),
        );
        expect(
          await p.list(
            '/patient/clinics/${p.tid}/doctors?speciality=General Medicine',
          ),
          hasLength(2),
        );
        expect(
          await p.list(
            '/patient/clinics/${p.tid}/doctors?speciality=Cardiology',
          ),
          isEmpty,
        );
        expect(
          await p.get('/patient/clinics/${p.tid}/doctors/${p.doctor}'),
          containsPair('doctorId', p.doctor),
        );
        expect(
          await p.status('GET', '/patient/clinics/${p.tid}/doctors/dr_missing'),
          404,
        );
        expect((await p.list('/patient/clinics/${p.tid}/specialities')), [
          'General Medicine',
        ]);
      },
    );

    test('availability comes from the scheduling engine', () async {
      final a = await p.get(
        '/patient/clinics/${p.tid}/availability?branchId=${p.br}&doctorId=${p.doctor}&date=$tuesday&typeId=${p.type}',
      );
      expect((a['slots']! as List), isNotEmpty);
      expect(
        await p.status(
          'GET',
          '/patient/clinics/${p.tid}/availability?branchId=x&doctorId=y&date=$tuesday',
        ),
        anyOf(400, 404, 422),
      );
    });
  });

  group('booking', () {
    test(
      'a linked patient books; the clinic confirms; source is the patient app',
      () async {
        final a = await p.book();
        expect(a['status'], 'pending');
        expect(a['source'], 'patient_app');
        expect(a['clinicId'], p.tid);
        expect(a['localDate'], tuesday);
        expect(a['doctorName'], isNotNull);
        expect(a.containsKey('notes'), isFalse);
        final stored = h.docsOf('appointments').single;
        expect(stored['patientId'], p.patientId);
        expect(
          h.docsOf('patient_audit_logs').map((d) => d['action']),
          contains('portal.appointment_booked'),
        );
        final auditRow = h.docsOf('appointment_audit_logs').first;
        expect(auditRow['actorRole'], 'patient');
      },
    );

    test(
      'the same Idempotency-Key books once; another body is a conflict',
      () async {
        final a = await p.book(idemKey: 'key-book-0001');
        final b = await p.book(idemKey: 'key-book-0001');
        expect(b['appointmentId'], a['appointmentId']);
        expect(h.docsOf('appointments'), hasLength(1));
        expect(
          await p.status(
            'POST',
            '/patient/appointments',
            body: p.bookBody(time: '09:30'),
            headers: {'idempotency-key': 'key-book-0001'},
          ),
          409,
        );
        expect(
          await p.status(
            'POST',
            '/patient/appointments',
            body: p.bookBody(time: '09:30'),
          ),
          400,
        );
      },
    );

    test('a taken slot is refused, never reported as success', () async {
      await p.book();
      await p.createAccount('other');
      final p2 =
          (await h.okData(
                h.call(
                  'POST',
                  '/patients',
                  uid: 'recep',
                  body: patientBody(
                    p.br,
                    name: 'Ravi Kumar',
                    dob: '1985-02-02',
                    phone: '9876500123',
                  ),
                ),
                status: 201,
              ))['patientId']!
              as String;
      await p.link('other', p2);
      expect(
        await p.status(
          'POST',
          '/patient/appointments',
          uid: 'other',
          body: p.bookBody(),
          headers: {'idempotency-key': p.key()},
        ),
        409,
      );
      expect(h.docsOf('appointments'), hasLength(1));
    });

    test('racing patients get one booking for one slot', () async {
      final accounts = <String>[];
      for (var i = 0; i < 4; i++) {
        final uid = 'racer$i';
        await p.createAccount(uid);
        final pid =
            (await h.okData(
                  h.call(
                    'POST',
                    '/patients',
                    uid: 'recep',
                    body: patientBody(
                      p.br,
                      name: 'Racer Number$i',
                      dob: '19${70 + i}-01-01',
                      phone: '98765009${i}0',
                    ),
                  ),
                  status: 201,
                ))['patientId']!
                as String;
        await p.link(uid, pid);
        accounts.add(uid);
      }
      final res = await Future.wait([
        for (final uid in accounts)
          h.call(
            'POST',
            '/patient/appointments',
            uid: uid,
            headers: {'idempotency-key': p.key()},
            body: p.bookBody(),
          ),
      ]);
      expect(res.where((r) => r.statusCode == 201), hasLength(1));
      expect(res.where((r) => r.statusCode == 409), hasLength(3));
      expect(h.docsOf('appointments'), hasLength(1));
    });

    test(
      'policy: not in the past, not beyond the booking window, valid input',
      () async {
        Future<int> post(Map<String, Object?> b) => p.status(
          'POST',
          '/patient/appointments',
          body: b,
          headers: {'idempotency-key': p.key()},
        );
        expect(await post(p.bookBody(date: '2026-05-31')), 409);
        expect(await post(p.bookBody(date: '2026-09-01')), 409);
        expect(await post(p.bookBody(date: 'tomorrow')), 422);
        expect(await post(p.bookBody(time: '25:00')), 422);
        expect(await post({...p.bookBody(), 'status': 'confirmed'}), 422);
        expect(await post({...p.bookBody(), 'patientId': 'pt_x'}), 422);
        expect(await post(p.bookBody(time: '20:00')), anyOf(409, 422));
        expect(h.docsOf('appointments'), isEmpty);
      },
    );

    test(
      'a patient cannot book at a clinic they are not linked to, or with a tampered clinic id',
      () async {
        await p.createAccount('stranger');
        expect(
          await p.status(
            'POST',
            '/patient/appointments',
            uid: 'stranger',
            body: p.bookBody(),
            headers: {'idempotency-key': p.key()},
          ),
          404,
        );
        expect(
          await p.status(
            'POST',
            '/patient/appointments',
            body: p.bookBody(clinicId: 'ten_other'),
            headers: {'idempotency-key': p.key()},
          ),
          404,
        );
        expect(
          await p.status(
            'POST',
            '/patient/appointments',
            body: p.bookBody(accountId: 'pa_unknown'),
            headers: {'idempotency-key': p.key()},
          ),
          404,
        );
      },
    );

    test('a read-only or suspended clinic refuses new bookings', () async {
      h.store.docs['tenants/${p.tid}']!['status'] = 'suspended';
      expect(
        await p.status(
          'POST',
          '/patient/appointments',
          body: p.bookBody(),
          headers: {'idempotency-key': p.key()},
        ),
        anyOf(403, 404),
      );
    });
  });

  group('managing appointments', () {
    test(
      'lists, filters and shows details of only the patient\'s own',
      () async {
        final a = await p.book();
        final list = await p.list('/patient/appointments');
        expect(list, hasLength(1));
        expect(
          await p.list('/patient/appointments?filter=upcoming'),
          hasLength(1),
        );
        expect(await p.list('/patient/appointments?filter=cancelled'), isEmpty);
        final d = await p.get(
          '/patient/clinics/${p.tid}/appointments/${a['appointmentId']}',
        );
        expect(d['appointmentId'], a['appointmentId']);
        // someone else
        await p.createAccount('other');
        expect(await p.list('/patient/appointments', uid: 'other'), isEmpty);
        expect(
          await p.status(
            'GET',
            '/patient/clinics/${p.tid}/appointments/${a['appointmentId']}',
            uid: 'other',
          ),
          404,
        );
        expect(
          await p.status(
            'GET',
            '/patient/clinics/${p.tid}/appointments/apt_missing',
          ),
          404,
        );
      },
    );

    test('cancel works, is a replay when repeated, and is audited', () async {
      final a = await p.book();
      final id = a['appointmentId']! as String;
      final c = await h.okData(
        h.call(
          'POST',
          '/patient/clinics/${p.tid}/appointments/$id/cancel',
          uid: 'asha',
          body: {'reason': 'Cannot attend'},
        ),
      );
      expect(c['status'], 'cancelled');
      final again = await h.okData(
        h.call(
          'POST',
          '/patient/clinics/${p.tid}/appointments/$id/cancel',
          uid: 'asha',
          body: {},
        ),
      );
      expect(again['idempotentReplay'], true);
      expect(
        h.docsOf('patient_audit_logs').map((d) => d['action']),
        contains('portal.appointment_cancelled'),
      );
      // the slot is free again
      await p.book();
    });

    test('changes need two hours notice', () async {
      final a = await p.book(date: tuesday, time: '09:00');
      final id = a['appointmentId']! as String;
      // move the clock to 08:00 IST on Tuesday: one hour before the visit
      h.clock.now = DateTime.utc(2026, 6, 2, 2, 30);
      expect(
        await p.status(
          'POST',
          '/patient/clinics/${p.tid}/appointments/$id/cancel',
          body: {},
        ),
        409,
      );
      expect(
        await p.status(
          'POST',
          '/patient/clinics/${p.tid}/appointments/$id/reschedule',
          body: {'date': wednesday, 'startTime': '09:00'},
        ),
        409,
      );
    });

    test('reschedule moves the visit and keeps history', () async {
      final a = await p.book();
      final id = a['appointmentId']! as String;
      final r = await h.okData(
        h.call(
          'POST',
          '/patient/clinics/${p.tid}/appointments/$id/reschedule',
          uid: 'asha',
          body: {'date': wednesday, 'startTime': '09:30'},
        ),
      );
      expect(r['clinicId'], p.tid);
      final all = h.docsOf('appointments');
      expect(all, hasLength(2));
      expect(
        all.map((d) => d['status']),
        containsAll(['rescheduled', 'pending']),
      );
      expect(
        await p.status(
          'POST',
          '/patient/clinics/${p.tid}/appointments/$id/reschedule',
          body: {'date': wednesday, 'startTime': '10:00'},
        ),
        409,
      );
    });

    test(
      'another patient cannot cancel, move or check in someone else\'s visit',
      () async {
        final a = await p.book();
        final id = a['appointmentId']! as String;
        await p.createAccount('mallory');
        final bodies = <String, Map<String, Object?>>{
          'cancel': {},
          'reschedule': {'date': wednesday, 'startTime': '09:00'},
          'check-in': {},
        };
        for (final e in bodies.entries) {
          expect(
            await p.status(
              'POST',
              '/patient/clinics/${p.tid}/appointments/$id/${e.key}',
              uid: 'mallory',
              body: e.value,
            ),
            404,
            reason: e.key,
          );
        }
        expect(h.docsOf('appointments').single['status'], 'pending');
      },
    );

    test(
      'a caregiver with the right scope books and manages for the patient; without it, nothing',
      () async {
        await p.createAccount('ravi');
        Future<String> relate(List<String> scopes) async {
          final rel = await h.okData(
            h.call(
              'POST',
              '/patient-accounts/me/family',
              uid: 'ravi',
              body: {
                'relationshipType': 'caregiver',
                'subjectAccountId': p.accountId,
                'permissionScope': scopes,
              },
            ),
            status: 201,
          );
          await h.okData(
            h.call(
              'POST',
              '/family-relationships/${rel['relationshipId']}/verify',
              uid: 'asha',
              body: {'decision': 'approve'},
            ),
          );
          return rel['relationshipId']! as String;
        }

        // no relationship yet
        expect(
          await p.status(
            'POST',
            '/patient/appointments',
            uid: 'ravi',
            body: p.bookBody(accountId: p.accountId),
            headers: {'idempotency-key': p.key()},
          ),
          404,
        );
        final rid = await relate(['manage_appointments']);
        final a = await p.book(uid: 'ravi', accountId: p.accountId);
        expect(a['status'], 'pending');
        expect(
          await p.list(
            '/patient/appointments?accountId=${p.accountId}',
            uid: 'ravi',
          ),
          hasLength(1),
        );
        // the scope does not include records or billing
        expect(
          await p.status(
            'GET',
            '/patient/medical-records?accountId=${p.accountId}',
            uid: 'ravi',
          ),
          404,
        );
        expect(
          await p.status(
            'GET',
            '/patient/invoices?accountId=${p.accountId}',
            uid: 'ravi',
          ),
          404,
        );
        // revoking ends access at once
        await h.okData(
          h.call(
            'POST',
            '/family-relationships/$rid/revoke',
            uid: 'asha',
            body: {},
          ),
        );
        expect(
          await p.status(
            'GET',
            '/patient/appointments?accountId=${p.accountId}',
            uid: 'ravi',
          ),
          404,
        );
        expect(
          await p.status(
            'POST',
            '/patient/appointments',
            uid: 'ravi',
            body: p.bookBody(time: '09:30', accountId: p.accountId),
            headers: {'idempotency-key': p.key()},
          ),
          404,
        );
      },
    );
  });

  group('check-in and queue', () {
    Future<String> confirmedToday() async {
      // book tuesday, staff confirm, then it is Tuesday 10:00 IST
      final a = await p.book(time: '11:00');
      final id = a['appointmentId']! as String;
      await h.actOk('recep', '/appointments/$id/confirm');
      h.clock.now = DateTime.utc(2026, 6, 2, 4, 30);
      return id;
    }

    test(
      'check-in needs a confirmed visit on the day; it issues a token and is not repeated',
      () async {
        final a = await p.book(time: '11:00');
        final id = a['appointmentId']! as String;
        expect(
          await p.status(
            'POST',
            '/patient/clinics/${p.tid}/appointments/$id/check-in',
            body: {},
          ),
          409,
          reason: 'not confirmed',
        );
        await h.actOk('recep', '/appointments/$id/confirm');
        expect(
          await p.status(
            'POST',
            '/patient/clinics/${p.tid}/appointments/$id/check-in',
            body: {},
          ),
          409,
          reason: 'not the day yet',
        );
        h.clock.now = DateTime.utc(2026, 6, 2, 4, 30);
        final c = await h.okData(
          h.call(
            'POST',
            '/patient/clinics/${p.tid}/appointments/$id/check-in',
            uid: 'asha',
            body: {},
          ),
        );
        expect(c['status'], 'checked_in');
        expect(c['tokenDisplay'], isNotNull);
        final again = await h.okData(
          h.call(
            'POST',
            '/patient/clinics/${p.tid}/appointments/$id/check-in',
            uid: 'asha',
            body: {},
          ),
        );
        expect(again['idempotentReplay'], true);
        expect(h.docsOf('queue_entries'), hasLength(1));
      },
    );

    test('queue status shows token and counts, never other patients', () async {
      // another patient, booked earlier in the morning, is ahead in the queue
      final p2 =
          (await h.okData(
                h.call(
                  'POST',
                  '/patients',
                  uid: 'recep',
                  body: patientBody(
                    p.br,
                    name: 'Ahead Person',
                    dob: '1980-03-03',
                    phone: '9876500456',
                  ),
                ),
                status: 201,
              ))['patientId']!
              as String;
      final other = await h.bookOk(
        'recep',
        p.k.c.body(start: '09:30', patientId: p2),
      );
      final id = await confirmedToday();
      await h.actOk(
        'recep',
        '/appointments/${other['appointmentId']}/check-in',
      );
      await h.okData(
        h.call(
          'POST',
          '/patient/clinics/${p.tid}/appointments/$id/check-in',
          uid: 'asha',
          body: {},
        ),
      );
      final q = await p.get('/patient/clinics/${p.tid}/appointments/$id/queue');
      expect(q['status'], 'waiting');
      expect(q['token'], isNotNull);
      expect(q['queuePosition'], 2);
      expect(q['patientsAhead'], 1);
      expect(q['estimatedWait'], isNull);
      expect(q['estimatedWaitNote'], isNotNull);
      final text = q.toString();
      expect(text, isNot(contains('Ahead Person')));
      expect(text, isNot(contains('9876500456')));
      expect(q.containsKey('entries'), isFalse);
      // before checking in: no queue
      final fresh = await p.book(time: '12:00');
      final nq = await p.get(
        '/patient/clinics/${p.tid}/appointments/${fresh['appointmentId']}/queue',
      );
      expect(nq['status'], 'not_in_queue');
    });

    test('nobody else can read a visit\'s queue status', () async {
      final id = await confirmedToday();
      await h.okData(
        h.call(
          'POST',
          '/patient/clinics/${p.tid}/appointments/$id/check-in',
          uid: 'asha',
          body: {},
        ),
      );
      await p.createAccount('mallory');
      expect(
        await p.status(
          'GET',
          '/patient/clinics/${p.tid}/appointments/$id/queue',
          uid: 'mallory',
        ),
        404,
      );
      expect(
        await p.status(
          'GET',
          '/patient/clinics/ten_other/appointments/$id/queue',
        ),
        404,
      );
    });
  });
}
