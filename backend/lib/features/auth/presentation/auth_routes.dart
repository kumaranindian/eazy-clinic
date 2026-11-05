import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:validation/validation.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/middleware/rate_limit_middleware.dart';
import '../../../core/responses/responses.dart';
import '../../../core/security/rate_limiter.dart';
import '../../../core/validation/request_validator.dart';
import '../application/account_service.dart';
import '../application/auth_context_keys.dart';
import '../application/auth_middleware.dart';
import '../application/security_event_recorder.dart';
import '../application/token_verifier.dart';
import '../data/firebase_auth_admin.dart';
import '../domain/access_resolver.dart';
import '../domain/platform_user.dart';

AuthProfileDto _profile(PlatformUser u) => AuthProfileDto(
  uid: u.uid,
  displayName: u.displayName,
  email: u.email,
  emailVerified: u.emailVerified,
  accountStatus: u.accountStatus,
  phoneNumber: u.phoneNumber,
  profileImageUrl: u.profileImageUrl,
  lastLoginAt: u.lastLoginAt?.toUtc().toIso8601String(),
  preferredLanguage: u.preferredLanguage,
);

AuthSessionDto _session(PlatformUser u, List<MembershipSummaryDto> m) =>
    AuthSessionDto(
      uid: u.uid,
      accountStatus: u.accountStatus,
      emailVerified: u.emailVerified,
      accessGranted: u.accountStatus.canAccessProtectedFeatures,
      platformRole: u.platformRole,
      memberships: m,
      preferredLanguage: u.preferredLanguage,
    );

/// Everything the auth feature needs, built once at startup.
class AuthModule {
  AuthModule({
    required this.verifier,
    required this.authAdmin,
    required this.accounts,
    required this.access,
    required this.events,
    required this.checkRevoked,
    required this.trustForwardedFor,
    RateLimiter? ipLimiter,
    RateLimiter? revokeLimiter,
  }) : ipLimiter =
           ipLimiter ??
           RateLimiter(maxRequests: 60, window: const Duration(minutes: 1)),
       revokeLimiter =
           revokeLimiter ??
           RateLimiter(maxRequests: 5, window: const Duration(minutes: 15));

  final TokenVerifier verifier;
  final FirebaseAuthAdmin? authAdmin;
  final AccountService accounts;
  final AccessResolver access;
  final SecurityEventRecorder events;
  final bool checkRevoked;
  final bool trustForwardedFor;
  final RateLimiter ipLimiter;
  final RateLimiter revokeLimiter;

  /// Middleware for *any* protected business route: authenticate, then
  /// authorize account status (active only unless [allowedStatuses] says so).
  /// Later phases wrap their routers with this.
  Middleware protect({
    Set<AccountStatus> allowedStatuses = const {AccountStatus.active},
  }) {
    return (inner) => const Pipeline()
        .addMiddleware(
          tokenAuthMiddleware(
            verifier: verifier,
            authAdmin: authAdmin,
            checkRevoked: checkRevoked,
            events: events,
          ),
        )
        .addMiddleware(
          accountMiddleware(
            accounts: accounts,
            access: access,
            events: events,
            allowedStatuses: allowedStatuses,
          ),
        )
        .addHandler(inner);
  }

  /// Token-only protection (no profile required), used by provisioning.
  Middleware _identityOnly() => tokenAuthMiddleware(
    verifier: verifier,
    authAdmin: authAdmin,
    checkRevoked: checkRevoked,
    events: events,
  );

