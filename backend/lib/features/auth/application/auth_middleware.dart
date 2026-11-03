import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../../core/errors/api_exception.dart';
import '../../../core/responses/responses.dart';
import '../data/firebase_auth_admin.dart';
import '../data/signing_key_provider.dart';
import '../domain/access_resolver.dart';
import '../domain/auth_context.dart';
import '../domain/verified_identity.dart';
import 'account_service.dart';
import 'auth_context_keys.dart';
import 'security_event_recorder.dart';
import 'token_verifier.dart';

final RegExp _bearer = RegExp(r'^Bearer ([A-Za-z0-9\-_=.]+)$');

/// Step 1: proves *who* is calling.
///
/// Extracts and verifies the Firebase ID token (signature, expiry, issuer,
/// audience), optionally checks revocation and that the Firebase user is not
/// disabled, then attaches a `VerifiedIdentity`. Raw tokens are never logged
/// and verification details are never returned to the client.
Middleware tokenAuthMiddleware({
  required TokenVerifier verifier,
  required FirebaseAuthAdmin? authAdmin,
  required bool checkRevoked,
  required SecurityEventRecorder events,
}) {
  return (inner) => (request) async {
    final header = request.headers['authorization'];
    final match = header == null ? null : _bearer.firstMatch(header);
    if (match == null) {
      throw const ApiException.unauthenticated();
    }

    final VerifiedIdentity identity;
    try {
      identity = await verifier.verify(match.group(1)!);
    } on TokenVerificationException catch (e) {
      await events.record(
        SecurityEvent.tokenRejected,
        requestId: requestIdOf(request),
        outcome: 'denied',
        reason: e.failure.name,
        persist: false,
      );
      if (e.failure == TokenFailure.expired) {
        throw const ApiException(
          ApiErrorCode.tokenExpired,
          'Your session has expired. Please sign in again.',
        );
      }
      throw const ApiException.unauthenticated('Invalid credentials.');
    } on SigningKeysUnavailableException {
      throw const ApiException(
        ApiErrorCode.unavailable,
        'Authentication is temporarily unavailable.',
      );
    }

    if (checkRevoked) {
      if (authAdmin == null) {
        throw const ApiException(
          ApiErrorCode.unavailable,
          'Authentication is temporarily unavailable.',
        );
      }
      final AuthUserRecord? record;
      try {
        record = await authAdmin.lookup(identity.uid);
      } on Object {
        // Fail closed: if revocation cannot be checked, do not authenticate.
        throw const ApiException(
          ApiErrorCode.unavailable,
          'Authentication is temporarily unavailable.',
        );
      }
      if (record == null) {
        throw const ApiException.unauthenticated('Invalid credentials.');
      }
      if (record.disabled) {
        throw const ApiException(
          ApiErrorCode.accountDisabled,
          'This account has been disabled.',
        );
      }
      final validSince = record.validSince;
      if (validSince != null && identity.authTime.isBefore(validSince)) {
        await events.record(
          SecurityEvent.tokenRejected,
          uid: identity.uid,
          requestId: requestIdOf(request),
          outcome: 'denied',
          reason: 'revoked',
          persist: false,
        );
        throw const ApiException(
          ApiErrorCode.sessionRevoked,
          'Your session was ended. Please sign in again.',
        );
      }
    }
    return inner(withIdentity(request, identity));
  };
}

/// Step 2: decides whether the verified identity may proceed.
///
/// Loads the trusted `platform_users` profile, enforces [allowedStatuses] and
/// attaches the `AuthContext`. Role, tenant and status come exclusively from
/// server-side records.
Middleware accountMiddleware({
  required AccountService accounts,
  required AccessResolver access,
  required SecurityEventRecorder events,
  Set<AccountStatus> allowedStatuses = const {AccountStatus.active},
}) {
  return (inner) => (request) async {
    final identity = identityOf(request);
    final user = await accounts.resolve(
      identity,
      requestId: requestIdOf(request),
    );
    if (!allowedStatuses.contains(user.accountStatus)) {
      await events.record(
        SecurityEvent.accessDenied,
        uid: user.uid,
        requestId: requestIdOf(request),
        outcome: 'denied',
        reason: user.accountStatus.wireName,
        persist: false,
      );
      throw switch (user.accountStatus) {
        AccountStatus.pending => const ApiException(
          ApiErrorCode.accountPending,
          'Please verify your e-mail address to continue.',
        ),
        AccountStatus.suspended => const ApiException(
          ApiErrorCode.accountSuspended,
          'This account is suspended. Contact support.',
        ),
        AccountStatus.disabled => const ApiException(
          ApiErrorCode.accountDisabled,
          'This account has been disabled.',
        ),
        AccountStatus.active => const ApiException.forbidden(),
      };
    }
    final memberships = await access.membershipsFor(user);
    return inner(
      withAuthContext(
        request,
        AuthContext(identity: identity, user: user, memberships: memberships),
      ),
    );
  };
}
