import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/tenant_context.dart';
import '../scheduling/scheduling_support.dart';
import '../scheduling/time_support.dart';

const int reportScanCap = 5000;
const int maxReportDays = 366;

const List<String> reportKinds = [
  'appointments',
  'queues',
  'patients',
  'consultations',
  'laboratory',
  'billing',
];

/// One report: summary figures, a table (the same table is what exports
/// contain), the definitions behind the figures and the data-quality flags.
class ReportResult {
  ReportResult({
    required this.kind,
    required this.title,
    required this.columns,
    required this.rows,
    required this.summary,
    required this.definitions,
    required this.filters,
    required this.generatedAt,
    this.truncated = false,
    this.notes = const [],
  });

  final String kind;
  final String title;
  final List<String> columns;
  final List<Map<String, Object?>> rows;
  final Map<String, Object?> summary;
  final Map<String, String> definitions;
  final Map<String, Object?> filters;
  final String generatedAt;
  final bool truncated;
  final List<String> notes;

  Map<String, Object?> toJson() => {
    'report': kind,
    'title': title,
    'filters': filters,
    'generatedAt': generatedAt,
    'summary': summary,
    'columns': columns,
    'rows': rows,
    'definitions': definitions,
    'truncated': truncated,
    'notes': notes,
  };
}

class _Range {
  _Range(this.from, this.to, this.lo, this.hi, this.zone);
  final String from;
  final String to;
  final DateTime lo;
  final DateTime hi;
  final ClinicZone zone;
}

/// Operational reports computed from persisted records only.
///
/// Common rules (see docs/phase-10/REPORTING_DEFINITIONS.md):
///  * dates are clinic-local calendar dates in the clinic's time zone, inclusive
///    at both ends; timestamps are converted with the same zone;
///  * the caller's branch scope always applies, and a doctor sees only their own
///    appointments, queues and consultations;
///  * a section needs both `reports.view` and the permission of its own module;
///  * at most [reportScanCap] records are read; the report says `truncated`
///    when that cap was reached, and its figures are then incomplete;
///  * a rate whose denominator is zero is `null`, never 0% or 100%.
class ReportService {
  ReportService(this._d, this._sched);

  final ClinicDeps _d;
  final SchedulingSupport _sched;

  String _p(TenantContext t, String c) => 'tenants/${t.tenantId}/$c';

  // ------------------------------------------------------------- plumbing

  Future<_Range> _range(TenantContext t, Map<String, String> q) async {
    final doc = await _d.store.get(_p(t, 'clinic_settings/operations'));
    final zone = ClinicZone.resolve(doc?['timezone'] as String?);
    final today = zone.localDate(_d.now);
    final from = q['from'] ?? '${today.substring(0, 8)}01';
    final to = q['to'] ?? today;
    if (!Dates.valid(from) || !Dates.valid(to)) {
      throw const ApiException.badRequest('from and to must be YYYY-MM-DD.');
    }
    if (to.compareTo(from) < 0) {
      throw const ApiException.badRequest('to must not be before from.');
    }
    if (Dates.daysBetween(from, to) >= maxReportDays) {
      throw const ApiException.badRequest(
        'Choose a range shorter than $maxReportDays days.',
      );
    }
    return _Range(
      from,
      to,
      zone.toUtc(from, 0),
      zone.toUtc(Dates.addDays(to, 1), 0),
      zone,
    );
  }

  List<QueryFilter> _scope(TenantContext t, String? branchId) {
    if (branchId != null) {
      t.scope.require(branchId);
      return [QueryFilter('branchId', FilterOp.eq, branchId)];
    }
    if (t.scope.allBranches) return const [];
    if (t.scope.branchIds.length > 30) {
      throw const ApiException.forbidden(
        'Your branch access is too broad for this report; ask for all-branch access.',
      );
    }
    return [
      QueryFilter('branchId', FilterOp.inList, t.scope.branchIds.toList()),
    ];
  }

  /// The doctor filter: doctors are limited to themselves.
  Future<String?> _doctor(TenantContext t, Map<String, String> q) async {
    final asked = q['doctorId'];
    if (t.role == ClinicRole.doctor) {
      final own = await _sched.ownDoctorId(t);
      if (own == null) {
        throw const ApiException.forbidden(
          'Your login is not linked to a doctor profile.',
        );
      }
      if (asked != null && asked != own) {
        throw const ApiException.forbidden(
          'Doctors can see reports about their own work only.',
        );
      }
      return own;
    }
    return asked;
  }

