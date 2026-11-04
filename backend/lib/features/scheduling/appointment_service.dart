import 'dart:convert';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../patients/patient_support.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import 'appointment_type_service.dart';
import 'queue_service.dart';
import 'scheduling_support.dart';
import 'slot_service.dart';
import 'time_support.dart';

const List<String> appointmentStatuses = [
  'pending',
  'confirmed',
  'checked_in',
  'in_progress',
  'completed',
  'cancelled',
  'rescheduled',
  'no_show',
];

/// Allowed appointment status changes. Nothing else is accepted, and no
/// endpoint takes a status from the client.
///
/// `checked_in → cancelled` needs `appointments.cancel_checked_in` and a
/// reason; `checked_in → no_show` happens only through the queue (a called
/// patient who does not respond).
const Map<String, Set<String>> appointmentTransitions = {
  'pending': {'confirmed', 'cancelled', 'rescheduled'},
  'confirmed': {'checked_in', 'cancelled', 'rescheduled', 'no_show'},
  'checked_in': {'in_progress', 'cancelled', 'no_show'},
  'in_progress': {'completed'},
  'completed': {},
  'cancelled': {},
  'rescheduled': {},
  'no_show': {},
};

const Set<String> openStatuses = {'pending', 'confirmed', 'checked_in'};

class AppointmentService {
  AppointmentService(
    this._s,
    this._slots,
    this._types,
    this._queue,
    this._patients,
  );

  final SchedulingSupport _s;
  final SlotService _slots;
  final AppointmentTypeService _types;
  final QueueService _queue;
  final PatientSupport _patients;

  static const String collection = 'appointments';

  // ------------------------------------------------------------------ utils

  String _sourceOf(TenantContext t) => t is PatientActingContext
      ? 'patient_app'
      : switch (t.role) {
          ClinicRole.clinicOwner || ClinicRole.clinicAdmin => 'clinic_admin',
          ClinicRole.doctor => 'doctor',
          _ => 'reception',
        };

