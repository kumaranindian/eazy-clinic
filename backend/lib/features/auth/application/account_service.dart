import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';

import '../../../core/errors/api_exception.dart';
import '../data/firebase_auth_admin.dart';
import '../data/platform_user_store.dart';
import '../domain/platform_user.dart';
import '../domain/verified_identity.dart';
import 'security_event_recorder.dart';

/// Identity and account-status logic, independent of HTTP.
class AccountService {
  AccountService({
    required PlatformUserStore store,
    required FirebaseAuthAdmin authAdmin,
    required SecurityEventRecorder events,
    DateTime Function()? clock,
  }) : _store = store,
       _admin = authAdmin,
       _events = events,
       _clock = clock ?? DateTime.now;

  final PlatformUserStore _store;
  final FirebaseAuthAdmin _admin;
  final SecurityEventRecorder _events;
  final DateTime Function() _clock;

  /// Loads the trusted profile for [identity].
  ///
  /// Throws `account_not_provisioned` when none exists. A pending account whose
  /// token proves a verified e-mail is activated here (server-side, from the
  /// verified token — never from client input).
  Future<PlatformUser> resolve(
    VerifiedIdentity identity, {
    String? requestId,
  }) async {
    var user = await _store.get(identity.uid);
    if (user == null) {
      throw const ApiException(
        ApiErrorCode.accountNotProvisioned,
        'Your account setup is incomplete. Please sign in again.',
      );
    }
    if (user.emailVerified != identity.emailVerified) {
      final now = _clock();
      await _store.update(user.uid, {
        'emailVerified': identity.emailVerified,
        'updatedAt': now.toUtc(),
      });
      user = user.copyWith(
        emailVerified: identity.emailVerified,
        updatedAt: now,
      );
    }
    if (user.accountStatus == AccountStatus.pending && identity.emailVerified) {
      user = await _transition(user, AccountStatus.active, requestId);
      await _events.record(
        SecurityEvent.accountActivated,
        uid: user.uid,
        requestId: requestId,
        reason: 'email_verified',
      );
    }
    return user;
  }

  /// Creates `platform_users/{uid}` for a first-time identity, or refreshes
  /// the existing one, and records the login. Grants no roles or memberships.
  Future<PlatformUser> provision(
    VerifiedIdentity identity, {
    String? requestId,
  }) async {
    final email = identity.email;
    if (email == null || email.isEmpty) {
      throw const ApiException.badRequest(
        'An e-mail address is required to create an account.',
      );
    }
    final now = _clock();
    var user = await _store.get(identity.uid);
    if (user == null) {
      final created = PlatformUser(
        uid: identity.uid,
        displayName: (identity.name ?? '').trim(),
        email: email,
        emailVerified: identity.emailVerified,
        accountStatus: identity.emailVerified
            ? AccountStatus.active
            : AccountStatus.pending,
        createdAt: now,
        updatedAt: now,
        lastLoginAt: now,
      );
      try {
        await _store.create(created);
        user = created;
        await _events.record(
          SecurityEvent.userProvisioned,
          uid: user.uid,
          requestId: requestId,
        );
      } on AlreadyExistsException {
        user = await _store.get(identity.uid); // lost a race; reuse the winner
      }
    }
    if (user == null) throw const ApiException.notFound();

    user = await resolve(identity, requestId: requestId);
    if (user.accountStatus == AccountStatus.suspended ||
        user.accountStatus == AccountStatus.disabled) {
      await _events.record(
        SecurityEvent.loginDenied,
        uid: user.uid,
        requestId: requestId,
        outcome: 'denied',
        reason: user.accountStatus.wireName,
      );
      return user;
    }
    final updates = <String, Object?>{
      'lastLoginAt': now.toUtc(),
      'updatedAt': now.toUtc(),
      if (user.email != email) 'email': email,
    };
    await _store.update(user.uid, updates);
    await _events.record(
      SecurityEvent.loginRecorded,
      uid: user.uid,
      requestId: requestId,
    );
    return user.copyWith(email: email, lastLoginAt: now, updatedAt: now);
  }

  /// Revokes every refresh token of [targetUid].
  Future<void> revokeSessions({
    required String targetUid,
    required String actorUid,
    String? requestId,
  }) async {
    await _admin.revokeRefreshTokens(targetUid);
    await _events.record(
      SecurityEvent.sessionsRevoked,
      uid: targetUid,
      actorUid: actorUid,
      requestId: requestId,
    );
  }

  Future<bool> userExists(String uid) async => (await _store.get(uid)) != null;

  Future<PlatformUser> _transition(
    PlatformUser user,
    AccountStatus next,
    String? requestId,
  ) async {
    if (!user.accountStatus.canTransitionTo(next)) {
      throw StateError('Invalid account status transition.');
    }
    final now = _clock();
    await _store.update(user.uid, {
      'accountStatus': next.wireName,
      'updatedAt': now.toUtc(),
    });
    return user.copyWith(accountStatus: next, updatedAt: now);
  }
}
