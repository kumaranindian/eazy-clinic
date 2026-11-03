import 'package:firebase_auth/firebase_auth.dart' as fb;

import '../domain/auth_failure.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';

/// [AuthRepository] backed by the Firebase Authentication client SDK.
///
/// Session persistence and token refresh are handled by the SDK (secure
/// platform storage on Android, IndexedDB on web). This class never stores or
/// logs passwords or ID tokens.
class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository([fb.FirebaseAuth? auth])
    : _auth = auth ?? fb.FirebaseAuth.instance;

  final fb.FirebaseAuth _auth;

  static AuthUser? _map(fb.User? u) => u == null
      ? null
      : AuthUser(
          uid: u.uid,
          email: u.email,
          displayName: u.displayName,
          emailVerified: u.emailVerified,
        );

  @override
  Stream<AuthUser?> authStateChanges() => _auth.authStateChanges().map(_map);

  @override
  Future<AuthUser> signIn({required String email, required String password}) =>
      _guard(() async {
        final cred = await _auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
        return _map(cred.user)!;
      });

  @override
  Future<AuthUser> register({
    required String displayName,
    required String email,
    required String password,
  }) => _guard(() async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    final user = cred.user!;
    await user.updateDisplayName(displayName.trim());
    // Refresh so the ID token carries the display name for the backend.
    await user.getIdToken(true);
    await user.sendEmailVerification();
    return _map(_auth.currentUser)!;
  });

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email.trim()));

  @override
  Future<void> sendEmailVerification() => _guard(() async {
    await _auth.currentUser?.sendEmailVerification();
  });

  @override
  Future<AuthUser?> reload() => _guard(() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await user.reload();
    await _auth.currentUser?.getIdToken(true);
    return _map(_auth.currentUser);
  });

  @override
  Future<void> signOut() => _guard(_auth.signOut);

  @override
  Future<String?> idToken({bool forceRefresh = false}) =>
      _guard(() async => _auth.currentUser?.getIdToken(forceRefresh));

  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on fb.FirebaseAuthException catch (e) {
      throw AuthFailure(mapCode(e.code));
    }
  }

  /// Maps Firebase error codes to [AuthFailureCode]. Exposed for testing.
  static AuthFailureCode mapCode(String code) => switch (code) {
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' ||
    'invalid-login-credentials' => AuthFailureCode.invalidCredentials,
    'user-disabled' => AuthFailureCode.accountDisabled,
    'email-already-in-use' => AuthFailureCode.emailInUse,
    'weak-password' => AuthFailureCode.weakPassword,
    'invalid-email' || 'missing-email' => AuthFailureCode.invalidEmail,
    'too-many-requests' => AuthFailureCode.tooManyRequests,
    'network-request-failed' => AuthFailureCode.network,
    'requires-recent-login' ||
    'user-token-expired' => AuthFailureCode.requiresRecentLogin,
    _ => AuthFailureCode.unknown,
  };
}