  Object? _canon(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((e) => '$e').toList()..sort();
      return {for (final k in keys) k: _canon(v[k])};
    }
    if (v is List) return v.map(_canon).toList();
    return v;
  }

  String _hash(String s) => sha256.convert(utf8.encode(s)).toString();

  Future<DocData> load(TenantContext t, String id) async {
    final a = await _s.d.store.get(_s.d.path(t, collection, id));
    if (a == null || !t.scope.allows('${a['branchId']}')) {
      throw const ApiException.notFound('Appointment not found.');
    }
    return a;
  }

  String _reference(String date) {
    const a = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final id = newId(
      length: 4,
    ).toUpperCase().split('').map((c) => a.contains(c) ? c : 'X').join();
    return 'APT-${Dates.compact(date)}-$id';
  }

  Map<String, Object?> present(DocData a) {
    final out = jsonSafe(a)! as Map<String, Object?>;
    out.remove('lane');
    return out;
  }

  // ---------------------------------------------------------------- booking

  static const Set<String> _bookFields = {
    'patientId',
    'doctorId',
    'branchId',
    'typeId',
    'date',
    'startTime',
    'notes',
    'status',
  };

  Future<Map<String, Object?>> book(
    TenantContext t,
    Map<String, Object?> body, {
    required String? idempotencyKey,
    String? requestId,
  }) => _create(
    t,
    body,
    walkIn: false,
    idempotencyKey: idempotencyKey,
    requestId: requestId,
  );

  Future<Map<String, Object?>> walkIn(
    TenantContext t,
    Map<String, Object?> body, {
    required String? idempotencyKey,
    String? requestId,
  }) => _create(
    t,
    body,
    walkIn: true,
    idempotencyKey: idempotencyKey,
    requestId: requestId,
  );

  Future<Map<String, Object?>> _create(
    TenantContext t,
    Map<String, Object?> body, {
    required bool walkIn,
    required String? idempotencyKey,
    String? requestId,
  }) async {
    t.require(ClinicPermission.appointmentsBook);
    _s.requireFeature(t);
    if (idempotencyKey == null ||
        !RegExp(r'^[A-Za-z0-9_\-]{8,64}$').hasMatch(idempotencyKey)) {
      throw const ApiException.badRequest(
        'Send an Idempotency-Key header (8-64 letters, digits, - or _).',
      );
    }
    final allowed = walkIn
        ? {'patientId', 'doctorId', 'branchId', 'typeId', 'notes', 'priority'}
        : _bookFields;
    final r = BodyReader(body)..rejectUnknown(allowed);
    final patientId = r.str('patientId', max: 40);
    final doctorId = r.str('doctorId', max: 40);
    final branchId = r.str('branchId', max: 40);
    final typeId = r.str('typeId', max: 40);
    final notes = r.str('notes', max: 500, required: false);
    String? date;
    String? startTime;
    var pending = false;
    var priority = 'normal';
    if (walkIn) {
      priority =
          r.enumOf<String>(
            'priority',
            const ['normal', 'priority'],
            (v) => v,
            required: false,
          ) ??
          'normal';
      if (priority == 'priority' && !t.can(ClinicPermission.queuePriority)) {
        throw const ApiException.forbidden(
          'You are not allowed to give a patient priority.',
        );
      }
    } else {
      if (!Dates.valid(r.body['date'])) {
        r.addIssue('date', 'invalid_date', 'Use YYYY-MM-DD.');
      } else {
        date = r.body['date'] as String;
      }
      if (Hm.parse(r.body['startTime']) == null) {
        r.addIssue('startTime', 'invalid_time', 'Use a time like 09:30.');
      } else {
        startTime = r.body['startTime'] as String;
      }
      final st = r.enumOf<String>(
        'status',
        const ['pending', 'confirmed'],
        (v) => v,
        required: false,
      );
      pending = st == 'pending';
    }
    r.throwIfInvalid();

    final fingerprint = _hash(jsonEncode(_canon(body)));
    final keyPath = _s.d.path(
      t,
      'appointment_idempotency',
      _hash('${t.uid}:${walkIn ? 'w' : 'b'}:$idempotencyKey'),
    );
    final replay = await _replay(t, keyPath, fingerprint);
    if (replay != null) return replay;

    final patient = await _patients.load(t, patientId!);
    if (patient['status'] != 'active') {
      throw const ApiException.conflict('The patient record is not active.');
    }
    final branch = await _s.branch(t, branchId!);
    final doctor = await _s.assignedDoctor(t, doctorId!, branchId);
    final type = await _types.activeType(t, typeId!);

    try {
      return await _createLoop(
        t,
        walkIn: walkIn,
        patientId: patientId,
        branchId: branchId,
        doctorId: doctorId,
        typeId: typeId,
        branch: branch,
        patient: patient,
        doctor: doctor,
        type: type,
        date: date,
        startTime: startTime,
        pending: pending,
        priority: priority,
        notes: notes,
        keyPath: keyPath,
        fingerprint: fingerprint,
        requestId: requestId,
      );
    } on ApiException {
      // A concurrent request with the same key may have just won: answer with
      // its appointment instead of an error.
      final again = await _replay(t, keyPath, fingerprint);
      if (again != null) return again;
      rethrow;
    }
  }

  /// The appointment created by an earlier request with the same key.
  Future<Map<String, Object?>?> _replay(
    TenantContext t,
    String keyPath,
    String fingerprint,
  ) async {
    final prior = await _s.d.store.get(keyPath);
    if (prior == null) return null;
    if (prior['fingerprint'] != fingerprint) {
      throw const ApiException.conflict(
        'This Idempotency-Key was already used for a different request.',
      );
    }
    final existing = await _s.d.store.get(
      _s.d.path(t, collection, '${prior['appointmentId']}'),
    );
    return existing == null
        ? null
        : {...present(existing), 'idempotentReplay': true};
  }

  Future<Map<String, Object?>> _createLoop(
    TenantContext t, {
    required bool walkIn,
    required String patientId,
    required String branchId,
    required String doctorId,
    required String typeId,
    required DocData branch,
    required DocData patient,
    required DocData doctor,
    required DocData type,
    required String? date,
    required String? startTime,
    required bool pending,
    required String priority,
    required String? notes,
    required String keyPath,
    required String fingerprint,
    String? requestId,
  }) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final zone = await _s.zoneFor(t, branch);
      final localDate = walkIn ? zone.localDate(_s.d.now) : date!;
      final comp = await _slots.compute(
        t,
        branch: branch,
        doctorId: doctorId,
        date: localDate,
        typeId: typeId,
        includeCurrent: walkIn,
      );
      Slot? slot;
      if (walkIn) {
        // nearest slot with room; never overbook
        for (final s in comp.slots) {
          if (s.free) {
            slot = s;
            break;
          }
        }
        if (slot == null) {
          throw const ApiException.conflict(
            'No capacity is left today for this doctor. Walk-ins cannot overbook.',
          );
        }
      } else {
        final want = Hm.parse(startTime)!;
        final candidate = comp.slots.where((s) => s.start == want).toList();
        if (candidate.isEmpty) {
          throw ApiException.validation([
            FieldIssue(
              field: 'startTime',
              code: 'not_available',
              message: comp.plan.closed
                  ? (comp.plan.reason ??
                        'The doctor is not available on this date.')
                  : 'The doctor does not offer an appointment at this time.',
            ),
          ]);
        }
        slot = candidate.single;
      }

      final id = 'apt_${newId(length: 14)}';
      final reference = _reference(localDate);
      final now = _s.d.now;
      final startUtc = zone.toUtc(localDate, slot.start);
      final endUtc = zone.toUtc(localDate, slot.end);
      final doc = <String, Object?>{
        'appointmentId': id,
        'reference': reference,
        'tenantId': t.tenantId,
        'branchId': branchId,
        'patientId': patientId,
        'patientName': patient['fullName'],
        'patientMrn': patient['mrn'],
        'doctorId': doctorId,
        'doctorName': doctor['fullName'],
        'typeId': typeId,
        'typeName': type['name'],
        'localDate': localDate,
        'startTime': Hm.format(slot.start),
        'endTime': Hm.format(slot.end),
        'startUtc': startUtc,
        'endUtc': endUtc,
        'timezone': zone.name,
        'durationMinutes': slot.duration,
        'bufferMinutes': slot.buffer,
        'source': walkIn ? 'walk_in' : _sourceOf(t),
        'status': walkIn ? 'checked_in' : (pending ? 'pending' : 'confirmed'),
        'notes': notes,
        'queueEntryId': null,
        'needsAttention': false,
        'attentionReason': null,
        'version': 1,
        'createdAt': now,
        'updatedAt': now,
        'createdBy': t.uid,
        'updatedBy': t.uid,
      };
      try {
        return await _s.d.store.transaction((tx) async {
          final curPatient = await _patients.loadIn(tx, t, patientId);
          if (curPatient['status'] != 'active') {
            throw const ApiException.conflict(
              'The patient record is not active.',
            );
          }
          // re-check inside the transaction: the earlier answer is not trusted
          final occ = await _slots.occupancy(t, doctorId, localDate, tx: tx);
          final lane = _slots.freeLane(
            occ,
            comp.plan.capacity,
            slot!.start,
            slot.reservedUntil,
          );
          if (lane == null) {
            throw const ApiException(
              ApiErrorCode.conflict,
              'That time was just taken. Choose another slot.',
              issues: [],
            );
          }
          await _requireNoPatientClash(
            tx,
            t,
            patientId,
            localDate,
            slot.start,
            slot.end,
          );
          final ops = <WriteOp>[
            CreateOp(_s.d.path(t, collection, id), {...doc, 'lane': lane}),
            CreateOp(_s.d.path(t, 'appointment_references', reference), {
              'appointmentId': id,
              'createdAt': now,
            }),
            CreateOp(keyPath, {
              'fingerprint': fingerprint,
              'appointmentId': id,
              'uid': t.uid,
              'createdAt': now,
            }),
            ..._reservationOps(
              t,
              doctorId,
              branchId,
              localDate,
              id,
              lane,
              slot.start,
              slot.reservedUntil,
            ),
            _s.audit(
              t,
              action: 'appointment.created',
              resourceType: 'appointment',
              resourceId: id,
              branchId: branchId,
              appointmentId: id,
              requestId: requestId,
              after: {
                'status': doc['status'],
                'source': doc['source'],
                'date': localDate,
                'startTime': doc['startTime'],
              },
            ),
          ];
          var result = doc;
          if (walkIn) {
            final q = await _queue.addEntry(
              tx,
              t,
              doc,
              priority: priority,
              requestId: requestId,
            );
            ops.addAll(q.ops);
            result = {
              ...doc,
              'queueEntryId': q.entry['entryId'],
              'tokenDisplay': q.entry['displayToken'],
            };
            ops
              ..removeAt(0)
              ..insert(
                0,
                CreateOp(_s.d.path(t, collection, id), {
                  ...result,
                  'lane': lane,
                  'checkedInAt': now,
                  'checkedInBy': t.uid,
                }),
              )
              ..add(
                _s.audit(
                  t,
                  action: 'appointment.checked_in',
                  resourceType: 'appointment',
                  resourceId: id,
                  branchId: branchId,
                  appointmentId: id,
                  requestId: requestId,
                  after: {'status': 'checked_in', 'walkIn': true},
                ),
              );
          }
          tx.write(ops);
          return present(result);
        });
      } on AlreadyExistsException {
        // another request took the same reservation or reference: look again
        continue;
      }
    }
    throw const ApiException.conflict(
      'That time was just taken. Choose another slot.',
    );
  }

  Future<void> _requireNoPatientClash(
    TxContext tx,
    TenantContext t,
    String patientId,
    String date,
    int start,
    int end, {
    String? exceptId,
  }) async {
    final rows = await tx.query(
      DocQuery(
        _s.d.path(t, collection),
        filters: [
          QueryFilter('patientId', FilterOp.eq, patientId),
          QueryFilter('localDate', FilterOp.eq, date),
        ],
        limit: 50,
      ),
    );
    for (final r in rows) {
      if (r.id == exceptId || !openStatuses.contains(r.data['status'])) {
        continue;
      }
      final a = Hm.parse(r.data['startTime'])!;
      final b = Hm.parse(r.data['endTime'])!;
      if (a < end && b > start) {
        throw const ApiException.conflict(
          'The patient already has an appointment at this time.',
        );
      }
    }
  }

  List<WriteOp> _reservationOps(
    TenantContext t,
    String doctorId,
    String branchId,
    String date,
    String appointmentId,
    int lane,
    int from,
    int until,
  ) {
    final now = _s.d.now;
    return [
      for (var c = from ~/ cellMinutes; c <= (until - 1) ~/ cellMinutes; c++)
        CreateOp(
          _s.d.path(
            t,
            'appointment_slot_reservations',
            _slots.reservationId(doctorId, date, c, lane),
          ),
          {
            'doctorId': doctorId,
            'branchId': branchId,
            'localDate': date,
            'cell': c,
            'lane': lane,
            'appointmentId': appointmentId,
            'createdAt': now,
          },
        ),
    ];
  }

  Future<List<StoredDoc>> _reservationsOf(
    TxContext tx,
    TenantContext t,
    String appointmentId,
  ) => tx.query(
    DocQuery(
      _s.d.path(t, 'appointment_slot_reservations'),
      filters: [QueryFilter('appointmentId', FilterOp.eq, appointmentId)],
      limit: 200,
    ),
  );

  // ------------------------------------------------------------- lifecycle

  Future<Map<String, Object?>> _simpleTransition(
    TenantContext t,
    String id,
    String to, {
    required String permission,
    required String action,
    String? reason,
    String? requestId,
    Map<String, Object?> extra = const {},
    bool release = false,
    bool Function(DocData appt)? guard,
  }) async {
    t.require(permission);
    _s.requireFeature(t);
    await load(t, id);
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final path = _s.d.path(t, collection, id);
      final cur = await tx.get(path);
      if (cur == null || !t.scope.allows('${cur['branchId']}')) {
        throw const ApiException.notFound('Appointment not found.');
      }
      final from = '${cur['status']}';
      if (!(appointmentTransitions[from]?.contains(to) ?? false)) {
        throw ApiException.conflict('A $from appointment cannot become $to.');
      }
      if (guard != null && !guard(cur)) {
        throw const ApiException.conflict(
          'This action is not allowed for the appointment right now.',
        );
      }
      final ops = <WriteOp>[];
      if (release) {
        for (final r in await _reservationsOf(tx, t, id)) {
          ops.add(DeleteOp(r.path));
        }
      }
      // a linked queue entry follows the appointment
      final entryId = cur['queueEntryId'] as String?;
      if (entryId != null && to == 'cancelled') {
        final ePath = _s.d.path(t, QueueService.entries, entryId);
        final e = await tx.get(ePath);
        if (e != null &&
            e['status'] != 'completed' &&
            e['status'] != 'cancelled') {
          ops.add(
            UpdateOp(ePath, {
              'status': 'cancelled',
              'cancelReason': reason,
              'updatedAt': now,
              'version': ((e['version'] as int?) ?? 1) + 1,
            }),
          );
        }
      }
      final patch = {
        'status': to,
        ...extra,
        'updatedAt': now,
        'updatedBy': t.uid,
        'version': ((cur['version'] as int?) ?? 1) + 1,
        if (to == 'cancelled' || to == 'no_show') 'needsAttention': false,
        if (to == 'cancelled' || to == 'no_show') 'attentionReason': null,
      };
      ops
        ..add(UpdateOp(path, patch))
        ..add(
          _s.audit(
            t,
            action: action,
            resourceType: 'appointment',
            resourceId: id,
            branchId: '${cur['branchId']}',
            appointmentId: id,
            reason: reason,
            requestId: requestId,
            before: {'status': from},
            after: {'status': to},
          ),
        );
      tx.write(ops);
      return present({...cur, ...patch});
    });
  }

  Future<Map<String, Object?>> confirm(
    TenantContext t,
    String id, {
    String? requestId,
  }) => _simpleTransition(
    t,
    id,
    'confirmed',
    permission: ClinicPermission.appointmentsManage,
    action: 'appointment.confirmed',
    extra: {'confirmedAt': _s.d.now, 'confirmedBy': t.uid},
    requestId: requestId,
  );

  Future<Map<String, Object?>> cancel(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', min: 3, max: 300);
    r.throwIfInvalid();
    t.require(ClinicPermission.appointmentsManage);
    final cur = await load(t, id);
    if (cur['status'] == 'checked_in' &&
        !t.can(ClinicPermission.appointmentsCancelCheckedIn)) {
      throw const ApiException.forbidden(
        'You cannot cancel a patient who has checked in.',
      );
    }
    return _simpleTransition(
      t,
      id,
      'cancelled',
      permission: ClinicPermission.appointmentsManage,
      action: 'appointment.cancelled',
      reason: reason,
      release: true,
      extra: {
        'cancelledAt': _s.d.now,
        'cancelledBy': t.uid,
        'cancelReason': reason,
        'cancelSource': _sourceOf(t),
      },
      requestId: requestId,
    );
  }

  Future<Map<String, Object?>> markNoShow(
    TenantContext t,
    String id, {
    String? requestId,
  }) => _simpleTransition(
    t,
    id,
    'no_show',
    permission: ClinicPermission.appointmentsManage,
    action: 'appointment.no_show',
    release: true,
    guard: (a) => !(a['startUtc'] as DateTime).isAfter(_s.d.now),
    extra: {'noShowAt': _s.d.now, 'noShowBy': t.uid},
    requestId: requestId,
  );

  Future<Map<String, Object?>> updateNotes(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.appointmentsManage);
    final r = BodyReader(body)..rejectUnknown({'notes'});
    final notes = r.str('notes', max: 500);
    r.throwIfInvalid();
    await load(t, id);
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final path = _s.d.path(t, collection, id);
      final cur = await tx.get(path);
      if (cur == null) {
        throw const ApiException.notFound('Appointment not found.');
      }
      if (!openStatuses.contains(cur['status'])) {
        throw const ApiException.conflict(
          'This appointment can no longer be edited.',
        );
      }
      tx.write([
        UpdateOp(path, {
          'notes': notes,
          'updatedAt': now,
          'updatedBy': t.uid,
          'version': ((cur['version'] as int?) ?? 1) + 1,
        }),
        _s.audit(
          t,
          action: 'appointment.notes_updated',
          resourceType: 'appointment',
          resourceId: id,
          branchId: '${cur['branchId']}',
          appointmentId: id,
          requestId: requestId,
        ),
      ]);
      return present({...cur, 'notes': notes});
    });
  }

  Future<Map<String, Object?>> reschedule(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.appointmentsManage);
    _s.requireFeature(t);
    final r = BodyReader(body)
      ..rejectUnknown({'date', 'startTime', 'typeId', 'reason'});
    String? date;
    if (!Dates.valid(r.body['date'])) {
      r.addIssue('date', 'invalid_date', 'Use YYYY-MM-DD.');
    } else {
      date = r.body['date'] as String;
    }
    if (Hm.parse(r.body['startTime']) == null) {
      r.addIssue('startTime', 'invalid_time', 'Use a time like 09:30.');
    }
    final typeId = r.str('typeId', max: 40, required: false);
    final reason = r.str('reason', min: 3, max: 300);
    r.throwIfInvalid();
    final old = await load(t, id);
    if (old['status'] != 'pending' && old['status'] != 'confirmed') {
      throw ApiException.conflict(
        'A ${old['status']} appointment cannot be rescheduled.',
      );
    }
    final branch = await _s.branch(t, '${old['branchId']}');
    final doctorId = '${old['doctorId']}';
    await _s.assignedDoctor(t, doctorId, '${old['branchId']}');
    final newTypeId = typeId ?? '${old['typeId']}';
    final type = await _types.activeType(t, newTypeId);
    final want = Hm.parse(r.body['startTime'])!;

    for (var attempt = 0; attempt < 3; attempt++) {
      final comp = await _slots.compute(
        t,
        branch: branch,
        doctorId: doctorId,
        date: date!,
        typeId: newTypeId,
      );
      final cand = comp.slots.where((s) => s.start == want).toList();
      if (cand.isEmpty) {
        throw ApiException.validation([
          FieldIssue(
            field: 'startTime',
            code: 'not_available',
            message: 'The doctor does not offer an appointment at this time.',
          ),
        ]);
      }
      final slot = cand.single;
      final newId0 = 'apt_${newId(length: 14)}';
      final reference = _reference(date);
      final now = _s.d.now;
      final startUtc = comp.zone.toUtc(date, slot.start);
      final endUtc = comp.zone.toUtc(date, slot.end);
      try {
        return await _s.d.store.transaction((tx) async {
          final cur = await tx.get(_s.d.path(t, collection, id));
          if (cur == null ||
              (cur['status'] != 'pending' && cur['status'] != 'confirmed')) {
            throw const ApiException.conflict(
              'The appointment cannot be rescheduled.',
            );
          }
          final occ = await _slots.occupancy(t, doctorId, date!, tx: tx);
          final mine = await _reservationsOf(tx, t, id);
          // the appointment's own old cells do not block its new time
          for (final m in mine) {
            if (m.data['localDate'] == date) {
              occ[m.data['cell']! as int]?.remove(m.data['lane']);
            }
          }
          final lane = _slots.freeLane(
            occ,
            comp.plan.capacity,
            slot.start,
            slot.reservedUntil,
          );
          if (lane == null) {
            throw const ApiException.conflict(
              'That time was just taken. Choose another slot.',
            );
          }
          await _requireNoPatientClash(
            tx,
            t,
            '${cur['patientId']}',
            date,
            slot.start,
            slot.end,
            exceptId: id,
          );
          final doc = <String, Object?>{
            ...cur,
            'appointmentId': newId0,
            'reference': reference,
            'typeId': newTypeId,
            'typeName': type['name'],
            'localDate': date,
            'startTime': Hm.format(slot.start),
            'endTime': Hm.format(slot.end),
            'startUtc': startUtc,
            'endUtc': endUtc,
            'durationMinutes': slot.duration,
            'bufferMinutes': slot.buffer,
            'lane': lane,
            'rescheduledFromId': id,
            'needsAttention': false,
            'attentionReason': null,
            'version': 1,
            'createdAt': now,
            'updatedAt': now,
            'createdBy': t.uid,
            'updatedBy': t.uid,
          };
          tx.write([
            for (final m in mine) DeleteOp(m.path),
            CreateOp(_s.d.path(t, collection, newId0), doc),
            CreateOp(_s.d.path(t, 'appointment_references', reference), {
              'appointmentId': newId0,
              'createdAt': now,
            }),
            ..._reservationOps(
              t,
              doctorId,
              '${cur['branchId']}',
              date,
              newId0,
              lane,
              slot.start,
              slot.reservedUntil,
            ),
            UpdateOp(_s.d.path(t, collection, id), {
              'status': 'rescheduled',
              'rescheduledToId': newId0,
              'rescheduledAt': now,
              'rescheduledBy': t.uid,
              'rescheduleReason': reason,
              'needsAttention': false,
              'attentionReason': null,
              'updatedAt': now,
              'updatedBy': t.uid,
              'version': ((cur['version'] as int?) ?? 1) + 1,
            }),
            _s.audit(
              t,
              action: 'appointment.rescheduled',
              resourceType: 'appointment',
              resourceId: id,
              branchId: '${cur['branchId']}',
              appointmentId: id,
              reason: reason,
              requestId: requestId,
              before: {
                'status': cur['status'],
                'date': cur['localDate'],
                'startTime': cur['startTime'],
              },
              after: {
                'status': 'rescheduled',
                'newAppointmentId': newId0,
                'date': date,
                'startTime': Hm.format(slot.start),
              },
            ),
            _s.audit(
              t,
              action: 'appointment.created',
              resourceType: 'appointment',
              resourceId: newId0,
              branchId: '${cur['branchId']}',
              appointmentId: newId0,
              requestId: requestId,
              after: {'status': doc['status'], 'rescheduledFrom': id},
            ),
          ]);
          return present(doc);
        });
      } on AlreadyExistsException {
        continue;
      }
    }
    throw const ApiException.conflict(
      'That time was just taken. Choose another slot.',
    );
  }

  // ---------------------------------------------------------------- check-in

  Future<Map<String, Object?>> checkIn(
    TenantContext t,
    String id, {
    Map<String, Object?> body = const {},
    String? requestId,
  }) async {
    t.require(ClinicPermission.appointmentsCheckIn);
    _s.requireFeature(t);
    final r = BodyReader(body)..rejectUnknown({'priority'});
    final priority =
        r.enumOf<String>(
          'priority',
          const ['normal', 'priority'],
          (v) => v,
          required: false,
        ) ??
        'normal';
    r.throwIfInvalid();
    if (priority == 'priority' && !t.can(ClinicPermission.queuePriority)) {
      throw const ApiException.forbidden(
        'You are not allowed to give a patient priority.',
      );
    }
    final appt0 = await load(t, id);
    final branch = await _s.branch(
      t,
      '${appt0['branchId']}',
      mustBeActive: false,
    );
    final zone = await _s.zoneFor(t, branch);
    final settings = await _s.settings(t);
    final early = (settings['checkInEarlyMinutes'] as int?) ?? 120;
    final late = (settings['checkInLateMinutes'] as int?) ?? 60;
    final now = _s.d.now;
    return _retryOnContention(
      () => _s.d.store.transaction((tx) async {
        final path = _s.d.path(t, collection, id);
        final cur = await tx.get(path);
        if (cur == null || !t.scope.allows('${cur['branchId']}')) {
          throw const ApiException.notFound('Appointment not found.');
        }
        if (cur['status'] == 'checked_in' || cur['queueEntryId'] != null) {
          throw const ApiException.conflict(
            'The patient is already checked in.',
          );
        }
        if (cur['status'] != 'confirmed') {
          throw ApiException.conflict(
            'A ${cur['status']} appointment cannot be checked in.',
          );
        }
        if (zone.localDate(now) != cur['localDate']) {
          throw const ApiException.conflict(
            'Check-in is only possible on the day of the appointment.',
          );
        }
        final startUtc = cur['startUtc'] as DateTime;
        final endUtc = cur['endUtc'] as DateTime;
        if (now.isBefore(startUtc.subtract(Duration(minutes: early)))) {
          throw ApiException.conflict(
            'Too early to check in (allowed from $early minutes before the appointment).',
          );
        }
        if (now.isAfter(endUtc.add(Duration(minutes: late)))) {
          throw ApiException.conflict(
            'Too late to check in ($late minutes after the appointment ended).',
          );
        }
        final q = await _queue.addEntry(
          tx,
          t,
          cur,
          priority: priority,
          requestId: requestId,
        );
        final patch = {
          'status': 'checked_in',
          'checkedInAt': now,
          'checkedInBy': t.uid,
          'queueEntryId': q.entry['entryId'],
          'tokenDisplay': q.entry['displayToken'],
          'updatedAt': now,
          'updatedBy': t.uid,
          'version': ((cur['version'] as int?) ?? 1) + 1,
        };
        tx.write([
          UpdateOp(path, patch),
          ...q.ops,
          _s.audit(
            t,
            action: 'appointment.checked_in',
            resourceType: 'appointment',
            resourceId: id,
            branchId: '${cur['branchId']}',
            appointmentId: id,
            queueEntryId: '${q.entry['entryId']}',
            requestId: requestId,
            before: {'status': 'confirmed'},
            after: {'status': 'checked_in', 'token': q.entry['displayToken']},
          ),
        ]);
        return present({...cur, ...patch});
      }),
    );
  }

  /// Token keys are unique: when two check-ins race for the same number the
  /// loser simply looks again.
  Future<T> _retryOnContention<T>(Future<T> Function() f) async {
    for (var i = 0; i < 8; i++) {
      try {
        return await f();
      } on AlreadyExistsException {
        continue;
      }
    }
    throw const ApiException.conflict('The queue is busy. Please try again.');
  }

  /// `start` and `complete` act on the linked queue entry so the appointment
  /// and the queue can never disagree.
  Future<Map<String, Object?>> consult(
    TenantContext t,
    String id,
    String action, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.appointmentsConsult);
    final appt = await load(t, id);
    final entryId = appt['queueEntryId'] as String?;
    if (entryId == null) {
      throw const ApiException.conflict('The patient has not checked in.');
    }
    if (t.role == ClinicRole.doctor &&
        await _s.ownDoctorId(t) != appt['doctorId']) {
      throw const ApiException.forbidden();
    }
    await _queue.transition(
      t,
      entryId,
      action == 'start' ? 'in_progress' : 'completed',
      action: action,
      permission: ClinicPermission.queueConsult,
      requestId: requestId,
    );
    return present((await _s.d.store.get(_s.d.path(t, collection, id)))!);
  }

  // ------------------------------------------------------------------ reads

  Future<Map<String, Object?>> detail(TenantContext t, String id) async {
    t.require(ClinicPermission.appointmentsView);
    final a = await load(t, id);
    final history = await _s.d.store.query(
      DocQuery(
        _s.d.path(t, 'appointment_audit_logs'),
        filters: [QueryFilter('appointmentId', FilterOp.eq, id)],
        orderBy: const OrderBy('timestamp', descending: true),
        limit: 100,
      ),
    );
    return {
      ...present(a),
      'history': [
        for (final h in history)
          {
            'action': h.data['action'],
            'timestamp': jsonSafe(h.data['timestamp']),
            'actorRole': h.data['actorRole'],
            'reason': h.data['reason'],
            'before': h.data['before'],
            'after': h.data['after'],
          },
      ],
    };
  }

  Future<Paged> auditLogs(TenantContext t, String id, Request req) async {
    t.require(ClinicPermission.appointmentsView);
    await load(t, id);
    return runPaged(
      _s.d.store,
      DocQuery(
        _s.d.path(t, 'appointment_audit_logs'),
        filters: [QueryFilter('appointmentId', FilterOp.eq, id)],
        orderBy: const OrderBy('timestamp', descending: true),
      ),
      req,
    );
  }

  Future<Paged> list(
    TenantContext t,
    Request req, {
    String? date,
    String? from,
    String? to,
    String? doctorId,
    String? branchId,
    String? status,
    String? reference,
    String? q,
    bool needsAttention = false,
  }) async {
    t.require(ClinicPermission.appointmentsView);
    for (final d in [date, from, to]) {
      if (d != null && !Dates.valid(d)) {
        throw const ApiException.badRequest('Dates must be YYYY-MM-DD.');
      }
    }
    if (status != null && !appointmentStatuses.contains(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    if (branchId != null) t.scope.require(branchId);
    if (!t.scope.allBranches && t.scope.branchIds.length > 30) {
      throw const ApiException.forbidden(
        'Your branch access is too broad to list appointments.',
      );
    }
    final lo = date ?? from;
    final hi = date ?? to;
    if (lo != null && hi != null && Dates.daysBetween(lo, hi) > 62) {
      throw const ApiException.badRequest('Choose at most 62 days.');
    }
    if (reference != null) {
      final rows = await _s.d.store.query(
        DocQuery(
          _s.d.path(t, collection),
          filters: [
            QueryFilter('reference', FilterOp.eq, reference.toUpperCase()),
          ],
          limit: 5,
        ),
      );
      return Paged([
        for (final r in rows)
          if (t.scope.allows('${r.data['branchId']}')) r,
      ], const PageMeta(limit: 5, hasMore: false));
    }
    final page = await runPaged(
      _s.d.store,
      DocQuery(
        _s.d.path(t, collection),
        filters: [
          if (lo != null) QueryFilter('localDate', FilterOp.gte, lo),
          if (hi != null) QueryFilter('localDate', FilterOp.lte, hi),
          if (doctorId != null) QueryFilter('doctorId', FilterOp.eq, doctorId),
          if (status != null) QueryFilter('status', FilterOp.eq, status),
          if (needsAttention)
            const QueryFilter('needsAttention', FilterOp.eq, true),
          if (branchId != null)
            QueryFilter('branchId', FilterOp.eq, branchId)
          else if (!t.scope.allBranches)
            QueryFilter(
              'branchId',
              FilterOp.inList,
              t.scope.branchIds.toList(),
            ),
        ],
        orderBy: const OrderBy('localDate'),
      ),
      req,
    );
    final needle = q?.trim().toLowerCase();
    final docs =
        [
          for (final d in page.docs)
            if (needle == null ||
                needle.isEmpty ||
                '${d.data['patientName']}'.toLowerCase().contains(needle) ||
                '${d.data['patientMrn']}'.toLowerCase().contains(needle) ||
                '${d.data['reference']}'.toLowerCase().contains(needle))
              d,
        ]..sort((a, b) {
          final c = '${a.data['localDate']}'.compareTo(
            '${b.data['localDate']}',
          );
          return c != 0
              ? c
              : '${a.data['startTime']}'.compareTo('${b.data['startTime']}');
        });
    return Paged(docs, page.meta);
  }

  Future<Paged> forPatient(
    TenantContext t,
    String patientId,
    Request req, {
    String? from,
    String? to,
  }) async {
    t.require(ClinicPermission.appointmentsView);
    await _patients.load(t, patientId);
    for (final d in [from, to]) {
      if (d != null && !Dates.valid(d)) {
        throw const ApiException.badRequest('Dates must be YYYY-MM-DD.');
      }
    }
    final page = await runPaged(
      _s.d.store,
      DocQuery(
        _s.d.path(t, collection),
        filters: [
          QueryFilter('patientId', FilterOp.eq, patientId),
          if (from != null) QueryFilter('localDate', FilterOp.gte, from),
          if (to != null) QueryFilter('localDate', FilterOp.lte, to),
        ],
        orderBy: const OrderBy('localDate', descending: true),
      ),
      req,
    );
    return Paged(
      page.docs.where((d) => t.scope.allows('${d.data['branchId']}')).toList(),
      page.meta,
    );
  }
}
