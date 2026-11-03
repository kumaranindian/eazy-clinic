import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../data/signing_key_provider.dart';
import '../domain/verified_identity.dart';

enum TokenFailure { malformed, invalidSignature, expired, invalidClaims }

/// The token was rejected. [failure] is for logging/mapping only and is never
/// sent to clients verbatim.
class TokenVerificationException implements Exception {
  const TokenVerificationException(this.failure);
  final TokenFailure failure;
  @override
  String toString() => 'TokenVerificationException(${failure.name})';
}

abstract interface class TokenVerifier {
  Future<VerifiedIdentity> verify(String idToken);
}

/// Verifies Firebase ID tokens following Firebase's documented rules:
/// RS256, `kid` published by Google, signature, `exp`, `iat`, `auth_time` in
/// the past, `aud` = project id, `iss` = `https://securetoken.google.com/<id>`
/// and a non-empty `sub` of at most 128 characters.
class FirebaseTokenVerifier implements TokenVerifier {
  FirebaseTokenVerifier({
    required this.projectId,
    required SigningKeyProvider keys,
    DateTime Function()? clock,
    this.clockSkew = const Duration(seconds: 30),
  }) : _keys = keys,
       _clock = clock ?? DateTime.now;

  final String projectId;
  final SigningKeyProvider _keys;
  final DateTime Function() _clock;
  final Duration clockSkew;

  static const int _maxTokenLength = 8192;

  @override
  Future<VerifiedIdentity> verify(String idToken) async {
    if (idToken.isEmpty || idToken.length > _maxTokenLength) {
      throw const TokenVerificationException(TokenFailure.malformed);
    }
    final parts = idToken.split('.');
    if (parts.length != 3) {
      throw const TokenVerificationException(TokenFailure.malformed);
    }

    final Map<String, Object?> header;
    try {
      header = _decodeSegment(parts[0]);
    } on Object {
      throw const TokenVerificationException(TokenFailure.malformed);
    }
    final kid = header['kid'];
    if (header['alg'] != 'RS256' || kid is! String || kid.isEmpty) {
      // Rejects "none", HS256 key-confusion attempts and missing kid.
      throw const TokenVerificationException(TokenFailure.malformed);
    }

    final key = await _keys.keyFor(kid);
    if (key == null) {
      throw const TokenVerificationException(TokenFailure.invalidSignature);
    }

    final JWT jwt;
    try {
      jwt = JWT.verify(
        idToken,
        key,
        checkExpiresIn: false, // checked below against the injected clock
        checkNotBefore: false,
      );
    } on JWTInvalidException {
      throw const TokenVerificationException(TokenFailure.invalidSignature);
    } on JWTException {
      throw const TokenVerificationException(TokenFailure.invalidSignature);
    }

    final claims = jwt.payload;
    if (claims is! Map) {
      throw const TokenVerificationException(TokenFailure.invalidClaims);
    }
    return _validateClaims(claims.cast<String, Object?>());
  }

  VerifiedIdentity _validateClaims(Map<String, Object?> c) {
    final now = _clock();
    DateTime? ts(String name) {
      final v = c[name];
      return v is int
          ? DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true)
          : null;
    }

    final exp = ts('exp');
    final iat = ts('iat');
    final authTime = ts('auth_time');
    if (exp == null || iat == null || authTime == null) {
      throw const TokenVerificationException(TokenFailure.invalidClaims);
    }
    if (now.isAfter(exp.add(clockSkew))) {
      throw const TokenVerificationException(TokenFailure.expired);
    }
    if (iat.isAfter(now.add(clockSkew)) ||
        authTime.isAfter(now.add(clockSkew))) {
      throw const TokenVerificationException(TokenFailure.invalidClaims);
    }
    if (c['aud'] != projectId ||
        c['iss'] != 'https://securetoken.google.com/$projectId') {
      throw const TokenVerificationException(TokenFailure.invalidClaims);
    }
    final sub = c['sub'];
    if (sub is! String || sub.isEmpty || sub.length > 128) {
      throw const TokenVerificationException(TokenFailure.invalidClaims);
    }
    final firebase = (c['firebase'] as Map?)?.cast<String, Object?>();
    final provider = firebase?['sign_in_provider'];
    if (provider is! String || provider == 'anonymous') {
      // Anonymous and unknown providers are not valid application identities.
      throw const TokenVerificationException(TokenFailure.invalidClaims);
    }
    return VerifiedIdentity(
      uid: sub,
      email: c['email'] as String?,
      emailVerified: c['email_verified'] == true,
      name: c['name'] as String?,
      authTime: authTime,
      issuedAt: iat,
      expiresAt: exp,
      signInProvider: provider,
    );
  }

  static Map<String, Object?> _decodeSegment(String segment) {
    final bytes = base64Url.decode(base64Url.normalize(segment));
    return (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
  }
}
