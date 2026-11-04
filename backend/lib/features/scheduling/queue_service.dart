import 'dart:convert';

import 'package:common_models/common_models.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'scheduling_support.dart';
import 'time_support.dart';

/// Queue entry state machine.
///
/// ```
/// waiting ─call→ called ─start→ in_progress ─complete→ completed
///    │             │ └recall (stays called)
///    │             ├─skip→ skipped ─restore→ waiting
///    │             └─no-show→ no_show
///    └─skip→ skipped      skipped ─no-show→ no_show
/// waiting | called | skipped ─cancel→ cancelled
/// ```
/// `completed`, `cancelled` and `no_show` are final. (`checked_in` is an
/// appointment status: a checked-in patient is a `waiting` queue entry.)
const Map<String, Set<String>> queueTransitions = {
  'waiting': {'called', 'skipped', 'cancelled'},
  'called': {'in_progress', 'skipped', 'cancelled', 'no_show'},
  'skipped': {'waiting', 'cancelled', 'no_show'},
  'in_progress': {'completed'},
  'completed': {},
  'cancelled': {},
  'no_show': {},
};

class QueueService {
  QueueService(this._s);

  final SchedulingSupport _s;

  static const String queues = 'queues';
  static const String entries = 'queue_entries';

  /// Stable id of the queue for one branch, doctor and local date.
  static String queueId(String branchId, String doctorId, String date) =>
      'q_${sha256.convert(utf8.encode('$branchId|$doctorId|$date')).toString().substring(0, 24)}';

  String _display(String prefix, int n) =>
      '$prefix${n.toString().padLeft(3, '0')}';

  // ------------------------------------------------------------ token + add

  /// Creates a `waiting` entry with the next token for the appointment's queue,
  /// inside the caller's transaction. The counter lives on the queue document
  /// and every token also has a uniqueness key, so duplicates are impossible.
  Future<({List<WriteOp> ops, DocData entry})> addEntry(
    TxContext tx,
    TenantContext t,
    DocData appt, {
    String priority = 'normal',
    String? requestId,
  }) async {
    final branchId = '${appt['branchId']}';
    final doctorId = '${appt['doctorId']}';
    final date = '${appt['localDate']}';
    final qid = queueId(branchId, doctorId, date);
    final qPath = _s.d.path(t, queues, qid);
    final q = await tx.get(qPath);
    final settings = await _s.settings(t);
    final prefix = (settings['queueTokenPrefix'] as String?) ?? 'A';
    final n = ((q?['nextToken'] as int?) ?? 1);
    final now = _s.d.now;
    final id = 'qe_${newId(length: 12)}';
    final entry = <String, Object?>{
      'entryId': id,
      'queueId': qid,
      'tenantId': t.tenantId,
      'branchId': branchId,
      'doctorId': doctorId,
      'patientId': appt['patientId'],
      'patientName': appt['patientName'],
      'appointmentId': appt['appointmentId'],
      'appointmentReference': appt['reference'],
      'appointmentStartUtc': appt['startUtc'],
      'source': appt['source'],
      'queueDate': date,
      'tokenNumber': n,
      'displayToken': _display(prefix, n),
      'priority': priority,
      'status': 'waiting',
      'recallCount': 0,
      'checkInAt': now,
      'queuedAt': now,
      'calledAt': null,
      'startedAt': null,
      'completedAt': null,
      'checkedInBy': t.uid,
      'version': 1,
      'createdAt': now,
      'updatedAt': now,
    };
    final qDoc = {
      'queueId': qid,
      'tenantId': t.tenantId,
      'branchId': branchId,
      'doctorId': doctorId,
      'queueDate': date,
      'doctorName': appt['doctorName'],
      'nextToken': n + 1,
      'version': ((q?['version'] as int?) ?? 0) + 1,
      'lastEventAt': now,
      'updatedAt': now,
    };
    return (
      ops: <WriteOp>[
        if (q == null)
          CreateOp(qPath, {...qDoc, 'createdAt': now, 'prefix': prefix})
        else
          UpdateOp(qPath, qDoc),
        CreateOp(_s.d.path(t, 'queue_tokens', '${qid}_$n'), {
          'entryId': id,
          'createdAt': now,
        }),
        CreateOp(_s.d.path(t, entries, id), entry),
        _s.audit(
          t,
          action: 'queue.token_generated',
          resourceType: 'queue_entry',
          resourceId: id,
          branchId: branchId,
          appointmentId: '${appt['appointmentId']}',
          queueEntryId: id,
          requestId: requestId,
          after: {'token': entry['displayToken'], 'priority': priority},
        ),
      ],
      entry: entry,
    );
  }

