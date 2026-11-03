import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:backend/app.dart';
import 'package:backend/config/app_config.dart';
import 'package:backend/core/data/document_store.dart'
    show AlreadyExistsException;
import 'package:backend/core/logging/app_logger.dart';
import 'package:backend/features/auth/application/account_service.dart';
import 'package:backend/features/auth/application/security_event_recorder.dart';
import 'package:backend/features/auth/application/token_verifier.dart';
import 'package:backend/features/auth/data/firebase_auth_admin.dart';
import 'package:backend/features/auth/data/platform_user_store.dart';
import 'package:backend/features/auth/data/signing_key_provider.dart';
import 'package:backend/features/auth/domain/access_resolver.dart';
import 'package:backend/features/auth/domain/platform_user.dart';
import 'package:backend/features/auth/presentation/auth_routes.dart';
import 'package:common_models/common_models.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:pointycastle/export.dart' as pc;
import 'package:shelf/shelf.dart';

const String testProjectId = 'eazyclinic-test';
const String testKid = 'test-key-1';

/// Test doubles live in `test/` only; production code has no fake auth.
class InMemoryUserStore implements PlatformUserStore {
  final Map<String, PlatformUser> users = {};
  final List<Map<String, Object?>> audit = [];

  @override
  Future<PlatformUser?> get(String uid) async => users[uid];

  @override
  Future<void> create(PlatformUser user) async {
    if (users.containsKey(user.uid)) throw const AlreadyExistsException();
    users[user.uid] = user;
  }

  @override
  Future<void> update(String uid, Map<String, Object?> fields) async {
    final map = users[uid]!.toMap()..addAll(fields);
    users[uid] = PlatformUser.fromMap(map)!;
  }

  @override
  Future<void> appendAuditLog(Map<String, Object?> event) async =>
      audit.add(event);
}

class FakeAuthAdmin implements FirebaseAuthAdmin {
  final Map<String, AuthUserRecord> records = {};
  final List<String> revoked = [];
  bool failLookup = false;

  @override
  Future<AuthUserRecord?> lookup(String uid) async {
    if (failLookup) throw const AuthAdminException('down');
    return records[uid];
  }

  @override
  Future<void> revokeRefreshTokens(String uid) async {
    revoked.add(uid);
    records[uid] = AuthUserRecord(
      disabled: false,
      validSince: DateTime.now().toUtc().add(const Duration(seconds: 1)),
    );
  }
}

class StaticKeyProvider implements SigningKeyProvider {
  StaticKeyProvider(this.keys);
  final Map<String, RSAPublicKey> keys;
  @override
  Future<RSAPublicKey?> keyFor(String kid) async => keys[kid];
}

/// An RSA key pair that signs Firebase-shaped tokens.
class TestKeys {
  TestKeys._(this.privateKey, this.publicKey);

  factory TestKeys.generate() {
    final random = pc.FortunaRandom()
      ..seed(
        pc.KeyParameter(
          Uint8List.fromList(
            List<int>.generate(32, (_) => Random.secure().nextInt(256)),
          ),
        ),
      );
    final generator = pc.RSAKeyGenerator()
      ..init(
        pc.ParametersWithRandom(
          pc.RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          random,
        ),
      );
    final pair = generator.generateKeyPair();
    return TestKeys._(
      RSAPrivateKey.raw(pair.privateKey),
      RSAPublicKey.raw(pair.publicKey),
    );
  }

  final RSAPrivateKey privateKey;
  final RSAPublicKey publicKey;

  String token({
    String uid = 'user-1',
    String? email = 'user@example.test',
    bool emailVerified = true,
    String? name = 'Test User',
    String audience = testProjectId,
    String? issuer,
    Duration expiresIn = const Duration(hours: 1),
    Duration issuedAgo = const Duration(minutes: 1),
    Duration authAgo = const Duration(minutes: 1),
    String provider = 'password',
    String kid = testKid,
    JWTKey? signWith,
    JWTAlgorithm algorithm = JWTAlgorithm.RS256,
    Map<String, Object?> extra = const {},
  }) {
    int secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;
    final now = DateTime.now();
    final jwt = JWT(
      {
        'iss': issuer ?? 'https://securetoken.google.com/$testProjectId',
        'aud': audience,
        'sub': uid,
        'iat': secs(now.subtract(issuedAgo)),
        'exp': secs(now.add(expiresIn)),
        'auth_time': secs(now.subtract(authAgo)),
        if (email != null) 'email': email,
        'email_verified': emailVerified,
        if (name != null) 'name': name,
        'firebase': {'sign_in_provider': provider},
        ...extra,
      },
      header: {'kid': kid},
    );
    return jwt.sign(
      signWith ?? privateKey,
      algorithm: algorithm,
      noIssueAt: true,
      expiresIn: null,
    );
  }
}

/// A fully wired app with in-memory persistence.
class AuthHarness {
  AuthHarness({bool checkRevoked = true, TestKeys? keys})
    : keys = keys ?? sharedKeys {
    admin.records['user-1'] = const AuthUserRecord(disabled: false);
    final events = SecurityEventRecorder(logger, store);
    module = AuthModule(
      verifier: FirebaseTokenVerifier(
        projectId: testProjectId,
        keys: StaticKeyProvider({testKid: this.keys.publicKey}),
      ),
      authAdmin: admin,
      accounts: AccountService(store: store, authAdmin: admin, events: events),
      access: const NoMembershipsAccessResolver(),
      events: events,
      checkRevoked: checkRevoked,
      trustForwardedFor: false,
    );
    handler = buildApp(
      AppConfig.fromEnvironment({'APP_ENV': 'dev'}),
      logger,
      auth: module,
    );
  }

  static final TestKeys sharedKeys = TestKeys.generate();

  final TestKeys keys;
  final InMemoryUserStore store = InMemoryUserStore();
  final FakeAuthAdmin admin = FakeAuthAdmin();
  final List<String> logs = [];
  late final AppLogger logger = AppLogger(
    minLevel: LogLevel.debug,
    sink: logs.add,
  );
  late final AuthModule module;
  late final Handler handler;

  PlatformUser seedUser({
    String uid = 'user-1',
    AccountStatus status = AccountStatus.active,
    PlatformRole? platformRole,
    bool emailVerified = true,
  }) {
    final now = DateTime.now().toUtc();
    final user = PlatformUser(
      uid: uid,
      displayName: 'Seeded $uid',
      email: '$uid@example.test',
      emailVerified: emailVerified,
      accountStatus: status,
      createdAt: now,
      updatedAt: now,
      platformRole: platformRole,
    );
    store.users[uid] = user;
    admin.records.putIfAbsent(uid, () => const AuthUserRecord(disabled: false));
    return user;
  }

  Future<Response> call(
    String method,
    String path, {
    String? token,
    String? authorization,
    Object? body,
    Map<String, String> headers = const {},
  }) {
    final h = <String, String>{
      if (token != null) 'authorization': 'Bearer $token',
      if (authorization != null) 'authorization': authorization,
      if (body != null) 'content-type': 'application/json',
      ...headers,
    };
    return Future.sync(
      () => handler(
        Request(
          method,
          Uri.parse('http://localhost/api/v1$path'),
          headers: h,
          body: body == null ? null : jsonEncode(body),
        ),
      ),
    );
  }
}

Future<Map<String, Object?>> jsonBody(Response r) async =>
    (jsonDecode(await r.readAsString()) as Map).cast<String, Object?>();

Future<String> errorCode(Response r) async =>
    ((await jsonBody(r))['error']! as Map)['code']! as String;
