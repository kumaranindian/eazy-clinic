import 'dart:convert';

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
import 'package:backend/features/platform/platform_module.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import 'auth_fixtures.dart';
import 'memory_document_store.dart';
import 'platform_fixtures.dart';

/// Whole app (auth + platform) over an in-memory document store, with real
/// signed test tokens. Nothing here is available in production code.
class PlatformHarness {
  PlatformHarness({TestClock? clock}) : clock = clock ?? TestClock() {
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
    handler = buildApp(
      AppConfig.fromEnvironment({'APP_ENV': 'dev'}),
      AppLogger(minLevel: LogLevel.debug, sink: logs.add),
      auth: auth,
      platform: platform,
    );
  }

  final TestClock clock;
  final MemoryDocumentStore store = MemoryDocumentStore();
  final FakeAuthAdmin authAdmin = FakeAuthAdmin();
  final List<String> logs = [];
  late final PlatformModule platform;
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