  // ------------------------------------------------------------------ reads

  Future<DocData> _entry(TenantContext t, String id) async {
    final e = await _s.d.store.get(_s.d.path(t, entries, id));
    if (e == null || !t.scope.allows('${e['branchId']}')) {
      throw const ApiException.notFound('Queue entry not found.');
    }
    return e;
  }

  Future<DocData> queueDoc(TenantContext t, String qid) async {
    final q = await _s.d.store.get(_s.d.path(t, queues, qid));
    if (q == null || !t.scope.allows('${q['branchId']}')) {
      throw const ApiException.notFound('Queue not found.');
    }
    return q;
  }

  /// Entries ordered for display: in progress, called, waiting (by the clinic's
  /// ordering policy, priority first), skipped, then finished ones.
  Future<List<DocData>> orderedEntries(TenantContext t, String qid) async {
    final rows = await _s.d.store.query(
      DocQuery(
        _s.d.path(t, entries),
        filters: [QueryFilter('queueId', FilterOp.eq, qid)],
        limit: 500,
      ),
    );
    final byAppointmentTime =
        (await _s.settings(t))['queueOrdering'] == 'appointment_time';
    final all = rows.map((r) => r.data).toList();
    DateTime when(DocData e, String f) =>
        (e[f] as DateTime?) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    int group(DocData e) => switch (e['status']) {
      'in_progress' => 0,
      'called' => 1,
      'waiting' => 2,
      'skipped' => 3,
      _ => 4,
    };
    all.sort((a, b) {
      final g = group(a).compareTo(group(b));
      if (g != 0) return g;
      if (group(a) == 2) {
        final pa = a['priority'] == 'priority' ? 0 : 1;
        final pb = b['priority'] == 'priority' ? 0 : 1;
        if (pa != pb) return pa.compareTo(pb);
        if (byAppointmentTime) {
          final c = when(
            a,
            'appointmentStartUtc',
          ).compareTo(when(b, 'appointmentStartUtc'));
          if (c != 0) return c;
        }
        final c = when(a, 'queuedAt').compareTo(when(b, 'queuedAt'));
        return c != 0
            ? c
            : ((a['tokenNumber'] as int?) ?? 0).compareTo(
                (b['tokenNumber'] as int?) ?? 0,
              );
      }
      return when(a, 'updatedAt').compareTo(when(b, 'updatedAt'));
    });
    var pos = 0;
    return [
      for (final e in all)
        {...e, 'queuePosition': e['status'] == 'waiting' ? ++pos : null},
    ];
  }

  Map<String, Object?> presentEntry(DocData e) {
    final out = jsonSafe(e)! as Map<String, Object?>;
    // no clinical data lives here; keep only what the queue screens need
    return out;
  }

  Future<Map<String, Object?>> summary(TenantContext t, DocData q) async {
    final list = await orderedEntries(t, '${q['queueId']}');
    int count(String s) => list.where((e) => e['status'] == s).length;
    final appts = await _s.d.store.query(
      DocQuery(
        _s.d.path(t, 'appointments'),
        filters: [
          QueryFilter('branchId', FilterOp.eq, q['branchId']),
          QueryFilter('doctorId', FilterOp.eq, q['doctorId']),
          QueryFilter('localDate', FilterOp.eq, q['queueDate']),
        ],
        limit: 500,
      ),
    );
    int appt(String s) => appts.where((a) => a.data['status'] == s).length;
    DocData? first(bool Function(DocData) f) {
      for (final e in list) {
        if (f(e)) return e;
      }
      return null;
    }

    final current =
        first((e) => e['status'] == 'in_progress') ??
        first((e) => e['status'] == 'called');
    final next = first((e) => e['status'] == 'waiting');
    return {
      'queueId': q['queueId'],
      'branchId': q['branchId'],
      'doctorId': q['doctorId'],
      'doctorName': q['doctorName'],
      'queueDate': q['queueDate'],
      'version': q['version'],
      'lastEventAt': jsonSafe(q['lastEventAt']),
      'scheduledAppointments': appts
          .where(
            (a) =>
                a.data['status'] != 'rescheduled' &&
                a.data['status'] != 'cancelled',
          )
          .length,
      'checkedIn': list.length,
      'waiting': count('waiting'),
      'called': count('called'),
      'inConsultation': count('in_progress'),
      'completed': count('completed'),
      'skipped': count('skipped'),
      'cancelled': count('cancelled'),
      'noShow': appt('no_show'),
      'currentToken': current == null ? null : presentEntry(current),
      'nextToken': next == null ? null : presentEntry(next),
    };
  }

