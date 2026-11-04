import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/audit/audit_service.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'scheduling_support.dart';
import 'time_support.dart';

const List<String> blockingExceptionTypes = [
  'doctor_leave',
  'personal_leave',
  'sick_leave',
  'clinic_holiday',
  'branch_closure',
  'emergency_unavailability',
];
const List<String> openingExceptionTypes = [
  'special_working_day',
  'schedule_modification',
];
const List<String> branchLevelTypes = [
  'clinic_holiday',
  'branch_closure',
  'emergency_unavailability',
];

/// What a doctor can do on one date at one branch, after recurring hours and
/// exceptions are applied (precedence: blocks > special day / modification >
/// weekly schedule).
class DayPlan {
  DayPlan({
    required this.date,
    required this.sessions,
    required this.breaks,
    required this.blocks,
    required this.closed,
    required this.capacity,
    required this.defaultDuration,
    required this.defaultBuffer,
    required this.typeDurations,
    this.reason,
    this.scheduleId,
  });

  final String date;
  final List<Span> sessions;
  final List<Span> breaks;
  final List<Span> blocks;
  final bool closed;
  final int capacity;
  final int defaultDuration;
  final int defaultBuffer;
  final Map<String, int> typeDurations;
  final String? reason;
  final String? scheduleId;

  Map<String, Object?> toJson() => {
    'date': date,
    'closed': closed,
    'reason': reason,
    'sessions': sessions.map((s) => s.toJson()).toList(),
    'breaks': breaks.map((s) => s.toJson()).toList(),
    'blocked': blocks.map((s) => s.toJson()).toList(),
    'capacity': capacity,
  };
}

/// Doctor schedules per branch and the exceptions that override them.
class AvailabilityService {
  AvailabilityService(this._s);

  final SchedulingSupport _s;

  static const String schedules = 'doctor_availability';
  static const String exceptions = 'doctor_schedule_exceptions';

  // ---------------------------------------------------------------- parsing

  /// Sessions and breaks of one day. Sessions must not overlap, breaks must not
  /// overlap and must lie inside a session.
  ({List<Map<String, Object?>> sessions, List<Map<String, Object?>> breaks})?
  parseDay(BodyReader r, Object? raw, String field) {
    if (raw is! Map) {
      r.addIssue(field, 'invalid_type', 'Must be an object.');
      return null;
    }
    for (final k in raw.keys) {
      if (k != 'sessions' && k != 'breaks') {
        r.addIssue('$field.$k', 'not_allowed', 'This field is not accepted.');
      }
    }
    List<Span>? spans(String key, int max) {
      final v = raw[key] ?? const <Object?>[];
      if (v is! List || v.length > max) {
        r.addIssue('$field.$key', 'invalid_value', 'At most $max entries.');
        return null;
      }
      final out = <Span>[];
      for (var i = 0; i < v.length; i++) {
        final e = v[i];
        final a = e is Map ? Hm.parse(e['from']) : null;
        final b = e is Map ? Hm.parse(e['to']) : null;
        if (a == null || b == null) {
          r.addIssue(
            '$field.$key[$i]',
            'invalid_time',
            'Use times like 09:00.',
          );
          return null;
        }
        if (b <= a) {
          r.addIssue(
            '$field.$key[$i]',
            'invalid_period',
            'The end must be after the start.',
          );
          return null;
        }
        out.add(Span(a, b));
      }
      out.sort((x, y) => x.from.compareTo(y.from));
      for (var i = 1; i < out.length; i++) {
        if (out[i].from < out[i - 1].to) {
          r.addIssue('$field.$key', 'overlap', '$key must not overlap.');
          return null;
        }
      }
      return out;
    }

    final sessions = spans('sessions', 4);
    final breaks = spans('breaks', 6);
    if (sessions == null || breaks == null) return null;
    for (final b in breaks) {
      if (!sessions.any((s) => b.from >= s.from && b.to <= s.to)) {
        r.addIssue(
          '$field.breaks',
          'outside_hours',
          'A break must be inside a working session.',
        );
        return null;
      }
    }
    return (
      sessions: sessions.map((s) => s.toJson()).toList(),
      breaks: breaks.map((s) => s.toJson()).toList(),
    );
  }

