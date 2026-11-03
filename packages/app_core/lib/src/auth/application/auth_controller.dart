import 'dart:async';

import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_api.dart';
import '../domain/auth_failure.dart';
import '../domain/auth_state.dart';
import '../domain/auth_user.dart';
import 'auth_providers.dart';

final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Owns authentication state for the whole app.
///
/// Firebase proves identity; the backend decides access. The state is never
/// `Authenticated` until the backend has confirmed an active account that the
/// current app admits, so protected routes stay closed until then.
class AuthController extends Notifier<AuthState> {
  StreamSubscription<AuthUser?>? _subscription;
  bool _explicitFlow = false;
  AuthUser? _lastUser;

  @override
  AuthState build() {
    final repo = ref.read(authRepositoryProvider);
    _subscription = repo.authStateChanges().listen(_onAuthChanged);
    ref.onDispose(() => _subscription?.cancel());
    return const AuthResolving();
  }

  // ---------------------------------------------------------------- actions

  /// Signs in. Returns a failure to display, or `null` on success.
  Future<AuthFailure?> signIn({
    required String email,
    required String password,
  }) => _explicit(() async {
    final user = await ref
        .read(authRepositoryProvider)
        .signIn(email: email, password: password);
    await _resolve(user, login: true);
  });

  /// Creates an identity. Grants no clinic or platform access.
  Future<AuthFailure?> register({
    required String displayName,
    required String email,
    required String password,
  }) => _explicit(() async {
    final user = await ref
        .read(authRepositoryProvider)
        .register(displayName: displayName, email: email, password: password);
    await _resolve(user, login: true);
  });

  /// Sends a reset e-mail. "No such user" is reported as success so the form
  /// cannot be used to discover which e-mails have accounts.
  Future<AuthFailure?> sendPasswordReset(String email) async {
    try {
      await ref.read(authRepositoryProvider).sendPasswordReset(email);
      return null;
    } on AuthFailure catch (e) {
      return e;
    }
  }

  Future<AuthFailure?> resendVerificationEmail() async {
    try {
      await ref.read(authRepositoryProvider).sendEmailVerification();
      return null;
    } on AuthFailure catch (e) {
      return e;
    }
  }

  /// Re-checks e-mail verification: reloads the user, refreshes the token and
  /// asks the backend again.
  Future<AuthFailure?> refreshAccess() async {
    try {
      final user = await ref.read(authRepositoryProvider).reload();
      if (user == null) {
        _toUnauthenticated();
        return null;
      }
      await _resolve(user, login: false);
      return null;
    } on AuthFailure catch (e) {
      return e;
    }
  }

  /// Re-runs session resolution after [AuthFailed].
  Future<void> retry() async {
    final user = _lastUser;
    if (user == null) {
      _toUnauthenticated();
      return;
    }
    state = const AuthResolving();
    await _resolve(user, login: false);
  }

  /// Ends the session. Local state is always cleared, even if the network or
  /// the SDK fails, so protected screens close immediately.
  Future<AuthFailure?> signOut({bool allDevices = false}) async {
    AuthFailure? failure;
    try {
      await ref
          .read(authApiProvider)
          .logout(allDevices: allDevices)
          .timeout(const Duration(seconds: 5));
    } on Object {
      // Best effort: the Firebase sign-out below is what ends this session.
    }
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on AuthFailure catch (e) {
      failure = e;
    }
    _toUnauthenticated();
    return failure;
  }

  /// Call when any API request reports a dead session
  /// (`session_revoked`, `token_expired` after a refresh, `unauthenticated`).
  Future<void> handleSessionInvalid() async {
    try {
      await ref.read(authRepositoryProvider).signOut();
    } on Object {
      // fall through: local state is cleared regardless
    }
    _toUnauthenticated(notice: 'Your session has ended. Please sign in again.');
  }

  // --------------------------------------------------------------- internals

  Future<AuthFailure?> _explicit(Future<void> Function() action) async {
    _explicitFlow = true;
    try {
      await action();
      return null;
    } on AuthFailure catch (e) {
      return e;
    } finally {
      _explicitFlow = false;
    }
  }

  void _onAuthChanged(AuthUser? user) {
    if (_explicitFlow) return; // the explicit flow resolves state itself
    if (user == null) {
      _toUnauthenticated();
    } else {
      unawaited(_resolve(user, login: false));
    }
  }

  void _toUnauthenticated({String? notice}) {
    _lastUser = null;
    state = Unauthenticated(notice: notice);
  }

  Future<void> _resolve(AuthUser user, {required bool login}) async {
    _lastUser = user;
    final api = ref.read(authApiProvider);
    try {
      final AuthSessionDto session;
      if (login) {
        session = await api.provision();
      } else {
        try {
          session = await api.getSession();
        } on AuthApiException catch (e) {
          if (e.code != ApiErrorCode.accountNotProvisioned) rethrow;
          final provisioned = await api.provision();
          state = _fromSession(user, provisioned);
          return;
        }
      }
      state = _fromSession(user, session);
    } on AuthApiException catch (e) {
      state = _fromError(user, e);
    }
  }

  AuthState _fromSession(AuthUser user, AuthSessionDto session) {
    switch (session.accountStatus) {
      case AccountStatus.pending:
        return AccessDenied(
          reason: AccessDeniedReason.emailUnverified,
          user: user,
        );
      case AccountStatus.suspended:
        return AccessDenied(reason: AccessDeniedReason.suspended, user: user);
      case AccountStatus.disabled:
        return AccessDenied(reason: AccessDeniedReason.disabled, user: user);
      case AccountStatus.active:
        return ref.read(appAudienceProvider).admits(session)
            ? Authenticated(user: user, session: session)
            : AccessDenied(
                reason: AccessDeniedReason.notAuthorized,
                user: user,
              );
    }
  }

  AuthState _fromError(AuthUser user, AuthApiException e) {
    if (e.isNetwork) return const AuthFailed(isNetwork: true);
    switch (e.code) {
      case ApiErrorCode.accountSuspended:
        return AccessDenied(reason: AccessDeniedReason.suspended, user: user);
      case ApiErrorCode.accountDisabled:
        return AccessDenied(reason: AccessDeniedReason.disabled, user: user);
      case ApiErrorCode.accountPending:
        return AccessDenied(
          reason: AccessDeniedReason.emailUnverified,
          user: user,
        );
      case ApiErrorCode.sessionRevoked:
      case ApiErrorCode.tokenExpired:
      case ApiErrorCode.unauthenticated:
        // Credentials are dead: close the session instead of retrying.
        unawaited(handleSessionInvalid());
        return const Unauthenticated(
          notice: 'Your session has ended. Please sign in again.',
        );
      default:
        return const AuthFailed(isNetwork: false);
    }
  }
}
