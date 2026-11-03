import '../domain/platform_user.dart';

class AlreadyExistsException implements Exception {
  const AlreadyExistsException();
}

/// Persistence for platform identities and platform audit events.
abstract interface class PlatformUserStore {
  Future<PlatformUser?> get(String uid);

  /// Creates the document; throws [AlreadyExistsException] if it exists.
  Future<void> create(PlatformUser user);

  /// Merges [fields] into an existing document.
  Future<void> update(String uid, Map<String, Object?> fields);

  Future<void> appendAuditLog(Map<String, Object?> event);
}
