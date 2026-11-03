import '../../../core/data/document_store.dart';
import '../../../core/ids.dart';
import '../domain/platform_user.dart';
import 'platform_user_store.dart';

/// [PlatformUserStore] on top of the generic [DocumentStore].
class DocumentPlatformUserStore implements PlatformUserStore {
  DocumentPlatformUserStore(this._store);

  final DocumentStore _store;

  static const String usersCollection = 'platform_users';
  static const String auditCollection = 'platform_audit_logs';

  @override
  Future<PlatformUser?> get(String uid) async {
    final data = await _store.get('$usersCollection/$uid');
    return data == null ? null : PlatformUser.fromMap(data);
  }

  @override
  Future<void> create(PlatformUser user) =>
      _store.commit([CreateOp('$usersCollection/${user.uid}', user.toMap())]);

  @override
  Future<void> update(String uid, Map<String, Object?> fields) =>
      _store.commit([UpdateOp('$usersCollection/$uid', fields)]);

  @override
  Future<void> appendAuditLog(Map<String, Object?> event) =>
      _store.commit([CreateOp('$auditCollection/${newId()}', event)]);
}