  static double? _rate(num part, num whole) =>
      whole == 0 ? null : (part / whole * 10000).round() / 10000;

  static Map<String, int> _count(Iterable<DocData> rows, String field) {
    final m = <String, int>{};
    for (final r in rows) {
      final k = '${r[field]}';
      m[k] = (m[k] ?? 0) + 1;
    }
    return m;
  }

  static int _sum(Iterable<DocData> rows, String field) =>
      rows.fold(0, (a, r) => a + ((r[field] as int?) ?? 0));

  Future<List<StoredDoc>> _scan(DocQuery q) => _d.store.query(
    DocQuery(q.collection, filters: q.filters, limit: reportScanCap),
  );

  ReportResult _result(
    String kind,
    String title,
    _Range r,
    Map<String, Object?> filters,
    List<String> columns,
    List<Map<String, Object?>> rows,
    Map<String, Object?> summary,
    Map<String, String> defs, {
    bool truncated = false,
    List<String> notes = const [],
  }) => ReportResult(
    kind: kind,
    title: title,
    columns: columns,
    rows: rows,
    summary: summary,
    definitions: defs,
    filters: {'from': r.from, 'to': r.to, 'timezone': r.zone.name, ...filters},
    generatedAt: _d.now.toUtc().toIso8601String(),
    truncated: truncated,
    notes: [
      ...notes,
      if (truncated)
        'More than $reportScanCap records match; figures cover only the first $reportScanCap and are incomplete.',
    ],
  );

  // ------------------------------------------------------------------ run

  Future<ReportResult> run(
    TenantContext t,
    String kind,
    Map<String, String> q,
  ) async {
    t.require(ClinicPermission.reportsView);
    if (t.entitlements.features[FeatureKey.reports] != true) {
      throw const ApiException.forbidden(
        'Your subscription does not include reports.',
      );
    }
    switch (kind) {
      case 'appointments':
        t.require(ClinicPermission.appointmentsView);
        return _appointments(t, q);
      case 'queues':
        t.require(ClinicPermission.queueView);
        return _queues(t, q);
      case 'patients':
        t.require(ClinicPermission.patientsView);
        if (t.role == ClinicRole.doctor) {
          throw const ApiException.forbidden(
            'Patient registration reports are not available to doctors.',
          );
        }
        return _patients(t, q);
      case 'consultations':
        t.require(ClinicPermission.consultationsView);
        return _consultations(t, q);
      case 'laboratory':
        if (t.entitlements.features[FeatureKey.laboratory] != true) {
          throw const ApiException.forbidden(
            'Your subscription does not include the laboratory.',
          );
        }
        t.require(ClinicPermission.labDashboardView);
        return _laboratory(t, q);
      case 'billing':
        if (t.entitlements.features[FeatureKey.billing] != true) {
          throw const ApiException.forbidden(
            'Your subscription does not include billing.',
          );
        }
        t.require(ClinicPermission.financeReportsView);
        return _billing(t, q);
      default:
        throw const ApiException.notFound('Unknown report.');
    }
  }

  // ---------------------------------------------------------- appointments

  static const _apptCols = [
    'date',
    'total',
    'pending',
    'confirmed',
    'checked_in',
    'in_progress',
    'completed',
    'cancelled',
    'no_show',
    'rescheduled',
  ];