  Future<List<Map<String, Object?>>> listQueues(
    TenantContext t, {
    required String branchId,
    String? date,
    String? doctorId,
  }) async {
    t.require(ClinicPermission.queueView);
    final branch = await _s.branch(t, branchId, mustBeActive: false);
    final zone = await _s.zoneFor(t, branch);
    final d = date ?? zone.localDate(_s.d.now);
    if (!Dates.valid(d)) {
      throw const ApiException.badRequest('date must be YYYY-MM-DD.');
    }
    final rows = await _s.d.store.query(
      DocQuery(
        _s.d.path(t, queues),
        filters: [
          QueryFilter('branchId', FilterOp.eq, branchId),
          QueryFilter('queueDate', FilterOp.eq, d),
          if (doctorId != null) QueryFilter('doctorId', FilterOp.eq, doctorId),
        ],
        limit: 100,
      ),
    );
    return [for (final r in rows) await summary(t, r.data)];
  }

  /// The queue of one doctor today (or [date]); an empty summary when nothing
  /// has been checked in yet.
  Future<Map<String, Object?>> current(
    TenantContext t, {
    required String branchId,
    required String doctorId,
    String? date,
  }) async {
    t.require(ClinicPermission.queueView);
    final branch = await _s.branch(t, branchId, mustBeActive: false);
    final zone = await _s.zoneFor(t, branch);
    final d = date ?? zone.localDate(_s.d.now);
    if (!Dates.valid(d)) {
      throw const ApiException.badRequest('date must be YYYY-MM-DD.');
    }
    final doc = await _s.doctor(t, doctorId);
    final qid = queueId(branchId, doctorId, d);
    final q =
        await _s.d.store.get(_s.d.path(t, queues, qid)) ??
        {
          'queueId': qid,
          'branchId': branchId,
          'doctorId': doctorId,
          'doctorName': doc['fullName'],
          'queueDate': d,
          'version': 0,
        };
    return summary(t, q);
  }

  Future<Map<String, Object?>> detail(TenantContext t, String qid) async {
    t.require(ClinicPermission.queueView);
    return summary(t, await queueDoc(t, qid));
  }