  /// `/api/v1/auth/*`.
  Router get router {
    final r = Router();
    const anyStatus = {
      AccountStatus.pending,
      AccountStatus.active,
      AccountStatus.suspended,
      AccountStatus.disabled,
    };

    Handler wrap(Handler h, Middleware m) =>
        const Pipeline().addMiddleware(m).addHandler(h);

    // Account must exist and be pending/active.
    r.get(
      '/me',
      wrap(
        _me,
        protect(allowedStatuses: {AccountStatus.pending, AccountStatus.active}),
      ),
    );
    // Status oracle: any status is allowed so the UI can explain *why*.
    r.get(
      '/session',
      wrap(_sessionHandler, protect(allowedStatuses: anyStatus)),
    );
    r.post('/profile/initialize', wrap(_initializeProfile, _identityOnly()));
    r.patch(
      '/me',
      wrap(
        _updateMe,
        protect(allowedStatuses: {AccountStatus.pending, AccountStatus.active}),
      ),
    );
    r.post('/logout', wrap(_logout, protect(allowedStatuses: anyStatus)));
    r.post('/revoke-sessions', wrap(_revokeSessions, protect()));
    // POST /account-status is intentionally not registered (deferred).

    final limitedByIp = rateLimitMiddleware(
      ipLimiter,
      (request) => clientKeyOf(request, trustForwardedFor: trustForwardedFor),
      onLimited: (request) => events.record(
        SecurityEvent.rateLimited,
        requestId: requestIdOf(request),
        outcome: 'denied',
        reason: 'ip',
        persist: false,
      ),
    );
    return Router()..mount(
      '/',
      const Pipeline().addMiddleware(limitedByIp).addHandler(r.call),
    );
  }

  Future<Response> _me(Request request) async {
    final ctx = authContextOf(request);
    return ok(request, _profile(ctx.user).toJson());
  }

  Future<Response> _sessionHandler(Request request) async {
    final ctx = authContextOf(request);
    return ok(request, _session(ctx.user, ctx.memberships).toJson());
  }

  Future<Response> _initializeProfile(Request request) async {
    final identity = identityOf(request);
    final body = await _optionalBody(request);
    // Strict allow-list: privileged or identity fields are rejected, not ignored.
    _rejectUnknownFields(body, const {'displayName'});
    final v = RequestValidator(body);
    final hint = body.containsKey('displayName')
        ? v.string(
            'displayName',
            Validators.compose([
              (s) => Validators.required(s, field: 'displayName'),
              Validators.minLength(2, field: 'displayName'),
              Validators.maxLength(80, field: 'displayName'),
            ]),
          )
        : null;
    v.throwIfInvalid();
    final user = await accounts.initializeProfile(
      identity,
      displayNameHint: hint,
      requestId: requestIdOf(request),
    );
    final memberships = user.accountStatus.canAccessProtectedFeatures
        ? await access.membershipsFor(user)
        : <MembershipSummaryDto>[];
    return ok(request, {
      ..._session(user, memberships).toJson(),
      'profile': _profile(user).toJson(),
    });
  }

  Future<Response> _updateMe(Request request) async {
    final ctx = authContextOf(request);
    final body = await readJsonObject(request);
    _rejectUnknownFields(body, const {
      'displayName',
      'phoneNumber',
      'preferredLanguage',
    });
    final v = RequestValidator(body);
    String? name;
    if (body.containsKey('displayName')) {
      name = v.string(
        'displayName',
        Validators.compose([
          (s) => Validators.required(s, field: 'displayName'),
          Validators.minLength(2, field: 'displayName'),
          Validators.maxLength(80, field: 'displayName'),
        ]),
      );
    }
    String? phone;
    final clearPhone =
        body.containsKey('phoneNumber') && body['phoneNumber'] == null;
    if (body.containsKey('phoneNumber') && !clearPhone) {
      phone = v.string('phoneNumber', Validators.indianMobile);
    }
    String? language;
    final clearLanguage =
        body.containsKey('preferredLanguage') &&
        body['preferredLanguage'] == null;
    if (body.containsKey('preferredLanguage') && !clearLanguage) {
      language = v.string(
        'preferredLanguage',
        (s) => isSupportedUiLanguage(s?.trim())
            ? null
            : ValidationFailure(
                'unsupported_language',
                'Choose one of: ${supportedUiLanguages.join(', ')}.',
              ),
      );
    }
    v.throwIfInvalid();
    if (name == null &&
        phone == null &&
        !clearPhone &&
        language == null &&
        !clearLanguage) {
      throw const ApiException.badRequest('No profile fields to update.');
    }
    final updated = await accounts.updateProfile(
      ctx.user,
      displayName: name,
      phoneNumber: phone,
      clearPhone: clearPhone,
      preferredLanguage: language,
      clearPreferredLanguage: clearLanguage,
      requestId: requestIdOf(request),
    );
    return ok(request, _profile(updated).toJson());
  }