  Map<String, Object?>? _weekly(BodyReader r, Object? raw) {
    if (raw is! Map) {
      r.addIssue(
        'weeklyHours',
        'invalid_type',
        'Must be an object keyed by weekday 1-7.',
      );
      return null;
    }
    final out = <String, Object?>{};
    var ok = true;
    for (final k in raw.keys) {
      final n = int.tryParse('$k');
      if (n == null || n < 1 || n > 7) {
        r.addIssue('weeklyHours.$k', 'invalid_value', 'Weekday must be 1-7.');
        ok = false;
      }
    }
    var working = false;
    for (var d = 1; d <= 7; d++) {
      final v = raw['$d'];
      if (v == null) {
        out['$d'] = {'sessions': <Object?>[], 'breaks': <Object?>[]};
        continue;
      }
      final day = parseDay(r, v, 'weeklyHours.$d');
      if (day == null) {
        ok = false;
      } else {
        if (day.sessions.isNotEmpty) working = true;
        out['$d'] = {'sessions': day.sessions, 'breaks': day.breaks};
      }
    }
    if (ok && !working) {
      r.addIssue(
        'weeklyHours',
        'no_working_days',
        'Add at least one working session.',
      );
      return null;
    }
    return ok ? out : null;
  }

  Map<String, Object?> _parseSchedule(
    Map<String, Object?> body, {
    required bool partial,
    required String today,
  }) {
    final r = BodyReader(body, partial: partial)
      ..rejectUnknown({
        'branchId',
        'weeklyHours',
        'defaultDurationMinutes',
        'bufferMinutes',
        'maxPerSlot',
        'typeDurations',
        'effectiveFrom',
        'effectiveTo',
        'status',
      });
    final branchId = r.str('branchId', max: 40, required: !partial);
    final weekly = r.has('weeklyHours') || !partial
        ? _weekly(r, r.body['weeklyHours'])
        : null;
    final duration = r.integer(
      'defaultDurationMinutes',
      min: 5,
      max: 240,
      required: false,
    );
    final buffer = r.integer(
      'bufferMinutes',
      min: 0,
      max: 120,
      required: false,
    );
    final cap = r.integer('maxPerSlot', min: 1, max: 10, required: false);
    Map<String, int>? typeDurations;
    if (r.has('typeDurations')) {
      final raw = r.body['typeDurations'];
      if (raw is! Map || raw.length > 30) {
        r.addIssue(
          'typeDurations',
          'invalid_value',
          'Provide up to 30 entries.',
        );
      } else {
        typeDurations = {};
        for (final e in raw.entries) {
          final v = e.value;
          if (v is! int || v < 5 || v > 240) {
            r.addIssue(
              'typeDurations.${e.key}',
              'out_of_range',
              'Minutes must be 5-240.',
            );
          } else {
            typeDurations['${e.key}'] = v;
          }
        }
      }
    }
    String? from;
    if (r.has('effectiveFrom')) {
      if (!Dates.valid(r.body['effectiveFrom'])) {
        r.addIssue('effectiveFrom', 'invalid_date', 'Use YYYY-MM-DD.');
      } else {
        from = r.body['effectiveFrom'] as String;
      }
    }
    String? to;
    if (r.body['effectiveTo'] != null) {
      if (!Dates.valid(r.body['effectiveTo'])) {
        r.addIssue('effectiveTo', 'invalid_date', 'Use YYYY-MM-DD.');
      } else {
        to = r.body['effectiveTo'] as String;
      }
    }
    if ((from ?? (partial ? null : today)) != null &&
        to != null &&
        to.compareTo(from ?? today) < 0) {
      r.addIssue(
        'effectiveTo',
        'invalid_period',
        'Must not be before the start.',
      );
    }
    final status = r.enumOf<String>(
      'status',
      const ['active', 'inactive'],
      (v) => v,
      required: false,
    );
    r.throwIfInvalid();
    return {
      'branchId': ?branchId,
      'weeklyHours': ?weekly,
      'defaultDurationMinutes': ?duration,
      'bufferMinutes': ?buffer,
      'maxPerSlot': ?cap,
      'typeDurations': ?typeDurations,
      'effectiveFrom': ?from,
      if (r.has('effectiveTo')) 'effectiveTo': to,
      'status': ?status,
    };
  }

  // -------------------------------------------------------------- schedules

