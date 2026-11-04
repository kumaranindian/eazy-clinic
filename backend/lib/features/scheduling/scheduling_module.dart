import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../../core/errors/api_exception.dart';
import '../../core/responses/responses.dart';
import '../clinic/clinic_module.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/tenant_context.dart';
import '../patients/patient_support.dart';
import '../platform/common/paging.dart';
import 'appointment_service.dart';
import 'appointment_type_service.dart';
import 'availability_service.dart';
import 'queue_service.dart';
import 'scheduling_support.dart';
import 'slot_service.dart';

/// Services of Phase 5: availability, appointment types, slots, appointments,
/// queue and tokens.
class SchedulingModule {
  SchedulingModule(ClinicDeps deps, PatientSupport patients)
    : support = SchedulingSupport(deps) {
    availability = AvailabilityService(support);
    types = AppointmentTypeService(support);
    slots = SlotService(support, availability, types);
    queue = QueueService(support);
    appointments = AppointmentService(support, slots, types, queue, patients);
  }

  final SchedulingSupport support;

  /// Set by the clinic module: tells the notification pipeline about an
  /// appointment or queue event done by staff. A failure here never undoes or
  /// fails the business action.
  Future<void> Function(
    TenantContext t,
    String type,
    Map<String, Object?> data,
  )?
  onEvent;

  Future<Map<String, Object?>> notify(
    TenantContext t,
    String type,
    Map<String, Object?> out,
  ) async {
    final h = onEvent;
    if (h != null && out['idempotentReplay'] != true) {
      try {
        await h(t, type, out);
      } on Object {
        // notifications are best effort; the durable event is retried by the worker
      }
    }
    return out;
  }

  late final AvailabilityService availability;
  late final AppointmentTypeService types;
  late final SlotService slots;
  late final QueueService queue;
  late final AppointmentService appointments;
}

const String _v1 = apiV1Prefix;