  /// Fails with 422 listing every field that is not in [allowed]. Security
  /// sensitive names (uid, accountStatus, roles, tenant ids ...) therefore
  /// produce an explicit rejection instead of being silently dropped.
  void _rejectUnknownFields(Map<String, Object?> body, Set<String> allowed) {
    final extra = body.keys.where((k) => !allowed.contains(k)).toList();
    if (extra.isEmpty) return;
    throw ApiException.validation([
      for (final k in extra)
        FieldIssue(
          field: k,
          code: 'not_allowed',
          message: 'This field cannot be set by the client.',
        ),
    ]);
  }

  Future<Response> _logout(Request request) async {
    final ctx = authContextOf(request);
    final body = await _optionalBody(request);
    final v = RequestValidator(body);
    final allDevices = _optionalBool(v, body, 'allDevices');
    v.throwIfInvalid();
    if (allDevices) {
      await accounts.revokeSessions(
        targetUid: ctx.user.uid,
        actorUid: ctx.user.uid,
        requestId: requestIdOf(request),
      );
    }
    await events.record(
      SecurityEvent.logout,
      uid: ctx.user.uid,
      requestId: requestIdOf(request),
      reason: allDevices ? 'all_devices' : 'this_device',
    );
    return ok(request, {'revokedAllSessions': allDevices});
  }

  Future<Response> _revokeSessions(Request request) async {
    final ctx = authContextOf(request);
    final wait = revokeLimiter.hit(ctx.user.uid);
    if (wait != null) {
      throw const ApiException(
        ApiErrorCode.rateLimited,
        'Too many requests. Please try again later.',
      );
    }
    final body = await _optionalBody(request);
    final v = RequestValidator(body);
    final target = body.containsKey('targetUid')
        ? v.string(
            'targetUid',
            Validators.compose([
              (s) => Validators.required(s, field: 'targetUid'),
              Validators.maxLength(128, field: 'targetUid'),
            ]),
          )
        : ctx.user.uid;
    v.throwIfInvalid();

    // `targetUid` names who to act on; it is not proof of who is acting.
    if (target != ctx.user.uid &&
        !PermissionPolicy.platformRoleHas(
          ctx.user.platformRole,
          Permission.revokeUserSessions,
        )) {
      await events.record(
        SecurityEvent.accessDenied,
        uid: ctx.user.uid,
        requestId: requestIdOf(request),
        outcome: 'denied',
        reason: 'missing_permission',
        persist: false,
      );
      throw const ApiException.forbidden();
    }
    if (!await accounts.userExists(target)) {
      throw const ApiException.notFound('User not found.');
    }
    await accounts.revokeSessions(
      targetUid: target,
      actorUid: ctx.user.uid,
      requestId: requestIdOf(request),
    );
    return ok(request, {'revoked': true});
  }

  /// Parses an optional JSON object body (empty body → `{}`).
  Future<Map<String, Object?>> _optionalBody(Request request) async {
    if (request.contentLength == 0) return {};
    return readJsonObject(request);
  }

  bool _optionalBool(RequestValidator v, Map<String, Object?> body, String f) {
    final raw = body[f];
    if (raw == null) return false;
    if (raw is bool) return raw;
    throw ApiException.validation([
      FieldIssue(
        field: f,
        code: 'invalid_type',
        message: '$f must be a boolean.',
      ),
    ]);
  }
}