  Future<DocData> _doctorFor(TenantContext t, String doctorId) async {
    final doc = await _s.doctor(t, doctorId);
    return doc;
  }

  Future<Paged> listSchedules(
    TenantContext t,
    String doctorId,
    Request req,
  ) async {
    t.require(ClinicPermission.availabilityView);
    await _doctorFor(t, doctorId);
    final page = await runPaged(
      _s.d.store,
      DocQuery(
        _s.d.path(t, schedules),
        filters: [QueryFilter('doctorId', FilterOp.eq, doctorId)],
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      req,
    );
    // scoped callers only see schedules of their branches
    return Paged(
      page.docs.where((d) => t.scope.allows('${d.data['branchId']}')).toList(),
      page.meta,
    );
  }

  Future<Map<String, Object?>> createSchedule(
    TenantContext t,
    String doctorId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    _s.requireFeature(t);
    await _s.requireManageDoctor(
      t,
      doctorId,
      all: ClinicPermission.availabilityManage,
      own: ClinicPermission.availabilityManageOwn,
    );
    await _doctorFor(t, doctorId);
    final probeBranch = body['branchId'];
    if (probeBranch is! String) {
      throw ApiException.validation([
        FieldIssue(
          field: 'branchId',
          code: 'required',
          message: 'branchId is required.',
        ),
      ]);
    }
    final branch = await _s.branch(t, probeBranch);
    final zone = await _s.zoneFor(t, branch);
    final today = zone.localDate(_s.d.now);
    final input = _parseSchedule(body, partial: false, today: today);
    final branchId = input['branchId']! as String;
    if (!await _s.isAssigned(t, doctorId, branchId)) {
      throw const ApiException.conflict(
        'The doctor is not assigned to this branch.',
      );
    }
    final from = (input['effectiveFrom'] as String?) ?? today;
    final to = input['effectiveTo'] as String?;
    final id = 'sch_${newId(length: 12)}';
    final now = _s.d.now;
    final doc = <String, Object?>{
      'scheduleId': id,
      'tenantId': t.tenantId,
      'doctorId': doctorId,
      'branchId': branchId,
      'weeklyHours': input['weeklyHours'],
      'defaultDurationMinutes': input['defaultDurationMinutes'] ?? 15,
      'bufferMinutes': input['bufferMinutes'] ?? 0,
      'maxPerSlot': input['maxPerSlot'] ?? 1,
      'typeDurations': input['typeDurations'] ?? <String, Object?>{},
      'timezone': zone.name,
      'effectiveFrom': from,
      'effectiveTo': to,
      'status': 'active',
      'version': 1,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': t.uid,
      'updatedBy': t.uid,
    };
    return _s.d.store.transaction((tx) async {
      await _requireNoOverlap(tx, t, doctorId, branchId, from, to, null);
      tx.write([
        CreateOp(_s.d.path(t, schedules, id), doc),
        _s.d.audit.op(
          AuditEntry(
            actor: _s.d.actorOf(t),
            action: 'availability.created',
            targetType: 'doctor_availability',
            targetId: id,
            tenantId: t.tenantId,
            requestId: requestId,
            after: {'doctorId': doctorId, 'branchId': branchId, 'from': from},
          ),
        ),
      ]);
      return _pres(doc);
    });
  }

  Future<void> _requireNoOverlap(
    TxContext tx,
    TenantContext t,
    String doctorId,
    String branchId,
    String from,
    String? to,
    String? exceptId,
  ) async {
    final rows = await tx.query(
      DocQuery(
        _s.d.path(t, schedules),
        filters: [
          QueryFilter('doctorId', FilterOp.eq, doctorId),
          QueryFilter('branchId', FilterOp.eq, branchId),
          const QueryFilter('status', FilterOp.eq, 'active'),
        ],
        limit: 200,
      ),
    );
    for (final row in rows) {
      if (row.id == exceptId) continue;
      final f = row.data['effectiveFrom'] as String;
      final e = row.data['effectiveTo'] as String?;
      final startsBeforeOtherEnds = e == null || from.compareTo(e) <= 0;
      final otherStartsBeforeEnds = to == null || f.compareTo(to) <= 0;
      if (startsBeforeOtherEnds && otherStartsBeforeEnds) {
        throw const ApiException.conflict(
          'An active schedule already covers these dates for this doctor and branch. End it first or change its dates.',
        );
      }
    }
  }

  Future<Map<String, Object?>> updateSchedule(
    TenantContext t,
    String doctorId,
    String scheduleId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    _s.requireFeature(t);
    await _s.requireManageDoctor(
      t,
      doctorId,
      all: ClinicPermission.availabilityManage,
      own: ClinicPermission.availabilityManageOwn,
    );
    if (body.containsKey('branchId')) {
      throw ApiException.validation([
        FieldIssue(
          field: 'branchId',
          code: 'immutable',
          message: 'The branch cannot be changed.',
        ),
      ]);
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final path = _s.d.path(t, schedules, scheduleId);
      final cur = await tx.get(path);
      if (cur == null ||
          cur['doctorId'] != doctorId ||
          !t.scope.allows('${cur['branchId']}')) {
        throw const ApiException.notFound('Schedule not found.');
      }
      final input = _parseSchedule(
        body,
        partial: true,
        today: '${cur['effectiveFrom']}',
      );
      if (input.isEmpty) {
        throw const ApiException.badRequest('No fields to update.');
      }
      final from =
          (input['effectiveFrom'] as String?) ??
          cur['effectiveFrom']! as String;
      final to = input.containsKey('effectiveTo')
          ? input['effectiveTo'] as String?
          : cur['effectiveTo'] as String?;
      if (to != null && to.compareTo(from) < 0) {
        throw ApiException.validation([
          FieldIssue(
            field: 'effectiveTo',
            code: 'invalid_period',
            message: 'Must not be before the start.',
          ),
        ]);
      }
      final status = (input['status'] as String?) ?? cur['status'];
      if (status == 'active') {
        await _requireNoOverlap(
          tx,
          t,
          doctorId,
          '${cur['branchId']}',
          from,
          to,
          scheduleId,
        );
      }
      final patch = {
        ...input,
        'updatedAt': now,
        'updatedBy': t.uid,
        'version': ((cur['version'] as int?) ?? 1) + 1,
      };
      tx.write([
        UpdateOp(path, patch),
        // the replaced version is kept
        CreateOp(_s.d.path(t, 'availability_revisions', newId()), {
          'scheduleId': scheduleId,
          'doctorId': doctorId,
          'branchId': cur['branchId'],
          'snapshot': cur,
          'supersededAt': now,
          'supersededBy': t.uid,
        }),
        _s.d.audit.op(
          AuditEntry(
            actor: _s.d.actorOf(t),
            action: 'availability.updated',
            targetType: 'doctor_availability',
            targetId: scheduleId,
            tenantId: t.tenantId,
            requestId: requestId,
            after: {'fields': input.keys.toList()},
          ),
        ),
      ]);
      return _pres({...cur, ...patch});
    });
  }

