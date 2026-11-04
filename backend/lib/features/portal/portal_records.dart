import '../../core/data/document_store.dart';
import '../auth/domain/auth_context.dart';
import 'portal_support.dart';

/// What a patient may read of their clinic records.
///
/// Every list is built from an allow-list of fields, never from a whole
/// document, and only for records of the subject's *linked* clinic record.
/// Drafts, clinician-only notes, observations, assessments, alerts, restricted
/// notes and records of other patients are never returned. Records stay
/// grouped by clinic: nothing is merged across clinics.
class PortalRecordsService {
  PortalRecordsService(this._s);

  final PortalSupport _s;

  Future<List<DocData>> _forPatient(
    ClinicLink link,
    String collection, {
    int limit = 100,
    List<QueryFilter> extra = const [],
  }) async {
    final rows = await _s.store.query(
      DocQuery(
        _s.path(link.tenantId, collection),
        filters: [
          QueryFilter('patientId', FilterOp.eq, link.patientId),
          ...extra,
        ],
        limit: limit,
      ),
    );
    return [for (final r in rows) r.data];
  }

  Future<CreateOp?> _audit(
    ClinicLink link,
    AuthContext ctx,
    String action,
  ) async {
    final t = await _s.actingIn(ctx, link.tenantId);
    return _s.audit(t, link, action);
  }

  /// Allergies, conditions, history and medicines recorded by the clinic.
  Future<List<Map<String, Object?>>> overview(
    AuthContext ctx, {
    String? accountId,
    String? clinicId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeRecords,
    );
    final out = <Map<String, Object?>>[];
    final audits = <WriteOp>[];
    for (final link in await _s.links(subject, clinicId: clinicId)) {
      final allergies = await _forPatient(link, 'patient_allergies');
      final history = await _forPatient(link, 'patient_history_entries');
      final meds = await _forPatient(link, 'patient_medications');
      out.add({
        'clinicId': link.tenantId,
        'clinicName': link.clinicName,
        'mrn': link.mrn,
        'allergies': [
          for (final a in allergies)
            if (a['status'] != 'inactive' && a['status'] != 'entered_in_error')
              PortalSupport.pick(a, [
                'allergen',
                'category',
                'reaction',
                'severity',
                'status',
              ]),
        ],
        'history': [
          for (final h in history)
            if (h['status'] != 'entered_in_error')
              PortalSupport.pick(h, [
                'category',
                'title',
                'description',
                'status',
                'onsetDate',
                'resolvedDate',
                'eventDate',
              ]),
        ],
        'medications': [
          for (final m in meds)
            if (m['status'] != 'entered_in_error')
              PortalSupport.pick(m, [
                'name',
                'strength',
                'dosage',
                'route',
                'frequency',
                'startDate',
                'endDate',
                'status',
              ]),
        ],
      });
      final a = await _audit(link, ctx, 'portal.records_viewed');
      if (a != null) audits.add(a);
    }
    if (audits.isNotEmpty) await _s.store.commit(audits);
    return out;
  }

