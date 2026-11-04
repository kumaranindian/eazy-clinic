import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../auth/domain/auth_context.dart';
import '../platform/common/body_reader.dart';
import '../scheduling/appointment_service.dart';
import '../scheduling/queue_service.dart';
import '../scheduling/time_support.dart';
import 'portal_notifier.dart';
import 'portal_support.dart';

/// Booking policy for the patient app. These are product defaults, validated
/// by the backend on every call; the clinic cannot configure them yet (TD-65).
abstract final class PatientBookingPolicy {
  /// How far ahead a patient may book.
  static const int advanceDays = 60;

  /// Cancelling or rescheduling must happen at least this long before the visit.
  static const Duration changeNotice = Duration(hours: 2);
}

/// A patient's appointments, through the Phase 5 engine.
///
/// The portal proves who the patient is and that the appointment is theirs,
/// applies the patient policy, then calls the same booking, cancel, reschedule
/// and check-in code staff use. The client never sets a status.
class PortalAppointmentService {
  PortalAppointmentService(this._s, this._appts, this._queue, this._notifier);

  final PortalSupport _s;
  final AppointmentService _appts;
  final QueueService _queue;
  final PortalNotifier _notifier;

  static const List<String> _fields = [
    'appointmentId',
    'reference',
    'branchId',
    'branchName',
    'doctorId',
    'doctorName',
    'typeId',
    'typeName',
    'localDate',
    'startTime',
    'endTime',
    'timezone',
    'durationMinutes',
    'status',
    'tokenDisplay',
    'source',
    'createdAt',
    'cancelReason',
  ];

  Map<String, Object?> _present(
    DocData a,
    ClinicLink link, {
    String? clinicName,
  }) => {
    ...PortalSupport.pick(a, _fields),
    'clinicId': link.tenantId,
    'clinicName': clinicName ?? link.clinicName,
    'patientAccountId': link.accountId,
    'canCancel': const {'pending', 'confirmed'}.contains(a['status']),
  };

  Future<DocData> _owned(ClinicLink link, String appointmentId) async {
    final a = await _s.store.get(
      _s.path(link.tenantId, 'appointments', appointmentId),
    );
    if (a == null || a['patientId'] != link.patientId) {
      throw const ApiException.notFound('Appointment not found.');
    }
    return a;
  }

  /// Upcoming and past appointments of the subject across linked clinics.
  Future<List<Map<String, Object?>>> list(
    AuthContext ctx, {
    String? accountId,
    String? clinicId,
    String? filter,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeAppointments,
    );
    final out = <Map<String, Object?>>[];
    for (final link in await _s.links(subject, clinicId: clinicId)) {
      final rows = await _s.store.query(
        DocQuery(
          _s.path(link.tenantId, 'appointments'),
          filters: [QueryFilter('patientId', FilterOp.eq, link.patientId)],
          limit: 100,
        ),
      );
      final today = await _todayAt(link.tenantId);
      for (final r in rows) {
        final row = _present(r.data, link);
        row['upcoming'] =
            const {
              'pending',
              'confirmed',
              'checked_in',
              'in_consultation',
            }.contains(r.data['status']) &&
            '${r.data['localDate']}'.compareTo(today) >= 0;
        out.add(row);
      }
    }
    final shown =
        [
          for (final a in out)
            if (filter == null ||
                (filter == 'upcoming' && a['upcoming'] == true) ||
                (filter != 'upcoming' && a['status'] == filter))
              a,
        ]..sort((a, b) {
          final c = '${b['localDate']}${b['startTime']}'.compareTo(
            '${a['localDate']}${a['startTime']}',
          );
          return c;
        });
    return shown;
  }

  Future<Map<String, Object?>> detail(
    AuthContext ctx,
    String clinicId,
    String appointmentId, {
    String? accountId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeAppointments,
    );
    final link = await _s.requireLink(subject, clinicId);
    return _present(await _owned(link, appointmentId), link);
  }

