import 'dart:convert';
import 'dart:typed_data';

import 'package:backend/app.dart';
import 'package:backend/config/app_config.dart';
import 'package:backend/core/logging/app_logger.dart';
import 'package:backend/features/auth/application/account_service.dart';
import 'package:backend/features/auth/application/security_event_recorder.dart';
import 'package:backend/features/auth/application/token_verifier.dart';
import 'package:backend/features/auth/data/document_platform_user_store.dart';
import 'package:backend/features/auth/data/firebase_auth_admin.dart';
import 'package:backend/features/auth/data/membership_access_resolver.dart';
import 'package:backend/features/auth/domain/platform_user.dart';
import 'package:backend/features/auth/presentation/auth_routes.dart';
import 'package:backend/features/clinic/clinic_module.dart';
import 'package:backend/features/clinic/common/object_storage.dart';
import 'package:backend/features/notifications/notification_core.dart';
import 'package:backend/features/platform/platform_module.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import 'auth_fixtures.dart';
import 'memory_document_store.dart';
import 'platform_fixtures.dart';

/// Whole app (auth + platform) over an in-memory document store, with real
/// signed test tokens. Nothing here is available in production code.
class PlatformHarness {
  PlatformHarness({
    TestClock? clock,
    FcmSender fcm = const UnconfiguredFcmSender(),
    Map<String, MessageProvider> providers = const {},
  }) : clock = clock ?? TestClock() {
    final users = DocumentPlatformUserStore(store);
    final events = SecurityEventRecorder(
      AppLogger(minLevel: LogLevel.debug, sink: logs.add),
      users,
    );
    final auth = AuthModule(
      verifier: FirebaseTokenVerifier(
        projectId: testProjectId,
        keys: StaticKeyProvider({testKid: AuthHarness.sharedKeys.publicKey}),
      ),
      authAdmin: authAdmin,
      accounts: AccountService(
        store: users,
        authAdmin: authAdmin,
        events: events,
      ),
      access: MembershipAccessResolver(store),
      events: events,
      checkRevoked: true,
      trustForwardedFor: false,
    );
    platform = PlatformModule(auth: auth, store: store, clock: this.clock.call);
    clinic = ClinicModule(
      auth: auth,
      store: store,
      storage: storage,
      fcm: fcm,
      messageProviders: providers,
      clock: this.clock.call,
    );
    handler = buildApp(
      AppConfig.fromEnvironment({'APP_ENV': 'dev'}),
      AppLogger(minLevel: LogLevel.debug, sink: logs.add),
      auth: auth,
      platform: platform,
      clinic: clinic,
    );
  }

  final TestClock clock;
  final MemoryDocumentStore store = MemoryDocumentStore();
  final FakeAuthAdmin authAdmin = FakeAuthAdmin();
  final List<String> logs = [];
  final MemoryObjectStorage storage = MemoryObjectStorage();
  late final PlatformModule platform;
  late final ClinicModule clinic;
  late final Handler handler;

  /// Creates an active platform user (and its Firebase record).
  void user(
    String uid, {
    PlatformRole? role,
    AccountStatus status = AccountStatus.active,
  }) {
    final now = clock.now;
    store.docs['platform_users/$uid'] = PlatformUser(
      uid: uid,
      displayName: 'User $uid',
      email: '$uid@example.test',
      emailVerified: true,
      accountStatus: status,
      createdAt: now,
      updatedAt: now,
      platformRole: role,
    ).toMap();
    authAdmin.records[uid] = const AuthUserRecord(disabled: false);
  }

  String token(
    String uid, {
    Map<String, Object?> extra = const {},
    bool emailVerified = true,
  }) => AuthHarness.sharedKeys.token(
    uid: uid,
    email: '$uid@example.test',
    emailVerified: emailVerified,
    extra: extra,
  );

  Future<Response> call(
    String method,
    String path, {
    String? uid,
    Object? body,
    Map<String, String> headers = const {},
    Map<String, Object?> claims = const {},
    bool emailVerified = true,
  }) {
    return Future.sync(
      () => handler(
        Request(
          method,
          Uri.parse('http://localhost/api/v1$path'),
          headers: {
            if (uid != null)
              'authorization':
                  'Bearer ${token(uid, extra: claims, emailVerified: emailVerified)}',
            if (body != null) 'content-type': 'application/json',
            ...headers,
          },
          body: body == null ? null : jsonEncode(body),
        ),
      ),
    );
  }

  Future<Map<String, Object?>> data(Response r) async =>
      ((jsonDecode(await r.readAsString()) as Map)['data'] as Map)
          .cast<String, Object?>();

  Future<List<Object?>> list(Response r) async =>
      (jsonDecode(await r.readAsString()) as Map)['data'] as List;

