import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

/// Supplies Google's public signing keys, addressed by key id (`kid`).
abstract interface class SigningKeyProvider {
  /// Returns the public key for [kid], or `null` when Google does not
  /// publish it. Throws [SigningKeysUnavailableException] when keys cannot be
  /// fetched at all.
  Future<RSAPublicKey?> keyFor(String kid);
}

class SigningKeysUnavailableException implements Exception {
  const SigningKeysUnavailableException();
}

/// Fetches Firebase Auth's x509 certificates and caches them for the
/// `max-age` Google specifies.
class GoogleSigningKeyProvider implements SigningKeyProvider {
  GoogleSigningKeyProvider({
    required http.Client client,
    Uri? endpoint,
    DateTime Function()? clock,
    this.minRefreshInterval = const Duration(minutes: 1),
  }) : _client = client,
       _endpoint = endpoint ?? defaultEndpoint,
       _clock = clock ?? DateTime.now;

  static final Uri defaultEndpoint = Uri.parse(
    'https://www.googleapis.com/robot/v1/metadata/x509/'
    'securetoken@system.gserviceaccount.com',
  );

  final http.Client _client;
  final Uri _endpoint;
  final DateTime Function() _clock;
  final Duration minRefreshInterval;

  Map<String, RSAPublicKey> _keys = const {};
  DateTime _expiresAt = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  Future<RSAPublicKey?> keyFor(String kid) async {
    final now = _clock();
    if (now.isAfter(_expiresAt)) {
      await _refresh();
    } else if (!_keys.containsKey(kid) &&
        now.difference(_lastFetch) >= minRefreshInterval) {
      // Possible key rotation: refetch, but at most once per interval so an
      // attacker cannot force a fetch per request with random kids.
      await _refresh();
    }
    return _keys[kid];
  }

  Future<void> _refresh() async {
    _lastFetch = _clock();
    final http.Response response;
    try {
      response = await _client.get(_endpoint);
    } on Object {
      throw const SigningKeysUnavailableException();
    }
    if (response.statusCode != 200) {
      throw const SigningKeysUnavailableException();
    }
    try {
      final decoded = (jsonDecode(response.body) as Map)
          .cast<String, Object?>();
      _keys = {
        for (final e in decoded.entries)
          e.key: RSAPublicKey.cert(e.value! as String),
      };
    } on Object {
      throw const SigningKeysUnavailableException();
    }
    final maxAge = RegExp(
      r'max-age=(\d+)',
    ).firstMatch(response.headers['cache-control'] ?? '');
    final seconds = int.tryParse(maxAge?.group(1) ?? '') ?? 3600;
    _expiresAt = _clock().add(Duration(seconds: seconds));
  }
}
