import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/tenant_context.dart';
import '../patients/consent_service.dart';
import '../platform/common/body_reader.dart';
import '../platform/common/paging.dart';
import '../scheduling/queue_service.dart';
import 'clinical_support.dart';

const List<String> consultationTypes = [
  'general',
  'follow_up',
  'review',
  'emergency',
];

/// Consultation lifecycle: `draft → in_progress → finalized → amended`.
/// No generic status endpoint exists: every change goes through a method that
/// checks the rules below.
class ConsultationService {
  ConsultationService(this._s, this._queue);

  final ClinicalSupport _s;
  final QueueService _queue;

  static const String collection = 'consultations';

  // -------------------------------------------------------------- create

  Future<Map<String, Object?>> create(
    TenantContext t,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.consultationsManage);
    final doctorId = await _s.requireDoctorSelf(t);
    final r = BodyReader(body)
      ..rejectUnknown({
        'patientId',
        'appointmentId',
        'branchId',
        'type',
        'templateId',
        ...ConsultationSections.names,
      });
    final patientId = r.str('patientId', max: 40);
    final appointmentId = r.str('appointmentId', max: 40, required: false);
    final branchParam = r.str('branchId', max: 40, required: false);
    final type =
        r.enumOf<String>(
          'type',
          consultationTypes,
          (v) => v,
          required: false,
        ) ??
        'general';
    final templateId = r.str('templateId', max: 40, required: false);
    final sections = ConsultationSections.parse(r);
    r.throwIfInvalid();

    final patient = await _s.patients.load(t, patientId!);
    if (patient['status'] != 'active') {
      throw const ApiException.conflict('The patient record is not active.');
    }
    await _s.patients.requireConsent(
      t,
      patientId,
      ConsentCatalog.dataProcessing,
    );
    String branchId;
    DocData? appt;
    if (appointmentId != null) {
      appt = await _s.d.store.get(_s.path(t, 'appointments', appointmentId));
      if (appt == null || !t.scope.allows('${appt['branchId']}')) {
        throw const ApiException.notFound('Appointment not found.');
      }
      if (appt['doctorId'] != doctorId || appt['patientId'] != patientId) {
        throw const ApiException.forbidden(
          'The appointment is not yours or belongs to another patient.',
        );
      }
      if (!const {
        'confirmed',
        'checked_in',
        'in_progress',
      }.contains(appt['status'])) {
        throw ApiException.conflict(
          'A ${appt['status']} appointment cannot start a consultation.',
        );
      }
      branchId = '${appt['branchId']}';
    } else {
      if (branchParam == null) {
        throw ApiException.validation([
          issue(
            'branchId',
            'required',
            'branchId is required without an appointment.',
          ),
        ]);
      }
      t.scope.require(branchParam);
      if (!await _s.sched.isAssigned(t, doctorId, branchParam)) {
        throw const ApiException.forbidden(
          'You are not assigned to this branch.',
        );
      }
      branchId = branchParam;
    }
    var content = <String, Object?>{
      for (final n in ConsultationSections.names) n: <String, Object?>{},
    };
    if (templateId != null) {
      final tpl = await _s.d.store.get(
        _s.path(t, 'clinical_templates', templateId),
      );
      final usable =
          tpl != null &&
          tpl['status'] == 'active' &&
          (tpl['scope'] == 'clinic' || tpl['doctorId'] == doctorId);
      if (!usable) {
        throw ApiException.validation([
          issue(
            'templateId',
            'invalid_template',
            'This template cannot be used.',
          ),
        ]);
      }
      content = ConsultationSections.merge(content, {
        for (final e in ((tpl['content'] as Map?) ?? const {}).entries)
          '${e.key}': (e.value as Map).cast<String, Object?>(),
      });
    }
    content = ConsultationSections.merge(content, sections);

