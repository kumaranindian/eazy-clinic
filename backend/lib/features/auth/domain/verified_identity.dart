/// Facts proven by a verified Firebase ID token. Nothing here comes from the
/// request body, query or custom headers.
class VerifiedIdentity {
  const VerifiedIdentity({
    required this.uid,
    required this.emailVerified,
    required this.authTime,
    required this.issuedAt,
    required this.expiresAt,
    required this.signInProvider,
    this.email,
    this.name,
  });

  final String uid;
  final String? email;
  final bool emailVerified;
  final String? name;

  /// When the user last actively signed in (used for revocation checks).
  final DateTime authTime;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String signInProvider;
}
