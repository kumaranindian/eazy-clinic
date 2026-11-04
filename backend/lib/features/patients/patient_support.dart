import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/tenant_context.dart';

/// Shared helpers of the patient services: tenant/branch-checked loading,
/// patient audit records, revisions and consent lookups.
///
/// Every path is built from the caller's trusted tenant id; a patient outside
/// the caller's branch scope answers 404 so its existence is not revealed.
class PatientSupport {
  PatientSupport(this.d);

  final ClinicDeps d;

  String patientPath(TenantContext t, String id) => d.path(t, 'patients', id);

  /// The patient record, or 404 (missing, other tenant, or outside the
  /// caller's branches).
  Future<DocData> load(TenantContext t, String id) async {
    final p = await d.store.get(patientPath(t, id));
    return _check(t, p);
  }

  Future<DocData> loadIn(TxContext tx, TenantContext t, String id) async {
    final p = await tx.get(patientPath(t, id));
    return _check(t, p);
  }

  DocData _check(TenantContext t, DocData? p) {
    if (p == null || !t.scope.allows('${p['branchId']}')) {
      throw const ApiException.notFound('Patient not found.');
    }
    return p;
  }

  /// Patients that were archived or merged accept no further changes.
  void requireOpen(DocData p) {
    final s = p['status'];
    if (s == 'archived' || s == 'merged') {
      throw const ApiException.conflict(
        'This patient record is archived and cannot be changed.',
      );
    }
  }

  /// Age in whole years on [now] for an ISO date of birth.
  static int ageYears(String dob, DateTime now) {
    final d = DateTime.parse(dob);
    var age = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) {
      age--;
    }
    return age;
  }

  /// Age threshold for minors: a clinic setting (default 18).
  Future<int> minorAgeYears(TenantContext t) async {
    final s = await d.store.get(d.path(t, 'clinic_settings', 'operations'));
    final v = s?['minorAgeYears'];
    return v is int && v > 0 ? v : 18;
  }

  Future<bool> isMinor(TenantContext t, DocData patient) async =>
      ageYears(patient['dateOfBirth']! as String, d.now) <
      await minorAgeYears(t);

  /// Audit record for a patient (tenant scoped). Holds references and minimal
  /// metadata only, never clinical content.
  CreateOp auditOp(
    TenantContext t,
    String patientId,
    String? branchId,
    String action, {
    String resourceType = 'patient',
    String? resourceId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
    String? reason,
    String? requestId,
  }) => CreateOp(d.path(t, 'patient_audit_logs', newId()), {
    'tenantId': t.tenantId,
    'branchId': branchId,
    'patientId': patientId,
    'action': action,
    'resourceType': resourceType,
    'resourceId': resourceId ?? patientId,
    'actorUid': t.uid,
    'actorRole': t.actorLabel,
    'reason': reason,
    'requestId': requestId,
    'before': before,
    'after': after,
    'timestamp': d.now,
  });

  /// Standalone audit for reads of sensitive information.
  Future<void> recordAccess(
    TenantContext t,
    DocData patient,
    String action, {
    String resourceType = 'patient',
    String? resourceId,
    String? requestId,
  }) => d.store.commit([
    auditOp(
      t,
      patient['patientId']! as String,
      patient['branchId'] as String?,
      action,
      resourceType: resourceType,
      resourceId: resourceId,
      requestId: requestId,
    ),
  ]);

  /// Previous version of a changed record, kept so history is never lost.
  CreateOp revisionOp(
    TenantContext t,
    String patientId,
    String resourceType,
    String resourceId,
    DocData before,
  ) => CreateOp(d.path(t, 'patient_record_revisions', newId()), {
    'tenantId': t.tenantId,
    'patientId': patientId,
    'resourceType': resourceType,
    'resourceId': resourceId,
    'snapshot': before,
    'supersededAt': d.now,
    'supersededBy': t.uid,
  });

  /// Whether a granted, unexpired consent of [type] exists for the patient.
  Future<bool> hasConsent(
    TenantContext t,
    String patientId,
    String type, {
    TxContext? tx,
  }) async {
    final q = DocQuery(
      d.path(t, 'patient_consents'),
      filters: [
        QueryFilter('patientId', FilterOp.eq, patientId),
        QueryFilter('type', FilterOp.eq, type),
        const QueryFilter('status', FilterOp.eq, 'granted'),
      ],
      limit: 20,
    );
    final rows = tx == null ? await d.store.query(q) : await tx.query(q);
    final now = d.now;
    return rows.any((r) {
      final e = r.data['expiresAt'];
      return e == null || (e is DateTime && e.isAfter(now));
    });
  }

  Future<void> requireConsent(
    TenantContext t,
    String patientId,
    String type, {
    TxContext? tx,
  }) async {
    if (!await hasConsent(t, patientId, type, tx: tx)) {
      throw ApiException.conflict(
        'The patient has not given (or has revoked) consent for ${type.replaceAll('_', ' ')}.',
      );
    }
  }
}
