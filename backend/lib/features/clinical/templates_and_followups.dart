import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import '../scheduling/appointment_service.dart';
import '../scheduling/time_support.dart';
import 'clinical_support.dart';

/// Reusable starting points for a consultation. A template only pre-fills
/// editable sections of a **draft**; it never finalizes anything.
class TemplateService {
  TemplateService(this._s);

  final ClinicalSupport _s;

  static const String collection = 'clinical_templates';

  Map<String, Object?> _parse(
    Map<String, Object?> body, {
    required bool partial,
  }) {
    final r = BodyReader(body, partial: partial)
      ..rejectUnknown({'name', 'description', 'scope', 'content', 'status'});
    final name = r.str('name', min: 2, max: 80);
    final description = r.str('description', max: 200, required: false);
    final scope = r.enumOf<String>('scope', const [
      'clinic',
      'doctor',
    ], (v) => v);
    Map<String, Object?>? content;
    if (r.has('content')) {
      final raw = r.body['content'];
      if (raw is! Map) {
        r.addIssue('content', 'invalid_type', 'Must be an object.');
      } else {
        final cr = BodyReader(raw.cast<String, Object?>());
        content = {
          for (final e in ConsultationSections.parse(cr).entries)
            e.key: e.value,
        };
        cr.rejectUnknown(ConsultationSections.names.toSet());
        for (final x in cr.issues) {
          r.addIssue('content.${x.field}', x.code, x.message);
        }
        try {
          cr.throwIfInvalid();
        } on ApiException catch (e) {
          for (final x in e.issues) {
            r.addIssue('content.${x.field}', x.code, x.message);
          }
        }
      }
    } else if (!partial) {
      r.addIssue('content', 'required', 'content is required.');
    }
    final status = r.enumOf<String>(
      'status',
      const ['active', 'inactive'],
      (v) => v,
      required: false,
    );
    r.throwIfInvalid();
    return {
      'name': ?name,
      'description': ?description,
      'scope': ?scope,
      'content': ?content,
      'status': ?status,
    };
  }

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final f = _parse(body, partial: false);
    String? doctorId;
    if (f['scope'] == 'clinic') {
      t.require(ClinicPermission.clinicalTemplatesManageClinic);
    } else {
      t.require(ClinicPermission.clinicalTemplatesManage);
      doctorId = await _s.requireDoctorSelf(t);
    }
    final id = 'tpl_${newId(length: 12)}';
    final now = _s.d.now;
    final doc = {
      'templateId': id,
      'tenantId': t.tenantId,
      'doctorId': doctorId,
      ...f,
      'status': f['status'] ?? 'active',
      'createdAt': now,
      'updatedAt': now,
      'createdBy': t.uid,
    };
    await _s.d.store.commit([
      CreateOp(_s.path(t, collection, id), doc),
      _s.audit(
        t,
        action: 'template.created',
        resourceType: 'template',
        resourceId: id,
        requestId: requestId,
        after: {'scope': f['scope']},
      ),
    ]);
    return ClinicalSupport.present(doc);
  }

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    final f = _parse({
      ...body,
      'scope': body['scope'] ?? 'clinic',
    }, partial: true)..remove('scope');
    if (body.containsKey('scope')) {
      throw ApiException.validation([
        issue('scope', 'immutable', 'The scope cannot be changed.'),
      ]);
    }
    if (f.isEmpty) throw const ApiException.badRequest('Nothing to update.');
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final path = _s.path(t, collection, id);
      final cur = await tx.get(path);
      if (cur == null) throw const ApiException.notFound('Template not found.');
      if (cur['scope'] == 'clinic') {
        t.require(ClinicPermission.clinicalTemplatesManageClinic);
      } else {
        t.require(ClinicPermission.clinicalTemplatesManage);
        if (cur['doctorId'] != await _s.requireDoctorSelf(t)) {
          throw const ApiException.notFound('Template not found.');
        }
      }
      final patch = {...f, 'updatedAt': now};
      tx.write([
        UpdateOp(path, patch),
        _s.audit(
          t,
          action: 'template.updated',
          resourceType: 'template',
          resourceId: id,
          requestId: requestId,
          after: {'fields': f.keys.toList()},
        ),
      ]);
      return ClinicalSupport.present({...cur, ...patch});
    });
  }

  /// Active clinic templates plus the caller's own; managers of clinic
  /// templates also see inactive ones.
  Future<List<Map<String, Object?>>> list(
    TenantContext t, {
    String? status,
  }) async {
    t.require(ClinicPermission.clinicalTemplatesView);
    final rows = await _s.d.store.query(
      DocQuery(_s.path(t, collection), limit: 300),
    );
    final me = t.role == ClinicRole.doctor
        ? await _s.sched.ownDoctorId(t)
        : null;
    final manager = t.can(ClinicPermission.clinicalTemplatesManageClinic);
    return [
      for (final r in rows)
        if ((r.data['scope'] == 'clinic' ||
                (me != null && r.data['doctorId'] == me)) &&
            (status != null
                ? r.data['status'] == status
                : (manager || r.data['status'] == 'active')))
          ClinicalSupport.present(r.data),
    ];
  }
}