  /// "Delete" ends the schedule: it is kept as history.
  Future<Map<String, Object?>> deactivateSchedule(
    TenantContext t,
    String doctorId,
    String scheduleId, {
    String? requestId,
  }) => updateSchedule(t, doctorId, scheduleId, {
    'status': 'inactive',
  }, requestId: requestId);

  static Map<String, Object?> _pres(Map<String, Object?> d) =>
      jsonSafe(d)! as Map<String, Object?>;

  // -------------------------------------------------------------- day plans

  /// Recurring schedule of the doctor at the branch that covers [date].
  Future<DocData?> activeSchedule(
    TenantContext t,
    String doctorId,
    String branchId,
    String date,
  ) async {
    final rows = await _s.d.store.query(
      DocQuery(
        _s.d.path(t, schedules),
        filters: [
          QueryFilter('doctorId', FilterOp.eq, doctorId),
          QueryFilter('branchId', FilterOp.eq, branchId),
          const QueryFilter('status', FilterOp.eq, 'active'),
        ],
        limit: 200,
      ),
    );
    for (final r in rows) {
      final f = r.data['effectiveFrom'] as String;
      final e = r.data['effectiveTo'] as String?;
      if (f.compareTo(date) <= 0 && (e == null || e.compareTo(date) >= 0)) {
        return r.data;
      }
    }
    return null;
  }

