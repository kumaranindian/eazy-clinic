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

  Future<int> sched(
    String uid,
    Map<String, Object?> hours, {
    String? doctor,
    String? branch,
    Map<String, Object?>? extra,
  }) => h.status(
    'POST',
    '/doctors/${doctor ?? c.doc}/availability',
    uid: uid,
    body: {
      'branchId': branch ?? c.br,
      'weeklyHours': hours,
      'effectiveFrom': '2026-01-01',
      ...?extra,
    },
  );

  group('weekly schedules', () {
    test(
      'a schedule has sessions, breaks, capacity and dates; the tenant is stamped',
      () async {
        final list = await h.list(
          await h.call('GET', '/doctors/${c.doc}/availability', uid: 'owner'),
        );
        expect(list, hasLength(1));
        final first = list.single! as Map<String, Object?>;
        expect(first['tenantId'], c.tid);
        expect(first['status'], 'active');
        expect(first['timezone'], 'Asia/Kolkata');
      },
    );

    test(
      'multiple sessions with breaks are accepted (morning and evening)',
      () async {
        final hours = weekly(
          sessions: [
            {'from': '09:00', 'to': '13:00'},
            {'from': '17:00', 'to': '20:00'},
          ],
          breaks: [
            {'from': '11:00', 'to': '11:15'},
          ],
          days: [1, 3],
        );
        final d2 = await h.newDoctor(
          'owner',
          branchIds: [c.br],
          name: 'Dr Two',
          n: '2',
        );
        expect(await sched('owner', hours, doctor: d2), 201);
      },
    );

    test(
      'invalid hours are refused: overlap, bad times, breaks outside, no working day',
      () async {
        for (final bad in <Map<String, Object?>>[
          weekly(
            sessions: [
              {'from': '09:00', 'to': '13:00'},
              {'from': '12:00', 'to': '15:00'},
            ],
          ),
          weekly(
            sessions: [
              {'from': '13:00', 'to': '09:00'},
            ],
          ),
          weekly(
            sessions: [
              {'from': '9am', 'to': '13:00'},
            ],
          ),
          weekly(
            breaks: [
              {'from': '14:00', 'to': '14:15'},
            ],
          ),
          weekly(
            breaks: [
              {'from': '10:00', 'to': '10:30'},
              {'from': '10:15', 'to': '10:45'},
            ],
          ),
          {
            '8': {'sessions': <Object?>[], 'breaks': <Object?>[]},
          },
          weekly(days: []),
        ]) {
          expect(await sched('owner', bad), 422, reason: '$bad');
        }
      },
    );

    test(
      'the doctor must be assigned to the branch; different branches may differ',
      () async {
        final b2 = await h.newBranch('owner', code: 'EAST');
        expect(await sched('owner', weekly(), branch: b2), 409);
        await h.actOk(
          'owner',
          '/doctors/${c.doc}/branches',
          body: {'branchId': b2},
          status: 201,
        );
        expect(
          await sched(
            'owner',
            weekly(
              sessions: [
                {'from': '14:00', 'to': '18:00'},
              ],
            ),
            branch: b2,
          ),
          201,
        );
        final slots = await h.freeSlots(
          'recep',
          b2,
          c.doc,
          tuesday,
          typeId: c.type,
        );
        expect(slots.first['startTime'], '14:00');
        final slots1 = await h.freeSlots(
          'recep',
          c.br,
          c.doc,
          tuesday,
          typeId: c.type,
        );
        expect(slots1.first['startTime'], '09:00');
      },
    );

    test(
      'overlapping active schedules for one doctor and branch are refused; history is kept',
      () async {
        expect(
          await sched(
            'owner',
            weekly(),
            extra: {'effectiveFrom': '2026-03-01'},
          ),
          409,
        );
        final list = await h.list(
          await h.call('GET', '/doctors/${c.doc}/availability', uid: 'owner'),
        );
        final id = (list.single! as Map)['scheduleId'];
        // end the first schedule, then a follow-on one is allowed
        await h.actOk(
          'owner',
          '/doctors/${c.doc}/availability/$id',
          method: 'PATCH',
          body: {'effectiveTo': '2026-12-31'},
        );
        expect(
          await sched(
            'owner',
            weekly(),
            extra: {'effectiveFrom': '2027-01-01'},
          ),
          201,
        );
        expect(h.docsOf('availability_revisions'), hasLength(1));
        // DELETE ends a schedule but keeps it
        await h.actOk(
          'owner',
          '/doctors/${c.doc}/availability/$id',
          method: 'DELETE',
        );
        final after = await h.list(
          await h.call('GET', '/doctors/${c.doc}/availability', uid: 'owner'),
        );
        expect(after, hasLength(2));
        expect(
          after.where((s) => (s! as Map)['status'] == 'inactive'),
          hasLength(1),
        );
      },
    );

    test(
      'permissions: reception cannot change availability; a doctor only their own',
      () async {
        expect(await sched('recep', weekly()), 403);
        expect(
          await h.status('GET', '/doctors/${c.doc}/availability', uid: 'recep'),
          200,
        );
        final other = await h.newDoctor(
          'owner',
          branchIds: [c.br],
          name: 'Dr Other',
          n: '2',
        );
        expect(await sched('docuser', weekly(), doctor: other), 403);
        final mine = await h.newDoctor(
          'owner',
          branchIds: [c.br],
          name: 'Dr Mine',
          n: '4',
        );
        h.store.docs['tenants/${c.tid}/members/docuser']!['doctorId'] = mine;
        final own = await h.newSchedule('docuser', mine, c.br);
        expect(own['doctorId'], mine);
        expect(
          await h.status('GET', '/doctors/$other/availability', uid: 'acct'),
          403,
        );
      },
    );

    test('a client cannot choose id, tenant or status fields', () async {
      for (final extra in [
        {'scheduleId': 'sch_x'},
        {'tenantId': 'other'},
        {'createdBy': 'x'},
        {'version': 9},
      ]) {
        expect(
          await sched('owner', weekly(), extra: extra),
          422,
          reason: '$extra',
        );
      }
    });

    test('a branch outside the caller scope is not found', () async {
      final b2 = await h.newBranch('owner', code: 'EAST');
      h.member(
        'east',
        c.tid,
        'clinic_admin',
        allBranches: false,
        branchIds: [b2],
      );
      expect(await sched('east', weekly(), branch: c.br), 404);
    });
  });

  group('slot generation', () {
    test('slots follow sessions, breaks and the type duration', () async {
      final doc2 = await h.newDoctor(
        'owner',
        branchIds: [c.br],
        name: 'Dr Two',
        n: '2',
      );
      await h.newSchedule(
        'owner',
        doc2,
        c.br,
        duration: 20,
        hours: weekly(
          sessions: [
            {'from': '09:00', 'to': '10:00'},
            {'from': '17:00', 'to': '18:00'},
          ],
          breaks: [
            {'from': '09:30', 'to': '09:40'},
          ],
        ),
      );
      final s = await h.freeSlots('recep', c.br, doc2, tuesday);
      expect(s.map((e) => e['startTime']), [
        '09:00',
        '09:40',
        '17:00',
        '17:20',
        '17:40',
      ]);
      // type duration of 30 minutes
      final t30 = await h.freeSlots(
        'recep',
        c.br,
        doc2,
        tuesday,
        typeId: c.type,
      );
      expect(t30.map((e) => e['startTime']), ['09:00', '17:00', '17:30']);
    });

    test('buffers separate appointments', () async {
      final doc2 = await h.newDoctor(
        'owner',
        branchIds: [c.br],
        name: 'Dr Two',
        n: '2',
      );
      final t = await h.newType(
        'owner',
        name: 'Buffered',
        duration: 20,
        buffer: 10,
      );
      await h.newSchedule(
        'owner',
        doc2,
        c.br,
        hours: weekly(
          sessions: [
            {'from': '09:00', 'to': '10:30'},
          ],
        ),
      );
      final s = await h.freeSlots('recep', c.br, doc2, tuesday, typeId: t);
      expect(s.map((e) => e['startTime']), ['09:00', '09:30', '10:00']);
      expect(s.first['endTime'], '09:20');
    });

    test(
      'slots are computed in the branch time zone (IST = UTC+05:30)',
      () async {
        final s = await h.freeSlots(
          'recep',
          c.br,
          c.doc,
          tuesday,
          typeId: c.type,
        );
        expect(s.first['startTime'], '09:00');
        expect(s.first['startUtc'], '2026-06-02T03:30:00.000Z');
        expect(s.first['endUtc'], '2026-06-02T04:00:00.000Z');
      },
    );

    test(
      'a time zone that observes daylight saving is refused, not guessed',
      () async {
        await h.actOk(
          'owner',
          '/branches/${c.br}',
          method: 'PATCH',
          body: {'timezone': 'America/New_York'},
        );
        expect(
          await h.status(
            'GET',
            '/appointments/available-slots?branchId=${c.br}&doctorId=${c.doc}&date=$tuesday',
            uid: 'recep',
          ),
          409,
        );
      },
    );

    test('past times and past dates are never offered', () async {
      // 10:00 UTC on 2026-06-01 is 15:30 IST: only later slots remain today
      final s = await h.freeSlots('recep', c.br, c.doc, today, typeId: c.type);
      expect(s, isEmpty); // the session ended at 13:00
      expect(
        await h.status(
          'GET',
          '/appointments/available-slots?branchId=${c.br}&doctorId=${c.doc}&date=2026-05-31',
          uid: 'recep',
        ),
        409,
      );
      expect(
        await h.status(
          'GET',
          '/appointments/available-slots?branchId=${c.br}&doctorId=${c.doc}&date=2030-06-01',
          uid: 'recep',
        ),
        409,
      );
      expect(
        await h.status(
          'GET',
          '/appointments/available-slots?branchId=${c.br}&doctorId=${c.doc}&date=nope',
          uid: 'recep',
        ),
        400,
      );
    });

    test('closed days offer nothing and say why', () async {
      final d = await h.okData(
        h.call(
          'GET',
          '/appointments/available-slots?branchId=${c.br}&doctorId=${c.doc}&date=$sunday',
          uid: 'recep',
        ),
      );
      expect(d['slots'], isEmpty);
      expect((d['day']! as Map)['closed'], true);
    });

    test(
      'per-type durations configured for a doctor override the type default',
      () async {
        final doc2 = await h.newDoctor(
          'owner',
          branchIds: [c.br],
          name: 'Dr Two',
          n: '2',
        );
        await h.newSchedule(
          'owner',
          doc2,
          c.br,
          extra: {
            'typeDurations': {c.type: 15},
          },
        );
        final s = await h.freeSlots(
          'recep',
          c.br,
          doc2,
          tuesday,
          typeId: c.type,
        );
        expect(s.first['endTime'], '09:15');
      },
    );

    test(
      'the slot endpoint checks tenant, branch, doctor assignment and feature',
      () async {
        await h.createClinic('ownerB', name: 'Other Clinic');
        expect(
          await h.status(
            'GET',
            '/appointments/available-slots?branchId=${c.br}&doctorId=${c.doc}&date=$tuesday',
            uid: 'ownerB',
          ),
          anyOf(403, 404),
        );
        final other = await h.newDoctor(
          'owner',
          branchIds: [],
          name: 'Dr Free',
          n: '3',
        );
        expect(
          await h.status(
            'GET',
            '/appointments/available-slots?branchId=${c.br}&doctorId=$other&date=$tuesday',
            uid: 'recep',
          ),
          409,
        );
        expect(
          await h.status(
            'GET',
            '/appointments/available-slots?doctorId=${c.doc}&date=$tuesday',
            uid: 'recep',
          ),
          400,
        );
        expect(
          await h.status(
            'GET',
            '/appointments/available-slots?branchId=${c.br}&doctorId=${c.doc}&date=$tuesday',
            uid: 'acct',
          ),
          403,
        );
      },
    );
  });

  group('exceptions and holidays', () {
    Future<Map<String, Object?>> leave({
      String from = tuesday,
      String? to,
      Map<String, Object?>? extra,
      String uid = 'owner',
    }) => h.actOk(
      uid,
      '/doctors/${c.doc}/schedule-exceptions',
      status: 201,
      body: {
        'branchId': c.br,
        'type': 'doctor_leave',
        'startDate': from,
        'endDate': to ?? from,
        'reason': 'Conference',
        ...?extra,
      },
    );

    test('leave removes the doctor\'s slots for those days only', () async {
      await leave();
      expect(await h.freeSlots('recep', c.br, c.doc, tuesday), isEmpty);
      expect(await h.freeSlots('recep', c.br, c.doc, wednesday), isNotEmpty);
    });

    test('a partial-day block removes only that time', () async {
      await leave(
        extra: {'fullDay': false, 'fromTime': '10:00', 'toTime': '11:00'},
      );
      final s = await h.freeSlots(
        'recep',
        c.br,
        c.doc,
        tuesday,
        typeId: c.type,
      );
      expect(s.map((e) => e['startTime']), [
        '09:00',
        '09:30',
        '11:00',
        '11:30',
        '12:00',
        '12:30',
      ]);
    });

    test('a branch holiday blocks every doctor of the branch', () async {
      final doc2 = await h.newDoctor(
        'owner',
        branchIds: [c.br],
        name: 'Dr Two',
        n: '2',
      );
      await h.newSchedule('owner', doc2, c.br);
      await h.actOk(
        'owner',
        '/schedule-exceptions',
        status: 201,
        body: {
          'branchId': c.br,
          'type': 'clinic_holiday',
          'startDate': tuesday,
          'reason': 'Festival',
        },
      );
      expect(await h.freeSlots('recep', c.br, c.doc, tuesday), isEmpty);
      expect(await h.freeSlots('recep', c.br, doc2, tuesday), isEmpty);
    });

    test(
      'a special working day opens a normally closed day; a block still wins',
      () async {
        await h.actOk(
          'owner',
          '/doctors/${c.doc}/schedule-exceptions',
          status: 201,
          body: {
            'branchId': c.br,
            'type': 'special_working_day',
            'startDate': sunday,
            'reason': 'Camp',
            'sessions': [
              {'from': '10:00', 'to': '12:00'},
            ],
          },
        );
        final s = await h.freeSlots(
          'recep',
          c.br,
          c.doc,
          sunday,
          typeId: c.type,
        );
        expect(s.map((e) => e['startTime']), [
          '10:00',
          '10:30',
          '11:00',
          '11:30',
        ]);
        await leave(from: sunday);
        expect(await h.freeSlots('recep', c.br, c.doc, sunday), isEmpty);
      },
    );

    test('a schedule modification replaces the day\'s hours', () async {
      await h.actOk(
        'owner',
        '/doctors/${c.doc}/schedule-exceptions',
        status: 201,
        body: {
          'branchId': c.br,
          'type': 'schedule_modification',
          'startDate': tuesday,
          'reason': 'Short day',
          'sessions': [
            {'from': '09:00', 'to': '10:00'},
          ],
        },
      );
      expect(
        await h.freeSlots('recep', c.br, c.doc, tuesday, typeId: c.type),
        hasLength(2),
      );
    });

    test(
      'adding leave over booked appointments flags them but never cancels them',
      () async {
        final a = await h.bookOk(
          'recep',
          c.body(date: tuesday, start: '09:00'),
        );
        final b = await h.bookOk(
          'recep',
          c.body(
            date: tuesday,
            start: '10:00',
            patientId: await c.morePatient(1),
          ),
        );
        final out = await leave();
        final affected = (out['affectedAppointments']! as List)
            .cast<Map<String, Object?>>();
        expect(
          affected.map((e) => e['appointmentId']),
          unorderedEquals([a['appointmentId'], b['appointmentId']]),
        );
        final now = await h.actOk(
          'recep',
          '/appointments/${a['appointmentId']}',
          method: 'GET',
        );
        expect(now['status'], 'confirmed');
        expect(now['needsAttention'], true);
        expect(now['attentionReason'], startsWith('schedule_exception:'));
        final todo = await h.list(
          await h.call(
            'GET',
            '/appointments?needsAttention=true&date=$tuesday',
            uid: 'recep',
          ),
        );
        expect(todo, hasLength(2));
        // resolving it explicitly clears the flag
        await h.actOk(
          'recep',
          '/appointments/${a['appointmentId']}/reschedule',
          body: {
            'date': wednesday,
            'startTime': '09:00',
            'reason': 'Doctor on leave',
          },
        );
        expect(
          await h.list(
            await h.call(
              'GET',
              '/appointments?needsAttention=true&date=$tuesday',
              uid: 'recep',
            ),
          ),
          hasLength(1),
        );
        // cancelling the leave clears the rest
        await h.actOk(
          'owner',
          '/doctors/${c.doc}/schedule-exceptions/${out['exceptionId']}',
          method: 'DELETE',
        );
        expect(
          await h.list(
            await h.call(
              'GET',
              '/appointments?needsAttention=true&date=$tuesday',
              uid: 'recep',
            ),
          ),
          isEmpty,
        );
        expect(await h.freeSlots('recep', c.br, c.doc, wednesday), isNotEmpty);
      },
    );

    test('bookings inside a blocked period are refused', () async {
      await leave();
      expect(await h.bookStatus('recep', c.body()), 422);
    });

    test('permissions, validation and audit', () async {
      expect(
        await h.status(
          'POST',
          '/doctors/${c.doc}/schedule-exceptions',
          uid: 'recep',
          body: {
            'branchId': c.br,
            'type': 'doctor_leave',
            'startDate': tuesday,
            'reason': 'x1y',
          },
        ),
        403,
      );
      // a doctor may declare their own leave: self-declared, still blocking
      final own = await leave(uid: 'docuser');
      expect(own['approval'], 'self_declared');
      expect(own['approvedBy'], isNull);
      expect(await h.freeSlots('recep', c.br, c.doc, tuesday), isEmpty);
      for (final bad in [
        {
          'branchId': c.br,
          'type': 'doctor_leave',
          'startDate': tuesday,
          'endDate': '2026-05-01',
          'reason': 'x1y',
        },
        {
          'branchId': c.br,
          'type': 'clinic_holiday',
          'startDate': tuesday,
          'reason': 'x1y',
        },
        {
          'branchId': c.br,
          'type': 'doctor_leave',
          'startDate': tuesday,
          'reason': 'x',
        },
        {
          'branchId': c.br,
          'type': 'doctor_leave',
          'startDate': tuesday,
          'fullDay': false,
          'fromTime': '12:00',
          'toTime': '11:00',
          'reason': 'x1y',
        },
        {
          'branchId': c.br,
          'type': 'special_working_day',
          'startDate': tuesday,
          'reason': 'x1y',
        },
        {
          'branchId': c.br,
          'type': 'doctor_leave',
          'startDate': tuesday,
          'reason': 'x1y',
          'status': 'cancelled',
        },
        {
          'branchId': c.br,
          'type': 'doctor_leave',
          'startDate': tuesday,
          'reason': 'x1y',
          'tenantId': 'o',
        },
      ]) {
        expect(
          await h.status(
            'POST',
            '/doctors/${c.doc}/schedule-exceptions',
            uid: 'owner',
            body: bad,
          ),
          422,
          reason: '$bad',
        );
      }
      expect(
        h
            .docsOf('platform_audit_logs')
            .any(
              (d) =>
                  d['action'] == 'schedule_exception.created' &&
                  d['tenantId'] == c.tid,
            ),
        isTrue,
      );
    });

    test('editing and cancelling an exception', () async {
      final ex = await leave();
      final id = ex['exceptionId'];
      final edited = await h.actOk(
        'owner',
        '/doctors/${c.doc}/schedule-exceptions/$id',
        method: 'PATCH',
        body: {'endDate': wednesday},
      );
      expect(edited['endDate'], wednesday);
      expect(await h.freeSlots('recep', c.br, c.doc, wednesday), isEmpty);
      expect(
        await h.status(
          'PATCH',
          '/doctors/${c.doc}/schedule-exceptions/$id',
          uid: 'owner',
          body: {'type': 'sick_leave'},
        ),
        422,
      );
      await h.actOk(
        'owner',
        '/doctors/${c.doc}/schedule-exceptions/$id',
        method: 'DELETE',
      );
      expect(
        await h.status(
          'DELETE',
          '/doctors/${c.doc}/schedule-exceptions/$id',
          uid: 'owner',
        ),
        409,
      );
      expect(await h.freeSlots('recep', c.br, c.doc, tuesday), isNotEmpty);
      expect(
        await h.status(
          'PATCH',
          '/doctors/${c.doc}/schedule-exceptions/$id',
          uid: 'owner',
          body: {'reason': 'later'},
        ),
        409,
      );
    });

    test('exceptions of another clinic are not reachable', () async {
      final ex = await leave();
      await h.createClinic('ownerB', name: 'Other Clinic');
      expect(
        await h.status(
          'DELETE',
          '/doctors/${c.doc}/schedule-exceptions/${ex['exceptionId']}',
          uid: 'ownerB',
        ),
        anyOf(403, 404),
      );
      expect(
        await h.status(
          'GET',
          '/doctors/${c.doc}/schedule-exceptions',
          uid: 'ownerB',
        ),
        anyOf(403, 404),
      );
    });
  });

  group('appointment types', () {
    test(
      'create, validate, edit, activate and deactivate; names are unique',
      () async {
        expect(
          await h.status(
            'POST',
            '/appointment-types',
            uid: 'recep',
            body: {'name': 'X type', 'durationMinutes': 20},
          ),
          403,
        );
        for (final bad in [
          {'name': 'x', 'durationMinutes': 20},
          {'name': 'Follow-up', 'durationMinutes': 2},
          {'name': 'Follow-up', 'durationMinutes': 20, 'bufferMinutes': 500},
          {'name': 'Follow-up', 'durationMinutes': 20, 'status': 'inactive'},
          {'name': 'Follow-up', 'durationMinutes': 20, 'tenantId': 'o'},
        ]) {
          expect(
            await h.status(
              'POST',
              '/appointment-types',
              uid: 'owner',
              body: bad,
            ),
            422,
            reason: '$bad',
          );
        }
        final t = await h.actOk(
          'owner',
          '/appointment-types',
          status: 201,
          body: {
            'name': 'Follow-up',
            'durationMinutes': 15,
            'specialities': ['General Medicine'],
          },
        );
        expect(t['tenantId'], c.tid);
        expect(
          await h.status(
            'POST',
            '/appointment-types',
            uid: 'owner',
            body: {'name': 'follow-up', 'durationMinutes': 15},
          ),
          409,
        );
        final id = t['typeId'];
        expect(
          (await h.actOk(
            'owner',
            '/appointment-types/$id',
            method: 'PATCH',
            body: {'durationMinutes': 20},
          ))['durationMinutes'],
          20,
        );
        await h.actOk('owner', '/appointment-types/$id/deactivate');
        expect(
          await h.status(
            'POST',
            '/appointment-types/$id/deactivate',
            uid: 'owner',
          ),
          409,
        );
        expect(
          await h.status(
            'GET',
            '/appointments/available-slots?branchId=${c.br}&doctorId=${c.doc}&date=$tuesday&typeId=$id',
            uid: 'recep',
          ),
          409,
        );
        await h.actOk('owner', '/appointment-types/$id/activate');
        expect(
          await h.list(
            await h.call(
              'GET',
              '/appointment-types?status=active',
              uid: 'recep',
            ),
          ),
          hasLength(2),
        );
      },
    );

    test('types are tenant-specific', () async {
      await h.createClinic('ownerB', name: 'Other Clinic');
      expect(
        await h.status(
          'PATCH',
          '/appointment-types/${c.type}',
          uid: 'ownerB',
          body: {'durationMinutes': 99},
        ),
        anyOf(403, 404),
      );
      expect(consentBody(), isNotEmpty);
    });
  });
}
