import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/platform_user.dart';
import 'firestore_codec.dart';
import 'platform_user_store.dart';

/// Firestore (REST) implementation. [client] must already carry service
/// account credentials (Application Default Credentials in production).
/// Clients never reach Firestore: rules are deny-all.
class FirestorePlatformUserStore implements PlatformUserStore {
  FirestorePlatformUserStore({
    required this.projectId,
    required http.Client client,
    this.host = 'https://firestore.googleapis.com',
  }) : _client = client;

  final String projectId;
  final String host;
  final http.Client _client;

  String get _documents =>
      '$host/v1/projects/$projectId/databases/(default)/documents';

  static const String usersCollection = 'platform_users';
  static const String auditCollection = 'platform_audit_logs';

  @override
  Future<PlatformUser?> get(String uid) async {
    final response = await _client.get(
      Uri.parse('$_documents/$usersCollection/${Uri.encodeComponent(uid)}'),
    );
    if (response.statusCode == 404) return null;
    _ensureOk(response);
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final fields = (body['fields'] as Map?)?.cast<String, Object?>() ?? {};
    return PlatformUser.fromMap(decodeFields(fields));
  }

  @override
  Future<void> create(PlatformUser user) async {
    final response = await _client.post(
      Uri.parse(
        '$_documents/$usersCollection'
        '?documentId=${Uri.encodeQueryComponent(user.uid)}',
      ),
      headers: _json,
      body: jsonEncode({'fields': encodeFields(user.toMap())}),
    );
    if (response.statusCode == 409) throw const AlreadyExistsException();
    _ensureOk(response);
  }

  @override
  Future<void> update(String uid, Map<String, Object?> fields) async {
    final mask = fields.keys
        .map((k) => 'updateMask.fieldPaths=${Uri.encodeQueryComponent(k)}')
        .join('&');
    final response = await _client.patch(
      Uri.parse(
        '$_documents/$usersCollection/${Uri.encodeComponent(uid)}'
        '?$mask&currentDocument.exists=true',
      ),
      headers: _json,
      body: jsonEncode({'fields': encodeFields(fields)}),
    );
    _ensureOk(response);
  }

  @override
  Future<void> appendAuditLog(Map<String, Object?> event) async {
    final response = await _client.post(
      Uri.parse('$_documents/$auditCollection'),
      headers: _json,
      body: jsonEncode({'fields': encodeFields(event)}),
    );
    _ensureOk(response);
  }

  static const Map<String, String> _json = {'content-type': 'application/json'};

  /// Errors never include the response body (may echo document content).
  void _ensureOk(http.Response r) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw StoreException('Firestore request failed (${r.statusCode}).');
    }
  }
}

class StoreException implements Exception {
  const StoreException(this.message);
  final String message;
  @override
  String toString() => 'StoreException: $message';
}