  Future<List<Map<String, Object?>>> entriesOf(
    TenantContext t,
    String qid, {
    String? status,
  }) async {
    t.require(ClinicPermission.queueView);
    await queueDoc(t, qid);
    if (status != null && !queueTransitions.containsKey(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    return [
      for (final e in await orderedEntries(t, qid))
        if (status == null || e['status'] == status) presentEntry(e),
    ];
  }

  /// Audit trail of one queue (token and state events).
  Future<Paged> history(TenantContext t, String qid, Request req) async {
    t.require(ClinicPermission.queueView);
    await queueDoc(t, qid);
    final ids = (await orderedEntries(
      t,
      qid,
    )).map((e) => '${e['entryId']}').toSet();
    final page = await runPaged(
      _s.d.store,
      DocQuery(
        _s.d.path(t, 'appointment_audit_logs'),
        filters: [
          QueryFilter('resourceType', FilterOp.eq, 'queue_entry'),
          QueryFilter(
            'branchId',
            FilterOp.eq,
            (await queueDoc(t, qid))['branchId'],
          ),
        ],
        orderBy: const OrderBy('timestamp', descending: true),
      ),
      req,
    );
    return Paged(
      page.docs.where((d) => ids.contains(d.data['queueEntryId'])).toList(),
      page.meta,
    );
  }

  // ------------------------------------------------------------- transitions

  /// Doctors act only on their own queue; other roles on any queue in scope.
  Future<void> _requireOwnQueue(TenantContext t, DocData e) async {
    if (t.role == ClinicRole.doctor &&
        await _s.ownDoctorId(t) != e['doctorId']) {
      throw const ApiException.forbidden();
    }
  }

  Future<Map<String, Object?>> transition(
    TenantContext t,
    String entryId,
    String to, {
    required String action,
    required String permission,
    String? reason,
    bool reasonRequired = false,
    String? requestId,
  }) async {
    t.require(permission);
    _s.requireFeature(t);
    if (reasonRequired && (reason == null || reason.trim().length < 3)) {
      throw const ApiException.badRequest('A reason is required.');
    }
    await _requireOwnQueue(t, await _entry(t, entryId));
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final path = _s.d.path(t, entries, entryId);
      final cur = await tx.get(path);
      if (cur == null || !t.scope.allows('${cur['branchId']}')) {
        throw const ApiException.notFound('Queue entry not found.');
      }
      final from = '${cur['status']}';
      final recall = action == 'recall';
      if (recall
          ? from != 'called'
          : !(queueTransitions[from]?.contains(to) ?? false)) {
        throw ApiException.conflict('A $from entry cannot be $action.');
      }
      final apptPath = _s.d.path(t, 'appointments', '${cur['appointmentId']}');
      final appt = await tx.get(apptPath);
      final qPath = _s.d.path(t, queues, '${cur['queueId']}');
      final q = await tx.get(qPath);
      final ops = <WriteOp>[];
      final patch = <String, Object?>{
        if (!recall) 'status': to,
        'updatedAt': now,
        'version': ((cur['version'] as int?) ?? 1) + 1,
        'updatedBy': t.uid,
      };
      var apptPatch = <String, Object?>{};
      String? apptAction;
      switch (action) {
        case 'call':
        case 'recall':
          patch['calledAt'] = now;
          if (recall) {
            patch['recallCount'] = ((cur['recallCount'] as int?) ?? 0) + 1;
          }
        case 'skip':
          patch['skippedAt'] = now;
        case 'restore':
          patch['queuedAt'] = now; // back at the end of the waiting line
        case 'start':
          final busy = await tx.query(
            DocQuery(
              _s.d.path(t, entries),
              filters: [
                QueryFilter('queueId', FilterOp.eq, cur['queueId']),
                const QueryFilter('status', FilterOp.eq, 'in_progress'),
              ],
              limit: 2,
            ),
          );
          if (busy.isNotEmpty) {
            throw const ApiException.conflict(
              'Another patient is already in consultation. Complete it first.',
            );
          }
          if (appt == null || appt['status'] != 'checked_in') {
            throw const ApiException.conflict(
              'The appointment is not checked in.',
            );
          }
          patch['startedAt'] = now;
          apptPatch = {'status': 'in_progress', 'startedAt': now};
          apptAction = 'appointment.started';
        case 'complete':
          if (appt == null || appt['status'] != 'in_progress') {
            throw const ApiException.conflict(
              'The appointment is not in progress.',
            );
          }
          patch['completedAt'] = now;
          apptPatch = {'status': 'completed', 'completedAt': now};
          apptAction = 'appointment.completed';
        case 'cancel':
          patch['cancelReason'] = reason;
          if (appt != null && const {'checked_in'}.contains(appt['status'])) {
            // a checked-in patient who leaves cancels the visit
            if (!t.can(ClinicPermission.appointmentsCancelCheckedIn)) {
              throw const ApiException.forbidden();
            }
            apptPatch = {
              'status': 'cancelled',
              'cancelledAt': now,
              'cancelReason': reason,
              'cancelledBy': t.uid,
              'cancelSource': 'queue',
            };
            apptAction = 'appointment.cancelled';
            ops.addAll(await _releaseReservations(tx, t, appt));
          }
        case 'no-show':
          patch['noShowAt'] = now;
          if (appt != null && appt['status'] == 'checked_in') {
            apptPatch = {
              'status': 'no_show',
              'noShowAt': now,
              'noShowBy': t.uid,
            };
            apptAction = 'appointment.no_show';
            ops.addAll(await _releaseReservations(tx, t, appt));
          }
      }
      ops.addAll([
        UpdateOp(path, patch),
        if (q != null)
          UpdateOp(qPath, {
            'version': ((q['version'] as int?) ?? 0) + 1,
            'lastEventAt': now,
            'updatedAt': now,
          }),
        _s.audit(
          t,
          action: 'queue.$action',
          resourceType: 'queue_entry',
          resourceId: entryId,
          branchId: '${cur['branchId']}',
          appointmentId: '${cur['appointmentId']}',
          queueEntryId: entryId,
          reason: reason?.trim(),
          requestId: requestId,
          before: {'status': from},
          after: {'status': recall ? from : to, 'token': cur['displayToken']},
        ),
      ]);
      if (apptPatch.isNotEmpty && appt != null) {
        ops
          ..add(
            UpdateOp(apptPath, {
              ...apptPatch,
              'updatedAt': now,
              'updatedBy': t.uid,
              'version': ((appt['version'] as int?) ?? 1) + 1,
            }),
          )
          ..add(
            _s.audit(
              t,
              action: apptAction!,
              resourceType: 'appointment',
              resourceId: '${appt['appointmentId']}',
              branchId: '${appt['branchId']}',
              appointmentId: '${appt['appointmentId']}',
              queueEntryId: entryId,
              reason: reason?.trim(),
              requestId: requestId,
              before: {'status': appt['status']},
              after: {'status': apptPatch['status']},
            ),
          );
      }
      tx.write(ops);
      return presentEntry({...cur, ...patch});
    });
  }

