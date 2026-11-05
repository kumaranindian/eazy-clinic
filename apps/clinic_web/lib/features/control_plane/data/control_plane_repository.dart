import 'dart:typed_data';

import 'package:app_core/app_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef Json = Map<String, Object?>;

/// All control-plane API calls (applicant + platform + tenant). Thin on
/// purpose: validation, authorization and business rules live on the backend.
class ControlPlaneRepository {
  ControlPlaneRepository(this._api);

  final ApiClient _api;

  // Lists ----------------------------------------------------------------
  Future<ApiResult> list(String path, Map<String, String> query) =>
      _api.get(path, query: query);

  // Generic helpers for the clinic-administration screens -------------------
  Future<Json> getMap(String path, [Map<String, String>? query]) async =>
      (await _api.get(path, query: query)).map;
  Future<List<Json>> getList(String path, [Map<String, String>? query]) async =>
      (await _api.get(path, query: query)).list;
  Future<Json> sendMap(
    String method,
    String path, [
    Json? body,
    Map<String, String>? headers,
  ]) async {
    final r = switch (method) {
      'POST' => await _api.post(path, body: body, headers: headers),
      'PATCH' => await _api.patch(path, body: body),
      'PUT' => await _api.put(path, body: body),
      _ => throw ArgumentError('Unsupported method $method'),
    };
    return r.data is Map ? r.map : const {};
  }

  Future<void> deleteAt(String path) async {
    await _api.delete(path);
  }

  Future<Uint8List> logoBytes() => _api.getBytes('/clinics/current/logo');

  /// A finished report export, through the authenticated API.
  Future<Uint8List> exportBytes(String exportId) =>
      _api.getBytes('/reports/exports/$exportId/download');

  /// A laboratory report file, streamed through the authenticated API.
  Future<Uint8List> reportBytes(String reportId) =>
      _api.getBytes('/laboratory/reports/$reportId/download');

  // Applicant ------------------------------------------------------------
  Future<Json> submitApplication(Json body) async =>
      (await _api.post('/clinic-applications', body: body)).map;

  /// Countries a new clinic may choose (client-safe fields only).
  Future<List<Json>> onboardableCountries() async =>
      ((await _api.get('/countries')).map['items']! as List)
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();
  Future<Json> myApplication(String id) async =>
      (await _api.get('/clinic-applications/$id')).map;
  Future<Json> respond(String id, Json body) async =>
      (await _api.post('/clinic-applications/$id/respond', body: body)).map;
  Future<Json> withdraw(String id) async =>
      (await _api.post('/clinic-applications/$id/withdraw')).map;

  // Tenant ---------------------------------------------------------------
  Future<Json> entitlements() async =>
      (await _api.get('/tenants/current/entitlements')).map;

  // Platform: dashboard / audit -------------------------------------------
  Future<Json> dashboard() async => (await _api.get('/platform/dashboard')).map;

  // Platform: applications -------------------------------------------------
  Future<Json> application(String id) async =>
      (await _api.get('/platform/clinic-applications/$id')).map;
  Future<Json> startReview(String id) async =>
      (await _api.post('/platform/clinic-applications/$id/start-review')).map;
  Future<Json> requestInformation(String id, String message) async =>
      (await _api.post(
        '/platform/clinic-applications/$id/request-information',
        body: {'message': message},
      )).map;
  Future<Json> approve(
    String id, {
    String? planId,
    bool trial = false,
    String? note,
  }) async => (await _api.post(
    '/platform/clinic-applications/$id/approve',
    body: {
      'confirm': true,
      'planId': ?planId,
      if (trial) 'startTrial': true,
      if (note != null && note.isNotEmpty) 'note': note,
    },
  )).map;
  Future<Json> reject(String id, String reason) async => (await _api.post(
    '/platform/clinic-applications/$id/reject',
    body: {'reason': reason},
  )).map;
  Future<void> addNote(String id, String note) async {
    await _api.post(
      '/platform/clinic-applications/$id/notes',
      body: {'note': note},
    );
  }

  // Platform: tenants ------------------------------------------------------
  Future<Json> tenant(String id) async =>
      (await _api.get('/platform/tenants/$id')).map;
  Future<Json> suspendTenant(String id, String reason) async =>
      (await _api.post(
        '/platform/tenants/$id/suspend',
        body: {'reason': reason},
      )).map;
  Future<Json> reactivateTenant(String id, String reason) async =>
      (await _api.post(
        '/platform/tenants/$id/reactivate',
        body: {'reason': reason},
      )).map;
  Future<Json> closeTenant(String id, String reason) async => (await _api.post(
    '/platform/tenants/$id/close',
    body: {'reason': reason, 'confirm': true},
  )).map;
  Future<Json> retryProvisioning(String id) async =>
      (await _api.post('/platform/tenants/$id/retry-provisioning')).map;

  Future<Json> assignTenantCountry(
    String id, {
    required String countryCode,
    required String reason,
    String? expectedCurrent,
  }) async => (await _api.post(
    '/platform/tenants/$id/country',
    body: {
      'countryCode': countryCode,
      'reason': reason,
      'confirm': true,
      'expectedCurrent': ?expectedCurrent,
    },
  )).map;

  // Platform: countries (Phase 12) ------------------------------------------
  Future<List<Json>> countries() async =>
      ((await _api.get('/platform/countries')).map['items']! as List)
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();
  Future<Json> updateCountry(String code, Json body) async =>
      (await _api.patch('/platform/countries/$code', body: body)).map;
  Future<void> seedCountries() async {
    await _api.post('/platform/countries/seed-baseline');
  }

  Future<Json> backfillReport() async =>
      (await _api.get('/platform/countries/backfill-report')).map;