  Future<Map<String, Object?>> book(
    AuthContext ctx,
    Map<String, Object?> body, {
    required String? idempotencyKey,
    String? requestId,
  }) async {
    final r = BodyReader(body)
      ..rejectUnknown({
        'clinicId',
        'accountId',
        'branchId',
        'doctorId',
        'typeId',
        'date',
        'startTime',
      });
    final clinicId = r.str('clinicId', max: 80);
    final accountId = r.str('accountId', max: 40, required: false);
    final branchId = r.str('branchId', max: 40);
    final doctorId = r.str('doctorId', max: 40);
    final typeId = r.str('typeId', max: 40);
    if (!Dates.valid(r.body['date'])) {
      r.addIssue('date', 'invalid_date', 'Use YYYY-MM-DD.');
    }
    if (Hm.parse(r.body['startTime']) == null) {
      r.addIssue('startTime', 'invalid_time', 'Use a time like 09:30.');
    }
    r.throwIfInvalid();
    final date = r.body['date']! as String;
    final startTime = r.body['startTime']! as String;
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeAppointments,
    );
    final link = await _s.requireLink(subject, clinicId!);
    final t = await _s.actingIn(ctx, clinicId, write: true);
    await _enforceWindow(t.tenantId, branchId!, date);
    final a = await _appts.book(
      t,
      {
        'patientId': link.patientId,
        'doctorId': doctorId,
        'branchId': branchId,
        'typeId': typeId,
        'date': date,
        'startTime': startTime,
        // the clinic confirms patient-app bookings
        'status': 'pending',
      },
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    await _s.store.commit([
      _s.audit(
        t,
        link,
        'portal.appointment_booked',
        resourceType: 'appointment',
        resourceId: '${a['appointmentId']}',
        requestId: requestId,
      ),
    ]);
    if (a['idempotentReplay'] != true) {
      await _notifier.publish(
        accountId: link.accountId,
        category: 'appointment_booked',
        title: 'Appointment requested',
        body:
            'Your appointment request was received. Open the app for details.',
        dedupeKey: 'booked:${a['appointmentId']}',
        clinicId: clinicId,
        resourceType: 'appointment',
        resourceId: '${a['appointmentId']}',
      );
    }
    return _present(a, link);
  }

  Future<void> _enforceWindow(
    String clinicId,
    String branchId,
    String date,
  ) async {
    final branch = await _s.store.get(_s.path(clinicId, 'branches', branchId));
    if (branch == null) throw const ApiException.notFound('Branch not found.');
    final zone = await _zone(clinicId, branch);
    final today = zone.localDate(_s.d.now);
    if (date.compareTo(today) < 0) {
      throw const ApiException.conflict('Choose today or a later date.');
    }
    if (Dates.daysBetween(today, date) > PatientBookingPolicy.advanceDays) {
      throw ApiException.conflict(
        'Appointments can be booked up to ${PatientBookingPolicy.advanceDays} days ahead.',
      );
    }
  }

  Future<String> _todayAt(String clinicId) async {
    final s = await _s.store.get(
      _s.path(clinicId, 'clinic_settings', 'operations'),
    );
    return ClinicZone.resolve(s?['timezone'] as String?).localDate(_s.d.now);
  }

  Future<ClinicZone> _zone(String clinicId, DocData branch) async {
    final own = branch['timezone'] as String?;
    if (own != null && own.isNotEmpty) return ClinicZone.resolve(own);
    final s = await _s.store.get(
      _s.path(clinicId, 'clinic_settings', 'operations'),
    );
    return ClinicZone.resolve(s?['timezone'] as String?);
  }

  /// The patient may not change a visit that is too close.
  Future<void> _requireNotice(String clinicId, DocData a) async {
    final branch = await _s.store.get(
      _s.path(clinicId, 'branches', '${a['branchId']}'),
    );
    final zone = await _zone(clinicId, branch ?? const {});
    final mins = Hm.parse(a['startTime']) ?? 0;
    final start = zone.toUtc('${a['localDate']}', mins);
    if (start.difference(_s.d.now) < PatientBookingPolicy.changeNotice) {
      throw ApiException.conflict(
        'Appointments can be changed up to ${PatientBookingPolicy.changeNotice.inHours} hours before the visit. Please contact the clinic.',
      );
    }
  }

