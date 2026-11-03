import 'dart:convert';

import 'package:http/http.dart' as http;

/// What the identity provider says about an account.
class AuthUserRecord {
  const AuthUserRecord({required this.disabled, this.validSince});

  final bool disabled;

  /// Refresh tokens issued before this instant are revoked.
  final DateTime? validSince;
}

/// Privileged Firebase Authentication operations (service account only).
abstract interface class FirebaseAuthAdmin {
  /// `null` when the Firebase user no longer exists.
  Future<AuthUserRecord?> lookup(String uid);

  /// Revokes all refresh tokens of [uid] (sets `validSince` to now).
  Future<void> revokeRefreshTokens(String uid);
}

class AuthAdminException implements Exception {
  const AuthAdminException(this.message);
  final String message;
  @override
  String toString() => 'AuthAdminException: $message';
}

/// Identity Toolkit REST implementation of [FirebaseAuthAdmin]. [client] must
/// carry service-account credentials.
class IdentityToolkitAuthAdmin implements FirebaseAuthAdmin {
  IdentityToolkitAuthAdmin({
    required this.projectId,
    required http.Client client,
    this.host = 'https://identitytoolkit.googleapis.com',
    DateTime Function()? clock,
  }) : _client = client,
       _clock = clock ?? DateTime.now;

  final String projectId;
  final String host;
  final http.Client _client;
  final DateTime Function() _clock;

  static const Map<String, String> _json = {'content-type': 'application/json'};

  @override
  Future<AuthUserRecord?> lookup(String uid) async {
    final response = await _client.post(
      Uri.parse('$host/v1/projects/$projectId/accounts:lookup'),
      headers: _json,
      body: jsonEncode({
        'localId': [uid],
      }),
    );
    if (response.statusCode != 200) {
      throw AuthAdminException(
        'Account lookup failed (${response.statusCode}).',
      );
    }
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final users = (body['users'] as List?) ?? const [];
    if (users.isEmpty) return null;
    final user = (users.first as Map).cast<String, Object?>();
    final seconds = int.tryParse('${user['validSince'] ?? ''}');
    return AuthUserRecord(
      disabled: user['disabled'] == true,
      validSince: seconds == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
    );
  }

  @override
  Future<void> revokeRefreshTokens(String uid) async {
    final seconds = _clock().millisecondsSinceEpoch ~/ 1000;
    final response = await _client.post(
      Uri.parse('$host/v1/projects/$projectId/accounts:update'),
      headers: _json,
      body: jsonEncode({'localId': uid, 'validSince': '$seconds'}),
    );
    if (response.statusCode != 200) {
      throw AuthAdminException(
        'Session revocation failed (${response.statusCode}).',
      );
    }
  }
}
