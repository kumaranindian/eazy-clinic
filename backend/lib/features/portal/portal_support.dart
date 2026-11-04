import 'package:common_models/common_models.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../auth/domain/auth_context.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/tenant_context.dart';
import '../patients/family_service.dart';
import '../patients/patient_support.dart';
import '../platform/entitlements/entitlement_service.dart';
import '../scheduling/scheduling_support.dart';

/// The person a request is about: the caller, or someone the caller is
/// authorized for through an active, verified family relationship.
class Subject {
  const Subject({
    required this.account,
    required this.isSelf,
    required this.allowedTenants,
  });

  final DocData account;
  final bool isSelf;

  /// Clinics the relationship allows; `null` means every clinic.
  final Set<String?>? allowedTenants;

  String get accountId => account['accountId']! as String;

  bool allows(String tenantId) =>
      isSelf ||
      allowedTenants == null ||
      allowedTenants!.contains(null) ||
      allowedTenants!.contains(tenantId);
}

/// A verified link between a patient account and one clinic's patient record.
class ClinicLink {
  const ClinicLink({
    required this.tenantId,
    required this.patientId,
    required this.accountId,
    this.mrn,
    this.clinicName,
  });

  final String tenantId;
  final String patientId;
  final String accountId;
  final String? mrn;
  final String? clinicName;
}

/// Shared rules of the patient portal.
///
/// Identity is never taken from the request: the caller is the verified
/// Firebase user, their patient account is found by uid, other people are
/// reached only through verified relationships, and a clinic record only
/// through an existing link (made with a clinic-issued code). Discovering a
/// clinic grants no access to any record.
class PortalSupport {
  PortalSupport(this.d, this.accounts, this.patients, this.sched);

  final ClinicDeps d;
  final PatientAccountService accounts;
  final PatientSupport patients;
  final SchedulingSupport sched;

  DocumentStore get store => d.store;

  /// Scope names (see `familyScopes`) used by the portal.
  static const String scopeAppointments = 'manage_appointments';
  static const String scopeRecords = 'view_records';
  static const String scopeConsent = 'give_consent';

  /// Resolves who the request is about. [accountId] is a selector, never a
  /// grant: anyone other than the caller needs a relationship with [scope].
  Future<Subject> subject(
    AuthContext ctx,
    String? accountId,
    String scope,
  ) async {
    final me = await accounts.requireAccount(ctx);
    final mine = me['accountId']! as String;
    if (accountId == null || accountId == mine) {
      return Subject(account: me, isSelf: true, allowedTenants: null);
    }
    final allowed = await accounts.allowedTenants(mine, accountId, scope);
    final other = allowed == null
        ? null
        : await store.get('patient_accounts/$accountId');
    if (allowed == null || other == null || other['status'] != 'active') {
      throw const ApiException.notFound('Patient not found.');
    }
    return Subject(account: other, isSelf: false, allowedTenants: allowed);
  }

  /// The subject's active clinic links, limited to what the relationship allows.
  Future<List<ClinicLink>> links(Subject s, {String? clinicId}) async {
    final rows = await store.query(
      DocQuery(
        'patient_clinic_links',
        filters: [
          QueryFilter('accountId', FilterOp.eq, s.accountId),
          const QueryFilter('status', FilterOp.eq, 'linked'),
        ],
        limit: 100,
      ),
    );
    return [
      for (final r in rows)
        if (s.allows('${r.data['tenantId']}') &&
            (clinicId == null || r.data['tenantId'] == clinicId))
          ClinicLink(
            tenantId: '${r.data['tenantId']}',
            patientId: '${r.data['patientId']}',
            accountId: s.accountId,
            mrn: r.data['mrn'] as String?,
            clinicName: r.data['clinicName'] as String?,
          ),
    ];
  }

  Future<ClinicLink> requireLink(Subject s, String clinicId) async {
    final l = await links(s, clinicId: clinicId);
    if (l.isEmpty) {
      throw const ApiException.notFound(
        'You are not linked to this clinic. Link your record with a code from the clinic first.',
      );
    }
    return l.first;
  }

  /// A clinic is open to patients when it is active, not blocked, and its plan
  /// includes the patient app.
  Future<bool> discoverable(String tenantId) async {
    final t = await store.get('tenants/$tenantId');
    if (t == null || t['status'] != 'active') return false;
    final ent = await d.entitlements.forTenant(tenantId);
    return ent.accessLevel != AccessLevel.blocked &&
        ent.features[FeatureKey.patientMobileApp] == true;
  }

  /// The context used to call the shared services for [tenantId]. Writes are
  /// refused for read-only clinics, like for staff.
  Future<PatientActingContext> actingIn(
    AuthContext ctx,
    String tenantId, {
    bool write = false,
  }) async {
    final ent = await d.entitlements.forTenant(tenantId);
    if (ent.accessLevel == AccessLevel.blocked ||
        ent.features[FeatureKey.patientMobileApp] != true) {
      throw const ApiException.forbidden(
        'This clinic is not available in the patient app.',
      );
    }
    if (write && !ent.writesAllowed) {
      throw const ApiException.forbidden(
        'This clinic is not accepting changes right now.',
      );
    }
    return PatientActingContext(
      tenantId: tenantId,
      uid: ctx.user.uid,
      entitlements: ent,
    );
  }

  String path(String tenantId, String collection, [String? id]) =>
      'tenants/$tenantId/$collection${id == null ? '' : '/$id'}';

  /// Audit entry in the clinic's patient audit trail.
  CreateOp audit(
    PatientActingContext t,
    ClinicLink link,
    String action, {
    String resourceType = 'patient',
    String? resourceId,
    String? requestId,
    Map<String, Object?>? after,
  }) => CreateOp(path(t.tenantId, 'patient_audit_logs', newId()), {
    'tenantId': t.tenantId,
    'patientId': link.patientId,
    'accountId': link.accountId,
    'action': action,
    'resourceType': resourceType,
    'resourceId': resourceId ?? link.patientId,
    'actorUid': t.uid,
    'actorRole': 'patient',
    'requestId': requestId,
    'after': after,
    'timestamp': d.now,
  });

  static Map<String, Object?> clean(Object? v) =>
      ((_safe(v) as Map?) ?? const {}).cast<String, Object?>();

  static Object? _safe(Object? v) {
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is Map) {
      return {for (final e in v.entries) '${e.key}': _safe(e.value)};
    }
    if (v is List) return v.map(_safe).toList();
    return v;
  }

  /// Copies only the named fields (an allow-list, never a deny-list).
  static Map<String, Object?> pick(DocData doc, Iterable<String> fields) =>
      clean({
        for (final f in fields)
          if (doc.containsKey(f)) f: doc[f],
      });
}
