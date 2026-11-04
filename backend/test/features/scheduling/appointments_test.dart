import 'package:common_models/common_models.dart';
import 'package:test/test.dart';

import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/scheduling_fixtures.dart';

void main() {
  late PlatformHarness h;
  late Clinic c;

  setUp(() async {
    h = PlatformHarness();
    c = Clinic(h);
    await c.init();
  });

  group('booking', () {
    test(
      'books a confirmed appointment with backend-set fields, reservation and audit',
      () async {
        final a = await h.bookOk('recep', c.body());
        expect(a['appointmentId'], startsWith('apt_'));
        expect(a['reference'], matches(RegExp(r'^APT-20260602-[A-Z0-9]{4}$')));
        expect(a['status'], 'confirmed');
        expect(a['source'], 'reception');
        expect(a['tenantId'], c.tid);
        expect(a['startTime'], '09:00');
        expect(a['endTime'], '09:30');
        expect(a['startUtc'], '2026-06-02T03:30:00.000Z');
        expect(a['createdBy'], 'recep');
        expect(a['patientName'], 'Asha Patil');
        expect(a.containsKey('lane'), isFalse);
        expect(
          h.reservations(),
          hasLength(6),
        ); // 30 minutes = six 5-minute cells
        expect(
          h.apptActions(a['appointmentId']! as String),
          contains('appointment.created'),
        );
        // the slot is gone
        expect(
          (await h.freeSlots(
            'recep',
            c.br,
            c.doc,
            tuesday,
            typeId: c.type,
          )).first['startTime'],
          '09:30',
        );
      },
    );

    test(
      'the booking source follows the role; the client cannot choose it',
      () async {
        expect(
          (await h.bookOk('owner', c.body(start: '09:30')))['source'],
          'clinic_admin',
        );
        h.member('docuser2', c.tid, 'doctor');
        expect(
          (await h.bookOk('docuser', c.body(start: '10:00')))['source'],
          'doctor',
        );
        for (final extra in [
          {'source': 'walk_in'},
          {'status': 'completed'},
          {'status': 'checked_in'},
          {'tenantId': 'other'},
          {'appointmentId': 'apt_x'},
          {'reference': 'APT-X'},
          {'createdBy': 'x'},
          {'queueEntryId': 'qe_x'},
        ]) {
          expect(
            await h.bookStatus(
              'recep',
              c.body(start: '11:00', extra: extra),
              key: 'key-spoof-${extra.keys.first}',
            ),
            422,
            reason: '$extra',
          );
        }
      },
    );

    test('pending bookings can be confirmed later', () async {
      final a = await h.bookOk('recep', c.body(extra: {'status': 'pending'}));
      expect(a['status'], 'pending');
      expect(
        (await h.actOk(
          'recep',
          '/appointments/${a['appointmentId']}/confirm',
        ))['status'],
        'confirmed',
      );
      expect(
        await h.act('recep', '/appointments/${a['appointmentId']}/confirm'),
        409,
      );
    });

    test(
      'backend revalidates: outside hours, breaks, past, leave, closed days',
      () async {
        expect(
          await h.bookStatus(
            'recep',
            c.body(start: '14:00'),
            key: 'key-late00',
          ),
          422,
        );
        expect(
          await h.bookStatus(
            'recep',
            c.body(start: '09:10'),
            key: 'key-off-grid',
          ),
          422,
        );
        expect(
          await h.bookStatus('recep', c.body(date: sunday), key: 'key-sunday0'),
          422,
        );
        expect(
          await h.bookStatus(
            'recep',
            c.body(date: '2026-05-30'),
            key: 'key-past000',
          ),
          409,
        );
        expect(
          await h.bookStatus(
            'recep',
            c.body(start: '25:00'),
            key: 'key-badtime',
          ),
          422,
        );
      },
    );

    test(
      'a doctor cannot be booked at a branch they are not assigned to',
      () async {
        final b2 = await h.newBranch('owner', code: 'EAST');
        expect(
          await h.bookStatus(
            'recep',
            h.bookBody(
              patientId: c.patient,
              doctorId: c.doc,
              branchId: b2,
              typeId: c.type,
            ),
          ),
          409,
        );
      },
    );

    test(
      'unknown or foreign ids are refused: patient, type, doctor, branch',
      () async {
        await h.createClinic('ownerB', name: 'Other Clinic');
        final brB = await h.newBranch('ownerB', code: 'BEE');
        final pB = (await h.newPatient('ownerB', brB))['patientId']! as String;
        expect(
          await h.bookStatus(
            'recep',
            c.body(patientId: pB),
            key: 'key-foreign1',
          ),
          404,
        );
        expect(
          await h.bookStatus(
            'recep',
            c.body(patientId: 'pt_missing0'),
            key: 'key-missing1',
          ),
          404,
        );
        expect(
          await h.bookStatus(
            'recep',
            c.body(extra: {'typeId': 'aty_missing'}),
            key: 'key-missing2',
          ),
          404,
        );
        expect(
          await h.bookStatus(
            'recep',
            c.body(extra: {'doctorId': 'dr_missing0'}),
            key: 'key-missing3',
          ),
          404,
        );
        expect(
          await h.bookStatus('ownerB', c.body(), key: 'key-crossten'),
          anyOf(403, 404),
        );
      },
    );

    test('an inactive patient cannot be booked', () async {
      await h.actOk(
        'owner',
        '/patients/${c.patient}/deactivate',
        body: {'reason': 'moved away'},
      );
      expect(await h.bookStatus('recep', c.body()), 409);
    });

    test('a patient cannot hold two overlapping appointments', () async {
      await h.bookOk('recep', c.body());
      final d2 = await h.newDoctor(
        'owner',
        branchIds: [c.br],
        name: 'Dr Two',
        n: '2',
      );
      await h.newSchedule('owner', d2, c.br);
      expect(
        await h.bookStatus(
          'recep',
          h.bookBody(
            patientId: c.patient,
            doctorId: d2,
            branchId: c.br,
            typeId: c.type,
          ),
          key: 'key-clash000',
        ),
        409,
      );
    });

    test(
      'roles: accountants cannot book or view; nurses can view only',
      () async {
        expect(await h.bookStatus('acct', c.body()), 403);
        expect(await h.bookStatus('nurse', c.body(), key: 'key-nurse000'), 403);
        expect(await h.status('GET', '/appointments', uid: 'acct'), 403);
        expect(
          await h.status('GET', '/appointments?date=$tuesday', uid: 'nurse'),
          200,
        );
      },
    );
  });

  group('double booking and idempotency', () {
    test('the same slot cannot be booked twice', () async {
      await h.bookOk('recep', c.body());
      final p2 = await c.morePatient(1);
      expect(
        await h.bookStatus('recep', c.body(patientId: p2), key: 'key-second00'),
        409,
      );
      expect(
        h.apptDocs().where((a) => a['status'] == 'confirmed'),
        hasLength(1),
      );
    });

    test(
      'concurrent requests for one slot create exactly one appointment',
      () async {
        final patients = [for (var i = 1; i <= 6; i++) await c.morePatient(i)];
        final results = await Future.wait([
          for (var i = 0; i < patients.length; i++)
            h.bookStatus(
              'recep',
              c.body(patientId: patients[i]),
              key: 'key-conc-$i-aaaa',
            ),
        ]);
        expect(results.where((s) => s == 201), hasLength(1));
        expect(results.where((s) => s == 409), hasLength(5));
        expect(
          h.apptDocs().where((a) => a['status'] == 'confirmed'),
          hasLength(1),
        );
        expect(h.reservations(), hasLength(6));
      },
    );

    test(
      'capacity 2 allows two appointments and no more, also under concurrency',
      () async {
        final h2 = PlatformHarness();
        final c2 = Clinic(h2);
        await c2.init(capacity: 2);
        final patients = [for (var i = 1; i <= 5; i++) await c2.morePatient(i)];
        final results = await Future.wait([
          for (var i = 0; i < patients.length; i++)
            h2.bookStatus(
              'recep',
              c2.body(patientId: patients[i]),
              key: 'key-cap-$i-aaaaa',
            ),
        ]);
        expect(results.where((s) => s == 201), hasLength(2));
        expect(results.where((s) => s == 409), hasLength(3));
      },
    );

    test(
      'overlapping slots of different types cannot both be booked',
      () async {
        final long = await h.newType('owner', name: 'Long visit', duration: 60);
        await h.bookOk('recep', c.body(extra: {'typeId': long}));
        expect(
          await h.bookStatus(
            'recep',
            c.body(start: '09:30', patientId: await c.morePatient(1)),
            key: 'key-overlap0',
          ),
          409,
        );
        expect(
          await h.bookStatus(
            'recep',
            c.body(start: '10:00', patientId: await c.morePatient(2)),
            key: 'key-overlap1',
          ),
          201,
        );
      },
    );

    test(
      'a doctor cannot be booked in two branches at the same time',
      () async {
        final b2 = await h.newBranch('owner', code: 'EAST');
        await h.actOk(
          'owner',
          '/doctors/${c.doc}/branches',
          body: {'branchId': b2},
          status: 201,
        );
        await h.newSchedule('owner', c.doc, b2);
        await h.bookOk('recep', c.body());
        final p2 = await c.morePatient(1);
        expect(
          await h.bookStatus(
            'owner',
            h.bookBody(
              patientId: p2,
              doctorId: c.doc,
              branchId: b2,
              typeId: c.type,
            ),
            key: 'key-twobranch',
          ),
          409,
        );
      },
    );

    test(
      'a repeated request with the same key returns the same appointment',
      () async {
        final a = await h.bookOk('recep', c.body(), key: 'key-retry-001');
        final b = await h.bookOk(
          'recep',
          c.body(),
          key: 'key-retry-001',
          status: 200,
        );
        expect(b['appointmentId'], a['appointmentId']);
        expect(b['idempotentReplay'], true);
        expect(h.apptDocs(), hasLength(1));
        expect(h.reservations(), hasLength(6));
      },
    );

    test('concurrent duplicates with one key create one appointment', () async {
      final results = await Future.wait([
        for (var i = 0; i < 4; i++)
          h.bookStatus('recep', c.body(), key: 'key-dupe-0001'),
      ]);
      expect(
        results.every((s) => s == 201 || s == 200),
        isTrue,
        reason: '$results',
      );
      expect(h.apptDocs(), hasLength(1));
    });

    test(
      'a key reused for a different request is refused; a key is required',
      () async {
        await h.bookOk('recep', c.body(), key: 'key-reuse-001');
        expect(
          await h.bookStatus(
            'recep',
            c.body(start: '10:00'),
            key: 'key-reuse-001',
          ),
          409,
        );
        expect(
          (await h.call(
            'POST',
            '/appointments',
            uid: 'recep',
            body: c.body(start: '10:00'),
          )).statusCode,
          400,
        );
        expect(
          await h.bookStatus('recep', c.body(start: '10:00'), key: 'short'),
          400,
        );
      },
    );
  });

  group('lifecycle', () {
    late String id;
    setUp(
      () async =>
          id = (await h.bookOk('recep', c.body()))['appointmentId']! as String,
    );

    test('cancel needs a reason, frees the slot and keeps history', () async {
      expect(await h.act('recep', '/appointments/$id/cancel'), 422);
      final x = await h.actOk(
        'recep',
        '/appointments/$id/cancel',
        body: {'reason': 'Patient called'},
      );
      expect(x['status'], 'cancelled');
      expect(x['cancelReason'], 'Patient called');
      expect(x['cancelledBy'], 'recep');
      expect(x['cancelSource'], 'reception');
      expect(h.reservations(), isEmpty);
      expect(
        await h.bookStatus(
          'recep',
          c.body(patientId: await c.morePatient(1)),
          key: 'key-rebook000',
        ),
        201,
      );
      expect(
        h.apptActions(id),
        containsAll(['appointment.created', 'appointment.cancelled']),
      );
      expect(
        await h.act(
          'recep',
          '/appointments/$id/cancel',
          body: {'reason': 'again'},
        ),
        409,
      );
    });

    test(
      'reschedule keeps the old record, links both and moves the reservation',
      () async {
        expect(
          await h.act(
            'recep',
            '/appointments/$id/reschedule',
            body: {'date': wednesday, 'startTime': '10:00'},
          ),
          422,
        );
        final n = await h.actOk(
          'recep',
          '/appointments/$id/reschedule',
          body: {
            'date': wednesday,
            'startTime': '10:00',
            'reason': 'Patient request',
          },
        );
        expect(n['appointmentId'], isNot(id));
        expect(n['rescheduledFromId'], id);
        expect(n['status'], 'confirmed');
        expect(n['localDate'], wednesday);
        final old = await h.actOk('recep', '/appointments/$id', method: 'GET');
        expect(old['status'], 'rescheduled');
        expect(old['rescheduledToId'], n['appointmentId']);
        expect(old['rescheduleReason'], 'Patient request');
        expect(old['startTime'], '09:00');
        expect(old['localDate'], tuesday);
        final hist = (old['history']! as List).cast<Map<String, Object?>>();
        final r = hist.firstWhere(
          (e) => e['action'] == 'appointment.rescheduled',
        );
        expect((r['before']! as Map)['date'], tuesday);
        expect((r['after']! as Map)['date'], wednesday);
        expect(h.reservations(), hasLength(6));
        expect(
          h.reservations().every((r) => r['localDate'] == wednesday),
          isTrue,
        );
        expect(
          await h.act(
            'recep',
            '/appointments/$id/reschedule',
            body: {'date': wednesday, 'startTime': '11:00', 'reason': 'again'},
          ),
          409,
        );
      },
    );

    test('rescheduling into a taken slot fails and changes nothing', () async {
      await h.bookOk(
        'recep',
        c.body(start: '10:00', patientId: await c.morePatient(1)),
      );
      expect(
        await h.act(
          'recep',
          '/appointments/$id/reschedule',
          body: {'date': tuesday, 'startTime': '10:00', 'reason': 'swap'},
        ),
        409,
      );
      expect(
        (await h.actOk('recep', '/appointments/$id', method: 'GET'))['status'],
        'confirmed',
      );
      // the appointment's own slot may be reused for a nearby time
      expect(
        await h.act(
          'recep',
          '/appointments/$id/reschedule',
          body: {'date': tuesday, 'startTime': '09:30', 'reason': 'later'},
        ),
        200,
      );
    });

    test('invalid status changes are refused', () async {
      expect(await h.act('docuser', '/appointments/$id/complete'), 409);
      expect(await h.act('docuser', '/appointments/$id/start'), 409);
      expect(
        await h.act('recep', '/appointments/$id/mark-no-show'),
        409,
        reason: 'not before the appointment time',
      );
      await h.actOk(
        'recep',
        '/appointments/$id/cancel',
        body: {'reason': 'Patient called'},
      );
      for (final a in [
        'confirm',
        'check-in',
        'start',
        'complete',
        'mark-no-show',
      ]) {
        expect(
          await h.act('owner', '/appointments/$id/$a'),
          anyOf(409, 403),
          reason: a,
        );
      }
      expect(
        await h.act(
          'recep',
          '/appointments/$id/reschedule',
          body: {'date': wednesday, 'startTime': '09:00', 'reason': 'x1y'},
        ),
        409,
      );
      expect(
        await h.status(
          'PATCH',
          '/appointments/$id',
          uid: 'owner',
          body: {'status': 'completed'},
        ),
        422,
      );
      expect(
        await h.status(
          'PATCH',
          '/appointments/$id',
          uid: 'owner',
          body: {'notes': 'late edit'},
        ),
        409,
      );
    });

    test('notes can be edited while open; trusted fields cannot', () async {
      final ok = await h.actOk(
        'recep',
        '/appointments/$id',
        method: 'PATCH',
        body: {'notes': 'Bring reports'},
      );
      expect(ok['notes'], 'Bring reports');
      for (final bad in [
        {'status': 'completed'},
        {'doctorId': 'dr_x'},
        {'startTime': '10:00'},
        {'patientId': 'pt_x'},
        {'tenantId': 'o'},
        {'queueEntryId': 'qe_x'},
      ]) {
        expect(
          await h.status('PATCH', '/appointments/$id', uid: 'recep', body: bad),
          422,
          reason: '$bad',
        );
      }
    });

    test('no-show after the start time frees the slot', () async {
      h.clock.now = DateTime.utc(2026, 6, 2, 4, 0); // 09:30 IST on the day
      final x = await h.actOk('recep', '/appointments/$id/mark-no-show');
      expect(x['status'], 'no_show');
      expect(h.reservations(), isEmpty);
      expect(await h.act('recep', '/appointments/$id/check-in'), 409);
    });

    test('status history and audit logs list every step', () async {
      await h.actOk(
        'recep',
        '/appointments/$id',
        method: 'PATCH',
        body: {'notes': 'x1'},
      );
      await h.actOk(
        'recep',
        '/appointments/$id/cancel',
        body: {'reason': 'Patient called'},
      );
      final d = await h.actOk('recep', '/appointments/$id', method: 'GET');
      expect(
        (d['history']! as List).map((e) => (e as Map)['action']),
        containsAll([
          'appointment.created',
          'appointment.notes_updated',
          'appointment.cancelled',
        ]),
      );
      final logs = await h.list(
        await h.call('GET', '/appointments/$id/audit-logs', uid: 'recep'),
      );
      expect(logs, hasLength(3));
      for (final m in ['POST', 'PATCH', 'DELETE']) {
        expect(
          await h.status(
            m,
            '/appointments/$id/audit-logs',
            uid: 'owner',
            body: {},
          ),
          anyOf(404, 405),
        );
      }
    });
  });

  group('check-in', () {
    late String id;
    setUp(
      () async => id =
          (await h
                  .bookOk(
                    'recep',
                    c.body(date: today, start: '15:00', extra: null),
                  )
                  .catchError((_) => <String, Object?>{}))['appointmentId']
              as String? ??
          '',
    );

    test('is possible only on the day, inside the window, once', () async {
      // appointment 09:00 on Tuesday; today is Monday
      final a = (await h.bookOk('recep', c.body()))['appointmentId']! as String;
      expect(await h.act('recep', '/appointments/$a/check-in'), 409);
      h.clock.now = DateTime.utc(2026, 6, 2, 0, 0); // 05:30 IST: too early
      expect(await h.act('recep', '/appointments/$a/check-in'), 409);
      h.clock.now = DateTime.utc(2026, 6, 2, 3, 0); // 08:30 IST
      final r = await h.actOk('recep', '/appointments/$a/check-in');
      expect(r['status'], 'checked_in');
      expect(r['tokenDisplay'], 'A001');
      expect(r['checkedInBy'], 'recep');
      expect(await h.act('recep', '/appointments/$a/check-in'), 409);
    });

    test(
      'is refused for cancelled appointments, late arrivals and unauthorized roles',
      () async {
        final a =
            (await h.bookOk('recep', c.body()))['appointmentId']! as String;
        h.clock.now = DateTime.utc(2026, 6, 2, 3, 0);
        expect(await h.act('acct', '/appointments/$a/check-in'), 403);
        await h.actOk(
          'recep',
          '/appointments/$a/cancel',
          body: {'reason': 'Patient called'},
        );
        expect(await h.act('recep', '/appointments/$a/check-in'), 409);
        final b =
            (await h.bookOk(
                  'recep',
                  c.body(start: '09:30', patientId: await c.morePatient(1)),
                ))['appointmentId']!
                as String;
        h.clock.now = DateTime.utc(
          2026,
          6,
          2,
          6,
          0,
        ); // 11:30 IST: > 60 min after the end
        expect(await h.act('recep', '/appointments/$b/check-in'), 409);
      },
    );

    test('the clinic can change the early and late windows', () async {
      await h.actOk(
        'owner',
        '/clinics/current/settings',
        method: 'PATCH',
        body: {'checkInEarlyMinutes': 0, 'checkInLateMinutes': 240},
      );
      final a = (await h.bookOk('recep', c.body()))['appointmentId']! as String;
      h.clock.now = DateTime.utc(2026, 6, 2, 3, 0);
      expect(await h.act('recep', '/appointments/$a/check-in'), 409);
      h.clock.now = DateTime.utc(
        2026,
        6,
        2,
        7,
        0,
      ); // 12:30 IST: 3 h after the end
      expect(await h.act('recep', '/appointments/$a/check-in'), 200);
      expect(id, isA<String>());
    });
  });

  group('walk-ins', () {
    setUp(() async {
      // make "now" fall inside the working day: Tuesday 10:10 IST
      h.clock.now = DateTime.utc(2026, 6, 2, 4, 40);
    });

    Future<Map<String, Object?>> walkIn(
      String uid, {
      String? patient,
      String key = 'walk-key-0001',
      Map<String, Object?>? extra,
    }) => h.okData(
      h.call(
        'POST',
        '/appointments/walk-in',
        uid: uid,
        headers: {'idempotency-key': key},
        body: {
          'patientId': patient ?? c.patient,
          'doctorId': c.doc,
          'branchId': c.br,
          'typeId': c.type,
          ...?extra,
        },
      ),
      status: 201,
    );

    test(
      'creates a checked-in walk-in appointment in the nearest free slot with a token',
      () async {
        final w = await walkIn('recep');
        expect(w['source'], 'walk_in');
        expect(w['status'], 'checked_in');
        expect(w['tokenDisplay'], 'A001');
        expect(w['startTime'], '10:00'); // the slot in progress at 10:10
        final w2 = await walkIn(
          'recep',
          patient: await c.morePatient(1),
          key: 'walk-key-0002',
        );
        expect(w2['tokenDisplay'], 'A002');
        expect(w2['startTime'], '10:30');
        final q = await h.actOk(
          'recep',
          '/queues/current?branchId=${c.br}&doctorId=${c.doc}',
          method: 'GET',
        );
        expect(q['waiting'], 2);
        expect(
          (q['nextToken']! as Map<String, Object?>)['displayToken'],
          'A001',
        );
      },
    );

    test(
      'never overbooks: when the day is full the walk-in is refused',
      () async {
        h.clock.now = DateTime.utc(
          2026,
          6,
          2,
          7,
          10,
        ); // 12:40 IST: one slot left
        await walkIn('recep');
        expect(
          await h.status(
            'POST',
            '/appointments/walk-in',
            uid: 'recep',
            headers: {'idempotency-key': 'walk-key-0009'},
            body: {
              'patientId': await c.morePatient(1),
              'doctorId': c.doc,
              'branchId': c.br,
              'typeId': c.type,
            },
          ),
          409,
        );
      },
    );

    test('is idempotent, validated and permission-checked', () async {
      final a = await walkIn('recep');
      final b = await h.okData(
        h.call(
          'POST',
          '/appointments/walk-in',
          uid: 'recep',
          headers: {'idempotency-key': 'walk-key-0001'},
          body: {
            'patientId': c.patient,
            'doctorId': c.doc,
            'branchId': c.br,
            'typeId': c.type,
          },
        ),
      );
      expect(b['appointmentId'], a['appointmentId']);
      expect(h.apptDocs(), hasLength(1));
      expect(
        await h.status(
          'POST',
          '/appointments/walk-in',
          uid: 'recep',
          headers: {'idempotency-key': 'walk-key-0003'},
          body: {
            'patientId': c.patient,
            'doctorId': c.doc,
            'branchId': c.br,
            'typeId': c.type,
            'date': tuesday,
          },
        ),
        422,
      );
      expect(
        await h.status(
          'POST',
          '/appointments/walk-in',
          uid: 'acct',
          headers: {'idempotency-key': 'walk-key-0004'},
          body: {
            'patientId': c.patient,
            'doctorId': c.doc,
            'branchId': c.br,
            'typeId': c.type,
          },
        ),
        403,
      );
    });

    test('priority needs the queue.priority permission', () async {
      expect(
        await h.status(
          'POST',
          '/appointments/walk-in',
          uid: 'recep',
          headers: {'idempotency-key': 'walk-key-0005'},
          body: {
            'patientId': c.patient,
            'doctorId': c.doc,
            'branchId': c.br,
            'typeId': c.type,
            'priority': 'priority',
          },
        ),
        403,
      );
      final w = await walkIn(
        'owner',
        key: 'walk-key-0006',
        extra: {'priority': 'priority'},
      );
      final q = await h.actOk(
        'recep',
        '/queues/current?branchId=${c.br}&doctorId=${c.doc}',
        method: 'GET',
      );
      expect((q['nextToken']! as Map<String, Object?>)['priority'], 'priority');
      expect(w['source'], 'walk_in');
    });
  });

  group('lists, calendar data and isolation', () {
    test(
      'filters by date range, doctor, status, reference and search text',
      () async {
        final a = await h.bookOk('recep', c.body());
        await h.bookOk(
          'recep',
          c.body(date: wednesday, patientId: await c.morePatient(1)),
        );
        Future<List<Object?>> q(String s) async =>
            h.list(await h.call('GET', '/appointments?$s', uid: 'recep'));
        expect(await q('date=$tuesday'), hasLength(1));
        expect(await q('from=$tuesday&to=$wednesday'), hasLength(2));
        expect(
          await q(
            'from=$tuesday&to=$wednesday&doctorId=${c.doc}&branchId=${c.br}',
          ),
          hasLength(2),
        );
        expect(await q('date=$tuesday&status=cancelled'), isEmpty);
        expect(await q('reference=${a['reference']}'), hasLength(1));
        expect(await q('from=$tuesday&to=$wednesday&q=number1'), hasLength(1));
        expect(
          await h.status('GET', '/appointments?status=bogus', uid: 'recep'),
          400,
        );
        expect(
          await h.status(
            'GET',
            '/appointments?from=2026-01-01&to=2026-12-31',
            uid: 'recep',
          ),
          400,
        );
      },
    );

    test(
      'a branch-scoped user and another clinic never see these appointments',
      () async {
        final a = await h.bookOk('recep', c.body());
        final b2 = await h.newBranch('owner', code: 'EAST');
        h.member(
          'east',
          c.tid,
          'receptionist',
          allBranches: false,
          branchIds: [b2],
        );
        expect(
          await h.list(
            await h.call('GET', '/appointments?date=$tuesday', uid: 'east'),
          ),
          isEmpty,
        );
        expect(
          await h.status(
            'GET',
            '/appointments/${a['appointmentId']}',
            uid: 'east',
          ),
          404,
        );
        expect(
          await h.status(
            'GET',
            '/appointments?date=$tuesday&branchId=${c.br}',
            uid: 'east',
          ),
          404,
        );
        expect(
          await h.act(
            'east',
            '/appointments/${a['appointmentId']}/cancel',
            body: {'reason': 'nope'},
          ),
          404,
        );
        await h.createClinic('ownerB', name: 'Other Clinic');
        expect(
          await h.list(
            await h.call('GET', '/appointments?date=$tuesday', uid: 'ownerB'),
          ),
          isEmpty,
        );
        expect(
          await h.status(
            'GET',
            '/appointments/${a['appointmentId']}',
            uid: 'ownerB',
          ),
          404,
        );
        expect(
          await h.act(
            'ownerB',
            '/appointments/${a['appointmentId']}/cancel',
            body: {'reason': 'nope'},
          ),
          404,
        );
        expect(
          await h.status(
            'GET',
            '/appointments/${a['appointmentId']}/audit-logs',
            uid: 'ownerB',
          ),
          404,
        );
      },
    );

    test('a suspended clinic cannot book; reads are blocked too', () async {
      await h.call(
        'POST',
        '/platform/tenants/${c.tid}/suspend',
        uid: 'root',
        body: {'reason': 'Policy review'},
      );
      expect(await h.bookStatus('recep', c.body()), 403);
      expect(
        await h.status('GET', '/appointments?date=$tuesday', uid: 'recep'),
        403,
      );
    });

    test('a plan without the appointments feature is refused', () async {
      final h2 = PlatformHarness();
      h2.user('root', role: PlatformRole.superAdmin);
      final plan = await h2.okData(
        h2.call(
          'POST',
          '/platform/subscription-plans',
          uid: 'root',
          body: {
            'name': 'No appts',
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
            'features': {'patient_management': true, 'appointments': false},
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
      final t2 = await h2.approve(
        await h2.apply('o2'),
        planId: plan['planId']! as String,
      );
      final b2 = await h2.newBranch('o2');
      expect(
        await h2.status(
          'POST',
          '/appointment-types',
          uid: 'o2',
          body: {'name': 'General', 'durationMinutes': 20},
        ),
        403,
      );
      expect(
        await h2.status(
          'GET',
          '/appointments/available-slots?branchId=$b2&doctorId=dr_x&date=$tuesday',
          uid: 'o2',
        ),
        403,
      );
      expect(t2, isNotEmpty);
    });

    test(
      'the patient timeline lists appointments newest first and respects scope',
      () async {
        await h.bookOk('recep', c.body());
        await h.bookOk('recep', c.body(date: wednesday));
        final rows = await h.list(
          await h.call(
            'GET',
            '/patients/${c.patient}/appointments',
            uid: 'recep',
          ),
        );
        expect(rows.map((r) => (r! as Map)['localDate']), [wednesday, tuesday]);
        expect(
          await h.list(
            await h.call(
              'GET',
              '/patients/${c.patient}/appointments?from=$wednesday',
              uid: 'recep',
            ),
          ),
          hasLength(1),
        );
        await h.createClinic('ownerB', name: 'Other Clinic');
        expect(
          await h.status(
            'GET',
            '/patients/${c.patient}/appointments',
            uid: 'ownerB',
          ),
          404,
        );
        expect(
          await h.status(
            'GET',
            '/patients/${c.patient}/appointments',
            uid: 'acct',
          ),
          403,
        );
        final text = await (await h.call(
          'GET',
          '/patients/${c.patient}/appointments',
          uid: 'recep',
        )).readAsString();
        expect(text, isNot(contains('consultation')));
      },
    );
  });
}