  /// Active exceptions at the branch that cover [date] (doctor-specific and
  /// branch-wide).
  Future<List<DocData>> exceptionsOn(
    TenantContext t,
    String branchId,
    String doctorId,
    String date,
  ) async {
    final rows = await _s.d.store.query(
      DocQuery(
        _s.d.path(t, exceptions),
        filters: [
          QueryFilter('branchId', FilterOp.eq, branchId),
          QueryFilter('endDate', FilterOp.gte, date),
        ],
        limit: 500,
      ),
    );
    return [
      for (final r in rows)
        if (r.data['status'] == 'active' &&
            '${r.data['startDate']}'.compareTo(date) <= 0 &&
            (r.data['doctorId'] == null || r.data['doctorId'] == doctorId))
          r.data,
    ];
  }

  List<Span> _spans(Object? raw) => [
    for (final e in (raw as List? ?? const []))
      Span(Hm.parse((e as Map)['from'])!, Hm.parse(e['to'])!),
  ];

  Future<DayPlan> dayPlan(
    TenantContext t,
    String doctorId,
    String branchId,
    String date,
  ) async {
    final sched = await activeSchedule(t, doctorId, branchId, date);
    final exs = await exceptionsOn(t, branchId, doctorId, date);
    DayPlan closed(String reason, {DocData? s}) => DayPlan(
      date: date,
      sessions: const [],
      breaks: const [],
      blocks: const [],
      closed: true,
      reason: reason,
      capacity: (s?['maxPerSlot'] as int?) ?? 1,
      defaultDuration: (s?['defaultDurationMinutes'] as int?) ?? 15,
      defaultBuffer: (s?['bufferMinutes'] as int?) ?? 0,
      typeDurations: const {},
      scheduleId: s?['scheduleId'] as String?,
    );
    if (sched == null) return closed('No schedule for this date.');
    final typeDurations = {
      for (final e in ((sched['typeDurations'] as Map?) ?? const {}).entries)
        '${e.key}': e.value as int,
    };
    final blocks = <Span>[];
    for (final e in exs) {
      if (!blockingExceptionTypes.contains(e['type'])) continue;
      if (e['fullDay'] == true) {
        return closed('${Fmt.label(e['type'])}: ${e['reason']}', s: sched);
      }
      final a = Hm.parse(e['fromTime']);
      final b = Hm.parse(e['toTime']);
      if (a != null && b != null) blocks.add(Span(a, b));
    }
    var sessions = <Span>[];
    var breaks = <Span>[];
    DocData? special;
    for (final e in exs) {
      if (openingExceptionTypes.contains(e['type']) && e['doctorId'] != null) {
        if (special == null ||
            '${e['createdAt']}'.compareTo('${special['createdAt']}') > 0) {
          special = e;
        }
      }
    }
    if (special != null) {
      sessions = _spans(special['sessions']);
      breaks = _spans(special['breaks']);
    } else {
      final day = (sched['weeklyHours'] as Map?)?['${Dates.weekday(date)}'];
      if (day is Map) {
        sessions = _spans(day['sessions']);
        breaks = _spans(day['breaks']);
      }
    }
    return DayPlan(
      date: date,
      sessions: sessions,
      breaks: breaks,
      blocks: blocks,
      closed: sessions.isEmpty,
      reason: sessions.isEmpty ? 'Not a working day.' : null,
      capacity: (sched['maxPerSlot'] as int?) ?? 1,
      defaultDuration: (sched['defaultDurationMinutes'] as int?) ?? 15,
      defaultBuffer: (sched['bufferMinutes'] as int?) ?? 0,
      typeDurations: typeDurations,
      scheduleId: sched['scheduleId'] as String?,
    );
  }

  // ------------------------------------------------------------- exceptions

