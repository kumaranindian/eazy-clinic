import 'dart:convert';

import 'package:backend/features/reports/export_service.dart';
import 'package:test/test.dart';

import '../../support/billing_fixtures.dart';
import '../../support/clinical_fixtures.dart';
import '../../support/lab_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/portal_fixtures.dart';
import '../../support/scheduling_fixtures.dart';

const _june = 'from=2026-06-01&to=2026-06-30';

void main() {
  late PlatformHarness h;
  late PortalClinic p;
  late List<String> apptIds;

  Map<String, Object?> doc(String coll, String id) =>
      h.store.docs['tenants/${p.tid}/$coll/$id']!;

  Future<Map<String, Object?>> report(
    String kind, {
    String uid = 'owner',
    String query = _june,
  }) => h.get(uid, '/reports/$kind?$query');

  setUp(() async {
    h = PlatformHarness();
    p = PortalClinic(h);
    await p.init();
    // four visits on Tuesday and one on Wednesday
    apptIds = [];
    for (final (d, t) in [
      (tuesday, '09:00'),
      (tuesday, '09:30'),
      (tuesday, '10:00'),
      (tuesday, '10:30'),
      (wednesday, '09:00'),
    ]) {
      final a = await h.bookOk('recep', p.k.c.body(date: d, start: t));
      apptIds.add(a['appointmentId']! as String);
    }
    doc('appointments', apptIds[0])['status'] = 'completed';
    doc('appointments', apptIds[1])['status'] = 'completed';
    doc('appointments', apptIds[2])['status'] = 'no_show';
    doc('appointments', apptIds[3])['status'] = 'rescheduled';
    doc('appointments', apptIds[4])['status'] = 'cancelled';
  });

  group('appointments report', () {
    test('counts by day and status, a moved visit counts once', () async {
      final r = await report('appointments');
      final s = r['summary'] as Map;
      expect(s['total'], 4, reason: 'the rescheduled slot is not counted');
      expect(s['completed'], 2);
      expect(s['noShow'], 1);
      expect(s['cancelled'], 1);
      expect(s['rescheduledAway'], 1);
      expect(s['noShowRate'], closeTo(1 / 3, 0.001));
      expect(s['cancellationRate'], 0.25);
      final rows = (r['rows'] as List).cast<Map<String, Object?>>();
      expect(rows.map((x) => x['date']), [tuesday, wednesday]);
      expect(rows.first['total'], 3);
      expect(rows.first['rescheduled'], 1);
      expect(r['definitions'], isNotEmpty);
      expect(r['generatedAt'], isNotNull);
      expect(r['truncated'], false);
    });

    test(
      'rates are empty, not zero, when there is nothing to divide by',
      () async {
        final r = await report(
          'appointments',
          query: 'from=2026-07-01&to=2026-07-31',
        );
        final s = r['summary'] as Map;
        expect(s['total'], 0);
        expect(s['noShowRate'], isNull);
        expect(s['cancellationRate'], isNull);
        expect(r['rows'], isEmpty);
      },
    );

    test('filters are validated', () async {
      for (final q in [
        'from=2026-13-01',
        'from=2026-06-10&to=2026-06-01',
        'from=2025-01-01&to=2026-06-01',
      ]) {
        expect(
          await h.status('GET', '/reports/appointments?$q', uid: 'owner'),
          400,
          reason: q,
        );
      }
      expect(await h.status('GET', '/reports/bogus', uid: 'owner'), 404);
    });

    test(
      'a doctor sees only their own work and cannot ask for another',
      () async {
        final mine = await report('appointments', uid: 'docuser');
        expect((mine['summary'] as Map)['total'], 4);
        expect(
          await h.status(
            'GET',
            '/reports/appointments?$_june&doctorId=${p.k.doc2}',
            uid: 'docuser',
          ),
          403,
        );
        // the second doctor has no appointments
        final other = await report('appointments', uid: 'doc2user');
        expect((other['summary'] as Map)['total'], 0);
      },
    );

    test('a branch the caller cannot access is refused', () async {
      final other = await h.newBranch('owner', code: 'SECOND');
      h.member(
        'narrow',
        p.tid,
        'receptionist',
        allBranches: false,
        branchIds: [p.br],
      );
      expect(
        await h.status(
          'GET',
          '/reports/appointments?$_june&branchId=$other',
          uid: 'narrow',
        ),
        404,
      );
      expect(
        await h.status(
          'GET',
          '/reports/appointments?$_june&branchId=${p.br}',
          uid: 'narrow',
        ),
        200,
      );
      // the scope also restricts an unfiltered report
      final nb = await h.newBranch('owner', code: 'THIRD');
      h.member(
        'narrow2',
        p.tid,
        'receptionist',
        allBranches: false,
        branchIds: [nb],
      );
      expect(
        ((await report('appointments', uid: 'narrow2'))['summary']
            as Map)['total'],
        0,
      );
    });
  });

  group('access', () {
    test('each section needs its own module permission', () async {
      // receptionist: appointments, queues, patients — not billing, lab, consultations
      expect(
        await h.status('GET', '/reports/appointments?$_june', uid: 'recep'),
        200,
      );
      expect(
        await h.status('GET', '/reports/queues?$_june', uid: 'recep'),
        200,
      );
      expect(
        await h.status('GET', '/reports/billing?$_june', uid: 'recep'),
        403,
      );
      expect(
        await h.status('GET', '/reports/laboratory?$_june', uid: 'recep'),
        403,
      );
      expect(
        await h.status('GET', '/reports/consultations?$_june', uid: 'recep'),
        403,
      );
      // accountant: billing only
      expect(
        await h.status('GET', '/reports/billing?$_june', uid: 'acct'),
        200,
      );
      expect(
        await h.status('GET', '/reports/appointments?$_june', uid: 'acct'),
        403,
      );
      expect(
        await h.status('GET', '/reports/patients?$_june', uid: 'acct'),
        403,
      );
      // doctors do not get clinic-wide patient registration reports
      expect(
        await h.status('GET', '/reports/patients?$_june', uid: 'docuser'),
        403,
      );
    });

    test('a plan without reports blocks them', () async {
      await h.createClinic(
        'lite',
        name: 'Lite Clinic',
        city: 'Nashik',
        pin: '422001',
        reports: false,
      );
      expect(await h.status('GET', '/reports/dashboard', uid: 'lite'), 403);
    });

    test('another clinic sees none of this clinic\'s data', () async {
      await h.createClinic(
        'rival',
        name: 'Rival Clinic',
        city: 'Nagpur',
        pin: '440001',
      );
      final r = await report('appointments', uid: 'rival');
      expect((r['summary'] as Map)['total'], 0);
      expect(
        ((await report('patients', uid: 'rival'))['summary']
            as Map)['activePatients'],
        0,
      );
    });

    test('unauthenticated callers are refused', () async {
      expect(await h.status('GET', '/reports/dashboard'), 401);
    });
  });

  group('queues', () {
    test('wait time uses only tokens with both timestamps', () async {
      final base = DateTime.utc(2026, 6, 2, 4); // 09:30 IST
      void entry(
        String id,
        DateTime? called,
        String status, {
        DateTime? checkIn,
      }) {
        h.store.docs['tenants/${p.tid}/queue_entries/$id'] = {
          'entryId': id,
          'branchId': p.br,
          'doctorId': p.doctor,
          'queueDate': tuesday,
          'status': status,
          'checkInAt': checkIn ?? base,
          'calledAt': called,
        };
      }

      entry('q1', base.add(const Duration(minutes: 10)), 'completed');
      entry('q2', base.add(const Duration(minutes: 30)), 'completed');
      entry('q3', null, 'skipped');
      entry('q4', null, 'no_show', checkIn: base.add(const Duration(hours: 5)));
      final r = await report('queues');
      final s = r['summary'] as Map;
      expect(s['tokens'], 4);
      expect(s['completed'], 2);
      expect(s['skipped'], 1);
      expect(s['noShow'], 1);
      final w = s['waitMinutes'] as Map;
      expect(w['average'], 20.0);
      expect(w['measured'], 2);
      expect(w['of'], 4);
      expect((s['peakHours'] as List).first['hour'], '09:00');
    });

    test('no data means no wait time, not zero', () async {
      final s = (await report('queues'))['summary'] as Map;
      expect(s['tokens'], 0);
      expect(s['waitMinutes'], isNull);
    });
  });

  group('patients', () {
    test(
      'registrations, new versus returning, aggregate demographics only',
      () async {
        // the fixture patient was created "today"; one older patient had a visit
        final older = await p.k.c.morePatient(2);
        doc('patients', older)['createdAt'] = DateTime.utc(2025, 1, 1);
        doc('appointments', apptIds[0])['patientId'] = older;
        final r = await report('patients');
        final s = r['summary'] as Map;
        expect(s['registrations'], greaterThanOrEqualTo(1));
        expect(s['returningPatients'], 1);
        expect(
          s['newPatients'],
          1,
          reason: 'the fixture patient completed a visit',
        );
        expect(s['visitingPatients'], 2);
        expect(s['byGender'], isA<Map<String, Object?>>());
        expect(jsonEncode(r).contains('fullName'), isFalse);
      },
    );
  });

  group('consultations', () {
    test('counts and statuses without clinical content', () async {
      final cid = await p.k.readyConsultation();
      await h.actOk('docuser', '/consultations/$cid/finalize');
      await p.k.readyConsultation();
      final r = await report('consultations', uid: 'owner');
      final s = r['summary'] as Map;
      expect(s['total'], 2);
      expect((s['byStatus'] as Map)['finalized'], 1);
      final raw = jsonEncode(r);
      for (final k in [
        'chiefComplaint',
        'Viral fever',
        'Fever for three days',
      ]) {
        expect(raw.contains(k), isFalse, reason: k);
      }
      // the doctor sees their own; another doctor sees none
      expect(
        ((await report('consultations', uid: 'docuser'))['summary']
            as Map)['total'],
        2,
      );
      expect(
        ((await report('consultations', uid: 'doc2user'))['summary']
            as Map)['total'],
        0,
      );
    });
  });

  group('laboratory', () {
    test('orders, open orders, published reports and turnaround', () async {
      final lab = LabClinic.on(h, p.k.c);
      final t = (await lab.test())['testId']! as String;
      final id = await lab.verified(t);
      h.clock.now = h.clock.now.add(const Duration(hours: 5));
      await lab.post('labtech2', '/laboratory/orders/$id/publish');
      await lab.order(t); // still open
      final s = (await report('laboratory', uid: 'owner'))['summary'] as Map;
      expect(s['ordersCreated'], 2);
      expect(s['reportsPublished'], 1);
      expect(s['openOrdersNow'], 1);
      expect((s['turnaroundHours'] as Map)['measured'], 1);
      expect((s['turnaroundHours'] as Map)['average'], greaterThanOrEqualTo(5));
      expect(
        await h.status('GET', '/reports/laboratory?$_june', uid: 'recep'),
        403,
      );
    });
  });

  group('billing', () {
    test('billed, collected, refunded and outstanding stay separate', () async {
      final b = BillingClinic.on(h, p.k.c);
      final inv = await b.finalized(amount: 100000);
      final pay = await b.pay(inv['invoiceId']! as String, 40000);
      final id = 'rf_seed';
      h.store.docs['tenants/${p.tid}/refunds/$id'] = {
        'refundId': id,
        'branchId': p.br,
        'status': 'completed',
        'amount': 5000,
        'completedAt': h.clock.now,
        'paymentId': pay['paymentId'],
      };
      final r = await report('billing', uid: 'acct');
      final s = r['summary'] as Map;
      expect(s['grossBilled'], 100000);
      expect(s['collected'], 40000);
      expect(s['refunded'], 5000);
      expect(s['netCollected'], 35000);
      expect(s['outstandingOnInvoicesInRange'], 60000);
      expect((s['byMethod'] as Map)['cash'], 40000);
      final raw = jsonEncode(r).toLowerCase();
      expect(raw.contains('"profit'), isFalse);
      expect(raw, contains('not profit'));
      expect(
        await h.status('GET', '/reports/billing?$_june', uid: 'nurse'),
        403,
      );
    });

    test('drafts and cancelled invoices are not billed', () async {
      final b = BillingClinic.on(h, p.k.c);
      await b.draft(
        lines: [
          {'description': 'Draft', 'unitMinor': 99900, 'quantity': 1},
        ],
      );
      final s = (await report('billing', uid: 'owner'))['summary'] as Map;
      expect(s['grossBilled'], 0);
      expect(s['invoices'], 0);
    });
  });

  group('dashboard', () {
    test(
      'shows what the caller may see and marks the rest unavailable',
      () async {
        final owner = await h.get('owner', '/reports/dashboard?$_june');
        final sec = owner['sections'] as Map;
        for (final k in ['appointments', 'queues', 'patients']) {
          expect((sec[k] as Map)['available'], true, reason: k);
        }
        final acct = await h.get('acct', '/reports/dashboard?$_june');
        final a = acct['sections'] as Map;
        expect((a['billing'] as Map)['available'], true);
        expect((a['appointments'] as Map)['available'], false);
        expect((a['appointments'] as Map)['reason'], 'not_permitted');
        expect(owner['generatedAt'], isNotNull);
        expect((owner['trend'] as Map)['points'], hasLength(2));
      },
    );
  });

  group('exports', () {
    Future<Map<String, Object?>> export(
      String uid,
      Map<String, Object?> body, {
      int status = 201,
    }) => h.okData(
      h.call('POST', '/reports/exports', uid: uid, body: body),
      status: status,
    );

    test('csv: ready, downloadable by the requester, audited', () async {
      final e = await export('admin', {
        'report': 'appointments',
        'format': 'csv',
        'from': '2026-06-01',
        'to': '2026-06-30',
      });
      expect(e['status'], 'ready');
      expect(e['rows'], 2);
      expect(e.containsKey('storagePath'), isFalse);
      final dl = await h.call(
        'GET',
        '/reports/exports/${e['exportId']}/download',
        uid: 'admin',
      );
      expect(dl.statusCode, 200);
      expect(dl.headers['content-type'], contains('text/csv'));
      expect(dl.headers['cache-control'], contains('no-store'));
      final text = await dl.readAsString();
      expect(text.split('\n').first, startsWith('date,total'));
      expect(text, contains('2026-06-02,3'));
      expect(
        h.docsOf('report_audit_logs').map((d) => d['action']),
        containsAll([
          'report.export_requested',
          'report.export_ready',
          'report.export_downloaded',
        ]),
      );
    });

    test('pdf export is a real pdf', () async {
      final e = await export('owner', {
        'report': 'billing',
        'format': 'pdf',
        'from': '2026-06-01',
        'to': '2026-06-30',
      });
      final dl = await h.call(
        'GET',
        '/reports/exports/${e['exportId']}/download',
        uid: 'owner',
      );
      expect(dl.headers['content-type'], 'application/pdf');
      final bytes = await dl.read().expand((x) => x).toList();
      expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    });

    test('same access rules as the screen', () async {
      // no export permission
      for (final uid in ['recep', 'acct', 'docuser', 'nurse']) {
        expect(
          await h.status(
            'POST',
            '/reports/exports',
            uid: uid,
            body: {'report': 'appointments', 'format': 'csv'},
          ),
          403,
          reason: uid,
        );
      }
      // the admin may export but not a section whose module permission is missing
      expect(
        await h.status(
          'POST',
          '/reports/exports',
          uid: 'admin',
          body: {'report': 'consultations', 'format': 'csv'},
        ),
        403,
      );
      final failed = h
          .docsOf('report_exports')
          .where((d) => d['status'] == 'failed');
      expect(failed, hasLength(1));
      expect(
        h.docsOf('report_audit_logs').map((d) => d['action']),
        contains('report.export_failed'),
      );
      // outside the caller's branches
      final other = await h.newBranch('owner', code: 'SECOND');
      h.member(
        'narrow',
        p.tid,
        'clinic_admin',
        allBranches: false,
        branchIds: [p.br],
      );
      expect(
        await h.status(
          'POST',
          '/reports/exports',
          uid: 'narrow',
          body: {'report': 'appointments', 'format': 'csv', 'branchId': other},
        ),
        404,
      );
    });

    test('validation: unknown report, format, extra fields, range', () async {
      expect(
        await h.status(
          'POST',
          '/reports/exports',
          uid: 'owner',
          body: {'report': 'payroll', 'format': 'csv'},
        ),
        422,
      );
      expect(
        await h.status(
          'POST',
          '/reports/exports',
          uid: 'owner',
          body: {'report': 'appointments', 'format': 'xlsx'},
        ),
        422,
      );
      expect(
        await h.status(
          'POST',
          '/reports/exports',
          uid: 'owner',
          body: {
            'report': 'appointments',
            'format': 'csv',
            'tenantId': 'other',
          },
        ),
        422,
      );
      expect(
        await h.status(
          'POST',
          '/reports/exports',
          uid: 'owner',
          body: {
            'report': 'appointments',
            'format': 'csv',
            'from': '2020-01-01',
            'to': '2026-01-01',
          },
        ),
        400,
      );
    });

    test('only the requester can see or download it, and it expires', () async {
      final e = await export('admin', {
        'report': 'appointments',
        'format': 'csv',
        'from': '2026-06-01',
        'to': '2026-06-30',
      });
      for (final uid in ['owner', 'recep', 'docuser']) {
        expect(
          await h.status('GET', '/reports/exports/${e['exportId']}', uid: uid),
          anyOf(403, 404),
          reason: uid,
        );
        expect(
          await h.status(
            'GET',
            '/reports/exports/${e['exportId']}/download',
            uid: uid,
          ),
          anyOf(403, 404),
          reason: uid,
        );
      }
      expect(
        await h.status(
          'GET',
          '/reports/exports/${e['exportId']}',
          uid: 'admin',
        ),
        200,
      );
      final hist = await h.list(
        await h.call('GET', '/reports/exports', uid: 'admin'),
      );
      expect(hist, hasLength(1));
      expect(jsonEncode(hist).contains('storagePath'), isFalse);
      h.clock.now = h.clock.now.add(const Duration(hours: 7));
      expect(
        await h.status(
          'GET',
          '/reports/exports/${e['exportId']}/download',
          uid: 'admin',
        ),
        404,
      );
      expect(
        ((await h.get(
          'admin',
          '/reports/exports/${e['exportId']}',
        ))['expired']),
        true,
      );
    });

    test('another clinic cannot reach it', () async {
      final e = await export('admin', {
        'report': 'appointments',
        'format': 'csv',
        'from': '2026-06-01',
        'to': '2026-06-30',
      });
      await h.createClinic(
        'rival',
        name: 'Rival Clinic',
        city: 'Nagpur',
        pin: '440001',
      );
      expect(
        await h.status(
          'GET',
          '/reports/exports/${e['exportId']}',
          uid: 'rival',
        ),
        404,
      );
      expect(
        await h.status(
          'GET',
          '/reports/exports/${e['exportId']}/download',
          uid: 'rival',
        ),
        404,
      );
    });

    test('concurrent exports each get their own file', () async {
      final res = await Future.wait([
        for (var i = 0; i < 3; i++)
          export('owner', {
            'report': 'appointments',
            'format': 'csv',
            'from': '2026-06-01',
            'to': '2026-06-30',
          }),
      ]);
      expect({for (final r in res) r['exportId']}, hasLength(3));
      expect(
        h.docsOf('report_exports').where((d) => d['status'] == 'ready'),
        hasLength(3),
      );
    });

    test('creation is rate limited', () async {
      var limited = 0;
      for (var i = 0; i < 22; i++) {
        final s = await h.status(
          'POST',
          '/reports/exports',
          uid: 'owner',
          body: {
            'report': 'queues',
            'format': 'csv',
            'from': '2026-06-01',
            'to': '2026-06-02',
          },
        );
        if (s == 429) limited++;
      }
      expect(limited, greaterThan(0));
    });
  });

  group('csv safety', () {
    test(
      'formula-like text is neutralised, other text and numbers untouched',
      () {
        expect(csvCell('=HYPERLINK("http://x")'), contains("'=HYPERLINK"));
        expect(csvCell('=1+1'), "'=1+1");
        expect(csvCell('+SUM(A1)'), "'+SUM(A1)");
        expect(csvCell('-2+3'), "'-2+3");
        expect(csvCell('@cmd'), "'@cmd");
        expect(csvCell('\tcmd'), "'\tcmd");
        expect(csvCell('Dr Rao'), 'Dr Rao');
        expect(csvCell(-5), '-5');
        expect(csvCell(12.5), '12.5');
        expect(csvCell(null), '');
        expect(csvCell('a,b'), '"a,b"');
        expect(csvCell('say "hi"'), '"say ""hi"""');
        expect(
          toCsv(
            ['a', 'b'],
            [
              {'a': '=x', 'b': 1},
            ],
          ),
          "a,b\n'=x,1\n",
        );
      },
    );
  });
}