  Future<ReportResult> _appointments(
    TenantContext t,
    Map<String, String> q,
  ) async {
    final r = await _range(t, q);
    final doctor = await _doctor(t, q);
    final branch = q['branchId'];
    final rows = await _scan(
      DocQuery(
        _p(t, 'appointments'),
        filters: [
          ..._scope(t, branch),
          if (doctor != null) QueryFilter('doctorId', FilterOp.eq, doctor),
          QueryFilter('localDate', FilterOp.gte, r.from),
          QueryFilter('localDate', FilterOp.lte, r.to),
        ],
      ),
    );
    final docs = [for (final x in rows) x.data];
    final byDate = <String, Map<String, Object?>>{};
    for (final a in docs) {
      final d = '${a['localDate']}';
      final row = byDate.putIfAbsent(
        d,
        () => {'date': d, for (final c in _apptCols.skip(1)) c: 0},
      );
      final s = '${a['status']}';
      if (row.containsKey(s)) row[s] = (row[s]! as int) + 1;
      if (s != 'rescheduled') row['total'] = (row['total']! as int) + 1;
    }
    final list = byDate.values.toList()
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final live = docs.where((a) => a['status'] != 'rescheduled').toList();
    int c(String s) => live.where((a) => a['status'] == s).length;
    final completed = c('completed');
    final noShow = c('no_show');
    Map<String, Map<String, Object?>> group(String idField, String nameField) {
      final m = <String, Map<String, Object?>>{};
      for (final a in live) {
        final id = '${a[idField]}';
        final g = m.putIfAbsent(
          id,
          () => {
            'id': id,
            'name': a[nameField],
            'total': 0,
            'completed': 0,
            'cancelled': 0,
            'no_show': 0,
          },
        );
        g['total'] = (g['total']! as int) + 1;
        final s = '${a['status']}';
        if (g.containsKey(s)) g[s] = (g[s]! as int) + 1;
      }
      return m;
    }

    return _result(
      'appointments',
      'Appointments',
      r,
      {'branchId': ?branch, 'doctorId': ?doctor},
      _apptCols,
      list,
      {
        'total': live.length,
        'completed': completed,
        'cancelled': c('cancelled'),
        'noShow': noShow,
        'rescheduledAway': docs.length - live.length,
        'noShowRate': _rate(noShow, completed + noShow),
        'cancellationRate': _rate(c('cancelled'), live.length),
        'byDoctor': group('doctorId', 'doctorName').values.toList(),
        'bySource': _count(live.map((a) => a), 'source'),
      },
      {
        'total':
            'Appointments with a visit date in the range, excluding those moved to another slot (status rescheduled), so a moved visit counts once.',
        'rescheduledAway':
            'Slots that were given up because the visit was moved; the new slot is counted in its own date.',
        'noShowRate':
            'No-shows divided by (completed + no-shows). Empty when neither exists.',
        'cancellationRate':
            'Cancelled divided by total. Empty when there are no appointments.',
        'date': 'Clinic-local visit date.',
      },
      truncated: rows.length >= reportScanCap,
    );
  }

  // ---------------------------------------------------------------- queues

  Future<ReportResult> _queues(TenantContext t, Map<String, String> q) async {
    final r = await _range(t, q);
    final doctor = await _doctor(t, q);
    final branch = q['branchId'];
    final rows = await _scan(
      DocQuery(
        _p(t, 'queue_entries'),
        filters: [
          ..._scope(t, branch),
          if (doctor != null) QueryFilter('doctorId', FilterOp.eq, doctor),
          QueryFilter('queueDate', FilterOp.gte, r.from),
          QueryFilter('queueDate', FilterOp.lte, r.to),
        ],
      ),
    );
    final docs = [for (final x in rows) x.data];
    final byDate = <String, Map<String, Object?>>{};
    final waits = <double>[];
    final hours = <int, int>{};
    for (final e in docs) {
      final d = '${e['queueDate']}';
      final row = byDate.putIfAbsent(
        d,
        () => {
          'date': d,
          'tokens': 0,
          'completed': 0,
          'skipped': 0,
          'no_show': 0,
          'cancelled': 0,
        },
      );
      row['tokens'] = (row['tokens']! as int) + 1;
      final s = '${e['status']}';
      if (row.containsKey(s)) row[s] = (row[s]! as int) + 1;
      final inAt = (e['checkInAt'] ?? e['queuedAt']) as DateTime?;
      final calledAt = e['calledAt'] as DateTime?;
      if (inAt != null) {
        final h = r.zone.localMinutes(inAt) ~/ 60;
        hours[h] = (hours[h] ?? 0) + 1;
      }
      if (inAt != null && calledAt != null && !calledAt.isBefore(inAt)) {
        waits.add(calledAt.difference(inAt).inSeconds / 60);
      }
    }
    final list = byDate.values.toList()
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    waits.sort();
    final peak = hours.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return _result(
      'queues',
      'Queues',
      r,
      {'branchId': ?branch, 'doctorId': ?doctor},
      const ['date', 'tokens', 'completed', 'skipped', 'no_show', 'cancelled'],
      list,
      {
        'tokens': docs.length,
        'completed': docs.where((e) => e['status'] == 'completed').length,
        'skipped': docs.where((e) => e['status'] == 'skipped').length,
        'noShow': docs.where((e) => e['status'] == 'no_show').length,
        'waitMinutes': waits.isEmpty
            ? null
            : {
                'average':
                    (waits.reduce((a, b) => a + b) / waits.length * 10)
                        .round() /
                    10,
                'median': (waits[waits.length ~/ 2] * 10).round() / 10,
                'max': (waits.last * 10).round() / 10,
                'measured': waits.length,
                'of': docs.length,
              },
        'peakHours': [
          for (final e in peak.take(3))
            {
              'hour': '${e.key.toString().padLeft(2, '0')}:00',
              'checkIns': e.value,
            },
        ],
      },
      {
        'tokens': 'Queue tokens issued to visits dated in the range.',
        'waitMinutes':
            'Minutes from check-in to being called. Only tokens that have both timestamps are measured; "of" shows how many tokens that leaves out.',
        'peakHours': 'Clinic-local hours with the most check-ins.',
      },
      truncated: rows.length >= reportScanCap,
    );
  }