  Map<String, Object?> _parseException(
    Map<String, Object?> body, {
    required String? doctorId,
    required bool partial,
  }) {
    final r = BodyReader(body, partial: partial)
      ..rejectUnknown({
        'branchId',
        'type',
        'startDate',
        'endDate',
        'fullDay',
        'fromTime',
        'toTime',
        'sessions',
        'breaks',
        'reason',
      });
    final branchId = r.str('branchId', max: 40, required: !partial);
    final allowed = doctorId == null
        ? branchLevelTypes
        : [
            ...blockingExceptionTypes.where(
              (e) =>
                  !branchLevelTypes.contains(e) ||
                  e == 'emergency_unavailability',
            ),
            ...openingExceptionTypes,
          ];
    final type = r.enumOf<String>(
      'type',
      allowed,
      (v) => v,
      required: !partial,
    );
    String? date(String f) {
      if (!r.has(f) && partial) return null;
      if (!Dates.valid(r.body[f])) {
        r.addIssue(f, 'invalid_date', 'Use YYYY-MM-DD.');
        return null;
      }
      return r.body[f] as String;
    }

    final start = date('startDate');
    final end = r.has('endDate') ? date('endDate') : start;
    if (start != null && end != null) {
      if (end.compareTo(start) < 0) {
        r.addIssue(
          'endDate',
          'invalid_period',
          'Must not be before the start.',
        );
      } else if (Dates.daysBetween(start, end) > 366) {
        r.addIssue('endDate', 'invalid_period', 'At most one year at a time.');
      }
    }
    final opening = type != null && openingExceptionTypes.contains(type);
    final fullDay = opening ? false : (r.boolean('fullDay') ?? true);
    int? a;
    int? b;
    if (!fullDay && !opening) {
      a = Hm.parse(r.body['fromTime']);
      b = Hm.parse(r.body['toTime']);
      if (a == null || b == null || b <= a) {
        r.addIssue(
          'fromTime',
          'invalid_time',
          'Give a from and to time (from before to).',
        );
      }
    }
    ({List<Map<String, Object?>> sessions, List<Map<String, Object?>> breaks})?
    day;
    if (opening) {
      day = parseDay(r, {
        'sessions': r.body['sessions'],
        'breaks': r.body['breaks'],
      }, 'sessions');
      if (day != null && day.sessions.isEmpty) {
        r.addIssue(
          'sessions',
          'required',
          'Give the working sessions for these days.',
        );
      }
    }
    final reason = r.str('reason', min: 3, max: 300, required: !partial);
    r.throwIfInvalid();
    return {
      'branchId': ?branchId,
      'type': ?type,
      'startDate': ?start,
      'endDate': ?end,
      if (type != null) 'fullDay': fullDay,
      if (a != null) 'fromTime': Hm.format(a),
      if (b != null) 'toTime': Hm.format(b),
      if (day != null) ...{'sessions': day.sessions, 'breaks': day.breaks},
      'reason': ?reason,
    };
  }

  Future<Paged> listExceptions(
    TenantContext t,
    Request req, {
    String? doctorId,
    String? branchId,
    String? from,
  }) async {
    t.require(ClinicPermission.availabilityView);
    if (doctorId != null) await _doctorFor(t, doctorId);
    if (branchId != null) t.scope.require(branchId);
    if (from != null && !Dates.valid(from)) {
      throw const ApiException.badRequest('from must be a date (YYYY-MM-DD).');
    }
    final page = await runPaged(
      _s.d.store,
      DocQuery(
        _s.d.path(t, exceptions),
        filters: [
          if (doctorId != null) QueryFilter('doctorId', FilterOp.eq, doctorId),
          if (branchId != null) QueryFilter('branchId', FilterOp.eq, branchId),
          if (from != null) QueryFilter('endDate', FilterOp.gte, from),
        ],
        orderBy: from != null
            ? const OrderBy('endDate')
            : const OrderBy('createdAt', descending: true),
      ),
      req,
    );
    return Paged(
      page.docs.where((d) => t.scope.allows('${d.data['branchId']}')).toList(),
      page.meta,
    );
  }