  /// Delete operations that free the slot reservations of [appt].
  Future<List<WriteOp>> _releaseReservations(
    TxContext tx,
    TenantContext t,
    DocData appt,
  ) async {
    final rows = await tx.query(
      DocQuery(
        _s.d.path(t, 'appointment_slot_reservations'),
        filters: [
          QueryFilter('appointmentId', FilterOp.eq, appt['appointmentId']),
        ],
        limit: 200,
      ),
    );
    return [for (final r in rows) DeleteOp(r.path)];
  }

  /// Walks the waiting line: the first waiting entry is called.
  Future<Map<String, Object?>> callNext(
    TenantContext t,
    String qid, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.queueOperate);
    await queueDoc(t, qid);
    final waiting = [
      for (final e in await orderedEntries(t, qid))
        if (e['status'] == 'waiting') e,
    ];
    if (waiting.isEmpty) {
      throw const ApiException.conflict('Nobody is waiting.');
    }
    final active = await _s.d.store.query(
      DocQuery(
        _s.d.path(t, entries),
        filters: [
          QueryFilter('queueId', FilterOp.eq, qid),
          const QueryFilter('status', FilterOp.inList, [
            'called',
            'in_progress',
          ]),
        ],
        limit: 5,
      ),
    );
    if (active.any((e) => e.data['status'] == 'in_progress')) {
      throw const ApiException.conflict('A patient is in consultation.');
    }
    return transition(
      t,
      '${waiting.first['entryId']}',
      'called',
      action: 'call',
      permission: ClinicPermission.queueOperate,
      requestId: requestId,
    );
  }

  Future<Map<String, Object?>> setPriority(
    TenantContext t,
    String entryId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.queuePriority);
    final r = BodyReader(body)..rejectUnknown({'priority', 'reason'});
    final p = r.enumOf<String>('priority', const [
      'normal',
      'priority',
    ], (v) => v);
    final reason = r.str('reason', min: 3, max: 300);
    r.throwIfInvalid();
    await _entry(t, entryId);
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final path = _s.d.path(t, entries, entryId);
      final cur = await tx.get(path);
      if (cur == null) {
        throw const ApiException.notFound('Queue entry not found.');
      }
      if (cur['status'] != 'waiting') {
        throw const ApiException.conflict(
          'Only a waiting entry can change priority.',
        );
      }
      tx.write([
        UpdateOp(path, {
          'priority': p,
          'updatedAt': now,
          'version': ((cur['version'] as int?) ?? 1) + 1,
        }),
        _s.audit(
          t,
          action: 'queue.priority_changed',
          resourceType: 'queue_entry',
          resourceId: entryId,
          branchId: '${cur['branchId']}',
          appointmentId: '${cur['appointmentId']}',
          queueEntryId: entryId,
          reason: reason,
          requestId: requestId,
          before: {'priority': cur['priority']},
          after: {'priority': p},
        ),
      ]);
      return presentEntry({...cur, 'priority': p});
    });
  }
}
