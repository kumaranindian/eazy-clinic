import 'dart:convert';

import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../clinic/common/tenant_context.dart';
import '../scheduling/time_support.dart';
import 'billing_support.dart';
import 'expense_service.dart';
import 'invoice_service.dart';
import 'refund_service.dart';

/// Documents read per source before a report says it is truncated.
const int reportScanCap = 5000;

class _Range {
  _Range(this.from, this.to, this.lo, this.hi);
  final String from;
  final String to;
  final DateTime lo;
  final DateTime hi;
}

/// Financial dashboard and reports, aggregated on the backend.
///
/// Metric definitions (also in docs/phase-7/FINANCIAL_REPORTS.md):
/// - **Collected**: sum of completed payments received in the period.
/// - **Refunded**: sum of refunds completed in the period.
/// - **Net collected**: collected minus refunded. It is *not* profit.
/// - **Invoiced**: sum of the adjusted totals of invoices dated in the period
///   (finalized, not cancelled).
/// - **Outstanding**: money still owed on finalized invoices *now*.
/// - **Overdue**: outstanding on invoices past their due date.
/// - **Expenses**: approved and paid expenses dated in the period, shown
///   separately from collections; no profit is calculated.
/// - **Doctor revenue**: consultation lines of invoices dated in the period,
///   by the doctor on the line (billed, not collected).
class ReportService {
  ReportService(this._s);

  final BillingSupport _s;

  Future<_Range> _range(
    TenantContext t,
    Request req, {
    int maxDays = 366,
  }) async {
    final zone = await _s.zone(t);
    final today = zone.localDate(_s.d.now);
    final q = req.url.queryParameters;
    final from = q['from'] ?? '${today.substring(0, 8)}01';
    final to = q['to'] ?? today;
    if (!Dates.valid(from) || !Dates.valid(to)) {
      throw const ApiException.badRequest('from and to must be YYYY-MM-DD.');
    }
    if (to.compareTo(from) < 0) {
      throw const ApiException.badRequest('to must not be before from.');
    }
    if (Dates.daysBetween(from, to) >= maxDays) {
      throw ApiException.badRequest(
        'Choose a range shorter than $maxDays days.',
      );
    }
    return _Range(
      from,
      to,
      zone.toUtc(from, 0),
      zone.toUtc(Dates.addDays(to, 1), 0),
    );
  }

  String? _branchParam(TenantContext t, Request req) {
    final b = req.url.queryParameters['branchId'];
    if (b == null || b.isEmpty) return null;
    t.scope.require(b);
    return b;
  }

  Future<({List<DocData> rows, bool truncated})> _scan(
    String collection,
    List<QueryFilter> filters,
    TenantContext t, {
    OrderBy? orderBy,
  }) async {
    final rows = await _s.d.store.query(
      DocQuery(
        _s.path(t, collection),
        filters: filters,
        orderBy: orderBy,
        limit: reportScanCap,
      ),
    );
    return (
      rows: [for (final r in rows) r.data],
      truncated: rows.length >= reportScanCap,
    );
  }

  Future<({List<DocData> rows, bool truncated})> _payments(
    TenantContext t,
    _Range r,
    String? branchId, {
    String? method,
  }) => _scan('payments', [
    ..._s.scopeFilters(t, branchId),
    if (method != null) QueryFilter('method', FilterOp.eq, method),
    QueryFilter('receivedAt', FilterOp.gte, r.lo),
    QueryFilter('receivedAt', FilterOp.lt, r.hi),
  ], t);

  Future<({List<DocData> rows, bool truncated})> _refundsDone(
    TenantContext t,
    _Range r,
    String? branchId,
  ) => _scan('refunds', [
    ..._s.scopeFilters(t, branchId),
    QueryFilter('status', FilterOp.eq, 'completed'),
    QueryFilter('completedAt', FilterOp.gte, r.lo),
    QueryFilter('completedAt', FilterOp.lt, r.hi),
  ], t);

  Future<({List<DocData> rows, bool truncated})> _invoicesIn(
    TenantContext t,
    _Range r,
    String? branchId,
  ) async {
    final s = await _scan(InvoiceService.collection, [
      ..._s.scopeFilters(t, branchId),
      QueryFilter('invoiceDate', FilterOp.gte, r.from),
      QueryFilter('invoiceDate', FilterOp.lte, r.to),
    ], t);
    return (
      rows: [
        for (final d in s.rows)
          if (d['status'] != 'draft' && d['status'] != 'cancelled') d,
      ],
      truncated: s.truncated,
    );
  }

