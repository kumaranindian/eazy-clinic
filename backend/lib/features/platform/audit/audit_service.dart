import 'package:shelf/shelf.dart';

import '../../../core/data/document_store.dart';
import '../../../core/ids.dart';
import '../common/paging.dart';

/// Who performed an audited action.
class Actor {
  const Actor(this.uid, this.role);
  final String uid;

  /// `super_admin`, `platform_support_admin`, `applicant`, `clinic_owner`, `system` ...
  final String role;
}

/// One immutable audit record (`platform_audit_logs/{id}`).
///
/// `before`/`after` must contain only small, non-sensitive metadata (statuses,
/// plan ids, limits). Never put tokens, e-mail addresses or clinical data here.
class AuditEntry {
  const AuditEntry({
    required this.actor,
    required this.action,
    required this.targetType,
    required this.targetId,
    this.tenantId,
    this.reason,
    this.requestId,
    this.before,
    this.after,
  });

  final Actor actor;
  final String action;
  final String targetType;
  final String targetId;
  final String? tenantId;
  final String? reason;
  final String? requestId;
  final Map<String, Object?>? before;
  final Map<String, Object?>? after;
}

/// Append-only audit trail. There is deliberately no update or delete.
class AuditService {
  AuditService(this._store, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final DateTime Function() _clock;

  static const String collection = 'platform_audit_logs';

  /// The write for [entry], to be committed atomically with the change it
  /// describes.
  CreateOp op(AuditEntry e) => CreateOp('$collection/${newId()}', {
    'action': e.action,
    'actorUid': e.actor.uid,
    'actorRole': e.actor.role,
    'targetType': e.targetType,
    'targetId': e.targetId,
    'tenantId': e.tenantId,
    'reason': e.reason,
    'requestId': e.requestId,
    'before': e.before,
    'after': e.after,
    'timestamp': _clock().toUtc(),
  });

  /// Standalone append (failures that have no accompanying state change).
  Future<void> record(AuditEntry e) => _store.commit([op(e)]);

  /// Newest first. Optional exact-match filters (each needs an index
  /// combination listed in firestore.indexes.json).
  Future<Paged> list(
    Request request, {
    String? tenantId,
    String? action,
    String? targetType,
    String? actorUid,
  }) => runPaged(
    _store,
    DocQuery(
      collection,
      filters: [
        if (tenantId != null) QueryFilter('tenantId', FilterOp.eq, tenantId),
        if (action != null) QueryFilter('action', FilterOp.eq, action),
        if (targetType != null)
          QueryFilter('targetType', FilterOp.eq, targetType),
        if (actorUid != null) QueryFilter('actorUid', FilterOp.eq, actorUid),
      ],
      orderBy: const OrderBy('timestamp', descending: true),
    ),
    request,
  );

  Future<List<Map<String, Object?>>> recent(int n, {String? tenantId}) async {
    final rows = await _store.query(
      DocQuery(
        collection,
        filters: [
          if (tenantId != null) QueryFilter('tenantId', FilterOp.eq, tenantId),
        ],
        orderBy: const OrderBy('timestamp', descending: true),
        limit: n,
      ),
    );
    return rows.map(present).toList();
  }

  /// API shape. Phase 1 security events (`event` field) are mapped onto it.
  static Map<String, Object?> present(StoredDoc d) {
    final m = d.data;
    return {
      'id': d.id,
      'action': m['action'] ?? m['event'],
      'actorUid': m['actorUid'] ?? m['uid'],
      'actorRole': m['actorRole'],
      'targetType': m['targetType'],
      'targetId': m['targetId'],
      'tenantId': m['tenantId'],
      'reason': m['reason'],
      'requestId': m['requestId'],
      'before': m['before'],
      'after': m['after'],
      'outcome': m['outcome'],
      'timestamp': jsonSafe(m['timestamp']),
    };
  }
}
