@Tags(['perf'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../support/patient_fixtures.dart';
import '../support/platform_http_fixtures.dart';
import '../support/portal_fixtures.dart';
import '../support/scheduling_fixtures.dart';

/// Performance baseline and concurrency checks (in-memory store).
///
/// Run with `PERF=1 dart test test/perf` (skipped otherwise). The in-memory
/// store has no network, so these numbers measure the application code only;
/// they are a regression baseline, not a Firestore capacity claim. Results are
/// written to `PERF_OUT` (default `perf_results.json`).
void main() {
  final enabled = Platform.environment['PERF'] == '1';
  final out = Platform.environment['PERF_OUT'] ?? 'perf_results.json';
  final results = <String, Object?>{};

  Map<String, Object?> stats(List<int> micros) {
    final s = [...micros]..sort();
    int pct(double p) => s[((s.length - 1) * p).round()];
    return {
      'n': s.length,
      'p50_ms': pct(.5) / 1000,
      'p95_ms': pct(.95) / 1000,
      'max_ms': s.last / 1000,
    };
  }

  Future<List<int>> time(int n, Future<void> Function(int i) f) async {
    final out = <int>[];
    for (var i = 0; i < n; i++) {
      final sw = Stopwatch()..start();
      await f(i);
      out.add(sw.elapsedMicroseconds);
    }
    return out;
  }

  tearDownAll(() {
    if (enabled) {
      File(
        out,
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(results));
    }
  });

  late PlatformHarness h;
  late PortalClinic p;

  setUp(() async {
    h = PlatformHarness();
    p = PortalClinic(h);
    await p.init();
  });

  test(
    'API latency on a clinic with realistic volumes',
    () async {
      // 1,500 appointments over 30 days, 400 notifications
      final base = DateTime.utc(2026, 6, 1);
      for (var i = 0; i < 1500; i++) {
        final d = base.add(Duration(days: i % 30));
        final date =
            '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
        h.store.docs['tenants/${p.tid}/appointments/perf_$i'] = {
          'appointmentId': 'perf_$i',
          'tenantId': p.tid,
          'branchId': p.br,
          'doctorId': p.doctor,
          'doctorName': 'Dr Perf',
          'patientId': p.patientId,
          'localDate': date,
          'startTime': '09:00',
          'startUtc': d.add(const Duration(hours: 3)),
          'status': const [
            'completed',
            'cancelled',
            'no_show',
            'confirmed',
          ][i % 4],
          'source': 'staff',
          'createdAt': d,
        };
      }
      for (var i = 0; i < 400; i++) {
        h.store.docs['tenants/${p.tid}/notifications/pn_$i'] = {
          'notificationId': 'pn_$i',
          'recipientUid': 'recep',
          'category': 'report_available',
          'title': 't',
          'body': 'b',
          'read': i % 2 == 0,
          'archived': false,
          'createdAt': base.add(Duration(minutes: i)),
        };
      }
      Future<void> get(String uid, String path) async {
        final r = await h.call('GET', path, uid: uid);
        expect(r.statusCode, 200, reason: path);
        await r.readAsString();
      }

      results['api'] = {
        'GET /appointments?date (list)': stats(
          await time(
            60,
            (_) => get('recep', '/appointments?date=2026-06-02&limit=50'),
          ),
        ),
        'GET /notifications (page 20)': stats(
          await time(60, (_) => get('recep', '/notifications?limit=20')),
        ),
        'GET /notifications/unread-count': stats(
          await time(60, (_) => get('recep', '/notifications/unread-count')),
        ),
        'GET /reports/appointments (1,500 rows, month)': stats(
          await time(
            15,
            (_) => get(
              'owner',
              '/reports/appointments?from=2026-06-01&to=2026-06-30',
            ),
          ),
        ),
        'GET /reports/dashboard (all sections)': stats(
          await time(
            8,
            (_) => get(
              'owner',
              '/reports/dashboard?from=2026-06-01&to=2026-06-30',
            ),
          ),
        ),
        'GET /laboratory/dashboard': stats(
          await time(15, (_) => get('owner', '/laboratory/dashboard')),
        ),
      };
      final sw = Stopwatch()..start();
      final exp = await h.call(
        'POST',
        '/reports/exports',
        uid: 'owner',
        body: {
          'report': 'appointments',
          'format': 'csv',
          'from': '2026-06-01',
          'to': '2026-06-30',
        },
      );
      results['export_csv_1500_appointments_ms'] = sw.elapsedMilliseconds;
      expect(exp.statusCode, 201);
    },
    skip: enabled ? false : 'set PERF=1',
  );

  test(
    'report on more records than the scan cap says so, and stays bounded',
    () async {
      for (var i = 0; i < 5200; i++) {
        h.store.docs['tenants/${p.tid}/appointments/big_$i'] = {
          'appointmentId': 'big_$i',
          'branchId': p.br,
          'doctorId': p.doctor,
          'patientId': p.patientId,
          'localDate': '2026-06-02',
          'status': 'completed',
        };
      }
      final sw = Stopwatch()..start();
      final r = await h.call(
        'GET',
        '/reports/appointments?from=2026-06-01&to=2026-06-30',
        uid: 'owner',
      );
      final body = jsonDecode(await r.readAsString()) as Map;
      results['report_over_cap_ms'] = sw.elapsedMilliseconds;
      expect((body['data'] as Map)['truncated'], true);
      final ex = await h.call(
        'POST',
        '/reports/exports',
        uid: 'owner',
        body: {
          'report': 'appointments',
          'format': 'csv',
          'from': '2026-06-01',
          'to': '2026-06-30',
        },
      );
      expect(
        ex.statusCode,
        422,
        reason: 'an incomplete report is never exported',
      );
    },
    skip: enabled ? false : 'set PERF=1',
  );

  test('concurrency: one slot, many bookers', () async {
    final others = <String>[];
    for (var i = 0; i < 30; i++) {
      others.add(await p.k.c.morePatient(10 + i));
    }
    final sw = Stopwatch()..start();
    final codes = await Future.wait([
      for (final pid in others)
        h
            .call(
              'POST',
              '/appointments',
              uid: 'recep',
              headers: {'idempotency-key': 'perf-${pid.hashCode}-key-0001'},
              body: p.k.c.body(start: '11:00', patientId: pid),
            )
            .then((r) => r.statusCode),
    ]);
    results['booking_race'] = {
      'requests': codes.length,
      'created': codes.where((c) => c == 201).length,
      'ms': sw.elapsedMilliseconds,
    };
    expect(codes.where((c) => c == 201).length, 1);
    expect(codes.where((c) => c >= 500), isEmpty);
  }, skip: enabled ? false : 'set PERF=1');

  test('concurrency: queue tokens stay unique', () async {
    final ids = <String>[];
    for (var i = 0; i < 8; i++) {
      final pid = await p.k.c.morePatient(10 + i);
      final a = await h.bookOk(
        'recep',
        p.k.c.body(
          start:
              '${(9 + i ~/ 2).toString().padLeft(2, '0')}:${i.isEven ? '00' : '30'}',
          patientId: pid,
        ),
      );
      ids.add(a['appointmentId']! as String);
    }
    h.clock.now = DateTime.utc(2026, 6, 2, 4, 30);
    final sw = Stopwatch()..start();
    final bodies = <String>[];
    final codes = await Future.wait([
      for (final id in ids)
        h.call('POST', '/appointments/$id/check-in', uid: 'recep').then((
          r,
        ) async {
          if (r.statusCode != 200) bodies.add(await r.readAsString());
          return r.statusCode;
        }),
    ]);
    final tokens = h
        .docsOf('queue_entries')
        .map((e) => e['tokenNumber'])
        .toList();
    results['checkin_race'] = {
      'requests': ids.length,
      'ok': codes.where((c) => c == 200).length,
      'tokens': tokens.length,
      'unique': tokens.toSet().length,
      'ms': sw.elapsedMilliseconds,
    };
    expect(codes.where((c) => c >= 500), isEmpty);
    expect(tokens.toSet().length, tokens.length);
  }, skip: enabled ? false : 'set PERF=1');

  test(
    'concurrency: notifications from many events and several workers',
    () async {
      final hub = h.clinic.hub;
      for (var i = 0; i < 150; i++) {
        await hub.emit(
          tenantId: p.tid,
          type: 'payment_received',
          dedupeKey: 'perf-$i',
          accountId: p.accountId,
          fallbackTitle: 'x',
          fallbackBody: 'y',
        );
      }
      final sw = Stopwatch()..start();
      await Future.wait([
        for (var w = 0; w < 4; w++) hub.processPending(p.tid, limit: 200),
      ]);
      await Future.wait([
        for (var w = 0; w < 4; w++) hub.dispatchDue(p.tid, limit: 200),
      ]);
      results['notification_workers'] = {
        'events': 150,
        'inbox': h.docsOf('patient_notifications').length,
        'ms': sw.elapsedMilliseconds,
      };
      expect(h.docsOf('patient_notifications').length, 150);
    },
    skip: enabled ? false : 'set PERF=1',
  );
}