  int _sum(Iterable<DocData> rows, String field) =>
      rows.fold<int>(0, (a, d) => a + ((d[field] as int?) ?? 0));

  Map<String, int> _groupSum(Iterable<DocData> rows, String key, String field) {
    final m = <String, int>{};
    for (final d in rows) {
      final k = '${d[key]}';
      m[k] = (m[k] ?? 0) + ((d[field] as int?) ?? 0);
    }
    return m;
  }

  // ---------------------------------------------------------- dashboard

  Future<Map<String, Object?>> dashboard(TenantContext t, Request req) async {
    t.require(ClinicPermission.financeReportsView);
    final zone = await _s.zone(t);
    final now = _s.d.now;
    final today = zone.localDate(now);
    final monthStart = '${today.substring(0, 8)}01';
    final weekStart = Dates.addDays(today, -6);
    final branchId = _branchParam(t, req);
    final currency = await _s.currency(t);
    final month = _Range(
      monthStart,
      today,
      zone.toUtc(monthStart, 0),
      zone.toUtc(Dates.addDays(today, 1), 0),
    );
    // one scan covers today, the last 7 days and the month so far
    final lowest = weekStart.compareTo(monthStart) < 0 ? weekStart : monthStart;
    final wide = _Range(
      lowest,
      today,
      zone.toUtc(lowest, 0),
      zone.toUtc(Dates.addDays(today, 1), 0),
    );
    final pay = await _payments(t, wide, branchId);
    final rf = await _refundsDone(t, wide, branchId);
    final inv = await _invoicesIn(t, month, branchId);
    final exp = await _scan('expenses', [
      ..._s.scopeFilters(t, branchId),
      QueryFilter('expenseDate', FilterOp.gte, monthStart),
      QueryFilter('expenseDate', FilterOp.lte, today),
    ], t);
    final open = await _scan(InvoiceService.collection, [
      ..._s.scopeFilters(t, branchId),
      QueryFilter('status', FilterOp.inList, const [
        'finalized',
        'partially_paid',
      ]),
    ], t);

    int collected(String from) => _sum(
      pay.rows.where(
        (p) =>
            zone.localDate(p['receivedAt']! as DateTime).compareTo(from) >= 0,
      ),
      'amount',
    );
    int refunded(String from) => _sum(
      rf.rows.where(
        (p) =>
            zone.localDate(p['completedAt']! as DateTime).compareTo(from) >= 0,
      ),
      'amount',
    );
    final monthPay = pay.rows.where(
      (p) =>
          zone.localDate(p['receivedAt']! as DateTime).compareTo(monthStart) >=
          0,
    );
    final outstanding = _sum(open.rows, 'outstanding');
    final overdueRows = [
      for (final d in open.rows)
        if (InvoiceService.presentWith(d, today)['overdue'] == true) d,
    ];
    final spend = exp.rows.where(
      (e) => e['status'] == 'approved' || e['status'] == 'paid',
    );

    Map<String, Object?> period(String from) => {
      'from': from,
      'to': today,
      'collected': collected(from),
      'refunded': refunded(from),
      'netCollected': collected(from) - refunded(from),
    };
    return {
      'currency': currency,
      'asOf': today,
      'today': period(today),
      'last7Days': period(weekStart),
      'monthToDate': {
        ...period(monthStart),
        'invoiced': _sum(inv.rows, 'adjustedTotal'),
        'expensesApproved': _sum(spend, 'amount'),
        'expensesPaid': _sum(
          spend.where((e) => e['status'] == 'paid'),
          'amount',
        ),
      },
      'outstanding': {
        'total': outstanding,
        'invoices': open.rows.length,
        'overdueTotal': _sum(overdueRows, 'outstanding'),
        'overdueInvoices': overdueRows.length,
      },
      'paymentMethods': _groupSum(monthPay, 'method', 'amount'),
      'branchWise': _byBranch(monthPay, rf.rows, inv.rows, month, zone),
      'doctorWise': _doctorRevenue(inv.rows),
      'truncated':
          pay.truncated ||
          rf.truncated ||
          inv.truncated ||
          exp.truncated ||
          open.truncated,
      'definitions': definitions,
    };
  }