  /// Creates a leave, holiday or special day. Existing appointments inside a
  /// blocked period are **not** cancelled: they are flagged for attention and
  /// returned so staff can reschedule or cancel them explicitly.
  Future<Map<String, Object?>> createException(
    TenantContext t,
    Map<String, Object?> body, {
    String? doctorId,
    String? requestId,
  }) async {
    _s.requireFeature(t);
    if (doctorId == null) {
      t.require(ClinicPermission.availabilityManage);
    } else {
      await _s.requireManageDoctor(
        t,
        doctorId,
        all: ClinicPermission.availabilityManage,
        own: ClinicPermission.availabilityManageOwn,
      );
      await _doctorFor(t, doctorId);
    }
    final probe = body['branchId'];
    if (probe is! String) {
      throw ApiException.validation([
        FieldIssue(
          field: 'branchId',
          code: 'required',
          message: 'branchId is required.',
        ),
      ]);
    }
    await _s.branch(t, probe, mustBeActive: false);
    final input = _parseException(body, doctorId: doctorId, partial: false);
    final branchId = input['branchId']! as String;
    if (doctorId != null && !await _s.isAssigned(t, doctorId, branchId)) {
      throw const ApiException.conflict(
        'The doctor is not assigned to this branch.',
      );
    }
    final id = 'exc_${newId(length: 12)}';
    final now = _s.d.now;
    final selfDeclared = !t.can(ClinicPermission.availabilityManage);
    final doc = <String, Object?>{
      'exceptionId': id,
      'tenantId': t.tenantId,
      'doctorId': doctorId,
      ...input,
      'status': 'active',
      'approvedBy': selfDeclared ? null : t.uid,
      'approval': selfDeclared ? 'self_declared' : 'approved',
      'createdAt': now,
      'updatedAt': now,
      'createdBy': t.uid,
    };
    final blocking = blockingExceptionTypes.contains(input['type']);
    final affected = blocking ? await _affected(t, doc) : <StoredDoc>[];
    final ops = <WriteOp>[
      CreateOp(_s.d.path(t, exceptions, id), doc),
      for (final a in affected)
        UpdateOp(a.path, {
          'needsAttention': true,
          'attentionReason': 'schedule_exception:$id',
          'updatedAt': now,
        }),
      _s.d.audit.op(
        AuditEntry(
          actor: _s.d.actorOf(t),
          action: 'schedule_exception.created',
          targetType: 'schedule_exception',
          targetId: id,
          tenantId: t.tenantId,
          requestId: requestId,
          reason: input['reason'] as String?,
          after: {
            'type': input['type'],
            'branchId': branchId,
            'affectedAppointments': affected.length,
          },
        ),
      ),
    ];
    await _s.d.store.commit(ops);
    return {
      ..._pres(doc),
      'affectedAppointments': [for (final a in affected) _brief(a.data)],
    };
  }

  Map<String, Object?> _brief(DocData a) => {
    'appointmentId': a['appointmentId'],
    'reference': a['reference'],
    'localDate': a['localDate'],
    'startTime': a['startTime'],
    'endTime': a['endTime'],
    'doctorId': a['doctorId'],
    'patientName': a['patientName'],
    'status': a['status'],
  };

  /// Open appointments that fall inside a blocking exception.
  Future<List<StoredDoc>> _affected(TenantContext t, DocData ex) async {
    final rows = await _s.d.store.query(
      DocQuery(
        _s.d.path(t, 'appointments'),
        filters: [
          QueryFilter('branchId', FilterOp.eq, ex['branchId']),
          QueryFilter('localDate', FilterOp.gte, ex['startDate']),
          QueryFilter('localDate', FilterOp.lte, ex['endDate']),
        ],
        limit: 300,
      ),
    );
    const open = {'pending', 'confirmed', 'checked_in'};
    final a = Hm.parse(ex['fromTime']);
    final b = Hm.parse(ex['toTime']);
    return [
      for (final r in rows)
        if (open.contains(r.data['status']) &&
            (ex['doctorId'] == null || r.data['doctorId'] == ex['doctorId']) &&
            (ex['fullDay'] == true ||
                a == null ||
                b == null ||
                (Hm.parse(r.data['startTime'])! < b &&
                    Hm.parse(r.data['endTime'])! > a)))
          r,
    ];
  }

  /// Appointments a (proposed or existing) exception affects, for the warning
  /// shown before and after creating it.
  Future<List<Map<String, Object?>>> affectedBy(
    TenantContext t,
    String exceptionId,
  ) async {
    t.require(ClinicPermission.availabilityView);
    final ex = await _s.d.store.get(_s.d.path(t, exceptions, exceptionId));
    if (ex == null || !t.scope.allows('${ex['branchId']}')) {
      throw const ApiException.notFound('Exception not found.');
    }
    return [for (final a in await _affected(t, ex)) _brief(a.data)];
  }