  // -------------------------------------------------------------- patients

  Future<ReportResult> _patients(TenantContext t, Map<String, String> q) async {
    final r = await _range(t, q);
    final branch = q['branchId'];
    final scope = _scope(t, branch);
    final created = await _scan(
      DocQuery(
        _p(t, 'patients'),
        filters: [
          ...scope,
          QueryFilter('createdAt', FilterOp.gte, r.lo),
          QueryFilter('createdAt', FilterOp.lt, r.hi),
        ],
      ),
    );
    final active = await _scan(
      DocQuery(
        _p(t, 'patients'),
        filters: [...scope, const QueryFilter('status', FilterOp.eq, 'active')],
      ),
    );
    final byDate = <String, int>{};
    final gender = <String, int>{};
    final bands = <String, int>{};
    for (final x in created) {
      final d = r.zone.localDate(x.data['createdAt']! as DateTime);
      byDate[d] = (byDate[d] ?? 0) + 1;
      final g = '${x.data['gender'] ?? 'not_recorded'}';
      gender[g] = (gender[g] ?? 0) + 1;
      final dob = x.data['dateOfBirth'];
      final age = dob == null ? null : _age('$dob', _d.now);
      final band = age == null
          ? 'not_recorded'
          : age < 13
          ? '0-12'
          : age < 18
          ? '13-17'
          : age < 40
          ? '18-39'
          : age < 65
          ? '40-64'
          : '65+';
      bands[band] = (bands[band] ?? 0) + 1;
    }
    // new versus returning among patients with a completed visit in the range
    final visits = await _scan(
      DocQuery(
        _p(t, 'appointments'),
        filters: [
          ...scope,
          const QueryFilter('status', FilterOp.eq, 'completed'),
          QueryFilter('localDate', FilterOp.gte, r.from),
          QueryFilter('localDate', FilterOp.lte, r.to),
        ],
      ),
    );
    final ids = {for (final v in visits) '${v.data['patientId']}'};
    var fresh = 0, returning = 0, unknown = 0;
    var looked = 0;
    for (final id in ids) {
      if (looked++ >= 300) {
        unknown++;
        continue;
      }
      final p = await _d.store.get(_p(t, 'patients/$id'));
      final at = p?['createdAt'] as DateTime?;
      if (at == null) {
        unknown++;
      } else if (!at.isBefore(r.lo)) {
        fresh++;
      } else {
        returning++;
      }
    }
    final list = [
      for (final e
          in byDate.entries.toList()..sort((a, b) => a.key.compareTo(b.key)))
        {'date': e.key, 'registrations': e.value},
    ];
    return _result(
      'patients',
      'Patients',
      r,
      {'branchId': ?branch},
      const ['date', 'registrations'],
      list,
      {
        'registrations': created.length,
        'activePatients': active.length,
        'visitingPatients': ids.length,
        'newPatients': fresh,
        'returningPatients': returning,
        'newPatientsUnknown': unknown,
        'byGender': gender,
        'byAgeBand': bands,
      },
      {
        'registrations': 'Patient records created in the range.',
        'activePatients':
            'Patient records with status active today (not limited to the range).',
        'newPatients':
            'Distinct patients with a completed visit in the range whose record was created in the range.',
        'returningPatients':
            'Distinct patients with a completed visit in the range whose record existed before the range.',
        'byAgeBand': 'Age today of patients registered in the range.',
      },
      truncated:
          created.length >= reportScanCap ||
          active.length >= reportScanCap ||
          visits.length >= reportScanCap,
    );
  }