  // Compliance (Phase 14) -----------------------------------------------------
  Future<Json> complianceDashboard() async =>
      (await _api.get('/compliance/dashboard')).map;
  Future<List<Json>> complianceCredentials() async =>
      ((await _api.get('/compliance/credentials')).map['items']! as List)
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();
  Future<Json> uploadComplianceEvidence(Json body) async =>
      (await _api.post('/compliance/evidence', body: body)).map;
  Future<Json> createComplianceCredential(Json body) async =>
      (await _api.post('/compliance/credentials', body: body)).map;
  Future<Json> attachCredentialDocument(String id, Json body) async =>
      (await _api.post('/compliance/credentials/$id/document', body: body)).map;
  Future<Json> archiveComplianceCredential(String id) async =>
      (await _api.post('/compliance/credentials/$id/archive')).map;
  Future<Uint8List> complianceEvidenceBytes(String evidenceId) =>
      _api.getBytes('/compliance/evidence/$evidenceId/file');

  // Platform: compliance ----------------------------------------------------
  Future<Json> complianceOverview() async =>
      (await _api.get('/platform/compliance/overview')).map;
  Future<List<Json>> complianceProfiles() async =>
      ((await _api.get('/platform/compliance/profiles')).map['items']! as List)
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();
  Future<List<Json>> complianceReviewQueue() async =>
      ((await _api.get('/platform/compliance/review-queue')).map['items']!
              as List)
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();
  Future<void> seedComplianceProfiles() async {
    await _api.post('/platform/compliance/profiles/seed-baseline');
  }

  Future<Json> platformComplianceTenant(String tenantId) async =>
      (await _api.get('/platform/tenants/$tenantId/compliance')).map;
  Future<List<Json>> platformComplianceCredentials(String tenantId) async =>
      ((await _api.get(
                '/platform/tenants/$tenantId/compliance/credentials',
              )).map['items']!
              as List)
          .map((e) => (e as Map).cast<String, Object?>())
          .toList();
  Future<void> setComplianceApplicability(
    String tenantId,
    String profileKey,
    String status,
    String reason,
  ) async {
    await _api.put(
      '/platform/tenants/$tenantId/compliance/applicability/$profileKey',
      body: {'status': status, 'reason': reason},
    );
  }

  Future<Json> reviewComplianceEvidence(
    String tenantId,
    String evidenceId,
    Json body,
  ) async => (await _api.post(
    '/platform/tenants/$tenantId/compliance/evidence/$evidenceId/review',
    body: body,
  )).map;
  Future<Json> setComplianceItemStatus(
    String tenantId,
    String profileKey,
    String reqKey,
    Json body,
  ) async => (await _api.post(
    '/platform/tenants/$tenantId/compliance/items/$profileKey/$reqKey/status',
    body: body,
  )).map;
  Future<Json> verifyComplianceCredential(
    String tenantId,
    String credentialId,
    Json body,
  ) async => (await _api.post(
    '/platform/tenants/$tenantId/compliance/credentials/$credentialId/verify',
    body: body,
  )).map;
  Future<Uint8List> platformEvidenceBytes(String tenantId, String evidenceId) =>
      _api.getBytes(
        '/platform/tenants/$tenantId/compliance/evidence/$evidenceId/file',
      );

  // Platform: plans --------------------------------------------------------
  Future<Json> plan(String id) async =>
      (await _api.get('/platform/subscription-plans/$id')).map;
  Future<Json> createPlan(Json body) async =>
      (await _api.post('/platform/subscription-plans', body: body)).map;
  Future<Json> updatePlan(String id, Json body) async =>
      (await _api.patch('/platform/subscription-plans/$id', body: body)).map;
  Future<Json> setPlanActive(
    String id, {
    required bool active,
  }) async => (await _api.post(
    '/platform/subscription-plans/$id/${active ? 'activate' : 'deactivate'}',
  )).map;

  // Platform: subscriptions ------------------------------------------------
  Future<Json> subscription(String id) async =>
      (await _api.get('/platform/subscriptions/$id')).map;
  Future<Json> assignSubscription({
    required String tenantId,
    required String planId,
    required bool trial,
    String? reason,
  }) async => (await _api.post(
    '/platform/subscriptions',
    body: {
      'tenantId': tenantId,
      'planId': planId,
      if (trial) 'trial': true,
      if (reason != null && reason.isNotEmpty) 'reason': reason,
    },
  )).map;
  Future<Json> changePlan(String id, String planId, String reason) async =>
      (await _api.patch(
        '/platform/subscriptions/$id',
        body: {'planId': planId, 'reason': reason},
      )).map;
  Future<Json> extendTrial(String id, int days, String reason) async =>
      (await _api.post(
        '/platform/subscriptions/$id/extend-trial',
        body: {'days': days, 'reason': reason},
      )).map;
  Future<Json> renew(String id) async =>
      (await _api.post('/platform/subscriptions/$id/renew')).map;
  Future<Json> markPastDue(String id) async =>
      (await _api.post('/platform/subscriptions/$id/mark-past-due')).map;
  Future<Json> suspendSubscription(String id, String reason) async =>
      (await _api.post(
        '/platform/subscriptions/$id/suspend',
        body: {'reason': reason},
      )).map;
  Future<Json> cancelSubscription(String id, String reason) async =>
      (await _api.post(
        '/platform/subscriptions/$id/cancel',
        body: {'reason': reason},
      )).map;
}

/// Overridden in tests; in the app it is built from [apiClientProvider].
final controlPlaneRepositoryProvider = Provider<ControlPlaneRepository>(
  (ref) => ControlPlaneRepository(ref.watch(apiClientProvider)),
);
