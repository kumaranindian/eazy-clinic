import 'auth_user.dart';

/// Identity provider operations (Firebase Authentication on the client).
///
/// Implementations throw `AuthFailure` for expected failures. Passwords are
/// passed straight through and never stored.
abstract interface class AuthRepository {
  /// Emits the current user (or `null`) on subscription and on every change.
  Stream<AuthUser?> authStateChanges();

  Future<AuthUser> signIn({required String email, required String password});

  /// Creates the identity, sets the display name and sends the verification
  /// email. Grants no application access.
  Future<AuthUser> register({
    required String displayName,
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset(String email);

  Future<void> sendEmailVerification();

  /// Reloads the user from the provider and refreshes the ID token so new
  /// claims (e.g. `email_verified`) are visible to the backend.
  Future<AuthUser?> reload();

  Future<void> signOut();

  /// A currently valid ID token, refreshed by the SDK when needed.
  Future<String?> idToken({bool forceRefresh = false});
}
