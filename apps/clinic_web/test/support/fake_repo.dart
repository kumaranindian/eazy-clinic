import 'dart:typed_data';

import 'package:api_contracts/api_contracts.dart';
import 'package:app_core/app_core.dart';
import 'package:clinic_web/features/control_plane/data/control_plane_repository.dart';

/// Scripted stand-in for the backend (tests only). Each repository method is
/// answered by a handler registered under its name; calls are recorded.
class FakeRepo implements ControlPlaneRepository {
  final Map<
    String,
    Object? Function(List<Object?> args, Map<String, Object?> named)
  >
  handlers = {
    // Landing pages list the user's applications: empty unless a test says otherwise.
    'list': (a, n) => listOf([]),
  };
  final List<String> calls = [];
  final List<List<Object?>> callArgs = [];
  final List<Map<String, Object?>> callNamed = [];

  void on(
    String name,
    Object? Function(List<Object?> args, Map<String, Object?> named) h,
  ) => handlers[name] = h;

  Future<T> _call<T>(
    String name,
    List<Object?> args,
    Map<String, Object?> named,
  ) async {
    calls.add(name);
    callArgs.add(args);
    callNamed.add(named);
    final h = handlers[name];
    if (h == null) throw StateError('FakeRepo: no handler for $name');
    final r = h(args, named);
    if (r is Map && r is! Map<String, Object?>) {
      return Map<String, Object?>.from(r) as T;
    }
    return r as T;
  }

  @override
  Future<ApiResult> list(String path, Map<String, String> query) =>
      _call<ApiResult>('list', [path, query], {});

  @override
  Future<Json> getMap(String path, [Map<String, String>? query]) =>
      _call<Json>('getMap', [path, query], {});

  @override
  Future<List<Json>> getList(String path, [Map<String, String>? query]) =>
      _call<List<Json>>('getList', [path, query], {});

  @override
  Future<Json> sendMap(
    String method,
    String path, [
    Json? body,
    Map<String, String>? headers,
  ]) => _call<Json>('sendMap', [method, path, body], {'headers': headers});

  @override
  Future<void> deleteAt(String path) => _call<void>('deleteAt', [path], {});

  @override
  Future<Uint8List> logoBytes() => _call<Uint8List>('logoBytes', [], {});

  @override
  Future<Json> submitApplication(Json body) =>
      _call<Json>('submitApplication', [body], {});

  @override
  Future<Json> myApplication(String id) =>
      _call<Json>('myApplication', [id], {});

  @override
  Future<Json> respond(String id, Json body) =>
      _call<Json>('respond', [id, body], {});

  @override
  Future<Json> withdraw(String id) => _call<Json>('withdraw', [id], {});

  @override
  Future<Json> entitlements() => _call<Json>('entitlements', [], {});

  @override
  Future<Json> dashboard() => _call<Json>('dashboard', [], {});

  @override
  Future<Json> application(String id) => _call<Json>('application', [id], {});

  @override
  Future<Json> startReview(String id) => _call<Json>('startReview', [id], {});

  @override
  Future<Json> requestInformation(String id, String message) =>
      _call<Json>('requestInformation', [id, message], {});

  @override
  Future<Json> approve(
    String id, {
    String? planId,
    bool trial = false,
    String? note,
  }) => _call<Json>(
    'approve',
    [id],
    {'planId': planId, 'trial': trial, 'note': note},
  );

  @override
  Future<Json> reject(String id, String reason) =>
      _call<Json>('reject', [id, reason], {});

  @override
  Future<void> addNote(String id, String note) =>
      _call<void>('addNote', [id, note], {});

  @override
  Future<Json> tenant(String id) => _call<Json>('tenant', [id], {});

  @override
  Future<Json> suspendTenant(String id, String reason) =>
      _call<Json>('suspendTenant', [id, reason], {});

  @override
  Future<Json> reactivateTenant(String id, String reason) =>
      _call<Json>('reactivateTenant', [id, reason], {});

  @override
  Future<Json> closeTenant(String id, String reason) =>
      _call<Json>('closeTenant', [id, reason], {});

  @override
  Future<Json> retryProvisioning(String id) =>
      _call<Json>('retryProvisioning', [id], {});

  @override
  Future<Json> plan(String id) => _call<Json>('plan', [id], {});

  @override
  Future<Json> createPlan(Json body) => _call<Json>('createPlan', [body], {});

  @override
  Future<Json> updatePlan(String id, Json body) =>
      _call<Json>('updatePlan', [id, body], {});

  @override
  Future<Json> setPlanActive(String id, {required bool active}) =>
      _call<Json>('setPlanActive', [id], {'active': active});

  @override
  Future<Json> subscription(String id) => _call<Json>('subscription', [id], {});

  @override
  Future<Json> assignSubscription({
    required String tenantId,
    required String planId,
    required bool trial,
    String? reason,
  }) => _call<Json>('assignSubscription', [], {
    'tenantId': tenantId,
    'planId': planId,
    'trial': trial,
    'reason': reason,
  });

  @override
  Future<Json> changePlan(String id, String planId, String reason) =>
      _call<Json>('changePlan', [id, planId, reason], {});

  @override
  Future<Json> extendTrial(String id, int days, String reason) =>
      _call<Json>('extendTrial', [id, days, reason], {});

  @override
  Future<Json> renew(String id) => _call<Json>('renew', [id], {});

  @override
  Future<Json> markPastDue(String id) => _call<Json>('markPastDue', [id], {});

  @override
  Future<Json> suspendSubscription(String id, String reason) =>
      _call<Json>('suspendSubscription', [id, reason], {});