  /// Submits an application as [uid] and returns its id.
  Future<String> apply(String uid, {Map<String, Object?>? body}) async {
    final r = await call(
      'POST',
      '/clinic-applications',
      uid: uid,
      body: body ?? applicationBody(),
    );
    if (r.statusCode != 201) {
      throw StateError(
        'apply failed: ${r.statusCode} ${await r.readAsString()}',
      );
    }
    return (await data(r))['applicationId']! as String;
  }

  Future<String> activePlan({String name = 'Starter'}) async {
    final c = await call(
      'POST',
      '/platform/subscription-plans',
      uid: 'root',
      body: planBody(name: name),
    );
    final id = (await data(c))['planId']! as String;
    await call(
      'POST',
      '/platform/subscription-plans/$id/activate',
      uid: 'root',
    );
    return id;
  }

  /// Approves [appId] as `root` and returns the tenant id.
  Future<String> approve(
    String appId, {
    String? planId,
    bool trial = false,
  }) async {
    final r = await call(
      'POST',
      '/platform/clinic-applications/$appId/approve',
      uid: 'root',
      body: {'confirm': true, 'planId': ?planId, if (trial) 'startTrial': true},
    );
    if (r.statusCode != 200) {
      throw StateError(
        'approve failed: ${r.statusCode} ${await r.readAsString()}',
      );
    }
    return (await data(r))['tenantId']! as String;
  }
}

/// In-memory [ObjectStorage] (tests only).
class MemoryObjectStorage implements ObjectStorage {
  final Map<String, (Uint8List, String)> objects = {};

  @override
  Future<void> put(String path, Uint8List bytes, String contentType) async =>
      objects[path] = (bytes, contentType);

  @override
  Future<(Uint8List, String)?> get(String path) async => objects[path];
}

/// A tiny valid PNG header + payload (enough for magic-byte detection).
Uint8List pngBytes([int extra = 16]) => Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  ...List.filled(extra, 7),
]);

extension ClinicFlows on PlatformHarness {
  /// Creates an approved, active clinic owned by [ownerUid] on a plan with the
  /// given limits/features. Returns the tenant id.
  Future<String> createClinic(
    String ownerUid, {
    String name = 'Green Valley Clinic',
    String city = 'Pune',
    String pin = '411001',
    int? maxBranches = 3,
    int? maxDoctors = 5,
    int? maxStaff = 5,
    bool multipleBranches = true,
    bool billing = true,
    bool patientApp = true,
    bool laboratory = true,
  }) async {
    if (!store.docs.containsKey('platform_users/$ownerUid')) user(ownerUid);
    final planRes = await call(
      'POST',
      '/platform/subscription-plans',
      uid: 'root',
      body: planBody(
        name: 'Plan $name',
        limits: {
          'max_branches': maxBranches,
          'max_doctors': maxDoctors,
          'max_staff': maxStaff,
          'max_patients': null,
        },
        features: {
          'appointments': true,
          'patient_management': true,
          'doctor_workspace': true,
          'billing': billing,
          'laboratory': laboratory,
          'patient_mobile_app': patientApp,
          'multiple_branches': multipleBranches,
        },
      ),
    );
    final planId = (await data(planRes))['planId']! as String;
    await call(
      'POST',
      '/platform/subscription-plans/$planId/activate',
      uid: 'root',
    );
    final appId = await apply(
      ownerUid,
      body: applicationBody(name: name, city: city, postalCode: pin),
    );
    return approve(appId, planId: planId);
  }

  /// Trusted membership record, as provisioning / invitation acceptance would
  /// create it (tests seed it directly to set up role scenarios).
  void member(
    String uid,
    String tenantId,
    String role, {
    bool allBranches = true,
    List<String> branchIds = const [],
    String status = 'active',
  }) {
    if (!store.docs.containsKey('platform_users/$uid')) user(uid);
    store.docs['tenants/$tenantId/members/$uid'] = {
      'uid': uid,
      'role': role,
      'status': status,
      'allBranches': allBranches,
      'branchIds': branchIds,
      'createdAt': clock.now,
    };
  }

  Future<Map<String, Object?>> okData(
    Future<Response> f, {
    int status = 200,
  }) async {
    final r = await f;
    if (r.statusCode != status) {
      throw StateError(
        'expected $status got ${r.statusCode}: ${await r.readAsString()}',
      );
    }
    return data(r);
  }
}

Map<String, Object?> branchBody({
  String name = 'Main Branch',
  String code = 'MAIN',
  String city = 'Pune',
}) => {
  'name': name,
  'code': code,
  'type': 'main',
  'email': 'main@gv.test',
  'phone': '9876543210',
  'address': {
    'line1': '12 Main Road',
    'city': city,
    'state': 'Maharashtra',
    'country': 'India',
    'postalCode': '411001',
  },
};

Map<String, Object?> day(
  String from,
  String to, [
  List<Map<String, String>> breaks = const [],
]) => {'open': true, 'from': from, 'to': to, 'breaks': breaks};
