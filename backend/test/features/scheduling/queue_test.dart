import 'package:test/test.dart';

import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/scheduling_fixtures.dart';

void main() {
  late PlatformHarness h;
  late Clinic c;
  var n = 0;

  setUp(() async {
    h = PlatformHarness();
    c = Clinic(h);
    n = 0;
    await c.init();
  });

  /// Books [count] appointments for Tuesday, then moves the clock to 08:30 IST.
  Future<List<String>> bookDay(
    int count, {
    String date = tuesday,
    String? doctor,
  }) async {
    final ids = <String>[];
    for (var i = 0; i < count; i++) {
      final p = await c.morePatient(++n);
      final start =
          '${(9 + (i * 30) ~/ 60).toString().padLeft(2, '0')}:${((i * 30) % 60).toString().padLeft(2, '0')}';
      final a = await h.bookOk(
        'recep',
        c.body(
          date: date,
          start: start,
          patientId: p,
          extra: doctor == null ? null : {'doctorId': doctor},
        ),
      );
      ids.add(a['appointmentId']! as String);
    }
    h.clock.now = DateTime.utc(2026, 6, 2, 3, 0);
    return ids;
  }

  Future<Map<String, Object?>> checkIn(
    String id, {
    String uid = 'recep',
    Object? body,
  }) => h.actOk(uid, '/appointments/$id/check-in', body: body);

  Future<Map<String, Object?>> current({
    String uid = 'recep',
    String? date,
  }) => h.actOk(
    uid,
    '/queues/current?branchId=${c.br}&doctorId=${c.doc}${date == null ? '' : '&date=$date'}',
    method: 'GET',
  );

  Future<Map<String, Object?>> entryAction(
    String uid,
    String entryId,
    String action, {
    Object? body,
  }) => h.actOk(uid, '/queue-entries/$entryId/$action', body: body);

  Future<int> entryStatus(
    String uid,
    String entryId,
    String action, {
    Object? body,
  }) => h.act(uid, '/queue-entries/$entryId/$action', body: body);

  group('tokens', () {
    test(
      'tokens are sequential, formatted with the clinic prefix, per doctor and day',
      () async {
        final ids = await bookDay(3);
        final tokens = [
          for (final id in ids) (await checkIn(id))['tokenDisplay'],
        ];
        expect(tokens, ['A001', 'A002', 'A003']);
        await h.actOk(
          'owner',
          '/clinics/current/settings',
          method: 'PATCH',
          body: {'queueTokenPrefix': 'B'},
        );
        // the prefix is fixed for the day once the queue exists; a new day uses the new one
        final next = await h.bookOk(
          'recep',
          c.body(
            date: wednesday,
            start: '09:00',
            patientId: await c.morePatient(++n),
          ),
        );
        h.clock.now = DateTime.utc(2026, 6, 3, 3, 0);
        expect(
          (await checkIn(next['appointmentId']! as String))['tokenDisplay'],
          'B001',
        );
        expect(
          await h.status(
            'PATCH',
            '/clinics/current/settings',
            uid: 'owner',
            body: {'queueTokenPrefix': 'abc'},
          ),
          422,
        );
        expect(
          await h.status(
            'PATCH',
            '/clinics/current/settings',
            uid: 'owner',
            body: {'queueTokenPrefix': 'ABCD'},
          ),
          422,
        );
      },
    );

    test('another doctor has an independent counter', () async {
      final d2 = await h.newDoctor(
        'owner',
        branchIds: [c.br],
        name: 'Dr Two',
        n: '2',
      );
      await h.newSchedule('owner', d2, c.br);
      final a = await bookDay(1);
      final p = await c.morePatient(++n);
      final b = await h.bookOk(
        'recep',
        h.bookBody(
          patientId: p,
          doctorId: d2,
          branchId: c.br,
          typeId: c.type,
          startTime: '10:00',
        ),
      );
      h.clock.now = DateTime.utc(2026, 6, 2, 3, 0);
      expect((await checkIn(a.single))['tokenDisplay'], 'A001');
      expect(
        (await checkIn(b['appointmentId']! as String))['tokenDisplay'],
        'A001',
      );
    });

    test('concurrent check-ins never produce duplicate tokens', () async {
      final ids = await bookDay(6);
      h.clock.now = DateTime.utc(2026, 6, 2, 4, 30); // 10:00 IST
      final results = await Future.wait([
        for (final id in ids)
          h.call(
            'POST',
            '/appointments/$id/check-in',
            uid: 'recep',
            body: <String, Object?>{},
          ),
      ]);
      expect(results.map((r) => r.statusCode), everyElement(200));
      final tokens = [
        for (final e in h.docsOf('queue_entries')) e['tokenNumber'],
      ];
      expect(tokens.toSet(), hasLength(6));
      expect(tokens.toSet(), {1, 2, 3, 4, 5, 6});
      expect(h.docsOf('queue_tokens'), hasLength(6));
    });

    test('a new day starts again at 001 and keeps the old queue', () async {
      final tue = await bookDay(2);
      await checkIn(tue[0]);
      await checkIn(tue[1]);
      final wed = await h.bookOk(
        'recep',
        c.body(
          date: wednesday,
          start: '09:00',
          patientId: await c.morePatient(++n),
        ),
      );
      h.clock.now = DateTime.utc(2026, 6, 3, 3, 0);
      expect(
        (await checkIn(wed['appointmentId']! as String))['tokenDisplay'],
        'A001',
      );
      expect((await current(date: tuesday))['checkedIn'], 2);
      expect((await current(date: wednesday))['checkedIn'], 1);
    });

    test(
      'a check-in cannot be repeated or forced into another queue',
      () async {
        final ids = await bookDay(1);
        final e = await checkIn(ids.single);
        expect(
          await h.act('recep', '/appointments/${ids.single}/check-in'),
          409,
        );
        expect(
          await h.act(
            'recep',
            '/queues/q_wrong/entries',
            body: {'appointmentId': ids.single},
          ),
          409,
        );
        expect(e['queueEntryId'], isNotNull);
        expect(h.docsOf('queue_entries'), hasLength(1));
      },
    );
  });

  group('ordering', () {
    test('check-in order, with priority first and positions', () async {
      final ids = await bookDay(3);
      final e2 = await checkIn(ids[1]);
      await checkIn(ids[0]);
      final e3 = await checkIn(ids[2]);
      var entries = (await h.list(
        await h.call(
          'GET',
          '/queues/${(await current())['queueId']}/entries',
          uid: 'recep',
        ),
      )).cast<Map<String, Object?>>();
      expect(entries.map((e) => e['queuePosition']), [1, 2, 3]);
      expect(entries.first['appointmentId'], ids[1]);
      // only authorized roles raise priority
      expect(
        await entryStatus(
          'recep',
          '${e3['queueEntryId']}',
          'priority',
          body: {'priority': 'priority', 'reason': 'Emergency'},
        ),
        403,
      );
      expect(
        await entryStatus(
          'docuser',
          '${e3['queueEntryId']}',
          'priority',
          body: {'priority': 'priority', 'reason': 'Emergency'},
        ),
        403,
      );
      await entryAction(
        'admin',
        '${e3['queueEntryId']}',
        'priority',
        body: {'priority': 'priority', 'reason': 'Emergency'},
      );
      entries = (await h.list(
        await h.call(
          'GET',
          '/queues/${(await current())['queueId']}/entries',
          uid: 'recep',
        ),
      )).cast<Map<String, Object?>>();
      expect(entries.first['appointmentId'], ids[2]);
      expect(
        h
            .docsOf('appointment_audit_logs')
            .any(
              (a) =>
                  a['action'] == 'queue.priority_changed' &&
                  a['reason'] == 'Emergency',
            ),
        isTrue,
      );
      expect(e2['tokenDisplay'], 'A001');
    });

    test('appointment-time ordering ignores arrival order', () async {
      await h.actOk(
        'owner',
        '/clinics/current/settings',
        method: 'PATCH',
        body: {'queueOrdering': 'appointment_time'},
      );
      final ids = await bookDay(3);
      await checkIn(ids[2]);
      await checkIn(ids[0]);
      await checkIn(ids[1]);
      final q = await current();
      final entries = (await h.list(
        await h.call('GET', '/queues/${q['queueId']}/entries', uid: 'recep'),
      )).cast<Map<String, Object?>>();
      expect(entries.map((e) => e['appointmentId']), [ids[0], ids[1], ids[2]]);
    });

    test(
      'priority cannot be set at check-in without the permission, and only on waiting entries',
      () async {
        final ids = await bookDay(2);
        expect(
          await h.act(
            'recep',
            '/appointments/${ids[0]}/check-in',
            body: {'priority': 'priority'},
          ),
          403,
        );
        final e = await checkIn(
          ids[1],
          uid: 'owner',
          body: {'priority': 'priority'},
        );
        await entryAction('docuser', '${e['queueEntryId']}', 'call');
        expect(
          await entryStatus(
            'owner',
            '${e['queueEntryId']}',
            'priority',
            body: {'priority': 'normal', 'reason': 'Changed mind'},
          ),
          409,
        );
      },
    );
  });

  group('state machine', () {
    late List<String> ids;
    late Map<String, Object?> e1;
    late Map<String, Object?> e2;
    setUp(() async {
      ids = await bookDay(2);
      e1 = await checkIn(ids[0]);
      e2 = await checkIn(ids[1]);
    });

    String id1() => '${e1['queueEntryId']}';
    String id2() => '${e2['queueEntryId']}';

    test(
      'call, recall, skip, restore, start and complete keep appointment and queue in step',
      () async {
        expect((await entryAction('recep', id1(), 'call'))['status'], 'called');
        final re = await entryAction('recep', id1(), 'recall');
        expect(re['status'], 'called');
        expect(re['recallCount'], 1);
        expect(
          (await entryAction('recep', id1(), 'skip'))['status'],
          'skipped',
        );
        h.clock.now = h.clock.now.add(const Duration(minutes: 1));
        expect(
          (await entryAction('recep', id1(), 'restore'))['status'],
          'waiting',
        );
        // restored patients return to the end of the line
        var q = await current();
        expect((q['nextToken']! as Map<String, Object?>)['entryId'], id2());
        await entryAction('recep', id2(), 'call');
        expect(
          await entryStatus('docuser', id2(), 'complete'),
          409,
          reason: 'not started',
        );
        final started = await entryAction('docuser', id2(), 'start');
        expect(started['status'], 'in_progress');
        expect(
          (await h.actOk(
            'recep',
            '/appointments/${ids[1]}',
            method: 'GET',
          ))['status'],
          'in_progress',
        );
        q = await current();
        expect(q['inConsultation'], 1);
        expect((q['currentToken']! as Map<String, Object?>)['entryId'], id2());
        await entryAction('docuser', id2(), 'complete');
        expect(
          (await h.actOk(
            'recep',
            '/appointments/${ids[1]}',
            method: 'GET',
          ))['status'],
          'completed',
        );
        q = await current();
        expect(q['completed'], 1);
        expect(q['waiting'], 1);
      },
    );

    test('invalid transitions are refused', () async {
      expect(
        await entryStatus('docuser', id1(), 'start'),
        409,
        reason: 'waiting patients must be called first',
      );
      expect(await entryStatus('recep', id1(), 'recall'), 409);
      expect(await entryStatus('recep', id1(), 'restore'), 409);
      await entryAction('recep', id1(), 'call');
      expect(await entryStatus('recep', id1(), 'call'), 409);
      await entryAction('docuser', id1(), 'start');
      for (final a in ['call', 'skip', 'restore']) {
        expect(await entryStatus('recep', id1(), a), 409, reason: a);
      }
      expect(
        await entryStatus(
          'recep',
          id1(),
          'cancel',
          body: {'reason': 'Left early'},
        ),
        409,
      );
      await entryAction('docuser', id1(), 'complete');
      for (final a in ['call', 'start', 'complete']) {
        expect(await entryStatus('docuser', id1(), a), 409, reason: a);
      }
    });

    test(
      'only one patient can be in consultation at a time; call-next skips nobody',
      () async {
        final qid = '${(await current())['queueId']}';
        final first = await h.actOk('recep', '/queues/$qid/call-next');
        expect(first['entryId'], id1());
        await entryAction('docuser', id1(), 'start');
        expect(await h.act('recep', '/queues/$qid/call-next'), 409);
        await entryAction('recep', id2(), 'call');
        expect(await entryStatus('docuser', id2(), 'start'), 409);
        await entryAction('docuser', id1(), 'complete');
        expect(await entryStatus('docuser', id2(), 'start'), 200);
        await entryAction('docuser', id2(), 'complete');
        expect(
          await h.act('recep', '/queues/$qid/call-next'),
          409,
          reason: 'nobody is waiting',
        );
      },
    );

    test(
      'roles: reception cannot run consultations; doctors only their own queue; others nothing',
      () async {
        await entryAction('recep', id1(), 'call');
        expect(await entryStatus('recep', id1(), 'start'), 403);
        h.member('docuser2', c.tid, 'doctor');
        final other = await h.newDoctor(
          'owner',
          branchIds: [c.br],
          name: 'Dr Other',
          n: '3',
        );
        h.store.docs['tenants/${c.tid}/members/docuser2']!['doctorId'] = other;
        expect(await entryStatus('docuser2', id1(), 'start'), 403);
        expect(await entryStatus('docuser2', id2(), 'call'), 403);
        expect(await entryStatus('acct', id1(), 'call'), 403);
        expect(await h.act('docuser2', '/appointments/${ids[0]}/start'), 403);
        expect(await h.act('recep', '/appointments/${ids[0]}/start'), 403);
        expect(await h.act('recep', '/appointments/${ids[0]}/complete'), 403);
        await entryAction('docuser', id1(), 'start');
        expect(
          await h.act('docuser2', '/appointments/${ids[0]}/complete'),
          403,
        );
        expect(await h.act('nurse', '/appointments/${ids[0]}/complete'), 403);
        expect(await h.act('docuser', '/appointments/${ids[0]}/complete'), 200);
      },
    );

    test(
      'cancelling an entry needs a reason and cancels the visit and its slot',
      () async {
        expect(await entryStatus('recep', id2(), 'cancel'), 400);
        expect(
          await entryStatus(
            'nurse',
            id2(),
            'cancel',
            body: {'reason': 'Patient left'},
          ),
          403,
        );
        final x = await entryAction(
          'recep',
          id2(),
          'cancel',
          body: {'reason': 'Patient left'},
        );
        expect(x['status'], 'cancelled');
        final a = await h.actOk(
          'recep',
          '/appointments/${ids[1]}',
          method: 'GET',
        );
        expect(a['status'], 'cancelled');
        expect(a['cancelSource'], 'queue');
        expect((await current())['cancelled'], 1);
        expect(
          h.reservations().where((r) => r['appointmentId'] == ids[1]),
          isEmpty,
        );
      },
    );

    test(
      'a called patient who does not answer can be marked no-show',
      () async {
        await entryAction('recep', id1(), 'call');
        final x = await entryAction('recep', id1(), 'no-show');
        expect(x['status'], 'no_show');
        expect(
          (await h.actOk(
            'recep',
            '/appointments/${ids[0]}',
            method: 'GET',
          ))['status'],
          'no_show',
        );
        expect((await current())['noShow'], 1);
        expect(await entryStatus('recep', id2(), 'no-show'), 409);
      },
    );

    test(
      'cancelling the appointment cancels the waiting queue entry',
      () async {
        expect(
          await h.act(
            'nurse',
            '/appointments/${ids[1]}/cancel',
            body: {'reason': 'Patient left'},
          ),
          403,
        );
        await h.actOk(
          'recep',
          '/appointments/${ids[1]}/cancel',
          body: {'reason': 'Patient left'},
        );
        final q = await current();
        expect(q['waiting'], 1);
        expect(q['cancelled'], 1);
      },
    );

    test(
      'every queue event is audited and listed in the queue history',
      () async {
        await entryAction('recep', id1(), 'call');
        await entryAction('docuser', id1(), 'start');
        final qid = '${(await current())['queueId']}';
        final hist = (await h.list(
          await h.call('GET', '/queues/$qid/history', uid: 'recep'),
        )).cast<Map<String, Object?>>();
        final actions = hist.map((e) => e['action']);
        expect(
          actions,
          containsAll(['queue.token_generated', 'queue.call', 'queue.start']),
        );
        expect(
          h.apptActions(ids[0]),
          containsAll(['appointment.checked_in', 'appointment.started']),
        );
      },
    );
  });

  group('dashboard and isolation', () {
    test('summary counts for the reception dashboard', () async {
      final ids = await bookDay(4);
      await h.actOk(
        'recep',
        '/appointments/${ids[3]}/cancel',
        body: {'reason': 'Patient called'},
      );
      final e = [for (final id in ids.take(3)) await checkIn(id)];
      await entryAction('recep', '${e[0]['queueEntryId']}', 'call');
      await entryAction('docuser', '${e[0]['queueEntryId']}', 'start');
      final q = await current();
      expect(q['scheduledAppointments'], 3);
      expect(q['checkedIn'], 3);
      expect(q['waiting'], 2);
      expect(q['inConsultation'], 1);
      expect(
        (q['currentToken']! as Map<String, Object?>)['displayToken'],
        'A001',
      );
      final summary = await h.actOk(
        'recep',
        '/queues/${q['queueId']}/summary',
        method: 'GET',
      );
      expect(summary['waiting'], 2);
      final list = await h.list(
        await h.call(
          'GET',
          '/queues?branchId=${c.br}&date=$tuesday',
          uid: 'recep',
        ),
      );
      expect(list, hasLength(1));
    });

    test(
      'the doctor queue shows names and tokens but no clinical data',
      () async {
        final ids = await bookDay(1);
        await checkIn(ids.single);
        final q = await current(uid: 'docuser');
        final text = q.toString();
        expect(text, contains('A001'));
        expect(text, isNot(contains('allerg')));
        expect(text, isNot(contains('phone')));
        expect(text, isNot(contains('9876')));
      },
    );

    test(
      'another clinic and other branches cannot see or change this queue',
      () async {
        final ids = await bookDay(1);
        final e = await checkIn(ids.single);
        final qid = '${(await current())['queueId']}';
        await h.createClinic('ownerB', name: 'Other Clinic');
        expect(await h.status('GET', '/queues/$qid', uid: 'ownerB'), 404);
        expect(
          await h.status('GET', '/queues/$qid/entries', uid: 'ownerB'),
          404,
        );
        expect(
          await h.status('GET', '/queues?branchId=${c.br}', uid: 'ownerB'),
          anyOf(403, 404),
        );
        expect(
          await entryStatus('ownerB', '${e['queueEntryId']}', 'call'),
          404,
        );
        expect(await h.act('ownerB', '/queues/$qid/call-next'), 404);
        final b2 = await h.newBranch('owner', code: 'EAST');
        h.member(
          'east',
          c.tid,
          'receptionist',
          allBranches: false,
          branchIds: [b2],
        );
        expect(await h.status('GET', '/queues/$qid', uid: 'east'), 404);
        expect(await entryStatus('east', '${e['queueEntryId']}', 'call'), 404);
        expect(
          await entryStatus(
            'east',
            '${e['queueEntryId']}',
            'cancel',
            body: {'reason': 'Not mine'},
          ),
          404,
        );
        expect(
          await h.status(
            'GET',
            '/queues/current?branchId=${c.br}&doctorId=${c.doc}',
            uid: 'east',
          ),
          404,
        );
        expect(
          await h.act('east', '/appointments/${ids.single}/check-in'),
          404,
        );
      },
    );

    test('a suspended clinic cannot operate the queue', () async {
      final ids = await bookDay(1);
      final e = await checkIn(ids.single);
      await h.call(
        'POST',
        '/platform/tenants/${c.tid}/suspend',
        uid: 'root',
        body: {'reason': 'Policy review'},
      );
      expect(await entryStatus('recep', '${e['queueEntryId']}', 'call'), 403);
      expect(
        await h.status(
          'GET',
          '/queues/current?branchId=${c.br}&doctorId=${c.doc}',
          uid: 'recep',
        ),
        403,
      );
    });

    test('clients cannot write trusted queue fields', () async {
      final ids = await bookDay(1);
      final e = await checkIn(ids.single);
      for (final m in ['PATCH', 'PUT', 'DELETE']) {
        expect(
          await h.status(
            m,
            '/queue-entries/${e['queueEntryId']}',
            uid: 'owner',
            body: {'status': 'completed', 'tokenNumber': 99},
          ),
          anyOf(404, 405),
          reason: m,
        );
      }
      expect(
        await h.status(
          'POST',
          '/queues/${(await current())['queueId']}/entries',
          uid: 'recep',
          body: {'appointmentId': ids.single, 'tokenNumber': 7},
        ),
        400,
      );
    });
  });
}