/// Follow-up plans. A follow-up is a recommendation: it becomes a booked visit
/// only through the Phase 5 appointment service.
class FollowupService {
  FollowupService(this._s, this._appointments);

  final ClinicalSupport _s;
  final AppointmentService _appointments;

  static const String collection = 'followups';
  static const Map<String, Set<String>> transitions = {
    'scheduled': {'completed', 'missed', 'cancelled'},
    'missed': {'completed', 'cancelled'},
    'completed': {},
    'cancelled': {},
  };

  Future<Map<String, Object?>> create(
    TenantContext t,
    String consultationId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.followupsManage);
    final r = BodyReader(body)
      ..rejectUnknown({'recommendedDate', 'reason', 'instructions'});
    String? date;
    if (!Dates.valid(r.body['recommendedDate'])) {
      r.addIssue('recommendedDate', 'invalid_date', 'Use YYYY-MM-DD.');
    } else {
      date = r.body['recommendedDate'] as String;
    }
    final reason = r.str('reason', min: 3, max: 300);
    final instructions = r.str('instructions', max: 1000, required: false);
    r.throwIfInvalid();
    final id = 'fu_${newId(length: 12)}';
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final c = await _s.consultation(t, consultationId, tx: tx);
      await _s.requireAuthor(t, c);
      final branch = await _s.d.store.get(
        _s.path(t, 'branches', '${c['branchId']}'),
      );
      final today = (await _s.sched.zoneFor(t, branch!)).localDate(now);
      if (date!.compareTo(today) < 0) {
        throw ApiException.validation([
          issue(
            'recommendedDate',
            'in_the_past',
            'The follow-up date cannot be in the past.',
          ),
        ]);
      }
      final existing = await tx.query(
        DocQuery(
          _s.path(t, collection),
          filters: [QueryFilter('consultationId', FilterOp.eq, consultationId)],
          limit: 20,
        ),
      );
      if (existing.where((e) => e.data['status'] == 'scheduled').length >= 3) {
        throw const ApiException.conflict(
          'Too many open follow-ups for this consultation.',
        );
      }
      final doc = <String, Object?>{
        'followupId': id,
        'consultationId': consultationId,
        'tenantId': t.tenantId,
        'branchId': c['branchId'],
        'patientId': c['patientId'],
        'patientName': c['patientName'],
        'patientMrn': c['patientMrn'],
        'doctorId': c['doctorId'],
        'doctorName': c['doctorName'],
        'recommendedDate': date,
        'reason': reason,
        'instructions': instructions,
        'status': 'scheduled',
        'appointmentId': null,
        'createdAt': now,
        'updatedAt': now,
        'createdBy': t.uid,
        'updatedBy': t.uid,
      }..removeWhere((k, v) => v == null && k != 'appointmentId');
      tx.write([
        CreateOp(_s.path(t, collection, id), doc),
        _s.audit(
          t,
          action: 'followup.created',
          resourceType: 'followup',
          resourceId: id,
          branchId: '${c['branchId']}',
          patientId: '${c['patientId']}',
          consultationId: consultationId,
          requestId: requestId,
          after: {'date': date},
        ),
      ]);
      return ClinicalSupport.present(doc);
    });
  }

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.followupsManage);
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({'status', 'recommendedDate', 'reason', 'instructions'});
    final status = r.enumOf<String>(
      'status',
      transitions.keys.toList(),
      (v) => v,
      required: false,
    );
    String? date;
    if (r.has('recommendedDate')) {
      if (!Dates.valid(r.body['recommendedDate'])) {
        r.addIssue('recommendedDate', 'invalid_date', 'Use YYYY-MM-DD.');
      } else {
        date = r.body['recommendedDate'] as String;
      }
    }
    final reason = r.str('reason', min: 3, max: 300, required: false);
    final instructions = r.str('instructions', max: 1000, required: false);
    r.throwIfInvalid();
    if (status == null &&
        date == null &&
        reason == null &&
        instructions == null) {
      throw const ApiException.badRequest('Nothing to update.');
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final path = _s.path(t, collection, id);
      final cur = await tx.get(path);
      if (cur == null || !await _s.canSee(t, cur)) {
        throw const ApiException.notFound('Follow-up not found.');
      }
      await _s.requireAuthor(t, cur);
      final from = '${cur['status']}';
      if (status != null && !(transitions[from]?.contains(status) ?? false)) {
        throw ApiException.conflict('A $from follow-up cannot become $status.');
      }
      if ((date != null || reason != null || instructions != null) &&
          from != 'scheduled') {
        throw const ApiException.conflict(
          'Only a scheduled follow-up can be edited.',
        );
      }
      final patch = {
        'status': ?status,
        'recommendedDate': ?date,
        'reason': ?reason,
        'instructions': ?instructions,
        'updatedAt': now,
        'updatedBy': t.uid,
      };
      tx.write([
        UpdateOp(path, patch),
        _s.audit(
          t,
          action: 'followup.updated',
          resourceType: 'followup',
          resourceId: id,
          branchId: '${cur['branchId']}',
          patientId: '${cur['patientId']}',
          consultationId: '${cur['consultationId']}',
          requestId: requestId,
          before: {'status': from},
          after: {
            'status': status ?? from,
            'fields': patch.keys
                .where((k) => k != 'updatedAt' && k != 'updatedBy')
                .toList(),
          },
        ),
      ]);
      return ClinicalSupport.present({...cur, ...patch});
    });
  }

  /// Follow-ups of the caller's doctor (or, for staff with `followups.view`,
  /// of their branches). Clinical wording is hidden from roles that cannot
  /// read consultations.
  Future<Paged> list(
    TenantContext t,
    Request req, {
    String? status,
    String? branchId,
    String? from,
    String? to,
    bool overdue = false,
    bool upcoming = false,
  }) async {
    t.require(ClinicPermission.followupsView);
    if (status != null && !transitions.containsKey(status)) {
      throw const ApiException.badRequest('status has an unsupported value.');
    }
    for (final d in [from, to]) {
      if (d != null && !Dates.valid(d)) {
        throw const ApiException.badRequest('Dates must be YYYY-MM-DD.');
      }
    }
    if (branchId != null) t.scope.require(branchId);
    if (!t.scope.allBranches && t.scope.branchIds.length > 30) {
      throw const ApiException.forbidden('Your branch access is too broad.');
    }
    final settings = await _s.sched.settings(t);
    final today = ClinicZone.resolve(
      settings['timezone'] as String?,
    ).localDate(_s.d.now);
    final me = t.role == ClinicRole.doctor
        ? await _s.sched.ownDoctorId(t)
        : null;
    if (t.role == ClinicRole.doctor && me == null) {
      throw const ApiException.forbidden(
        'Your login is not linked to a doctor profile.',
      );
    }
    final seesAll = t.can(ClinicPermission.consultationsViewAll);
    final page = await runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, collection),
        filters: [
          if (me != null && !seesAll) QueryFilter('doctorId', FilterOp.eq, me),
          if (overdue)
            const QueryFilter('status', FilterOp.eq, 'scheduled')
          else if (status != null)
            QueryFilter('status', FilterOp.eq, status),
          if (upcoming) const QueryFilter('status', FilterOp.eq, 'scheduled'),
          if (overdue)
            QueryFilter('recommendedDate', FilterOp.lt, today)
          else if (upcoming)
            QueryFilter('recommendedDate', FilterOp.gte, today)
          else ...[
            if (from != null)
              QueryFilter('recommendedDate', FilterOp.gte, from),
            if (to != null) QueryFilter('recommendedDate', FilterOp.lte, to),
          ],
          if (branchId != null)
            QueryFilter('branchId', FilterOp.eq, branchId)
          else if (!t.scope.allBranches)
            QueryFilter(
              'branchId',
              FilterOp.inList,
              t.scope.branchIds.toList(),
            ),
        ],
        orderBy: const OrderBy('recommendedDate'),
      ),
      req,
    );
    return page;
  }

  Map<String, Object?> present(
    TenantContext t,
    Map<String, Object?> f,
    String today,
  ) {
    final out = ClinicalSupport.present(f);
    if (!t.can(ClinicPermission.consultationsView)) {
      out
        ..remove('reason')
        ..remove('instructions')
        ..remove('consultationId');
    }
    out['overdue'] =
        f['status'] == 'scheduled' &&
        '${f['recommendedDate']}'.compareTo(today) < 0;
    return out;
  }

  Future<String> today(TenantContext t) async {
    final settings = await _s.sched.settings(t);
    return ClinicZone.resolve(
      settings['timezone'] as String?,
    ).localDate(_s.d.now);
  }

  /// Books the follow-up through the Phase 5 appointment service. A second
  /// request is refused while the first appointment is still open.
  Future<Map<String, Object?>> bookAppointment(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    required String? idempotencyKey,
    String? requestId,
  }) async {
    t.require(ClinicPermission.followupsView);
    final r = BodyReader(body)..rejectUnknown({'typeId', 'date', 'startTime'});
    final typeId = r.str('typeId', max: 40);
    final date = r.str('date', max: 10);
    final startTime = r.str('startTime', max: 5);
    r.throwIfInvalid();
    final fu = await _s.d.store.get(_s.path(t, collection, id));
    if (fu == null || !t.scope.allows('${fu['branchId']}')) {
      throw const ApiException.notFound('Follow-up not found.');
    }
    if (fu['status'] != 'scheduled') {
      throw ApiException.conflict(
        'A ${fu['status']} follow-up cannot be booked.',
      );
    }
    final existing = fu['appointmentId'] as String?;
    if (existing != null) {
      final a = await _s.d.store.get(_s.path(t, 'appointments', existing));
      if (a != null &&
          const {
            'pending',
            'confirmed',
            'checked_in',
            'in_progress',
            'completed',
          }.contains(a['status'])) {
        throw const ApiException.conflict(
          'This follow-up already has an appointment.',
        );
      }
    }
    final appt = await _appointments.book(
      t,
      {
        'patientId': fu['patientId'],
        'doctorId': fu['doctorId'],
        'branchId': fu['branchId'],
        'typeId': typeId,
        'date': date,
        'startTime': startTime,
      },
      idempotencyKey: idempotencyKey,
      requestId: requestId,
    );
    final now = _s.d.now;
    await _s.d.store.commit([
      UpdateOp(_s.path(t, collection, id), {
        'appointmentId': appt['appointmentId'],
        'appointmentReference': appt['reference'],
        'updatedAt': now,
        'updatedBy': t.uid,
      }),
      UpdateOp(_s.path(t, 'appointments', '${appt['appointmentId']}'), {
        'followupId': id,
      }),
      _s.audit(
        t,
        action: 'followup.appointment_booked',
        resourceType: 'followup',
        resourceId: id,
        branchId: '${fu['branchId']}',
        patientId: '${fu['patientId']}',
        consultationId: '${fu['consultationId']}',
        requestId: requestId,
        after: {'appointmentId': appt['appointmentId']},
      ),
    ]);
    return {'followupId': id, 'appointment': appt};
  }
}