  @override
  Future<Json> cancelSubscription(String id, String reason) =>
      _call<Json>('cancelSubscription', [id, reason], {});
}

ApiResult listOf(List<Map<String, Object?>> rows, {String? next}) => ApiResult(
  rows,
  PageMeta(limit: 20, hasMore: next != null, nextCursor: next),
);

Map<String, Object?> dashboardJson() => {
  'generatedAt': '2026-06-01T10:00:00Z',
  'applications': {
    'total': 9,
    'pending': 3,
    'additionalInformationRequired': 1,
    'approved': 4,
    'rejected': 1,
    'withdrawn': 0,
  },
  'tenants': {
    'total': 4,
    'active': 3,
    'suspended': 1,
    'provisioning': 0,
    'closed': 0,
  },
  'subscriptions': {
    'trial': 1,
    'active': 2,
    'pastDue': 1,
    'expired': 0,
    'cancelled': 0,
    'suspended': 0,
  },
  'planDistribution': [
    {'planId': 'plan_1', 'name': 'Starter', 'subscriptions': 3},
  ],
  'monthlyRecurringRevenue': {'available': false},
  'recentApplications': [
    {
      'applicationId': 'app_1',
      'clinicName': 'Green Valley Clinic',
      'status': 'submitted',
      'submittedAt': '2026-05-30T08:00:00Z',
    },
  ],
  'recentlyApprovedClinics': [
    {
      'tenantId': 'ten_1',
      'clinicName': 'Sunrise Dental',
      'status': 'active',
      'approvedAt': '2026-05-29T08:00:00Z',
    },
  ],
  'recentActivity': [
    {
      'action': 'tenant.created',
      'actorRole': 'super_admin',
      'timestamp': '2026-05-29T08:00:00Z',
    },
  ],
};

Map<String, Object?> applicationJson({String status = 'submitted'}) => {
  'applicationId': 'app_1',
  'status': status,
  'applicantEmail': 'asha@example.test',
  'clinic': {
    'name': 'Green Valley Clinic',
    'type': 'general_medicine',
    'email': 'info@gv.test',
    'phone': '9876543210',
  },
  'address': {
    'line1': '12 Main Road',
    'city': 'Pune',
    'state': 'MH',
    'country': 'India',
    'postalCode': '411001',
  },
  'owner': {
    'fullName': 'Dr Asha Rao',
    'email': 'asha@gv.test',
    'phone': '9876543211',
  },
  'expectations': {'doctors': 3, 'staff': 8, 'monthlyPatients': 600},
  'preferredPlanId': 'plan_1',
  'submittedAt': '2026-05-30T08:00:00Z',
  'infoRequest': null,
  'decisionReason': null,
  'tenantId': null,
  'history': [
    {
      'toStatus': 'submitted',
      'actorRole': 'applicant',
      'at': '2026-05-30T08:00:00Z',
      'reason': null,
    },
  ],
  'internalNotes': <Object?>[],
};

Map<String, Object?> tenantJson({
  String status = 'active',
  Map<String, Object?>? job,
}) => {
  'tenantId': 'ten_1',
  'clinicName': 'Green Valley Clinic',
  'slug': 'green-valley-clinic',
  'status': status,
  'ownerUid': 'u-owner',
  'applicationId': 'app_1',
  'createdAt': '2026-05-30T09:00:00Z',
  'approvedAt': '2026-05-30T09:00:00Z',
  'approvedBy': 'root',
  'owner': {
    'fullName': 'Dr Asha Rao',
    'email': 'asha@gv.test',
    'phone': '9876543211',
  },
  'application': {'applicationId': 'app_1', 'status': 'approved'},
  'subscription': {
    'subscriptionId': 'sub_1',
    'name': 'Starter',
    'planVersion': 1,
    'effectiveStatus': 'active',
    'priceMinor': 99900,
    'currency': 'INR',
    'billingInterval': 'monthly',
    'endDate': '2026-07-01T00:00:00Z',
  },
  'provisioning': job,
  'auditHistory': [
    {
      'action': 'tenant.created',
      'timestamp': '2026-05-30T09:00:00Z',
      'actorRole': 'super_admin',
    },
  ],
};

Map<String, Object?> entitlementsJson({
  String level = 'full',
  String? reason,
  String tenantStatus = 'active',
}) => {
  'tenantId': 'ten_1',
  'tenantStatus': tenantStatus,
  'accessLevel': level,
  'writesAllowed': level == 'full',
  'reason': reason,
  'subscription': {
    'planName': 'Starter',
    'status': 'active',
    'endsAt': '2026-07-01T00:00:00Z',
  },
  'features': {'appointments': level != 'blocked', 'billing': false},
  'limits': {'max_branches': 1, 'max_doctors': 3, 'max_patients': null},
};

/// Answers the clinic-admin read endpoints for a clinic owner (tests only).
Map<String, Object?> ownerAccess(String path, {bool writes = true}) {
  if (path.startsWith('/members/current/permissions')) {
    return {
      'tenantId': 'ten_1',
      'role': 'clinic_owner',
      'allBranches': true,
      'branches': <Object?>[],
      'accessLevel': writes ? 'full' : 'read_only',
      'writesAllowed': writes,
      'permissions': <Object?>[
        'clinic.view',
        'clinic.update',
        'branches.view',
        'doctors.view',
        'staff.view',
        'roles.view',
      ],
    };
  }
  if (path.startsWith('/clinics/current')) {
    return {
      'tenantId': 'ten_1',
      'status': 'active',
      'verificationStatus': 'verified',
      'profile': {'name': 'Test Clinic', 'type': 'clinic'},
    };
  }
  return <String, Object?>{};
}