  static const Map<String, String> definitions = {
    'collected': 'Completed payments received in the period.',
    'refunded': 'Refunds completed in the period.',
    'netCollected': 'Collected minus refunded. Not profit.',
    'invoiced':
        'Adjusted totals of finalized, non-cancelled invoices dated in the period.',
    'outstanding': 'Money still owed on finalized invoices now.',
    'overdue': 'Outstanding on invoices past their due date.',
    'expenses':
        'Approved and paid expenses dated in the period; not subtracted from collections.',
    'doctorRevenue':
        'Consultation lines of invoices dated in the period, by doctor (billed, not collected).',
  };

  List<Map<String, Object?>> _byBranch(
    Iterable<DocData> pay,
    Iterable<DocData> rf,
    Iterable<DocData> inv,
    _Range r,
    ClinicZone zone,
  ) {
    final ids = <String>{
      for (final d in pay) '${d['branchId']}',
      for (final d in rf) '${d['branchId']}',
      for (final d in inv) '${d['branchId']}',
    };
    final names = <String, String>{
      for (final d in inv) '${d['branchId']}': '${d['branchName'] ?? ''}',
      for (final d in pay) '${d['branchId']}': '',
    };
    return [
      for (final b in ids.toList()..sort())
        {
          'branchId': b,
          'branchName': names[b],
          'invoiced': _sum(
            inv.where((d) => d['branchId'] == b),
            'adjustedTotal',
          ),
          'collected': _sum(pay.where((d) => d['branchId'] == b), 'amount'),
          'refunded': _sum(rf.where((d) => d['branchId'] == b), 'amount'),
          'netCollected':
              _sum(pay.where((d) => d['branchId'] == b), 'amount') -
              _sum(rf.where((d) => d['branchId'] == b), 'amount'),
        },
    ];
  }

  List<Map<String, Object?>> _doctorRevenue(Iterable<DocData> invoices) {
    final byDoctor = <String, Map<String, Object?>>{};
    for (final inv in invoices) {
      for (final l in (inv['lines'] as List? ?? const [])) {
        final line = (l as Map).cast<String, Object?>();
        if (line['category'] != 'consultation' &&
            line['category'] != 'follow_up_consultation') {
          continue;
        }
        final doc = '${line['doctorId'] ?? 'unassigned'}';
        final row = byDoctor.putIfAbsent(
          doc,
          () => {'doctorId': doc, 'consultations': 0, 'revenue': 0},
        );
        row['consultations'] =
            (row['consultations']! as int) + (line['quantity'] as int);
        row['revenue'] = (row['revenue']! as int) + (line['total'] as int);
      }
    }
    return byDoctor.values.toList()
      ..sort((a, b) => (b['revenue']! as int).compareTo(a['revenue']! as int));
  }

  // ------------------------------------------------------------ reports

  Future<Map<String, Object?>> collections(TenantContext t, Request req) async {
    t.require(ClinicPermission.financeReportsView);
    final r = await _range(t, req);
    final zone = await _s.zone(t);
    final branchId = _branchParam(t, req);
    final method = req.url.queryParameters['method'];
    final monthly = req.url.queryParameters['groupBy'] == 'month';
    final pay = await _payments(t, r, branchId, method: method);
    final rf = method == null
        ? await _refundsDone(t, r, branchId)
        : (rows: const <DocData>[], truncated: false);
    String key(DateTime d) {
      final l = zone.localDate(d);
      return monthly ? l.substring(0, 7) : l;
    }

    final rows = <String, Map<String, Object?>>{};
    Map<String, Object?> row(String k) => rows.putIfAbsent(
      k,
      () => {
        'period': k,
        'payments': 0,
        'collected': 0,
        'refunded': 0,
        'netCollected': 0,
      },
    );
    for (final p in pay.rows) {
      final x = row(key(p['receivedAt']! as DateTime));
      x['payments'] = (x['payments']! as int) + 1;
      x['collected'] = (x['collected']! as int) + (p['amount']! as int);
    }
    for (final f in rf.rows) {
      final x = row(key(f['completedAt']! as DateTime));
      x['refunded'] = (x['refunded']! as int) + (f['amount']! as int);
    }
    for (final x in rows.values) {
      x['netCollected'] = (x['collected']! as int) - (x['refunded']! as int);
    }
    final list = rows.values.toList()
      ..sort((a, b) => '${a['period']}'.compareTo('${b['period']}'));
    return {
      'currency': await _s.currency(t),
      'from': r.from,
      'to': r.to,
      'rows': list,
      'totals': {
        'payments': pay.rows.length,
        'collected': _sum(pay.rows, 'amount'),
        'refunded': _sum(rf.rows, 'amount'),
        'netCollected': _sum(pay.rows, 'amount') - _sum(rf.rows, 'amount'),
      },
      'byMethod': _groupSum(pay.rows, 'method', 'amount'),
      'truncated': pay.truncated || rf.truncated,
    };
  }