    final doctor = await _s.sched.doctor(t, doctorId);
    final id = 'con_${newId(length: 14)}';
    final now = _s.d.now;
    final doc = <String, Object?>{
      'consultationId': id,
      'tenantId': t.tenantId,
      'branchId': branchId,
      'patientId': patientId,
      'patientName': patient['fullName'],
      'patientMrn': patient['mrn'],
      'doctorId': doctorId,
      'doctorName': doctor['fullName'],
      'appointmentId': appointmentId,
      'queueEntryId': appt?['queueEntryId'],
      'type': type,
      'status': 'draft',
      ...content,
      'templateId': templateId,
      'consultationAt': now,
      'startedAt': null,
      'finalizedAt': null,
      'finalizedBy': null,
      'revision': 0,
      'amendmentCount': 0,
      'version': 1,
      'createdAt': now,
      'updatedAt': now,
      'createdBy': t.uid,
      'updatedBy': t.uid,
    };
    try {
      await _s.d.store.commit([
        CreateOp(_s.path(t, collection, id), doc),
        // one open consultation per appointment
        if (appointmentId != null)
          CreateOp(_s.path(t, 'consultation_appointments', appointmentId), {
            'consultationId': id,
            'createdAt': now,
          }),
        _s.audit(
          t,
          action: 'consultation.created',
          resourceType: 'consultation',
          resourceId: id,
          branchId: branchId,
          patientId: patientId,
          consultationId: id,
          requestId: requestId,
          after: {
            'type': type,
            'appointmentId': appointmentId,
            'template': templateId,
          },
        ),
      ]);
    } on AlreadyExistsException {
      throw const ApiException.conflict(
        'A consultation already exists for this appointment.',
      );
    }
    return ClinicalSupport.present(doc);
  }

  // ---------------------------------------------------------------- read

  Future<Map<String, Object?>> detail(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.consultationsView);
    final c = await _s.consultation(t, id);
    final dx = await _diagnoses(t, id);
    final inv = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'investigation_requests'),
        filters: [QueryFilter('consultationId', FilterOp.eq, id)],
        limit: 50,
      ),
    );
    final rx = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'prescriptions'),
        filters: [QueryFilter('consultationId', FilterOp.eq, id)],
        limit: 50,
      ),
    );
    final fu = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'followups'),
        filters: [QueryFilter('consultationId', FilterOp.eq, id)],
        limit: 20,
      ),
    );
    await _s.d.store.commit([
      _s.audit(
        t,
        action: 'consultation.viewed',
        resourceType: 'consultation',
        resourceId: id,
        branchId: '${c['branchId']}',
        patientId: '${c['patientId']}',
        consultationId: id,
        requestId: requestId,
      ),
    ]);
    return {
      ...ClinicalSupport.present(c),
      'diagnoses': [for (final d in dx) ClinicalSupport.present(d)],
      'investigations': [for (final i in inv) ClinicalSupport.present(i.data)],
      'prescriptions': [
        for (final p in rx)
          {
            'prescriptionId': p.data['prescriptionId'],
            'number': p.data['number'],
            'status': p.data['status'],
            'version': p.data['version'],
            'medicineCount':
                ((p.data['medicines'] as List?) ?? const []).length,
          },
      ],
      'followups': [for (final f in fu) ClinicalSupport.present(f.data)],
    };
  }

  Future<List<DocData>> _diagnoses(
    TenantContext t,
    String consultationId, {
    TxContext? tx,
  }) async {
    final q = DocQuery(
      _s.path(t, 'diagnoses'),
      filters: [QueryFilter('consultationId', FilterOp.eq, consultationId)],
      limit: 100,
    );
    final rows = tx == null ? await _s.d.store.query(q) : await tx.query(q);
    final docs =
        [
          for (final r in rows)
            if (r.data['status'] == 'active') r.data,
        ]..sort((a, b) {
          const rank = {'primary': 0, 'secondary': 1, 'differential': 2};
          final byKind = (rank[a['kind']] ?? 3).compareTo(rank[b['kind']] ?? 3);
          return byKind != 0
              ? byKind
              : '${a['createdAt']}'.compareTo('${b['createdAt']}');
        });
    return docs;
  }

  // -------------------------------------------------------------- update

  Future<Map<String, Object?>> update(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.consultationsManage);
    final r = BodyReader(body)
      ..rejectUnknown({
        'expectedVersion',
        'type',
        ...ConsultationSections.names,
      });
    final expected = r.integer(
      'expectedVersion',
      min: 1,
      max: 100000,
      required: false,
    );
    final type = r.enumOf<String>(
      'type',
      consultationTypes,
      (v) => v,
      required: false,
    );
    final sections = ConsultationSections.parse(r);
    r.throwIfInvalid();
    if (sections.isEmpty && type == null) {
      throw const ApiException.badRequest('Nothing to update.');
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final cur = await _s.consultation(t, id, tx: tx);
      await _s.requireAuthor(t, cur);
      _s.requireOpen(cur);
      if (expected != null && expected != cur['version']) {
        throw const ApiException.conflict(
          'The consultation changed since you opened it. Reload before saving.',
        );
      }
      final merged = ConsultationSections.merge(
        ConsultationSections.contentOf(cur),
        sections,
      );
      final changed = ConsultationSections.changed(
        ConsultationSections.contentOf(cur),
        merged,
      );
      final patch = <String, Object?>{
        for (final n in changed) n: merged[n],
        'type': ?type,
        'updatedAt': now,
        'updatedBy': t.uid,
        'version': ((cur['version'] as int?) ?? 1) + 1,
      };
      tx.write([
        UpdateOp(_s.path(t, collection, id), patch),
        _s.audit(
          t,
          action: 'consultation.updated',
          resourceType: 'consultation',
          resourceId: id,
          branchId: '${cur['branchId']}',
          patientId: '${cur['patientId']}',
          consultationId: id,
          requestId: requestId,
          after: {'sections': changed, 'status': cur['status']},
        ),
      ]);
      return ClinicalSupport.present({...cur, ...patch});
    });
  }

  // --------------------------------------------------------------- start

  Future<Map<String, Object?>> start(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.consultationsManage);
    final cur = await _s.consultation(t, id);
    await _s.requireAuthor(t, cur);
    if (cur['status'] == 'in_progress') {
      return {...ClinicalSupport.present(cur), 'idempotentReplay': true};
    }
    if (cur['status'] != 'draft') {
      throw ApiException.conflict(
        'A ${cur['status']} consultation cannot be started.',
      );
    }
    // The linked visit follows: the patient must have checked in; a waiting
    // patient is called first, then the visit starts (Phase 5 services).
    final apptId = cur['appointmentId'] as String?;
    if (apptId != null) {
      final appt = await _s.d.store.get(_s.path(t, 'appointments', apptId));
      if (appt == null) {
        throw const ApiException.notFound('Appointment not found.');
      }
      if (appt['status'] == 'checked_in') {
        final entryId = appt['queueEntryId'] as String?;
        if (entryId == null) {
          throw const ApiException.conflict('The patient has no queue entry.');
        }
        final entry = await _s.d.store.get(
          _s.path(t, 'queue_entries', entryId),
        );
        if (entry?['status'] == 'waiting') {
          await _queue.transition(
            t,
            entryId,
            'called',
            action: 'call',
            permission: ClinicPermission.queueOperate,
            requestId: requestId,
          );
        }
        await _queue.transition(
          t,
          entryId,
          'in_progress',
          action: 'start',
          permission: ClinicPermission.queueConsult,
          requestId: requestId,
        );
      } else if (appt['status'] != 'in_progress') {
        throw ApiException.conflict(
          'The patient has not checked in (appointment is ${appt['status']}).',
        );
      }
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final fresh = await _s.consultation(t, id, tx: tx);
      if (fresh['status'] != 'draft') {
        throw const ApiException.conflict(
          'The consultation was already started.',
        );
      }
      final patch = {
        'status': 'in_progress',
        'startedAt': now,
        'updatedAt': now,
        'updatedBy': t.uid,
        'version': ((fresh['version'] as int?) ?? 1) + 1,
      };
      tx.write([
        UpdateOp(_s.path(t, collection, id), patch),
        _s.audit(
          t,
          action: 'consultation.started',
          resourceType: 'consultation',
          resourceId: id,
          branchId: '${fresh['branchId']}',
          patientId: '${fresh['patientId']}',
          consultationId: id,
          requestId: requestId,
          before: {'status': 'draft'},
          after: {'status': 'in_progress'},
        ),
      ]);
      return ClinicalSupport.present({...fresh, ...patch});
    });
  }

  // ------------------------------------------------------------ finalize

  Future<Map<String, Object?>> finalize(
    TenantContext t,
    String id, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.consultationsFinalize);
    final cur = await _s.consultation(t, id);
    await _s.requireAuthor(t, cur);
    // repeating the request returns the same result and writes nothing
    if (cur['status'] == 'finalized' || cur['status'] == 'amended') {
      return {...ClinicalSupport.present(cur), 'idempotentReplay': true};
    }
    if (cur['status'] != 'in_progress') {
      throw const ApiException.conflict(
        'Start the consultation before finalizing it.',
      );
    }
    _requireFinalizable(cur, await _diagnoses(t, id));
    // the visit is completed with the consultation
    final apptId = cur['appointmentId'] as String?;
    if (apptId != null) {
      final appt = await _s.d.store.get(_s.path(t, 'appointments', apptId));
      final entryId = appt?['queueEntryId'] as String?;
      if (appt?['status'] == 'in_progress' && entryId != null) {
        await _queue.transition(
          t,
          entryId,
          'completed',
          action: 'complete',
          permission: ClinicPermission.queueConsult,
          requestId: requestId,
        );
      }
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final fresh = await _s.consultation(t, id, tx: tx);
      if (fresh['status'] == 'finalized' || fresh['status'] == 'amended') {
        return {...ClinicalSupport.present(fresh), 'idempotentReplay': true};
      }
      final dx = await _diagnoses(t, id, tx: tx);
      _requireFinalizable(fresh, dx);
      final patch = {
        'status': 'finalized',
        'finalizedAt': now,
        'finalizedBy': t.uid,
        'updatedAt': now,
        'updatedBy': t.uid,
        'version': ((fresh['version'] as int?) ?? 1) + 1,
      };
      tx.write([
        UpdateOp(_s.path(t, collection, id), patch),
        // revision 0: the original record, kept forever
        CreateOp(_s.path(t, 'consultation_versions', '${id}_r0'), {
          'consultationId': id,
          'revision': 0,
          'content': ConsultationSections.contentOf(fresh),
          'diagnoses': [for (final d in dx) d],
          'createdAt': now,
          'createdBy': t.uid,
        }),
        _s.audit(
          t,
          action: 'consultation.finalized',
          resourceType: 'consultation',
          resourceId: id,
          branchId: '${fresh['branchId']}',
          patientId: '${fresh['patientId']}',
          consultationId: id,
          requestId: requestId,
          before: {'status': 'in_progress'},
          after: {'status': 'finalized', 'diagnoses': dx.length},
        ),
      ]);
      return ClinicalSupport.present({...fresh, ...patch});
    });
  }

  void _requireFinalizable(DocData c, List<DocData> dx) {
    final issues = [
      if (((c['chiefComplaint'] as Map?)?['reason'] as String?)
              ?.trim()
              .isEmpty ??
          true)
        issue(
          'chiefComplaint.reason',
          'required',
          'Record the main reason for the visit.',
        ),
      if (!dx.any((d) => d['kind'] == 'primary'))
        issue(
          'diagnoses',
          'primary_required',
          'Add a primary diagnosis (it may be provisional).',
        ),
    ];
    if (issues.isNotEmpty) throw ApiException.validation(issues);
  }

  // --------------------------------------------------------------- amend

  Future<Map<String, Object?>> amend(
    TenantContext t,
    String id,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.consultationsManage);
    final r = BodyReader(body)
      ..rejectUnknown({
        'reason',
        'diagnosisChanges',
        ...ConsultationSections.names,
      });
    final reason = r.str('reason', min: 5, max: 300);
    final sections = ConsultationSections.parse(r);
    final dxOps = _parseDiagnosisChanges(r);
    r.throwIfInvalid();
    final now = _s.d.now;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        return await _s.d.store.transaction((tx) async {
          final cur = await _s.consultation(t, id, tx: tx);
          await _s.requireAuthor(t, cur);
          if (cur['status'] != 'finalized' && cur['status'] != 'amended') {
            throw const ApiException.conflict(
              'Only a finalized consultation can be amended.',
            );
          }
          final before = ConsultationSections.contentOf(cur);
          final merged = ConsultationSections.merge(before, sections);
          final changedSections = ConsultationSections.changed(before, merged);
          final dxBefore = await _diagnoses(t, id, tx: tx);
          final dxWrites = <WriteOp>[];
          final dxChanged = <String>[];
          final dxAfter = _applyDiagnosisChanges(
            t,
            id,
            cur,
            dxBefore,
            dxOps,
            dxWrites,
            dxChanged,
            now,
          );
          if (changedSections.isEmpty && dxChanged.isEmpty) {
            throw ApiException.validation([
              issue('changes', 'no_changes', 'The amendment changes nothing.'),
            ]);
          }
          if (!dxAfter.any((d) => d['kind'] == 'primary')) {
            throw ApiException.validation([
              issue(
                'diagnosisChanges',
                'primary_required',
                'A primary diagnosis must remain.',
              ),
            ]);
          }
          final revision = ((cur['revision'] as int?) ?? 0) + 1;
          final amendmentId = 'amd_${newId(length: 12)}';
          final patch = <String, Object?>{
            for (final n in changedSections) n: merged[n],
            'status': 'amended',
            'revision': revision,
            'amendmentCount': ((cur['amendmentCount'] as int?) ?? 0) + 1,
            'updatedAt': now,
            'updatedBy': t.uid,
            'version': ((cur['version'] as int?) ?? 1) + 1,
          };
          tx.write([
            UpdateOp(_s.path(t, collection, id), patch),
            ...dxWrites,
            CreateOp(_s.path(t, 'consultation_amendments', amendmentId), {
              'amendmentId': amendmentId,
              'consultationId': id,
              'patientId': cur['patientId'],
              'branchId': cur['branchId'],
              'revision': revision,
              'reason': reason,
              'changedSections': changedSections,
              'changedDiagnoses': dxChanged,
              'before': {for (final n in changedSections) n: before[n]},
              'after': {for (final n in changedSections) n: merged[n]},
              'amendedBy': t.uid,
              'amendedByRole': t.role.wireName,
              'amendedAt': now,
            }),
            // full copy of the record as it is after this revision
            CreateOp(_s.path(t, 'consultation_versions', '${id}_r$revision'), {
              'consultationId': id,
              'revision': revision,
              'content': merged,
              'diagnoses': dxAfter,
              'createdAt': now,
              'createdBy': t.uid,
            }),
            _s.audit(
              t,
              action: 'consultation.amended',
              resourceType: 'consultation',
              resourceId: id,
              branchId: '${cur['branchId']}',
              patientId: '${cur['patientId']}',
              consultationId: id,
              reason: reason,
              requestId: requestId,
              before: {'status': cur['status'], 'revision': revision - 1},
              after: {
                'status': 'amended',
                'revision': revision,
                'sections': changedSections,
                'diagnoses': dxChanged,
              },
            ),
          ]);
          return {
            ...ClinicalSupport.present({...cur, ...patch}),
            'amendmentId': amendmentId,
          };
        });
      } on AlreadyExistsException {
        continue; // a concurrent amendment took the revision: look again
      }
    }
    throw const ApiException.conflict(
      'The consultation is being amended. Try again.',
    );
  }

  /// The amendment list and the stored versions of one consultation.
  Future<Map<String, Object?>> amendments(
    TenantContext t,
    String id,
    Request req,
  ) async {
    t.require(ClinicPermission.consultationsView);
    final c = await _s.consultation(t, id);
    final page = await runPaged(
      _s.d.store,
      DocQuery(
        _s.path(t, 'consultation_amendments'),
        filters: [QueryFilter('consultationId', FilterOp.eq, id)],
        orderBy: const OrderBy('amendedAt', descending: true),
      ),
      req,
    );
    final versions = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'consultation_versions'),
        filters: [QueryFilter('consultationId', FilterOp.eq, id)],
        limit: 50,
      ),
    );
    return {
      'consultationId': id,
      'status': c['status'],
      'revision': c['revision'],
      'amendments': [
        for (final a in page.docs) ClinicalSupport.present(a.data),
      ],
      'versions': [
        for (final v
            in versions..sort(
              (a, b) => ((a.data['revision'] as int?) ?? 0).compareTo(
                (b.data['revision'] as int?) ?? 0,
              ),
            ))
          ClinicalSupport.present(v.data),
      ],
      'hasMore': page.meta.hasMore,
    };
  }

  // ----------------------------------------------------------- diagnoses

  static const Set<String> _dxFields = {
    'kind',
    'certainty',
    'label',
    'description',
    'code',
    'codeSystem',
    'catalogueId',
    'notes',
  };

  Map<String, Object?> _parseDiagnosis(BodyReader r, {required bool partial}) {
    final kind = r.enumOf<String>(
      'kind',
      const ['primary', 'secondary', 'differential'],
      (v) => v,
      required: !partial,
    );
    final certainty = r.enumOf<String>(
      'certainty',
      const ['provisional', 'confirmed'],
      (v) => v,
      required: !partial,
    );
    return {
      'kind': ?kind,
      'certainty': ?certainty,
      'label': ?r.str('label', min: 2, max: 200, required: false),
      'description': ?r.str('description', max: 500, required: false),
      'code': ?r.str('code', max: 20, required: false),
      'codeSystem': ?r.str('codeSystem', max: 30, required: false),
      'catalogueId': ?r.str('catalogueId', max: 40, required: false),
      'notes': ?r.str('notes', max: 1000, required: false),
    };
  }

  /// Resolves a catalogue entry: label and code come from the catalogue, never
  /// from the client (codes are not invented).
  Future<Map<String, Object?>> _withCatalogue(
    TenantContext t,
    Map<String, Object?> fields, {
    DocData? current,
    TxContext? tx,
  }) async {
    final out = {...fields};
    final cid = fields['catalogueId'] as String?;
    if (cid != null) {
      final p = _s.path(t, 'diagnosis_catalogue', cid);
      final entry = tx == null ? await _s.d.store.get(p) : await tx.get(p);
      if (entry == null || entry['status'] != 'active') {
        throw ApiException.validation([
          issue(
            'catalogueId',
            'invalid_catalogue_entry',
            'This catalogue entry does not exist or is inactive.',
          ),
        ]);
      }
      out['label'] = entry['name'];
      out['code'] = entry['code'];
      out['codeSystem'] = entry['codeSystem'];
      return out;
    }
    if ((fields.containsKey('code') || fields.containsKey('codeSystem')) &&
        (fields['code'] == null) != (fields['codeSystem'] == null)) {
      throw ApiException.validation([
        issue(
          'code',
          'code_system_required',
          'Give the code together with the code system it comes from.',
        ),
      ]);
    }
    return out;
  }

  Future<Map<String, Object?>> addDiagnosis(
    TenantContext t,
    String consultationId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.consultationsManage);
    final r = BodyReader(body)..rejectUnknown(_dxFields);
    var fields = _parseDiagnosis(r, partial: false);
    r.throwIfInvalid();
    if (fields['label'] == null && fields['catalogueId'] == null) {
      throw ApiException.validation([
        issue(
          'label',
          'required',
          'Name the diagnosis or choose one from the catalogue.',
        ),
      ]);
    }
    final id = 'dx_${newId(length: 12)}';
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final c = await _s.consultation(t, consultationId, tx: tx);
      await _s.requireAuthor(t, c);
      _s.requireOpen(c);
      fields = await _withCatalogue(t, fields, tx: tx);
      final existing = await _diagnoses(t, consultationId, tx: tx);
      if (existing.length >= 20) {
        throw const ApiException.conflict(
          'At most 20 diagnoses per consultation.',
        );
      }
      if (fields['kind'] == 'primary' &&
          existing.any((d) => d['kind'] == 'primary')) {
        throw const ApiException.conflict(
          'There is already a primary diagnosis. Change it to secondary first.',
        );
      }
      final doc = <String, Object?>{
        'diagnosisId': id,
        'consultationId': consultationId,
        'tenantId': t.tenantId,
        'branchId': c['branchId'],
        'patientId': c['patientId'],
        'doctorId': c['doctorId'],
        ...fields,
        'status': 'active',
        'createdAt': now,
        'updatedAt': now,
        'createdBy': t.uid,
        'updatedBy': t.uid,
        'version': 1,
      };
      tx.write([
        CreateOp(_s.path(t, 'diagnoses', id), doc),
        _s.audit(
          t,
          action: 'diagnosis.added',
          resourceType: 'diagnosis',
          resourceId: id,
          branchId: '${c['branchId']}',
          patientId: '${c['patientId']}',
          consultationId: consultationId,
          requestId: requestId,
          after: {
            'kind': fields['kind'],
            'certainty': fields['certainty'],
            'code': fields['code'],
          },
        ),
      ]);
      return ClinicalSupport.present(doc);
    });
  }

  Future<Map<String, Object?>> updateDiagnosis(
    TenantContext t,
    String consultationId,
    String diagnosisId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.consultationsManage);
    final r = BodyReader(body, partial: true)
      ..rejectUnknown({..._dxFields, 'status'});
    var fields = _parseDiagnosis(r, partial: true);
    final remove = r.enumOf<String>(
      'status',
      const ['removed'],
      (v) => v,
      required: false,
    );
    r.throwIfInvalid();
    if (fields.isEmpty && remove == null) {
      throw const ApiException.badRequest('Nothing to update.');
    }
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final c = await _s.consultation(t, consultationId, tx: tx);
      await _s.requireAuthor(t, c);
      _s.requireOpen(c);
      final path = _s.path(t, 'diagnoses', diagnosisId);
      final cur = await tx.get(path);
      if (cur == null ||
          cur['consultationId'] != consultationId ||
          cur['status'] != 'active') {
        throw const ApiException.notFound('Diagnosis not found.');
      }
      fields = await _withCatalogue(t, fields, current: cur, tx: tx);
      if (fields['kind'] == 'primary' && cur['kind'] != 'primary') {
        final others = await _diagnoses(t, consultationId, tx: tx);
        if (others.any((d) => d['kind'] == 'primary')) {
          throw const ApiException.conflict(
            'There is already a primary diagnosis. Change it to secondary first.',
          );
        }
      }
      final patch = {
        ...fields,
        'status': ?remove,
        'updatedAt': now,
        'updatedBy': t.uid,
        'version': ((cur['version'] as int?) ?? 1) + 1,
      };
      tx.write([
        UpdateOp(path, patch),
        _s.audit(
          t,
          action: remove != null ? 'diagnosis.removed' : 'diagnosis.updated',
          resourceType: 'diagnosis',
          resourceId: diagnosisId,
          branchId: '${c['branchId']}',
          patientId: '${c['patientId']}',
          consultationId: consultationId,
          requestId: requestId,
          before: {'kind': cur['kind'], 'certainty': cur['certainty']},
          after: {'fields': fields.keys.toList(), 'removed': remove != null},
        ),
      ]);
      return ClinicalSupport.present({...cur, ...patch});
    });
  }

  // -------- diagnosis changes inside an amendment (finalized records)

  List<Map<String, Object?>> _parseDiagnosisChanges(BodyReader r) {
    if (!r.has('diagnosisChanges')) return const [];
    final raw = r.body['diagnosisChanges'];
    if (raw is! List || raw.length > 20) {
      r.addIssue('diagnosisChanges', 'invalid_value', 'Give up to 20 changes.');
      return const [];
    }
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) {
        r.addIssue(
          'diagnosisChanges[$i]',
          'invalid_type',
          'Must be an object.',
        );
        continue;
      }
      final c = BodyReader(item.cast<String, Object?>(), partial: true)
        ..rejectUnknown({..._dxFields, 'op', 'diagnosisId'});
      final op = c.enumOf<String>('op', const [
        'add',
        'update',
        'remove',
      ], (v) => v);
      final did = c.str('diagnosisId', max: 40, required: false);
      final fields = _parseDiagnosis(c, partial: op != 'add');
      for (final x in c.issues) {
        r.addIssue('diagnosisChanges[$i].${x.field}', x.code, x.message);
      }
      if (op != 'add' && did == null) {
        r.addIssue(
          'diagnosisChanges[$i].diagnosisId',
          'required',
          'diagnosisId is required.',
        );
      }
      out.add({'op': op, 'diagnosisId': did, ...fields});
    }
    return out;
  }

  List<DocData> _applyDiagnosisChanges(
    TenantContext t,
    String consultationId,
    DocData c,
    List<DocData> current,
    List<Map<String, Object?>> ops,
    List<WriteOp> writes,
    List<String> changed,
    DateTime now,
  ) {
    final list = [
      for (final d in current) {...d},
    ];
    for (final o in ops) {
      final op = o['op'];
      final fields = {...o}
        ..remove('op')
        ..remove('diagnosisId');
      if (op == 'add') {
        final id = 'dx_${newId(length: 12)}';
        final doc = <String, Object?>{
          'diagnosisId': id,
          'consultationId': consultationId,
          'tenantId': t.tenantId,
          'branchId': c['branchId'],
          'patientId': c['patientId'],
          'doctorId': c['doctorId'],
          ...fields,
          'status': 'active',
          'createdAt': now,
          'updatedAt': now,
          'createdBy': t.uid,
          'updatedBy': t.uid,
          'version': 1,
        };
        if (doc['label'] == null) {
          throw ApiException.validation([
            issue(
              'diagnosisChanges',
              'label_required',
              'Name the new diagnosis.',
            ),
          ]);
        }
        list.add(doc);
        writes.add(CreateOp(_s.path(t, 'diagnoses', id), doc));
        changed.add('added:$id');
      } else {
        final i = list.indexWhere((d) => d['diagnosisId'] == o['diagnosisId']);
        if (i < 0) {
          throw const ApiException.notFound('Diagnosis not found.');
        }
        final patch = op == 'remove' ? {'status': 'removed'} : fields;
        final next = {
          ...list[i],
          ...patch,
          'updatedAt': now,
          'updatedBy': t.uid,
        };
        if (op == 'remove') {
          list.removeAt(i);
        } else {
          list[i] = next;
        }
        writes.add(
          UpdateOp(_s.path(t, 'diagnoses', '${o['diagnosisId']}'), {
            ...patch,
            'updatedAt': now,
            'updatedBy': t.uid,
            'version': ((next['version'] as int?) ?? 1) + 1,
          }),
        );
        changed.add(
          '${op == 'remove' ? 'removed' : 'updated'}:${o['diagnosisId']}',
        );
      }
    }
    if (list.where((d) => d['kind'] == 'primary').length > 1) {
      throw const ApiException.conflict(
        'Only one primary diagnosis is allowed.',
      );
    }
    return list;
  }

  // ------------------------------------------------------- investigations

  Future<Map<String, Object?>> requestInvestigation(
    TenantContext t,
    String consultationId,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.investigationsRequest);
    final r = BodyReader(body)
      ..rejectUnknown({
        'testName',
        'code',
        'indication',
        'priority',
        'instructions',
      });
    final testName = r.str('testName', min: 2, max: 120);
    final code = r.str('code', max: 30, required: false);
    final indication = r.str('indication', min: 3, max: 300);
    final priority = r.enumOf<String>(
      'priority',
      const ['routine', 'urgent', 'stat'],
      (v) => v,
      required: false,
    );
    final instructions = r.str('instructions', max: 300, required: false);
    r.throwIfInvalid();
    final id = 'inv_${newId(length: 12)}';
    final now = _s.d.now;
    return _s.d.store.transaction((tx) async {
      final c = await _s.consultation(t, consultationId, tx: tx);
      await _s.requireAuthor(t, c);
      _s.requireOpen(c);
      final doc = <String, Object?>{
        'investigationId': id,
        'consultationId': consultationId,
        'tenantId': t.tenantId,
        'branchId': c['branchId'],
        'patientId': c['patientId'],
        'doctorId': c['doctorId'],
        'testName': testName,
        'code': code,
        'indication': indication,
        'priority': priority ?? 'routine',
        'instructions': instructions,
        // Phase 9 will pick requests up; until then nothing processes them
        'status': 'requested',
        'processing': 'not_available',
        'requestedBy': t.uid,
        'requestedAt': now,
      };
      tx.write([
        CreateOp(_s.path(t, 'investigation_requests', id), doc),
        _s.audit(
          t,
          action: 'investigation.requested',
          resourceType: 'investigation',
          resourceId: id,
          branchId: '${c['branchId']}',
          patientId: '${c['patientId']}',
          consultationId: consultationId,
          requestId: requestId,
          after: {'priority': doc['priority']},
        ),
      ]);
      return ClinicalSupport.present(doc);
    });
  }

  Future<List<Map<String, Object?>>> investigations(
    TenantContext t,
    String consultationId,
  ) async {
    t.require(ClinicPermission.consultationsView);
    await _s.consultation(t, consultationId);
    final rows = await _s.d.store.query(
      DocQuery(
        _s.path(t, 'investigation_requests'),
        filters: [QueryFilter('consultationId', FilterOp.eq, consultationId)],
        limit: 100,
      ),
    );
    return [for (final r in rows) ClinicalSupport.present(r.data)];
  }
}