void registerSchedulingRoutes(ClinicModule m, SchedulingModule s, Router r) {
  // ------------------------------------------------- doctor availability
  r.get(
    '$_v1/doctors/<did>/availability',
    m.secured((Request req, TenantContext t, String did) async {
      final page = await s.availability.listSchedules(t, m.id(did), req);
      return m.list(req, page, (d) => AvailabilityService.present(d.data));
    }),
  );
  r.post(
    '$_v1/doctors/<did>/availability',
    m.secured(
      (Request req, TenantContext t, String did) async => ok(
        req,
        await s.availability.createSchedule(
          t,
          m.id(did),
          await m.body(req),
          requestId: m.rid(req),
        ),
        status: 201,
      ),
      write: true,
    ),
  );
  r.patch(
    '$_v1/doctors/<did>/availability/<sid>',
    m.secured(
      (Request req, TenantContext t, String did, String sid) async => ok(
        req,
        await s.availability.updateSchedule(
          t,
          m.id(did),
          m.id(sid),
          await m.body(req),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );
  r.delete(
    '$_v1/doctors/<did>/availability/<sid>',
    m.secured(
      (Request req, TenantContext t, String did, String sid) async => ok(
        req,
        await s.availability.deactivateSchedule(
          t,
          m.id(did),
          m.id(sid),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );

  // --------------------------------------------------- schedule exceptions
  Response exceptionList(Request req, Paged p) =>
      m.list(req, p, (d) => AvailabilityService.present(d.data));
  r.get(
    '$_v1/doctors/<did>/schedule-exceptions',
    m.secured((Request req, TenantContext t, String did) async {
      final p = await s.availability.listExceptions(
        t,
        req,
        doctorId: m.id(did),
        branchId: m.query(req, 'branchId'),
        from: m.query(req, 'from'),
      );
      return exceptionList(req, p);
    }),
  );
  r.post(
    '$_v1/doctors/<did>/schedule-exceptions',
    m.secured(
      (Request req, TenantContext t, String did) async => ok(
        req,
        await s.availability.createException(
          t,
          await m.body(req),
          doctorId: m.id(did),
          requestId: m.rid(req),
        ),
        status: 201,
      ),
      write: true,
    ),
  );
  r.patch(
    '$_v1/doctors/<did>/schedule-exceptions/<eid>',
    m.secured(
      (Request req, TenantContext t, String did, String eid) async => ok(
        req,
        await s.availability.updateException(
          t,
          m.id(did),
          m.id(eid),
          await m.body(req),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );
  r.delete(
    '$_v1/doctors/<did>/schedule-exceptions/<eid>',
    m.secured(
      (Request req, TenantContext t, String did, String eid) async => ok(
        req,
        await s.availability.cancelException(
          t,
          m.id(did),
          m.id(eid),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );
  // branch-wide closures and holidays
  r.get(
    '$_v1/schedule-exceptions',
    m.secured((Request req, TenantContext t) async {
      final p = await s.availability.listExceptions(
        t,
        req,
        branchId: m.query(req, 'branchId'),
        from: m.query(req, 'from'),
      );
      return exceptionList(req, p);
    }),
  );
  r.post(
    '$_v1/schedule-exceptions',
    m.secured(
      (Request req, TenantContext t) async => ok(
        req,
        await s.availability.createException(
          t,
          await m.body(req),
          requestId: m.rid(req),
        ),
        status: 201,
      ),
      write: true,
    ),
  );
  r.patch(
    '$_v1/schedule-exceptions/<eid>',
    m.secured(
      (Request req, TenantContext t, String eid) async => ok(
        req,
        await s.availability.updateException(
          t,
          null,
          m.id(eid),
          await m.body(req),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );
  r.delete(
    '$_v1/schedule-exceptions/<eid>',
    m.secured(
      (Request req, TenantContext t, String eid) async => ok(
        req,
        await s.availability.cancelException(
          t,
          null,
          m.id(eid),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );
  r.get(
    '$_v1/schedule-exceptions/<eid>/affected-appointments',
    m.secured(
      (Request req, TenantContext t, String eid) async =>
          ok(req, await s.availability.affectedBy(t, m.id(eid))),
    ),
  );

  // -------------------------------------------------- appointment types
  r.get(
    '$_v1/appointment-types',
    m.secured((Request req, TenantContext t) async {
      final p = await s.types.list(t, req, status: m.query(req, 'status'));
      return m.list(req, p, (d) => AppointmentTypeService.present(d.data));
    }),
  );
  r.post(
    '$_v1/appointment-types',
    m.secured(
      (Request req, TenantContext t) async => ok(
        req,
        await s.types.create(t, await m.body(req), requestId: m.rid(req)),
        status: 201,
      ),
      write: true,
    ),
  );
  r.patch(
    '$_v1/appointment-types/<tid>',
    m.secured(
      (Request req, TenantContext t, String tid) async => ok(
        req,
        await s.types.update(
          t,
          m.id(tid),
          await m.body(req),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );
  for (final (path, status) in [
    ('activate', 'active'),
    ('deactivate', 'inactive'),
  ]) {
    r.post(
      '$_v1/appointment-types/<tid>/$path',
      m.secured(
        (Request req, TenantContext t, String tid) async => ok(
          req,
          await s.types.setStatus(t, m.id(tid), status, requestId: m.rid(req)),
        ),
        write: true,
      ),
    );
  }

  // ------------------------------------------------------- appointments
  r.get(
    '$_v1/appointments/available-slots',
    m.secured((Request req, TenantContext t) async {
      String need(String k) =>
          m.query(req, k) ?? (throw ApiException.badRequest('$k is required.'));
      return ok(
        req,
        await s.slots.availableSlots(
          t,
          branchId: need('branchId'),
          doctorId: need('doctorId'),
          date: need('date'),
          typeId: m.query(req, 'typeId'),
          includeFull: m.query(req, 'includeFull') == 'true',
        ),
      );
    }),
  );
  r.get(
    '$_v1/appointments',
    m.secured((Request req, TenantContext t) async {
      final p = await s.appointments.list(
        t,
        req,
        date: m.query(req, 'date'),
        from: m.query(req, 'from'),
        to: m.query(req, 'to'),
        doctorId: m.query(req, 'doctorId'),
        branchId: m.query(req, 'branchId'),
        status: m.query(req, 'status'),
        reference: m.query(req, 'reference'),
        q: m.query(req, 'q'),
        needsAttention: m.query(req, 'needsAttention') == 'true',
      );
      return m.list(req, p, (d) => s.appointments.present(d.data));
    }),
  );
  r.post(
    '$_v1/appointments',
    m.secured((Request req, TenantContext t) async {
      final out = await s.appointments.book(
        t,
        await m.body(req),
        idempotencyKey: req.headers['idempotency-key'],
        requestId: m.rid(req),
      );
      return ok(req, out, status: out['idempotentReplay'] == true ? 200 : 201);
    }, write: true),
  );
  r.post(
    '$_v1/appointments/walk-in',
    m.secured((Request req, TenantContext t) async {
      final out = await s.appointments.walkIn(
        t,
        await m.body(req),
        idempotencyKey: req.headers['idempotency-key'],
        requestId: m.rid(req),
      );
      return ok(req, out, status: out['idempotentReplay'] == true ? 200 : 201);
    }, write: true),
  );
  r.get(
    '$_v1/appointments/<aid>',
    m.secured(
      (Request req, TenantContext t, String aid) async =>
          ok(req, await s.appointments.detail(t, m.id(aid))),
    ),
  );
  r.patch(
    '$_v1/appointments/<aid>',
    m.secured(
      (Request req, TenantContext t, String aid) async => ok(
        req,
        await s.appointments.updateNotes(
          t,
          m.id(aid),
          await m.body(req),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );
  r.get(
    '$_v1/appointments/<aid>/audit-logs',
    m.secured((Request req, TenantContext t, String aid) async {
      final p = await s.appointments.auditLogs(t, m.id(aid), req);
      return m.list(req, p, (d) => jsonSafe(d.data)! as Map<String, Object?>);
    }),
  );
  r.post(
    '$_v1/appointments/<aid>/confirm',
    m.secured(
      (Request req, TenantContext t, String aid) async => ok(
        req,
        await s.notify(
          t,
          'appointment_confirmed',
          await s.appointments.confirm(t, m.id(aid), requestId: m.rid(req)),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/appointments/<aid>/cancel',
    m.secured(
      (Request req, TenantContext t, String aid) async => ok(
        req,
        await s.notify(
          t,
          'appointment_cancelled',
          await s.appointments.cancel(
            t,
            m.id(aid),
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/appointments/<aid>/reschedule',
    m.secured(
      (Request req, TenantContext t, String aid) async => ok(
        req,
        await s.notify(
          t,
          'appointment_rescheduled',
          await s.appointments.reschedule(
            t,
            m.id(aid),
            await m.body(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  r.post(
    '$_v1/appointments/<aid>/check-in',
    m.secured(
      (Request req, TenantContext t, String aid) async => ok(
        req,
        await s.notify(
          t,
          'token_generated',
          await s.appointments.checkIn(
            t,
            m.id(aid),
            body: await m.optionalBody(req),
            requestId: m.rid(req),
          ),
        ),
      ),
      write: true,
    ),
  );
  for (final action in ['start', 'complete']) {
    r.post(
      '$_v1/appointments/<aid>/$action',
      m.secured(
        (Request req, TenantContext t, String aid) async => ok(
          req,
          await s.appointments.consult(
            t,
            m.id(aid),
            action,
            requestId: m.rid(req),
          ),
        ),
        write: true,
      ),
    );
  }
  r.post(
    '$_v1/appointments/<aid>/mark-no-show',
    m.secured(
      (Request req, TenantContext t, String aid) async => ok(
        req,
        await s.appointments.markNoShow(t, m.id(aid), requestId: m.rid(req)),
      ),
      write: true,
    ),
  );
  r.get(
    '$_v1/patients/<pid>/appointments',
    m.secured((Request req, TenantContext t, String pid) async {
      final p = await s.appointments.forPatient(
        t,
        m.id(pid),
        req,
        from: m.query(req, 'from'),
        to: m.query(req, 'to'),
      );
      return m.list(req, p, (d) => s.appointments.present(d.data));
    }),
  );

  // -------------------------------------------------------------- queue
  r.get(
    '$_v1/queues',
    m.secured((Request req, TenantContext t) async {
      s.support.requireFeature(t);
      final branchId =
          m.query(req, 'branchId') ??
          (throw const ApiException.badRequest('branchId is required.'));
      return ok(
        req,
        await s.queue.listQueues(
          t,
          branchId: branchId,
          date: m.query(req, 'date'),
          doctorId: m.query(req, 'doctorId'),
        ),
      );
    }),
  );
  r.get(
    '$_v1/queues/current',
    m.secured((Request req, TenantContext t) async {
      s.support.requireFeature(t);
      String need(String k) =>
          m.query(req, k) ?? (throw ApiException.badRequest('$k is required.'));
      return ok(
        req,
        await s.queue.current(
          t,
          branchId: need('branchId'),
          doctorId: need('doctorId'),
          date: m.query(req, 'date'),
        ),
      );
    }),
  );
  r.get(
    '$_v1/queues/<qid>',
    m.secured(
      (Request req, TenantContext t, String qid) async =>
          ok(req, await s.queue.detail(t, m.id(qid))),
    ),
  );
  r.get(
    '$_v1/queues/<qid>/summary',
    m.secured(
      (Request req, TenantContext t, String qid) async =>
          ok(req, await s.queue.detail(t, m.id(qid))),
    ),
  );
  r.get(
    '$_v1/queues/<qid>/entries',
    m.secured(
      (Request req, TenantContext t, String qid) async => ok(
        req,
        await s.queue.entriesOf(t, m.id(qid), status: m.query(req, 'status')),
      ),
    ),
  );
  r.get(
    '$_v1/queues/<qid>/history',
    m.secured((Request req, TenantContext t, String qid) async {
      final p = await s.queue.history(t, m.id(qid), req);
      return m.list(req, p, (d) => jsonSafe(d.data)! as Map<String, Object?>);
    }),
  );
  r.post(
    '$_v1/queues/<qid>/entries',
    m.secured((Request req, TenantContext t, String qid) async {
      final body = await m.body(req);
      final aid = body['appointmentId'];
      if (aid is! String ||
          body.keys.any((k) => k != 'appointmentId' && k != 'priority')) {
        throw const ApiException.badRequest(
          'Send the appointmentId (and optionally priority).',
        );
      }
      final appt = await s.appointments.load(t, m.id(aid));
      if (QueueService.queueId(
            '${appt['branchId']}',
            '${appt['doctorId']}',
            '${appt['localDate']}',
          ) !=
          qid) {
        throw const ApiException.conflict(
          'The appointment belongs to another queue.',
        );
      }
      return ok(
        req,
        await s.appointments.checkIn(
          t,
          m.id(aid),
          body: {'priority': ?body['priority']},
          requestId: m.rid(req),
        ),
        status: 201,
      );
    }, write: true),
  );
  r.post(
    '$_v1/queues/<qid>/call-next',
    m.secured(
      (Request req, TenantContext t, String qid) async => ok(
        req,
        await s.notify(
          t,
          'doctor_calling',
          await s.queue.callNext(t, m.id(qid), requestId: m.rid(req)),
        ),
      ),
      write: true,
    ),
  );
  final entryActions = <(String, String, String, String, bool)>[
    ('call', 'called', 'call', ClinicPermission.queueOperate, false),
    ('recall', 'called', 'recall', ClinicPermission.queueOperate, false),
    ('skip', 'skipped', 'skip', ClinicPermission.queueOperate, false),
    ('restore', 'waiting', 'restore', ClinicPermission.queueOperate, false),
    ('start', 'in_progress', 'start', ClinicPermission.queueConsult, false),
    ('complete', 'completed', 'complete', ClinicPermission.queueConsult, false),
    ('cancel', 'cancelled', 'cancel', ClinicPermission.queueOperate, true),
    ('no-show', 'no_show', 'no-show', ClinicPermission.queueOperate, false),
  ];
  for (final (path, to, action, perm, needsReason) in entryActions) {
    r.post(
      '$_v1/queue-entries/<eid>/$path',
      m.secured((Request req, TenantContext t, String eid) async {
        final body = await m.optionalBody(req);
        final reason = body['reason'];
        final out = await s.queue.transition(
          t,
          m.id(eid),
          to,
          action: action,
          permission: perm,
          reason: reason is String ? reason : null,
          reasonRequired: needsReason,
          requestId: m.rid(req),
        );
        return ok(
          req,
          action == 'call' || action == 'recall'
              ? await s.notify(t, 'doctor_calling', out)
              : out,
        );
      }, write: true),
    );
  }
  r.post(
    '$_v1/queue-entries/<eid>/priority',
    m.secured(
      (Request req, TenantContext t, String eid) async => ok(
        req,
        await s.queue.setPriority(
          t,
          m.id(eid),
          await m.body(req),
          requestId: m.rid(req),
        ),
      ),
      write: true,
    ),
  );
}