  /// Tax summary: revenue, tax liability and collections side by side but
  /// never mixed. Rows are by period, branch, tax type and component.
  ///
  /// - **Taxable value**: net value of invoice lines the tax was charged on.
  /// - **Tax charged**: tax on invoices dated in the period.
  /// - **Tax credited / debited**: the tax part declared on credit / debit
  ///   notes created in the period.
  /// - **Net tax liability** = charged - credited + debited. It is a
  ///   *summary for review*, not a filing and not tax advice.
  /// - **Collected**: payments received (cash basis) - shown separately,
  ///   because tax becomes due on the invoice, not on payment.
  Future<Map<String, Object?>> tax(TenantContext t, Request req) async {
    t.require(ClinicPermission.financeReportsView);
    final r = await _range(t, req);
    final branchId = _branchParam(t, req);
    final monthly = req.url.queryParameters['groupBy'] == 'month';
    final inv = await _invoicesIn(t, r, branchId);
    final adj = await _scan('invoice_adjustments', [
      ..._s.scopeFilters(t, branchId),
      QueryFilter('createdAt', FilterOp.gte, r.lo),
      QueryFilter('createdAt', FilterOp.lt, r.hi),
    ], t);
    final pay = await _payments(t, r, branchId);
    final rows = <String, Map<String, Object?>>{};
    Map<String, Object?> row(
      String period,
      String branch,
      String type,
      String component,
    ) => rows.putIfAbsent(
      '$period|$branch|$type|$component',
      () => {
        'period': period,
        'branchId': branch,
        'taxType': type,
        'component': component,
        'taxableValue': 0,
        'taxCharged': 0,
        'taxCredited': 0,
        'taxDebited': 0,
        'netTaxLiability': 0,
      },
    );
    String per(String date) => monthly ? date.substring(0, 7) : date;
    var revenue = 0;
    for (final d in inv.rows) {
      for (final l in (d['lines'] as List? ?? const [])) {
        final line = (l as Map).cast<String, Object?>();
        final type = '${line['taxType'] ?? 'unspecified'}';
        final base = (line['taxableBase'] as int?) ?? 0;
        revenue += base;
        final parts = (line['taxParts'] as List? ?? const []);
        if (parts.isEmpty) {
          final x = row(
            per('${d['invoiceDate']}'),
            '${d['branchId']}',
            type,
            '-',
          );
          x['taxableValue'] = (x['taxableValue']! as int) + base;
          continue;
        }
        var first = true;
        for (final p in parts) {
          final part = (p as Map).cast<String, Object?>();
          final x = row(
            per('${d['invoiceDate']}'),
            '${d['branchId']}',
            type,
            '${part['name']}',
          );
          // the taxable value belongs to the line, so count it once
          if (first) x['taxableValue'] = (x['taxableValue']! as int) + base;
          first = false;
          x['taxCharged'] =
              (x['taxCharged']! as int) + (part['amount']! as int);
        }
      }
    }
    final zone = await _s.zone(t);
    for (final a in adj.rows) {
      final tx = (a['taxIncluded'] as int?) ?? 0;
      if (tx == 0) continue;
      final x = row(
        per(zone.localDate(a['createdAt']! as DateTime)),
        '${a['branchId']}',
        'adjustment',
        '${a['number']}'.startsWith('CN') ? 'credit notes' : 'debit notes',
      );
      final k = a['type'] == 'credit' ? 'taxCredited' : 'taxDebited';
      x[k] = (x[k]! as int) + tx;
    }
    for (final x in rows.values) {
      x['netTaxLiability'] =
          (x['taxCharged']! as int) -
          (x['taxCredited']! as int) +
          (x['taxDebited']! as int);
    }
    final list = rows.values.toList()
      ..sort(
        (
          a,
          b,
        ) => '${a['period']}${a['branchId']}${a['taxType']}${a['component']}'
            .compareTo(
              '${b['period']}${b['branchId']}${b['taxType']}${b['component']}',
            ),
      );
    int sum(String k) => list.fold(0, (a, x) => a + (x[k]! as int));
    return {
      'currency': await _s.currency(t),
      'from': r.from,
      'to': r.to,
      'disclaimer':
          'A summary of tax recorded on invoices for review. It is not a tax '
          'return, not tax advice, and not an accounting ledger.',
      'rows': list,
      'totals': {
        'revenue': revenue,
        'taxableValue': sum('taxableValue'),
        'taxCharged': sum('taxCharged'),
        'taxCredited': sum('taxCredited'),
        'taxDebited': sum('taxDebited'),
        'netTaxLiability': sum('netTaxLiability'),
        'collected': _sum(pay.rows, 'amount'),
      },
      'truncated': inv.truncated || adj.truncated || pay.truncated,
    };
  }

