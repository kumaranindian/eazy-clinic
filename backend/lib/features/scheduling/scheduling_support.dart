import 'package:common_models/common_models.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/tenant_context.dart';
import 'time_support.dart';

/// Shared checks of the scheduling services: entitlement, tenant/branch
/// loading, doctor assignment, doctor-owner detection and audit records.
class SchedulingSupport {
  SchedulingSupport(this.d);

  final ClinicDeps d;

  /// The subscription must include appointments.
  void requireFeature(TenantContext t) {
    if (t.entitlements.features[FeatureKey.appointments] != true) {
      throw const ApiException.forbidden(
        'Your subscription does not include appointments.',
      );
    }
  }

  /// An active branch inside the caller's scope (404 otherwise).
  Future<DocData> branch(
    TenantContext t,
    String branchId, {
    bool mustBeActive = true,
  }) async {
    t.scope.require(branchId);
    final b = await d.store.get(d.path(t, 'branches', branchId));
    if (b == null) throw const ApiException.notFound('Branch not found.');
    if (mustBeActive && b['status'] != 'active') {
      throw const ApiException.conflict('The branch is not active.');
    }
    return b;
  }

  /// Time zone of a branch: its own setting, else the clinic's, else India.
  Future<ClinicZone> zoneFor(TenantContext t, DocData branch) async {
    final own = branch['timezone'] as String?;
    if (own != null && own.isNotEmpty) return ClinicZone.resolve(own);
    final s = await d.store.get(d.path(t, 'clinic_settings', 'operations'));
    return ClinicZone.resolve(s?['timezone'] as String?);
  }

  Future<DocData> settings(TenantContext t) async =>
      await d.store.get(d.path(t, 'clinic_settings', 'operations')) ?? {};

  /// The doctor profile (404 when missing).
  Future<DocData> doctor(TenantContext t, String doctorId) async {
    final doc = await d.store.get(d.path(t, 'doctors', doctorId));
    if (doc == null) throw const ApiException.notFound('Doctor not found.');
    return doc;
  }

  /// Whether the doctor is actively assigned to the branch.
  Future<bool> isAssigned(
    TenantContext t,
    String doctorId,
    String branchId,
  ) async {
    final key = await d.store.get(
      d.path(t, 'doctor_branch_active', '${doctorId}_$branchId'),
    );
    if (key == null) return false;
    final a = await d.store.get(
      d.path(t, 'doctor_branch_assignments', '${key['assignmentId']}'),
    );
    return a != null && a['status'] == 'active';
  }

  /// An active doctor that works at [branchId]; otherwise 409/404.
  Future<DocData> assignedDoctor(
    TenantContext t,
    String doctorId,
    String branchId,
  ) async {
    final doc = await doctor(t, doctorId);
    if (doc['status'] != 'active') {
      throw const ApiException.conflict('The doctor is not active.');
    }
    if (!await isAssigned(t, doctorId, branchId)) {
      throw const ApiException.conflict(
        'The doctor is not assigned to this branch.',
      );
    }
    return doc;
  }

  /// The doctor profile linked to the caller's login (doctors only).
  Future<String?> ownDoctorId(TenantContext t) async {
    final m = await d.store.get(d.path(t, 'members', t.uid));
    return m?['doctorId'] as String?;
  }

  /// A doctor may act only for their own profile; others need the full
  /// permission.
  Future<void> requireManageDoctor(
    TenantContext t,
    String doctorId, {
    required String all,
    required String own,
  }) async {
    if (t.can(all)) return;
    if (t.can(own) && await ownDoctorId(t) == doctorId) return;
    throw const ApiException.forbidden();
  }

  /// Audit record of an appointment or queue event (tenant scoped).
  CreateOp audit(
    TenantContext t, {
    required String action,
    required String resourceType,
    required String resourceId,
    String? branchId,
    String? appointmentId,
    String? queueEntryId,
    String? reason,
    String? requestId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) => CreateOp(d.path(t, 'appointment_audit_logs', newId()), {
    'tenantId': t.tenantId,
    'branchId': branchId,
    'appointmentId': appointmentId,
    'queueEntryId': queueEntryId,
    'action': action,
    'resourceType': resourceType,
    'resourceId': resourceId,
    'actorUid': t.uid,
    'actorRole': t.role.wireName,
    'reason': reason,
    'requestId': requestId,
    'before': before,
    'after': after,
    'timestamp': d.now,
  });
}