  static int? _age(String dob, DateTime now) {
    final d = DateTime.tryParse(dob);
    if (d == null) return null;
    var a = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) a--;
    return a < 0 ? null : a;
  }

  // --------------------------------------------------------- consultations

  Future<ReportResult> _consultations(
    TenantContext t,
    Map<String, String> q,
  ) async {
    final r = await _range(t, q);
    final branch = q['branchId'];
    final doctor = await _doctor(t, q);
    if (doctor == null && !t.can(ClinicPermission.consultationsViewAll)) {
      throw const ApiException.forbidden(
        'You may see consultation reports about your own work only.',
      );
    }
    final rows = await _scan(
      DocQuery(
        _p(t, 'consultations'),
        filters: [
          ..._scope(t, branch),
          if (doctor != null) QueryFilter('doctorId', FilterOp.eq, doctor),
          QueryFilter('consultationAt', FilterOp.gte, r.lo),
          QueryFilter('consultationAt', FilterOp.lt, r.hi),
        ],
      ),
    );
    final docs = [for (final x in rows) x.data];
    final byDate = <String, Map<String, Object?>>{};
    for (final c in docs) {
      final d = r.zone.localDate(c['consultationAt']! as DateTime);
      final row = byDate.putIfAbsent(
        d,
        () => {
          'date': d,
          'total': 0,
          'draft': 0,
          'in_progress': 0,
          'finalized': 0,
          'amended': 0,
        },
      );
      row['total'] = (row['total']! as int) + 1;
      final s = '${c['status']}';
      if (row.containsKey(s)) row[s] = (row[s]! as int) + 1;
    }
    final list = byDate.values.toList()
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final byDoctor = <String, Map<String, Object?>>{};
    for (final c in docs) {
      final id = '${c['doctorId']}';
      final g = byDoctor.putIfAbsent(
        id,
        () => {'id': id, 'name': c['doctorName'], 'total': 0, 'finalized': 0},
      );
      g['total'] = (g['total']! as int) + 1;
      if (c['status'] == 'finalized' || c['status'] == 'amended') {
        g['finalized'] = (g['finalized']! as int) + 1;
      }
    }
    return _result(
      'consultations',
      'Consultations',
      r,
      {'branchId': ?branch, 'doctorId': ?doctor},
      const ['date', 'total', 'draft', 'in_progress', 'finalized', 'amended'],
      list,
      {
        'total': docs.length,
        'byStatus': _count(docs.map((c) => c), 'status'),
        'byDoctor': byDoctor.values.toList(),
      },
      {
        'total': 'Consultations started in the range (by clinic-local date).',
        'finalized':
            'Finalized and later amended consultations are both completed work.',
      },
      truncated: rows.length >= reportScanCap,
      notes: const ['Counts only: no clinical content is part of this report.'],
    );
  }

  // ------------------------------------------------------------ laboratory

  Future<ReportResult> _laboratory(
    TenantContext t,
    Map<String, String> q,
  ) async {
    final r = await _range(t, q);
    final branch = q['branchId'];
    final scope = _scope(t, branch);
    final orders = await _scan(
      DocQuery(
        _p(t, 'lab_orders'),
        filters: [
          ...scope,
          QueryFilter('createdAt', FilterOp.gte, r.lo),
          QueryFilter('createdAt', FilterOp.lt, r.hi),
        ],
      ),
    );
    final open = await _scan(
      DocQuery(
        _p(t, 'lab_orders'),
        filters: [
          ...scope,
          const QueryFilter('status', FilterOp.inList, [
            'requested',
            'accepted',
            'sample_pending',
            'recollection_required',
            'sample_collected',
            'processing',
            'result_entered',
            'verification_pending',
            'verified',
          ]),
        ],
      ),
    );
    final published = await _scan(
      DocQuery(
        _p(t, 'lab_orders'),
        filters: [
          ...scope,
          QueryFilter('publishedAt', FilterOp.gte, r.lo),
          QueryFilter('publishedAt', FilterOp.lt, r.hi),
        ],
      ),
    );
    final rejected = await _scan(
      DocQuery(
        _p(t, 'lab_samples'),
        filters: [
          ...scope,
          QueryFilter('rejectedAt', FilterOp.gte, r.lo),
          QueryFilter('rejectedAt', FilterOp.lt, r.hi),
        ],
      ),
    );
    final tat = <double>[];
    for (final o in published) {
      final c = o.data['createdAt'] as DateTime?;
      final p = o.data['publishedAt'] as DateTime?;
      if (c != null && p != null && !p.isBefore(c)) {
        tat.add(p.difference(c).inMinutes / 60);
      }
    }
    tat.sort();
    final byDate = <String, Map<String, Object?>>{};
    for (final o in orders) {
      final d = r.zone.localDate(o.data['createdAt']! as DateTime);
      final row = byDate.putIfAbsent(
        d,
        () => {'date': d, 'orders': 0, 'published': 0},
      );
      row['orders'] = (row['orders']! as int) + 1;
    }
    for (final o in published) {
      final d = r.zone.localDate(o.data['publishedAt']! as DateTime);
      final row = byDate.putIfAbsent(
        d,
        () => {'date': d, 'orders': 0, 'published': 0},
      );
      row['published'] = (row['published']! as int) + 1;
    }
    final list = byDate.values.toList()
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    return _result(
      'laboratory',
      'Laboratory',
      r,
      {'branchId': ?branch},
      const ['date', 'orders', 'published'],
      list,
      {
        'ordersCreated': orders.length,
        'byStatus': _count(orders.map((o) => o.data), 'status'),
        'byPriority': _count(orders.map((o) => o.data), 'priority'),
        'openOrdersNow': open.length,
        'reportsPublished': published.length,
        'rejectedSamples': rejected.length,
        'turnaroundHours': tat.isEmpty
            ? null
            : {
                'average':
                    (tat.reduce((a, b) => a + b) / tat.length * 10).round() /
                    10,
                'median': (tat[tat.length ~/ 2] * 10).round() / 10,
                'max': (tat.last * 10).round() / 10,
                'measured': tat.length,
              },
      },
      {
        'ordersCreated': 'Orders created in the range.',
        'openOrdersNow':
            'Orders not yet published, cancelled or rejected today (not limited to the range).',
        'reportsPublished':
            'Orders whose report was first published in the range.',
        'turnaroundHours':
            'Hours from order creation to publication, for orders published in the range. Amended republications are not counted again.',
        'rejectedSamples': 'Samples rejected in the range.',
      },
      truncated:
          orders.length >= reportScanCap ||
          open.length >= reportScanCap ||
          published.length >= reportScanCap,
    );
  }

  // --------------------------------------------------------------- billing

  Future<ReportResult> _billing(TenantContext t, Map<String, String> q) async {
    final r = await _range(t, q);
    final branch = q['branchId'];
    final scope = _scope(t, branch);
    final invoices = await _scan(
      DocQuery(
        _p(t, 'invoices'),
        filters: [
          ...scope,
          QueryFilter('invoiceDate', FilterOp.gte, r.from),
          QueryFilter('invoiceDate', FilterOp.lte, r.to),
        ],
      ),
    );
    final inv = [
      for (final i in invoices)
        if (i.data['status'] != 'draft' && i.data['status'] != 'cancelled')
          i.data,
    ];
    final payments = await _scan(
      DocQuery(
        _p(t, 'payments'),
        filters: [
          ...scope,
          QueryFilter('receivedAt', FilterOp.gte, r.lo),
          QueryFilter('receivedAt', FilterOp.lt, r.hi),
        ],
      ),
    );
    final refunds = await _scan(
      DocQuery(
        _p(t, 'refunds'),
        filters: [
          ...scope,
          const QueryFilter('status', FilterOp.eq, 'completed'),
          QueryFilter('completedAt', FilterOp.gte, r.lo),
          QueryFilter('completedAt', FilterOp.lt, r.hi),
        ],
      ),
    );
    int billed(DocData i) =>
        (i['adjustedTotal'] as int?) ?? (i['grandTotal'] as int?) ?? 0;
    final byDate = <String, Map<String, Object?>>{};
    Map<String, Object?> row(String d) => byDate.putIfAbsent(
      d,
      () => {'date': d, 'billed': 0, 'collected': 0, 'refunded': 0},
    );
    for (final i in inv) {
      final x = row('${i['invoiceDate']}');
      x['billed'] = (x['billed']! as int) + billed(i);
    }
    for (final p in payments) {
      final x = row(r.zone.localDate(p.data['receivedAt']! as DateTime));
      x['collected'] =
          (x['collected']! as int) + ((p.data['amount'] as int?) ?? 0);
    }
    for (final f in refunds) {
      final x = row(r.zone.localDate(f.data['completedAt']! as DateTime));
      x['refunded'] =
          (x['refunded']! as int) + ((f.data['amount'] as int?) ?? 0);
    }
    final list = byDate.values.toList()
      ..sort((a, b) => '${a['date']}'.compareTo('${b['date']}'));
    final collected = _sum(payments.map((p) => p.data), 'amount');
    final refunded = _sum(refunds.map((p) => p.data), 'amount');
    final byMethod = <String, int>{};
    for (final p in payments) {
      final m = '${p.data['method']}';
      byMethod[m] = (byMethod[m] ?? 0) + ((p.data['amount'] as int?) ?? 0);
    }
    return _result(
      'billing',
      'Billing',
      r,
      {'branchId': ?branch},
      const ['date', 'billed', 'collected', 'refunded'],
      list,
      {
        'currency': 'INR',
        'unit': 'minor (paise)',
        'invoices': inv.length,
        'grossBilled': inv.fold<int>(0, (a, i) => a + billed(i)),
        'collected': collected,
        'refunded': refunded,
        'netCollected': collected - refunded,
        'outstandingOnInvoicesInRange': _sum(inv, 'outstanding'),
        'byMethod': byMethod,
      },
      {
        'grossBilled':
            'Sum of the adjusted totals of invoices dated in the range, excluding drafts and cancelled invoices.',
        'collected':
            'Payments received in the range (by the date they were received), whichever invoice they pay.',
        'refunded': 'Completed refunds paid out in the range.',
        'netCollected':
            'Collected minus refunded. This is cash received, not profit.',
        'outstandingOnInvoicesInRange':
            'Amount still unpaid today on the invoices dated in the range.',
      },
      truncated:
          invoices.length >= reportScanCap ||
          payments.length >= reportScanCap ||
          refunds.length >= reportScanCap,
      notes: const [
        'Billed, collected, refunded and outstanding are different measures and are never added together. No profit or expense figure is part of this report.',
      ],
    );
  }

  // ------------------------------------------------------------- dashboard

  /// Headline figures for every section the caller may see. A section the
  /// caller may not see (or whose plan feature is missing) is reported as
  /// unavailable instead of failing the whole dashboard.
  Future<Map<String, Object?>> dashboard(
    TenantContext t,
    Map<String, String> q,
  ) async {
    t.require(ClinicPermission.reportsView);
    if (t.entitlements.features[FeatureKey.reports] != true) {
      throw const ApiException.forbidden(
        'Your subscription does not include reports.',
      );
    }
    final sections = <String, Object?>{};
    Map<String, Object?>? trend;
    String? from, to, tz;
    for (final kind in reportKinds) {
      try {
        final res = await run(t, kind, q);
        from = '${res.filters['from']}';
        to = '${res.filters['to']}';
        tz = '${res.filters['timezone']}';
        sections[kind] = {
          'available': true,
          'summary': {
            for (final e in res.summary.entries)
              if (e.value is num || e.value == null || e.value is String)
                e.key: e.value,
          },
          'truncated': res.truncated,
        };
        if (kind == 'appointments' && res.rows.length >= 2) {
          trend = {
            'metric': 'appointments per day',
            'points': [
              for (final x in res.rows)
                {'date': x['date'], 'value': x['total']},
            ],
          };
        }
      } on ApiException catch (e) {
        if (e.code == ApiErrorCode.forbidden) {
          sections[kind] = {'available': false, 'reason': 'not_permitted'};
        } else {
          rethrow;
        }
      }
    }
    return {
      'from': from,
      'to': to,
      'timezone': tz,
      'generatedAt': _d.now.toUtc().toIso8601String(),
      'sections': sections,
      'trend': trend,
      'note':
          'Figures are computed when you open the page from the clinic records. Rates are empty when there is nothing to divide by.',
    };
  }
}