  Future<Map<String, Object?>> outstanding(TenantContext t, Request req) async {
    t.require(ClinicPermission.financeReportsView);
    final zone = await _s.zone(t);
    final today = zone.localDate(_s.d.now);
    final branchId = _branchParam(t, req);
    final open = await _scan(InvoiceService.collection, [
      ..._s.scopeFilters(t, branchId),
      QueryFilter('status', FilterOp.inList, const [
        'finalized',
        'partially_paid',
      ]),
    ], t);
    final age = {
      'current': 0,
      'days1to30': 0,
      'days31to60': 0,
      'days61to90': 0,
      'over90': 0,
    };
    final rows = <Map<String, Object?>>[];
    for (final d in open.rows) {
      final due = d['dueDate'] as String? ?? today;
      final late = Dates.daysBetween(due, today);
      final out = (d['outstanding'] as int?) ?? 0;
      final k = late <= 0
          ? 'current'
          : late <= 30
          ? 'days1to30'
          : late <= 60
          ? 'days31to60'
          : late <= 90
          ? 'days61to90'
          : 'over90';
      age[k] = age[k]! + out;
      rows.add({
        'invoiceId': d['invoiceId'],
        'invoiceNumber': d['invoiceNumber'],
        'patientId': d['patientId'],
        'patientName': d['patientName'],
        'patientMrn': d['patientMrn'],
        'branchId': d['branchId'],
        'invoiceDate': d['invoiceDate'],
        'dueDate': due,
        'daysOverdue': late < 0 ? 0 : late,
        'grandTotal': d['adjustedTotal'],
        'amountPaid': d['amountPaid'],
        'outstanding': out,
        'status': d['status'],
      });
    }
    rows.sort((a, b) => '${a['dueDate']}'.compareTo('${b['dueDate']}'));
    return {
      'currency': await _s.currency(t),
      'asOf': today,
      'rows': rows,
      'totals': {
        'invoices': rows.length,
        'outstanding': _sum(open.rows, 'outstanding'),
        'overdue': rows
            .where((r) => (r['daysOverdue']! as int) > 0)
            .fold<int>(0, (a, r) => a + (r['outstanding']! as int)),
      },
      'ageing': age,
      'truncated': open.truncated,
    };
  }

