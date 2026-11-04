import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';

import '../../core/data/document_store.dart';
import '../../core/errors/api_exception.dart';
import '../../core/ids.dart';
import '../clinic/common/clinic_deps.dart';
import '../clinic/common/object_storage.dart';
import '../clinic/common/tenant_context.dart';
import '../patients/patient_support.dart';
import '../portal/portal_notifier.dart';
import '../scheduling/scheduling_support.dart';
import '../scheduling/time_support.dart';

FieldIssue labIssue(String f, String code, String m) =>
    FieldIssue(field: f, code: code, message: m);

const List<String> labCategories = [
  'hematology',
  'biochemistry',
  'clinical_pathology',
  'microbiology',
  'serology',
  'immunology',
  'other',
];

const List<String> sampleTypes = [
  'blood',
  'serum',
  'plasma',
  'urine',
  'stool',
  'swab',
  'sputum',
  'tissue',
  'csf',
  'other',
];

const List<String> labPriorities = ['routine', 'urgent', 'emergency'];

/// Order lifecycle. Moves not listed here are refused by the backend.
const Map<String, Set<String>> orderTransitions = {
  'requested': {'accepted', 'rejected', 'cancelled'},
  'accepted': {'sample_pending', 'cancelled'},
  'sample_pending': {'sample_collected', 'recollection_required', 'cancelled'},
  'recollection_required': {'sample_pending', 'cancelled'},
  'sample_collected': {'processing', 'recollection_required', 'cancelled'},
  'processing': {'result_entered', 'cancelled'},
  'result_entered': {'verification_pending', 'processing'},
  'verification_pending': {'verified', 'processing'},
  'verified': {'published', 'verification_pending'},
  'published': {'verification_pending'},
  'rejected': <String>{},
  'cancelled': <String>{},
};

/// Statuses in which an order still holds its "one active request per
/// consultation and test" key.
const Set<String> openOrderStatuses = {
  'requested',
  'accepted',
  'sample_pending',
  'recollection_required',
  'sample_collected',
  'processing',
  'result_entered',
  'verification_pending',
  'verified',
  'published',
};

/// Shared rules of the laboratory services: scope, numbering, status
/// history and the audit trail.
class LabSupport {
  LabSupport(this.d, this.patients, this.sched, this.storage);

  final ClinicDeps d;
  final PatientSupport patients;
  final SchedulingSupport sched;
  final ObjectStorage storage;

  /// Set by the clinic module so publication can reach the patient app.
  PortalNotifier? notifier;

  String path(TenantContext t, String collection, [String? id]) =>
      d.path(t, collection, id);

  void requireFeature(TenantContext t) {
    if (t.entitlements.features[FeatureKey.laboratory] != true) {
      throw const ApiException.forbidden(
        'Your subscription does not include the laboratory.',
      );
    }
  }

  Future<ClinicZone> zone(TenantContext t) async {
    final s = await d.store.get(path(t, 'clinic_settings', 'operations'));
    return ClinicZone.resolve(s?['timezone'] as String?);
  }

  /// Filters that keep a list inside the caller's branches.
  List<QueryFilter> scopeFilters(TenantContext t, String? branchId) {
    if (branchId != null) {
      t.scope.require(branchId);
      return [QueryFilter('branchId', FilterOp.eq, branchId)];
    }
    if (t.scope.allBranches) return const [];
    if (t.scope.branchIds.length > 30) {
      throw const ApiException.forbidden(
        'Your branch access is too broad to list this; ask for all-branch access.',
      );
    }
    return [
      QueryFilter('branchId', FilterOp.inList, t.scope.branchIds.toList()),
    ];
  }

  CreateOp audit(
    TenantContext t, {
    required String action,
    required String resourceType,
    required String resourceId,
    String? branchId,
    String? patientId,
    String? orderId,
    String? reason,
    String? requestId,
    Map<String, Object?>? before,
    Map<String, Object?>? after,
  }) => CreateOp(path(t, 'lab_audit_logs', newId()), {
    'tenantId': t.tenantId,
    'branchId': branchId,
    'patientId': patientId,
    'orderId': orderId,
    'action': action,
    'resourceType': resourceType,
    'resourceId': resourceId,
    'actorUid': t.uid,
    'actorRole': t.actorLabel,
    'reason': reason,
    'requestId': requestId,
    'before': before,
    'after': after,
    'timestamp': d.now,
  });

  /// Next `PREFIX-000001` number, written with the caller's transaction so
  /// concurrent callers cannot receive the same one.
  Future<String> nextNumber(
    TxContext tx,
    TenantContext t,
    List<WriteOp> ops, {
    required String counter,
    required String prefix,
    required String keys,
    required String ownerId,
  }) async {
    final cp = path(t, 'counters', counter);
    final c = await tx.get(cp);
    final n = ((c?['next'] as int?) ?? 0) + 1;
    final number = '$prefix-${n.toString().padLeft(6, '0')}';
    ops
      ..add(c == null ? CreateOp(cp, {'next': n}) : UpdateOp(cp, {'next': n}))
      ..add(
        CreateOp(path(t, keys, number), {
          'ownerId': ownerId,
          'createdAt': d.now,
        }),
      );
    return number;
  }

  Map<String, Object?> event(
    TenantContext t,
    String status, {
    String? reason,
  }) => {
    'status': status,
    'by': t.uid,
    'role': t.actorLabel,
    'at': d.now,
    'reason': reason,
  }..removeWhere((k, v) => v == null);

  List<Object?> history(DocData doc, Map<String, Object?> e) => [
    ...((doc['history'] as List?) ?? const []),
    e,
  ];

  /// Throws 409 unless [from] → [to] is a valid order move.
  void requireMove(String from, String to) {
    if (!(orderTransitions[from]?.contains(to) ?? false)) {
      throw ApiException.conflict('A $from order cannot become $to.');
    }
  }

  static Map<String, Object?> present(Map<String, Object?> doc) =>
      (_safe(doc)! as Map).cast<String, Object?>();

  static Object? _safe(Object? v) {
    if (v is DateTime) return v.toUtc().toIso8601String();
    if (v is Map) {
      return {for (final e in v.entries) '${e.key}': _safe(e.value)};
    }
    if (v is List) return v.map(_safe).toList();
    return v;
  }
}
