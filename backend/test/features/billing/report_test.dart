import 'package:test/test.dart';

import '../../support/billing_fixtures.dart';
import '../../support/patient_fixtures.dart';
import '../../support/platform_http_fixtures.dart';
import '../../support/scheduling_fixtures.dart';

void main() {
  late PlatformHarness h;
  late BillingClinic k;

  setUp(() async {
    h = PlatformHarness();
    k = BillingClinic(h);
    await k.init();
  });

  Future<Map<String, Object?>> get(String path, {String uid = 'acct'}) =>
      h.okData(h.call('GET', path, uid: uid));

  /// Invoice A: 100000, paid in cash, 20000 refunded.
  /// Invoice B: 60000 due in the past, 20000 paid by UPI.
  /// One approved and paid expense of 30000.
  Future<void> scenario() async {
    final a = await k.finalized(
      amount: 100000,
      lines: [
        {
          'description': 'Consultation',
          'category': 'consultation',
          'unitMinor': 100000,
          'quantity': 1,
        },
      ],
      extra: {'doctorId': k.doctor},
    );
    final pay = await k.pay(a['invoiceId']! as String, 100000);
    await k.refundDone(
      pay['paymentId']! as String,
      20000,
      invoiceId: a['invoiceId'] as String,
    );
    final p2 = await k.c.morePatient(2);
    final b = await k.finalized(
      amount: 60000,
      patientId: p2,
      extra: {'dueDate': '2026-05-25'},
    );
    await k.pay(
      b['invoiceId']! as String,
      20000,
      patientId: p2,
      method: 'upi',
      reference: 'UTR55',
    );
    final cat = (await h.okData(
      h.call(
        'POST',
        '/expenses/categories',
        uid: 'owner',
        body: {'name': 'Rent'},
      ),
      status: 201,
    ))['categoryId'];
    final e = await h.okData(
      h.call(
        'POST',
        '/expenses',
        uid: 'acct',
        body: {
          'categoryId': cat,
          'description': 'Monthly rent',
          'amountMinor': 30000,
          'expenseDate': '2026-06-01',
          'branchId': k.br,
        },
      ),
      status: 201,
    );
    final id = e['expenseId']! as String;
    await h.call('POST', '/expenses/$id/submit', uid: 'acct');
    await h.call('POST', '/expenses/$id/approve', uid: 'admin', body: {});
    await h.call(
      'POST',
      '/expenses/$id/pay',
      uid: 'acct',
      body: {'method': 'cash'},
    );
  }

  group('dashboard', () {
    test(
      'aggregates collections, refunds, outstanding and expenses on the backend',
      () async {
        await scenario();
        final d = await get('/finance/dashboard');
        expect(d['currency'], 'INR');
        expect(d['asOf'], '2026-06-01');
        final today = d['today']! as Map;
        expect(today['collected'], 120000);
        expect(today['refunded'], 20000);
        expect(today['netCollected'], 100000);
        final month = d['monthToDate']! as Map;
        expect(month['collected'], 120000);
        expect(month['invoiced'], 160000);
        expect(month['expensesPaid'], 30000);
        expect(month['expensesApproved'], 30000);
        final out = d['outstanding']! as Map;
        expect(out['total'], 40000);
        expect(out['invoices'], 1);
        expect(out['overdueTotal'], 40000);
        expect(out['overdueInvoices'], 1);
        expect(d['paymentMethods'], {'cash': 100000, 'upi': 20000});
        final branches = d['branchWise']! as List;
        expect(branches, hasLength(1));
        expect((branches.single as Map)['collected'], 120000);
        expect((branches.single as Map)['netCollected'], 100000);
        final doctors = d['doctorWise']! as List;
        expect((doctors.single as Map)['revenue'], 100000);
        expect((doctors.single as Map)['doctorId'], k.doctor);
        expect(d['definitions'], isA<Map<String, Object?>>());
        expect(d['truncated'], false);
      },
    );

    test('an empty clinic reports zeros, not errors', () async {
      final d = await get('/finance/dashboard');
      expect((d['today']! as Map)['collected'], 0);
      expect((d['outstanding']! as Map)['total'], 0);
      expect(d['paymentMethods'], isEmpty);
    });

    test('today, the last 7 days and the month are separate windows', () async {
      await scenario();
      h.clock.now = DateTime.utc(2026, 6, 5, 10);
      final d = await get('/finance/dashboard');
      expect((d['today']! as Map)['collected'], 0);
      expect((d['last7Days']! as Map)['collected'], 120000);
      expect((d['monthToDate']! as Map)['collected'], 120000);
      h.clock.now = DateTime.utc(2026, 6, 9, 10);
      final later = await get('/finance/dashboard');
      expect(
        (later['last7Days']! as Map)['collected'],
        0,
        reason: 'June 1 is more than 6 days back',
      );
      expect((later['monthToDate']! as Map)['collected'], 120000);
    });
  });

  group('reports', () {
    test('collections by day with method breakdown', () async {
      await scenario();
      final r = await get(
        '/finance/reports/collections?from=2026-06-01&to=2026-06-30',
      );
      final rows = r['rows']! as List;
      expect(rows, hasLength(1));
      expect((rows.single as Map)['period'], '2026-06-01');
      expect((rows.single as Map)['payments'], 2);
      final t = r['totals']! as Map;
      expect(t['collected'], 120000);
      expect(t['refunded'], 20000);
      expect(t['netCollected'], 100000);
      expect(r['byMethod'], {'cash': 100000, 'upi': 20000});
      final monthly = await get(
        '/finance/reports/collections?from=2026-06-01&to=2026-06-30&groupBy=month',
      );
      expect(((monthly['rows']! as List).single as Map)['period'], '2026-06');
      final upi = await get(
        '/finance/reports/collections?from=2026-06-01&to=2026-06-30&method=upi',
      );
      expect((upi['totals']! as Map)['collected'], 20000);
      final none = await get(
        '/finance/reports/collections?from=2026-05-01&to=2026-05-31',
      );
      expect(none['rows'], isEmpty);
    });

    test('outstanding report with ageing', () async {
      await scenario();
      final r = await get('/finance/reports/outstanding');
      final t = r['totals']! as Map;
      expect(t['outstanding'], 40000);
      expect(t['overdue'], 40000);
      expect((r['ageing']! as Map)['days1to30'], 40000);
      final row = (r['rows']! as List).single as Map;
      expect(row['daysOverdue'], 7);
      expect(row['invoiceNumber'], 'INV-000002');
    });

    test('refund, expense, branch-wise and doctor-wise reports', () async {
      await scenario();
      final rf = await get(
        '/finance/reports/refunds?from=2026-06-01&to=2026-06-30',
      );
      expect((rf['totals']! as Map)['amount'], 20000);
      expect((rf['byStatus']! as Map)['completed'], 20000);
      final ex = await get(
        '/finance/reports/expenses?from=2026-06-01&to=2026-06-30',
      );
      expect((ex['totals']! as Map)['paid'], 30000);
      expect((ex['byCategory']! as Map)['Rent'], 30000);
      final bw = await get(
        '/finance/reports/branch-wise?from=2026-06-01&to=2026-06-30',
      );
      expect(((bw['rows']! as List).single as Map)['invoiced'], 160000);
      final dw = await get(
        '/finance/reports/doctor-wise?from=2026-06-01&to=2026-06-30',
      );
      final row = (dw['rows']! as List).single as Map;
      expect(row['revenue'], 100000);
      expect(row['doctorName'], isNotNull);
    });

    test('ranges and filters are validated', () async {
      Future<int> status(String q) =>
          h.status('GET', '/finance/reports/collections$q', uid: 'acct');
      expect(await status('?from=2026-06-10&to=2026-06-01'), 400);
      expect(await status('?from=bad'), 400);
      expect(await status('?from=2024-01-01&to=2026-06-01'), 400);
      expect(
        await h.status(
          'GET',
          '/finance/reports/refunds?status=bogus',
          uid: 'acct',
        ),
        400,
      );
    });
  });

  group('access', () {
    test('reports need finance.reports.view and are branch scoped', () async {
      await scenario();
      for (final uid in ['recep', 'nurse', 'docuser']) {
        expect(
          await h.status('GET', '/finance/dashboard', uid: uid),
          403,
          reason: uid,
        );
        expect(
          await h.status('GET', '/finance/reports/collections', uid: uid),
          403,
          reason: uid,
        );
      }
      expect(await h.status('GET', '/finance/dashboard'), 401);
      // another clinic sees none of it
      await h.createClinic('ownerB', name: 'Other Clinic');
      final b = await get('/finance/dashboard', uid: 'ownerB');
      expect((b['today']! as Map)['collected'], 0);
      // an accountant restricted to another branch sees none of it
      final br2 = await h.newBranch('owner', code: 'BR2');
      h.member(
        'acctB2',
        k.tid,
        'accountant',
        allBranches: false,
        branchIds: [br2],
      );
      final scoped = await get('/finance/dashboard', uid: 'acctB2');
      expect((scoped['today']! as Map)['collected'], 0);
      expect((scoped['outstanding']! as Map)['total'], 0);
      expect(
        await h.status(
          'GET',
          '/finance/dashboard?branchId=${k.br}',
          uid: 'acctB2',
        ),
        404,
      );
      expect(
        await h.status('GET', '/finance/reports/branch-wise', uid: 'acctB2'),
        200,
      );
      final bw = await get(
        '/finance/reports/branch-wise?from=2026-06-01&to=2026-06-30',
        uid: 'acctB2',
      );
      expect(bw['rows'], isEmpty);
    });

    test('CSV export needs its own permission and neutralizes formulas', () async {
      await scenario();
      // a patient with a spreadsheet-formula name shows up in the outstanding rows
      final p3 =
          (await h.newPatient(
                'recep',
                k.br,
                name: '=HYPERLINK Evil',
                dob: '1985-01-01',
                phone: '9876500777',
              ))['patientId']!
              as String;
      await k.finalized(amount: 500, patientId: p3);
      final res = await h.call(
        'GET',
        '/finance/reports/outstanding?format=csv',
        uid: 'acct',
      );
      expect(res.statusCode, 200);
      expect(res.headers['content-type'], contains('text/csv'));
      final csv = await res.readAsString();
      expect(csv.split('\n').first, contains('"invoiceNumber"'));
      expect(csv, isNot(contains(',"=HYPERLINK')));
      expect(csv, contains("\"'=HYPERLINK"));
      expect(k.auditActions(), contains('report.exported'));
      // dashboards can be viewed by an admin but export is not granted to everyone with view
      expect(
        await h.status(
          'GET',
          '/finance/reports/outstanding?format=csv',
          uid: 'recep',
        ),
        403,
      );
    });
  });

  group('appointment to invoice to payment to refund to dashboard', () {
    test('the whole flow keeps every number consistent', () async {
      // service with GST, booked visit, invoice from the appointment
      final tax = await k.taxRule();
      final s = await k.service(
        taxRuleId: tax['taxRuleId']! as String,
        extra: {
          'doctorFees': {k.doctor: 80000},
        },
      );
      final appt = await h.bookOk('recep', k.c.body());
      final d = await k.draft(
        extra: {'appointmentId': appt['appointmentId']},
        lines: [
          {'serviceId': s['serviceId'], 'quantity': 1},
        ],
      );
      expect(d['doctorId'], k.doctor);
      expect(d['subtotal'], 80000);
      expect(d['taxTotal'], 14400);
      expect(d['grandTotal'], 94400);
      final id = d['invoiceId']! as String;
      final f = await h.okData(
        h.call('POST', '/billing/invoices/$id/finalize', uid: 'recep'),
      );
      expect(f['outstanding'], 94400);
      final p1 = await k.pay(id, 50000, method: 'upi', reference: 'UTR-A');
      final p2 = await k.pay(id, 44400);
      expect((await k.invoice(id))['status'], 'paid');
      await k.refundDone(p1['paymentId']! as String, 10000, invoiceId: id);
      final inv = await k.invoice(id);
      expect(inv['status'], 'partially_refunded');
      expect(inv['amountPaid'], 94400);
      expect(inv['amountRefunded'], 10000);
      expect(p2['receipt'], isNotNull);

      final dash = await get('/finance/dashboard');
      final today = dash['today']! as Map;
      expect(today['collected'], 94400);
      expect(today['refunded'], 10000);
      expect(today['netCollected'], 84400);
      expect((dash['outstanding']! as Map)['total'], 0);
      expect(((dash['doctorWise']! as List).single as Map)['revenue'], 94400);
      // sum of the ledger of money movements matches the dashboard
      final payments = h
          .docsOf('payments')
          .fold<int>(0, (a, p) => a + (p['amount'] as int));
      final refunds = h
          .docsOf('refunds')
          .where((r) => r['status'] == 'completed')
          .fold<int>(0, (a, r) => a + (r['amount'] as int));
      expect(payments - refunds, today['netCollected']);
    });
  });
}