  Future<Map<String, Object?>> refunds(TenantContext t, Request req) async {
    t.require(ClinicPermission.financeReportsView);
    final r = await _range(t, req);
    final branchId = _branchParam(t, req);
    final status = req.url.queryParameters['status'];
    if (status != null && !refundStatuses.contains(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    final s = await _scan('refunds', [
      ..._s.scopeFilters(t, branchId),
      if (status != null) QueryFilter('status', FilterOp.eq, status),
      QueryFilter('requestedAt', FilterOp.gte, r.lo),
      QueryFilter('requestedAt', FilterOp.lt, r.hi),
    ], t);
    final byStatus = <String, int>{};
    for (final d in s.rows) {
      byStatus['${d['status']}'] =
          (byStatus['${d['status']}'] ?? 0) + (d['amount']! as int);
    }
    return {
      'currency': await _s.currency(t),
      'from': r.from,
      'to': r.to,
      'rows': [
        for (final d in s.rows)
          {
            'refundId': d['refundId'],
            'requestedAt': BillingSupport.present({'x': d['requestedAt']})['x'],
            'patientName': d['patientName'],
            'invoiceNumber': d['invoiceNumber'],
            'paymentReceipt': d['paymentReceipt'],
            'amount': d['amount'],
            'status': d['status'],
            'method': d['method'],
            'reason': d['reason'],
          },
      ],
      'byStatus': byStatus,
      'totals': {'refunds': s.rows.length, 'amount': _sum(s.rows, 'amount')},
      'truncated': s.truncated,
    };
  }

  Future<Map<String, Object?>> expenses(TenantContext t, Request req) async {
    t.require(ClinicPermission.expenseView);
    t.require(ClinicPermission.financeReportsView);
    final r = await _range(t, req);
    final branchId = _branchParam(t, req);
    final status = req.url.queryParameters['status'];
    if (status != null && !expenseStatuses.contains(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    final s = await _scan('expenses', [
      ..._s.scopeFilters(t, branchId),
      if (status != null) QueryFilter('status', FilterOp.eq, status),
      QueryFilter('expenseDate', FilterOp.gte, r.from),
      QueryFilter('expenseDate', FilterOp.lte, r.to),
    ], t);
    final counted = s.rows.where(
      (e) => e['status'] == 'approved' || e['status'] == 'paid',
    );
    final month = <String, int>{};
    for (final e in counted) {
      final k = '${e['expenseDate']}'.substring(0, 7);
      month[k] = (month[k] ?? 0) + (e['amount']! as int);
    }
    return {
      'currency': await _s.currency(t),
      'from': r.from,
      'to': r.to,
      'rows': [
        for (final e in s.rows)
          {
            'expenseId': e['expenseId'],
            'expenseDate': e['expenseDate'],
            'branchId': e['branchId'],
            'categoryName': e['categoryName'],
            'description': e['description'],
            'vendor': e['vendor'],
            'amount': e['amount'],
            'status': e['status'],
          },
      ],
      'byCategory': _groupSum(counted, 'categoryName', 'amount'),
      'byStatus': _groupSum(s.rows, 'status', 'amount'),
      'monthly': month,
      'totals': {
        'expenses': s.rows.length,
        'approvedAndPaid': _sum(counted, 'amount'),
        'paid': _sum(s.rows.where((e) => e['status'] == 'paid'), 'amount'),
      },
      'truncated': s.truncated,
    };
  }

  Future<Map<String, Object?>> branchWise(TenantContext t, Request req) async {
    t.require(ClinicPermission.financeReportsView);
    final r = await _range(t, req);
    final zone = await _s.zone(t);
    final pay = await _payments(t, r, null);
    final rf = await _refundsDone(t, r, null);
    final inv = await _invoicesIn(t, r, null);
    return {
      'currency': await _s.currency(t),
      'from': r.from,
      'to': r.to,
      'rows': _byBranch(pay.rows, rf.rows, inv.rows, r, zone),
      'truncated': pay.truncated || rf.truncated || inv.truncated,
    };
  }

  Future<Map<String, Object?>> doctorWise(TenantContext t, Request req) async {
    t.require(ClinicPermission.financeReportsView);
    final r = await _range(t, req);
    final branchId = _branchParam(t, req);
    final inv = await _invoicesIn(t, r, branchId);
    final rows = _doctorRevenue(inv.rows);
    for (final row in rows) {
      final id = '${row['doctorId']}';
      if (id != 'unassigned') {
        final d = await _s.d.store.get(_s.path(t, 'doctors', id));
        row['doctorName'] = d?['fullName'];
      }
    }
    return {
      'currency': await _s.currency(t),
      'from': r.from,
      'to': r.to,
      'rows': rows,
      'definition': definitions['doctorRevenue'],
      'truncated': inv.truncated,
    };
  }

  // ----------------------------------------------------------------- csv

  /// CSV of a report's `rows`. Cells that could be read as formulas are
  /// prefixed with a quote so spreadsheets do not execute them.
  Future<Response> csv(
    TenantContext t,
    String name,
    Map<String, Object?> report, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.financeReportsExport);
    final rows = ((report['rows'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, Object?>())
        .toList();
    final cols = <String>[];
    for (final r in rows) {
      for (final k in r.keys) {
        if (!cols.contains(k)) cols.add(k);
      }
    }
    String cell(Object? v) {
      var s = v == null ? '' : '$v';
      if (s.isNotEmpty && '=+-@\t\r'.contains(s[0])) s = "'$s";
      return '"${s.replaceAll('"', '""')}"';
    }

    final body = StringBuffer()..writeln(cols.map(cell).join(','));
    for (final r in rows) {
      body.writeln(cols.map((c) => cell(r[c])).join(','));
    }
    await _s.d.store.commit([
      _s.audit(
        t,
        action: 'report.exported',
        resourceType: 'report',
        resourceId: name,
        requestId: requestId,
        after: {'rows': rows.length},
      ),
    ]);
    return Response.ok(
      utf8.encode(body.toString()),
      headers: {
        'content-type': 'text/csv; charset=utf-8',
        'content-disposition': 'attachment; filename="$name.csv"',
        'cache-control': 'no-store',
      },
    );
  }
}
