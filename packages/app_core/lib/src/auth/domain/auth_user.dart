/// The signed-in Firebase identity as seen by the app. Holds no credentials.
class AuthUser {
  const AuthUser({
    required this.uid,
    required this.emailVerified,
    this.email,
    this.displayName,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final bool emailVerified;
}
