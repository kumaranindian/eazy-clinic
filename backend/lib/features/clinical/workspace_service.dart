import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../clinic/common/tenant_context.dart';
import '../platform/common/paging.dart';
import '../scheduling/queue_service.dart';
import 'clinical_support.dart';

/// Doctor workspace reads: dashboard, today's visits, queue, and the clinical
/// view of a patient. Appointments and queues come from Phase 5; nothing is
/// copied.
class WorkspaceService {
  WorkspaceService(this._s, this._queue);

  final ClinicalSupport _s;
  final QueueService _queue;

  /// Branches the doctor actively works at and the caller may access.
  Future<List<String>> _branches(
    TenantContext t,
    String doctorId,
    String? branchId,
  ) async {
    if (branchId != null) {
      t.scope.require(branchId);
      if (!await _s.sched.isAssigned(t, doctorId, branchId)) {
        throw const ApiException.forbidden(
          'You are not assigned to this branch.',
        );
      }
      return [branchId];
    }
    final rows = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'doctor_branch_assignments'),
        filters: [
          QueryFilter('doctorId', FilterOp.eq, doctorId),
          const QueryFilter('status', FilterOp.eq, 'active'),
        ],
        limit: 50,
      ),
    );
    return [
      for (final r in rows)
        if (t.scope.allows('${r.data['branchId']}')) '${r.data['branchId']}',
    ];
  }

  Future<List<StoredDoc>> _today(
    TenantContext t,
    String doctorId,
    String branchId,
    String date,
  ) => _s.d.store.query(
    DocQuery(
      _s.path(t, 'appointments'),
      filters: [
        QueryFilter('branchId', FilterOp.eq, branchId),
        QueryFilter('doctorId', FilterOp.eq, doctorId),
        QueryFilter('localDate', FilterOp.eq, date),
      ],
      limit: 300,
    ),
  );

  Future<Map<String, Object?>> dashboard(
    TenantContext t, {
    String? branchId,
  }) async {
    t.require(ClinicPermission.consultationsView);
    final me = await _s.requireDoctorSelf(t);
    final now = _s.d.now;
    final counts = {
      'scheduled': 0,
      'checkedIn': 0,
      'waiting': 0,
      'inProgress': 0,
      'completed': 0,
      'cancelled': 0,
      'noShow': 0,
    };
    final upcoming = <Map<String, Object?>>[];
    final queues = <Map<String, Object?>>[];
    for (final b in await _branches(t, me, branchId)) {
      final branch = await _s.sched.branch(t, b, mustBeActive: false);
      final zone = await _s.sched.zoneFor(t, branch);
      final date = zone.localDate(now);
      for (final a in await _today(t, me, b, date)) {
        final st = '${a.data['status']}';
        if (st != 'cancelled' && st != 'rescheduled') {
          counts['scheduled'] = counts['scheduled']! + 1;
        }
        switch (st) {
          case 'checked_in':
            counts['checkedIn'] = counts['checkedIn']! + 1;
          case 'in_progress':
            counts['inProgress'] = counts['inProgress']! + 1;
          case 'completed':
            counts['completed'] = counts['completed']! + 1;
          case 'cancelled':
            counts['cancelled'] = counts['cancelled']! + 1;
          case 'no_show':
            counts['noShow'] = counts['noShow']! + 1;
        }
        if ((st == 'confirmed' || st == 'pending') &&
            (a.data['endUtc'] as DateTime).isAfter(now)) {
          upcoming.add(_apptRow(a.data));
        }
      }
      final q = await _queue.current(t, branchId: b, doctorId: me, date: date);
      counts['waiting'] = counts['waiting']! + ((q['waiting'] as int?) ?? 0);
      queues.add({...q, 'branchName': branch['name']});
    }
    upcoming.sort((a, b) {
      final c = '${a['localDate']}'.compareTo('${b['localDate']}');
      return c != 0 ? c : '${a['startTime']}'.compareTo('${b['startTime']}');
    });
    final recent = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'consultations'),
        filters: [QueryFilter('doctorId', FilterOp.eq, me)],
        orderBy: const OrderBy('consultationAt', descending: true),
        limit: 5,
      ),
    );
    return {
      'doctorId': me,
      'counts': counts,
      'upcoming': upcoming.take(5).toList(),
      'queues': queues,
      'recentConsultations': [for (final c in recent) _consultationRow(c.data)],
    };
  }

  Map<String, Object?> _apptRow(DocData a) => {
    'appointmentId': a['appointmentId'],
    'reference': a['reference'],
    'branchId': a['branchId'],
    'patientId': a['patientId'],
    'patientName': a['patientName'],
    'patientMrn': a['patientMrn'],
    'typeName': a['typeName'],
    'localDate': a['localDate'],
    'startTime': a['startTime'],
    'endTime': a['endTime'],
    'status': a['status'],
    'source': a['source'],
    'tokenDisplay': a['tokenDisplay'],
    'queueEntryId': a['queueEntryId'],
    'needsAttention': a['needsAttention'],
  };

  Map<String, Object?> _consultationRow(DocData c) => {
    'consultationId': c['consultationId'],
    'patientId': c['patientId'],
    'patientName': c['patientName'],
    'patientMrn': c['patientMrn'],
    'status': c['status'],
    'type': c['type'],
    'consultationAt': ClinicalSupport.present({'x': c['consultationAt']})['x'],
    'reason': (c['chiefComplaint'] as Map?)?['reason'],
  };

  Future<List<Map<String, Object?>>> todayAppointments(
    TenantContext t, {
    String? branchId,
  }) async {
    t.require(ClinicPermission.consultationsView);
    final me = await _s.requireDoctorSelf(t);
    final out = <Map<String, Object?>>[];
    for (final b in await _branches(t, me, branchId)) {
      final branch = await _s.sched.branch(t, b, mustBeActive: false);
      final date = (await _s.sched.zoneFor(t, branch)).localDate(_s.d.now);
      for (final a in await _today(t, me, b, date)) {
        out.add(_apptRow(a.data));
      }
    }
    out.sort((a, b) => '${a['startTime']}'.compareTo('${b['startTime']}'));
    return out;
  }

  Future<List<Map<String, Object?>>> queue(
    TenantContext t, {
    String? branchId,
  }) async {
    t.require(ClinicPermission.consultationsView);
    final me = await _s.requireDoctorSelf(t);
    final out = <Map<String, Object?>>[];
    for (final b in await _branches(t, me, branchId)) {
      final branch = await _s.sched.branch(t, b, mustBeActive: false);
      final date = (await _s.sched.zoneFor(t, branch)).localDate(_s.d.now);
      final q = await _queue.current(t, branchId: b, doctorId: me, date: date);
      final entries = q['version'] == 0
          ? <Map<String, Object?>>[]
          : await _queue.entriesOf(t, '${q['queueId']}');
      out.add({...q, 'branchName': branch['name'], 'entries': entries});
    }
    return out;
  }

  // --------------------------------------------------------- patient view

  int _age(String dob) => PatientSupportAge.years(dob, _s.d.now);

  /// Clinical overview: demographics, alerts, allergies, medicines, history
  /// entries and document names. Sections follow the caller's permissions.
  Future<Map<String, Object?>> overview(
    TenantContext t,
    String patientId, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.consultationsView);
    final p = await _s.patients.load(t, patientId);
    Future<List<Map<String, Object?>>> rows(
      String collection, {
      List<QueryFilter> extra = const [],
      int limit = 50,
    }) async => [
      for (final r in await _s.d.store.query(
        DocQuery(
          _s.path(t, collection),
          filters: [QueryFilter('patientId', FilterOp.eq, patientId), ...extra],
          limit: limit,
        ),
      ))
        ClinicalSupport.present(r.data),
    ];
    final contacts = await _s.d.store.get(
      _s.path(t, 'patient_emergency_contacts', patientId),
    );
    final allergies = t.can(ClinicPermission.allergiesView)
        ? [
            for (final a in await rows('patient_allergies'))
              if (a['status'] != 'inactive') a,
          ]
        : null;
    final meds = t.can(ClinicPermission.medicationsView)
        ? await rows('patient_medications')
        : null;
    final history = t.can(ClinicPermission.historyView)
        ? await rows('patient_history_entries')
        : null;
    final alerts = [
      for (final a in await rows('patient_alerts'))
        if (a['status'] == 'active') a,
    ];
    final docs = t.can(ClinicPermission.patientDocumentsView)
        ? [
            for (final d in await rows('patient_documents', limit: 20))
              if (d['status'] == 'active')
                {
                  'documentId': d['documentId'],
                  'name': d['name'],
                  'category': d['category'],
                  'uploadedAt': d['uploadedAt'],
                  'verificationStatus': d['verificationStatus'],
                },
          ]
        : null;
    await _s.d.store.commit([
      _s.audit(
        t,
        action: 'clinical.overview_viewed',
        resourceType: 'patient',
        resourceId: patientId,
        branchId: '${p['branchId']}',
        patientId: patientId,
        requestId: requestId,
      ),
      _s.patients.auditOp(
        t,
        patientId,
        p['branchId'] as String?,
        'clinical.overview_viewed',
        requestId: requestId,
      ),
    ]);
    return {
      'patient': {
        'patientId': patientId,
        'mrn': p['mrn'],
        'fullName': p['fullName'],
        'preferredName': p['preferredName'],
        'dateOfBirth': p['dateOfBirth'],
        'age': _age('${p['dateOfBirth']}'),
        'gender': p['gender'],
        'bloodGroup': p['bloodGroup'],
        'phone': p['phone'],
        'email': p['email'],
        'branchId': p['branchId'],
        'status': p['status'],
        if (t.can(ClinicPermission.historyView))
          'restrictedNotes': p['restrictedNotes'],
      },
      'emergencyContacts': contacts?['contacts'] ?? const <Object?>[],
      'alerts': alerts,
      'allergies': allergies,
      'medications': meds,
      'medicalHistory': history,
      'documents': docs,
    };
  }

  /// Previous consultations, prescriptions and follow-ups of one patient.
  /// Doctors see their own records; `consultations.view_all` holders see all.
  Future<(Map<String, Object?>, PageMeta)> history(
    TenantContext t,
    String patientId,
    Request req,
  ) async {
    t.require(ClinicPermission.consultationsView);
    final p = await _s.patients.load(t, patientId);
    final seesAll = t.can(ClinicPermission.consultationsViewAll);
    final me = seesAll ? null : await _s.requireDoctorSelf(t);
    List<QueryFilter> mine() => [
      QueryFilter('patientId', FilterOp.eq, patientId),
      if (me != null) QueryFilter('doctorId', FilterOp.eq, me),
    ];
    final page = await runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, 'consultations'),
        filters: mine(),
        orderBy: const OrderBy('consultationAt', descending: true),
      ),
      req,
    );
    final consultations = <Map<String, Object?>>[];
    for (final c in page.docs) {
      if (!t.scope.allows('${c.data['branchId']}')) continue;
      final dx = await _s.d.store.query(
        DocQuery(
          _s.path(t, 'diagnoses'),
          filters: [QueryFilter('consultationId', FilterOp.eq, c.id)],
          limit: 30,
        ),
      );
      consultations.add({
        ..._consultationRow(c.data),
        'doctorName': c.data['doctorName'],
        'revision': c.data['revision'],
        'diagnoses': [
          for (final d in dx)
            if (d.data['status'] == 'active')
              {
                'kind': d.data['kind'],
                'certainty': d.data['certainty'],
                'label': d.data['label'],
                'code': d.data['code'],
              },
        ],
      });
    }
    final rx = await _s.d.store.query(
      DocQuery(_s.path(t, 'prescriptions'), filters: mine(), limit: 50),
    );
    final fu = await _s.d.store.query(
      DocQuery(_s.path(t, 'followups'), filters: mine(), limit: 50),
    );
    // verified, published reports of this doctor's own orders only
    final labAvailable = t.entitlements.features[FeatureKey.laboratory] == true;
    final labReports = labAvailable
        ? await _s.d.store.query(
            DocQuery(
              _s.path(t, 'lab_reports'),
              filters: [
                ...mine(),
                const QueryFilter('status', FilterOp.eq, 'published'),
              ],
              limit: 50,
            ),
          )
        : const <StoredDoc>[];
    await _s.d.store.commit([
      _s.audit(
        t,
        action: 'clinical.history_viewed',
        resourceType: 'patient',
        resourceId: patientId,
        branchId: '${p['branchId']}',
        patientId: patientId,
      ),
    ]);
    return (
      {
        'consultations': consultations,
        'prescriptions': [
          for (final r in rx)
            if (r.data['status'] != 'draft' &&
                t.scope.allows('${r.data['branchId']}'))
              {
                'prescriptionId': r.data['prescriptionId'],
                'consultationId': r.data['consultationId'],
                'number': r.data['number'],
                'version': r.data['version'],
                'status': r.data['status'],
                'doctorName': r.data['doctorName'],
                'medicineCount':
                    ((r.data['medicines'] as List?) ?? const []).length,
                'finalizedAt': ClinicalSupport.present({
                  'x': r.data['finalizedAt'],
                })['x'],
              },
        ],
        'followups': [for (final f in fu) ClinicalSupport.present(f.data)],
        'laboratory': labAvailable
            ? {
                'available': true,
                'reports': [
                  for (final r in labReports)
                    if (r.data['current'] == true &&
                        t.scope.allows('${r.data['branchId']}'))
                      {
                        'reportId': r.data['reportId'],
                        'reportNumber': r.data['reportNumber'],
                        'orderNumber': r.data['orderNumber'],
                        'version': r.data['version'],
                        'external': r.data['external'],
                        'label': r.data['label'],
                        'publishedAt': ClinicalSupport.present({
                          'x': r.data['publishedAt'],
                        })['x'],
                      },
                ],
              }
            : {
                'available': false,
                'note': 'The laboratory is not part of this clinic\'s plan.',
              },
      },
      page.meta,
    );
  }
}

/// Age in whole years (small helper so the workspace does not depend on the
/// patient services).
abstract final class PatientSupportAge {
  static int years(String dob, DateTime now) {
    final d = DateTime.tryParse(dob);
    if (d == null) return 0;
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) age--;
    return age;
  }
}