  Future<Map<String, Object?>> cancel(
    AuthContext ctx,
    String clinicId,
    String appointmentId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown({'accountId', 'reason'});
    final accountId = r.str('accountId', max: 40, required: false);
    final reason =
        r.str('reason', min: 3, max: 300, required: false) ??
        'Cancelled by patient';
    r.throwIfInvalid();
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeAppointments,
    );
    final link = await _s.requireLink(subject, clinicId);
    final cur = await _owned(link, appointmentId);
    if (cur['status'] == 'cancelled') {
      return {..._present(cur, link), 'idempotentReplay': true};
    }
    if (cur['status'] != 'pending' && cur['status'] != 'confirmed') {
      throw ApiException.conflict(
        'A ${cur['status']} appointment cannot be cancelled here.',
      );
    }
    await _requireNotice(clinicId, cur);
    final t = await _s.actingIn(ctx, clinicId, write: true);
    final a = await _appts.cancel(t, appointmentId, {
      'reason': reason,
    }, requestId: requestId);
    await _s.store.commit([
      _s.audit(
        t,
        link,
        'portal.appointment_cancelled',
        resourceType: 'appointment',
        resourceId: appointmentId,
        requestId: requestId,
      ),
    ]);
    await _notifier.publish(
      accountId: link.accountId,
      category: 'appointment_cancelled',
      title: 'Appointment cancelled',
      body: 'Your appointment was cancelled.',
      dedupeKey: 'cancelled:$appointmentId',
      clinicId: clinicId,
      resourceType: 'appointment',
      resourceId: appointmentId,
    );
    return _present(a, link);
  }

  Future<Map<String, Object?>> reschedule(
    AuthContext ctx,
    String clinicId,
    String appointmentId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final r = BodyReader(body)
      ..rejectUnknown({'accountId', 'date', 'startTime', 'reason'});
    final accountId = r.str('accountId', max: 40, required: false);
    final reason =
        r.str('reason', min: 3, max: 300, required: false) ??
        'Rescheduled by patient';
    if (!Dates.valid(r.body['date'])) {
      r.addIssue('date', 'invalid_date', 'Use YYYY-MM-DD.');
    }
    if (Hm.parse(r.body['startTime']) == null) {
      r.addIssue('startTime', 'invalid_time', 'Use a time like 09:30.');
    }
    r.throwIfInvalid();
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeAppointments,
    );
    final link = await _s.requireLink(subject, clinicId);
    final cur = await _owned(link, appointmentId);
    if (cur['status'] != 'pending' && cur['status'] != 'confirmed') {
      throw ApiException.conflict(
        'A ${cur['status']} appointment cannot be rescheduled here.',
      );
    }
    await _requireNotice(clinicId, cur);
    await _enforceWindow(
      clinicId,
      '${cur['branchId']}',
      r.body['date']! as String,
    );
    final t = await _s.actingIn(ctx, clinicId, write: true);
    final res = await _appts.reschedule(t, appointmentId, {
      'date': r.body['date'],
      'startTime': r.body['startTime'],
      'reason': reason,
    }, requestId: requestId);
    final created = (res['appointment'] ?? res['newAppointment'] ?? res) as Map;
    final newId = '${created['appointmentId'] ?? ''}';
    await _s.store.commit([
      _s.audit(
        t,
        link,
        'portal.appointment_rescheduled',
        resourceType: 'appointment',
        resourceId: appointmentId,
        requestId: requestId,
        after: {'newAppointmentId': newId},
      ),
    ]);
    await _notifier.publish(
      accountId: link.accountId,
      category: 'appointment_rescheduled',
      title: 'Appointment rescheduled',
      body: 'Your appointment was moved to a new time.',
      dedupeKey: 'rescheduled:$appointmentId',
      clinicId: clinicId,
      resourceType: 'appointment',
      resourceId: newId.isEmpty ? appointmentId : newId,
    );
    return {...PortalSupport.clean(res), 'clinicId': clinicId};
  }

  Future<Map<String, Object?>> checkIn(
    AuthContext ctx,
    String clinicId,
    String appointmentId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final r = BodyReader(body)..rejectUnknown({'accountId'});
    final accountId = r.str('accountId', max: 40, required: false);
    r.throwIfInvalid();
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeAppointments,
    );
    final link = await _s.requireLink(subject, clinicId);
    final cur = await _owned(link, appointmentId);
    if (cur['status'] == 'checked_in') {
      return {..._present(cur, link), 'idempotentReplay': true};
    }
    if (cur['status'] != 'confirmed') {
      throw ApiException.conflict(
        cur['status'] == 'pending'
            ? 'The clinic has not confirmed this appointment yet.'
            : 'A ${cur['status']} appointment cannot be checked in.',
      );
    }
    final branch = await _s.store.get(
      _s.path(clinicId, 'branches', '${cur['branchId']}'),
    );
    final zone = await _zone(clinicId, branch ?? const {});
    if (cur['localDate'] != zone.localDate(_s.d.now)) {
      throw const ApiException.conflict(
        'You can check in on the day of the appointment.',
      );
    }
    final t = await _s.actingIn(ctx, clinicId, write: true);
    final a = await _appts.checkIn(t, appointmentId, requestId: requestId);
    await _s.store.commit([
      _s.audit(
        t,
        link,
        'portal.checked_in',
        resourceType: 'appointment',
        resourceId: appointmentId,
        requestId: requestId,
      ),
    ]);
    final token = a['tokenDisplay'];
    if (token != null) {
      await _notifier.publish(
        accountId: link.accountId,
        category: 'token_generated',
        title: 'You are checked in',
        body: 'Your queue token is ready. Open the app to follow the queue.',
        dedupeKey: 'token:$appointmentId',
        clinicId: clinicId,
        resourceType: 'appointment',
        resourceId: appointmentId,
      );
    }
    return _present(a, link);
  }

  /// Token and position for one appointment. Only counts and tokens: no other
  /// patient's name, phone or details, and no promised waiting time.
  Future<Map<String, Object?>> queue(
    AuthContext ctx,
    String clinicId,
    String appointmentId, {
    String? accountId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeAppointments,
    );
    final link = await _s.requireLink(subject, clinicId);
    final a = await _owned(link, appointmentId);
    final base = <String, Object?>{
      'appointmentId': appointmentId,
      'clinicId': clinicId,
      'appointmentStatus': a['status'],
      'checkedIn':
          a['status'] == 'checked_in' || a['status'] == 'in_consultation',
      'estimatedWait': null,
      'estimatedWaitNote':
          'A waiting time is not shown because it cannot be promised reliably.',
    };
    final entryId = a['queueEntryId'] as String?;
    if (entryId == null) return {...base, 'status': 'not_in_queue'};
    final t = await _s.actingIn(ctx, clinicId);
    final qid = QueueService.queueId(
      '${a['branchId']}',
      '${a['doctorId']}',
      '${a['localDate']}',
    );
    final entries = await _queue.orderedEntries(t, qid);
    final mine = entries.where((e) => e['appointmentId'] == appointmentId);
    if (mine.isEmpty) return {...base, 'status': 'not_in_queue'};
    final e = mine.first;
    final active = entries.where(
      (x) => x['status'] == 'in_progress' || x['status'] == 'called',
    );
    final waitingAhead = e['status'] == 'waiting' && e['queuePosition'] is int
        ? (e['queuePosition'] as int) - 1
        : null;
    return {
      ...base,
      'status': e['status'],
      'token': e['displayToken'],
      'queuePosition': e['queuePosition'],
      'patientsAhead': waitingAhead,
      'currentToken': active.isEmpty ? null : active.first['displayToken'],
      'asOf': PortalSupport.clean({'x': _s.d.now})['x'],
    };
  }
}