  Future<Map<String, Object?>> cancelException(
    TenantContext t,
    String? doctorId,
    String exceptionId, {
    String? requestId,
  }) async {
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final path = _s.d.path(t, exceptions, exceptionId);
      final cur = await tx.get(path);
      if (cur == null ||
          cur['doctorId'] != doctorId ||
          !t.scope.allows('${cur['branchId']}')) {
        throw const ApiException.notFound('Exception not found.');
      }
      if (doctorId == null) {
        t.require(ClinicPermission.availabilityManage);
      } else {
        await _s.requireManageDoctor(
          t,
          doctorId,
          all: ClinicPermission.availabilityManage,
          own: ClinicPermission.availabilityManageOwn,
        );
      }
      if (cur['status'] != 'active') {
        throw const ApiException.conflict(
          'The exception is already cancelled.',
        );
      }
      final flagged = await tx.query(
        DocQuery(
          _s.d.path(t, 'appointments'),
          filters: [
            QueryFilter(
              'attentionReason',
              FilterOp.eq,
              'schedule_exception:$exceptionId',
            ),
          ],
          limit: 300,
        ),
      );
      tx.write([
        UpdateOp(path, {
          'status': 'cancelled',
          'cancelledAt': now,
          'cancelledBy': t.uid,
          'updatedAt': now,
        }),
        // appointments flagged only because of this exception are cleared
        for (final a in flagged)
          UpdateOp(a.path, {
            'needsAttention': false,
            'attentionReason': null,
            'updatedAt': now,
          }),
        _s.d.audit.op(
          AuditEntry(
            actor: _s.d.actorOf(t),
            action: 'schedule_exception.cancelled',
            targetType: 'schedule_exception',
            targetId: exceptionId,
            tenantId: t.tenantId,
            requestId: requestId,
          ),
        ),
      ]);
      return _pres({...cur, 'status': 'cancelled'});
    });
  }

  Future<Map<String, Object?>> updateException(
    TenantContext t,
    String? doctorId,
    String exceptionId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final cur = await _s.d.store.get(_s.d.path(t, exceptions, exceptionId));
    if (cur == null ||
        cur['doctorId'] != doctorId ||
        !t.scope.allows('${cur['branchId']}')) {
      throw const ApiException.notFound('Exception not found.');
    }
    if (doctorId == null) {
      t.require(ClinicPermission.availabilityManage);
    } else {
      await _s.requireManageDoctor(
        t,
        doctorId,
        all: ClinicPermission.availabilityManage,
        own: ClinicPermission.availabilityManageOwn,
      );
    }
    if (cur['status'] != 'active') {
      throw const ApiException.conflict(
        'A cancelled exception cannot be edited.',
      );
    }
    if (body.containsKey('branchId') || body.containsKey('type')) {
      throw ApiException.validation([
        FieldIssue(
          field: 'type',
          code: 'immutable',
          message:
              'The branch and type cannot be changed. Cancel it and create a new one.',
        ),
      ]);
    }
    final input =
        _parseException(
            {...body, 'type': cur['type'], 'branchId': cur['branchId']},
            doctorId: doctorId,
            partial: true,
          )
          ..remove('type')
          ..remove('branchId');
    if (input.isEmpty) {
      throw const ApiException.badRequest('No fields to update.');
    }
    final now = _s.d.now;
    final merged = {...cur, ...input};
    final affected = blockingExceptionTypes.contains(cur['type'])
        ? await _affected(t, merged)
        : <StoredDoc>[];
    await _s.d.store.commit([
      UpdateOp(_s.d.path(t, exceptions, exceptionId), {
        ...input,
        'updatedAt': now,
      }),
      for (final a in affected)
        UpdateOp(a.path, {
          'needsAttention': true,
          'attentionReason': 'schedule_exception:$exceptionId',
          'updatedAt': now,
        }),
      _s.d.audit.op(
        AuditEntry(
          actor: _s.d.actorOf(t),
          action: 'schedule_exception.updated',
          targetType: 'schedule_exception',
          targetId: exceptionId,
          tenantId: t.tenantId,
          requestId: requestId,
          after: {
            'fields': input.keys.toList(),
            'affectedAppointments': affected.length,
          },
        ),
      ),
    ]);
    return {
      ..._pres(merged),
      'affectedAppointments': [for (final a in affected) _brief(a.data)],
    };
  }

  static Map<String, Object?> present(Map<String, Object?> d) => _pres(d);
}

/// Display helper kept local so the service has no UI dependency.
abstract final class Fmt {
  static String label(Object? v) {
    final s = '$v'.replaceAll('_', ' ');
    return s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  }
}