  /// Summaries the treating doctor released. A draft, in-progress or unreleased
  /// consultation does not exist for the patient.
  Future<List<Map<String, Object?>>> consultations(
    AuthContext ctx, {
    String? accountId,
    String? clinicId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeRecords,
    );
    final out = <Map<String, Object?>>[];
    final audits = <WriteOp>[];
    for (final link in await _s.links(subject, clinicId: clinicId)) {
      final rows = await _forPatient(
        link,
        'consultations',
        extra: const [QueryFilter('releasedToPatient', FilterOp.eq, true)],
      );
      final rx = await _forPatient(link, 'prescriptions');
      for (final c in rows) {
        if (c['status'] != 'finalized' && c['status'] != 'amended') continue;
        final cid = c['consultationId'];
        final dx = await _s.store.query(
          DocQuery(
            _s.path(link.tenantId, 'diagnoses'),
            filters: [QueryFilter('consultationId', FilterOp.eq, cid)],
            limit: 30,
          ),
        );
        final plan =
            (c['treatmentPlan'] as Map?)?.cast<String, Object?>() ?? const {};
        final follow =
            (c['followUp'] as Map?)?.cast<String, Object?>() ?? const {};
        out.add({
          'clinicId': link.tenantId,
          'clinicName': link.clinicName,
          'consultationId': cid,
          'consultationAt': PortalSupport.clean({
            'x': c['consultationAt'],
          })['x'],
          'doctorName': c['doctorName'],
          'amended': c['status'] == 'amended',
          'diagnoses': [
            for (final d in dx)
              if (d.data['status'] == 'active')
                PortalSupport.pick(d.data, ['label', 'kind', 'certainty']),
          ],
          'advice': PortalSupport.pick(plan, [
            'recommendations',
            'lifestyle',
            'diet',
            'procedures',
            'patientInstructions',
          ]),
          'followUp': PortalSupport.pick(follow, [
            'required',
            'recommendedDate',
            'reason',
            'instructions',
          ]),
          'prescriptions': [
            for (final p in rx)
              if (p['consultationId'] == cid && p['status'] == 'finalized')
                {'prescriptionId': p['prescriptionId'], 'number': p['number']},
          ],
        });
      }
      final a = await _audit(link, ctx, 'portal.consultations_viewed');
      if (a != null) audits.add(a);
    }
    out.sort(
      (a, b) => '${b['consultationAt']}'.compareTo('${a['consultationAt']}'),
    );
    if (audits.isNotEmpty) await _s.store.commit(audits);
    return out;
  }

  /// Doctor-issued prescriptions (finalized only). The newest version of each
  /// is `current`; earlier versions stay readable as history. This is a record
  /// of what the doctor prescribed, not advice from the app.
  Future<List<Map<String, Object?>>> prescriptions(
    AuthContext ctx, {
    String? accountId,
    String? clinicId,
  }) async {
    final subject = await _s.subject(
      ctx,
      accountId,
      PortalSupport.scopeRecords,
    );
    final out = <Map<String, Object?>>[];
    final audits = <WriteOp>[];
    for (final link in await _s.links(subject, clinicId: clinicId)) {
      for (final p in await _forPatient(link, 'prescriptions')) {
        if (p['status'] != 'finalized' && p['status'] != 'amended') continue;
        out.add(
          {
            'clinicId': link.tenantId,
            'clinicName': link.clinicName,
            'prescriptionId': p['prescriptionId'],
            'number': p['number'],
            'version': p['version'],
            'issuedAt': PortalSupport.clean({'x': p['finalizedAt']})['x'],
            'doctorName': p['doctorName'],
            'medicines': [
              for (final m in (p['medicines'] as List? ?? const []))
                PortalSupport.pick((m as Map).cast<String, Object?>(), [
                  'name',
                  'genericName',
                  'strength',
                  'dosage',
                  'route',
                  'frequency',
                  'durationValue',
                  'durationUnit',
                  'foodRelation',
                  'instructions',
                  'warnings',
                ]),
            ],
            'notes': p['notes'],
            'current': p['status'] == 'finalized',
            'superseded': p['status'] == 'amended',
            'disclaimer':
                'Issued by your doctor. Follow your doctor\'s instructions.',
          }..removeWhere((k, v) => v == null),
        );
      }
      final a = await _audit(link, ctx, 'portal.prescriptions_viewed');
      if (a != null) audits.add(a);
    }
    out.sort((a, b) => '${b['issuedAt']}'.compareTo('${a['issuedAt']}'));
    if (audits.isNotEmpty) await _s.store.commit(audits);
    return out;
  }

  /// Documents and laboratory reports are not exposed yet: there is no release
  /// flag or staff workflow that marks a file as shared with the patient, and
  /// laboratory results arrive with Phase 9. Answering honestly beats guessing.
  Map<String, Object?> documents() => {
    'available': false,
    'documents': <Object?>[],
    'reports': <Object?>[],
    'note':
        'Documents and laboratory reports are not available in the app yet.',
  };
}
