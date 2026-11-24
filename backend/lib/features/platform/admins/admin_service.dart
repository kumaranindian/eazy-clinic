import 'package:common_models/common_models.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../audit/audit_service.dart';

/// Platform administrators: who holds `super_admin` or
/// `platform_support_admin`, granting and removing those roles.
///
/// Rules:
///  * only a super admin may change roles (route permission);
///  * the person must already have a registered, active, e-mail-verified
///    account: a role is never attached to an address that has not signed up;
///  * nobody changes their own role;
///  * the last active super admin cannot be removed or demoted;
///  * every change needs a reason and is written to the platform audit log
///    (uids and roles only, never e-mail addresses).
/// The role is read from the server on every request, so a change takes
/// effect immediately; no token needs to be revoked.
class AdminService {
  AdminService(this._store, this._audit, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final DocumentStore _store;
  final AuditService _audit;
  final DateTime Function() _clock;

  static const String users = 'platform_users';
  static final List<String> _roles = [
    for (final r in PlatformRole.values) r.wireName,
  ];

  Map<String, Object?> _present(DocData u) => {
    'uid': u['uid'],
    'displayName': u['displayName'],
    'email': u['email'],
    'platformRole': u['platformRole'],
    'accountStatus': u['accountStatus'],
    'lastLoginAt': (u['lastLoginAt'] as DateTime?)?.toUtc().toIso8601String(),
  };

  Future<List<Map<String, Object?>>> list() async {
    final rows = await _store.query(
      DocQuery(
        users,
        filters: [QueryFilter('platformRole', FilterOp.inList, _roles)],
        limit: 200,
      ),
    );
    return [for (final r in rows) _present(r.data)]..sort(
      (a, b) => '${a['displayName']}'.toLowerCase().compareTo(
        '${b['displayName']}'.toLowerCase(),
      ),
    );
  }

  Future<int> _activeSupers(TxContext tx, {String? except}) async {
    final rows = await tx.query(
      DocQuery(
        users,
        filters: [
          QueryFilter(
            'platformRole',
            FilterOp.eq,
            PlatformRole.superAdmin.wireName,
          ),
        ],
        limit: 200,
      ),
    );
    return rows
        .where(
          (r) => r.data['accountStatus'] == 'active' && r.data['uid'] != except,
        )
        .length;
  }

  /// Gives [role] to the registered account with [email].
  Future<Map<String, Object?>> grant(
    Actor actor, {
    required String email,
    required String role,
    required String reason,
    String? requestId,
  }) async {
    if (!_roles.contains(role)) {
      throw const ApiException.badRequest('role has an unsupported value.');
    }
    final found = await _store.query(
      DocQuery(
        users,
        filters: [
          QueryFilter('email', FilterOp.eq, email.trim().toLowerCase()),
        ],
        limit: 2,
      ),
    );
    if (found.length != 1) {
      throw const ApiException.notFound(
        'No registered account has that e-mail address. The person must sign up first.',
      );
    }
    final uid = '${found.single.data['uid']}';
    if (uid == actor.uid) {
      throw const ApiException.conflict('You cannot change your own role.');
    }
    return _store.transaction((tx) async {
      final u = await tx.get('$users/$uid');
      if (u == null) throw const ApiException.notFound('Account not found.');
      if (u['accountStatus'] != 'active' || u['emailVerified'] != true) {
        throw const ApiException.conflict(
          'The account must be active and have a verified e-mail address.',
        );
      }
      final before = u['platformRole'] as String?;
      if (before == role) return {..._present(u), 'idempotentReplay': true};
      if (before == PlatformRole.superAdmin.wireName &&
          await _activeSupers(tx, except: uid) == 0) {
        throw const ApiException.conflict(
          'The last super admin cannot be demoted.',
        );
      }
      final patch = {'platformRole': role, 'updatedAt': _clock().toUtc()};
      tx.write([
        UpdateOp('$users/$uid', patch),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'platform_admin.granted',
            targetType: 'platform_user',
            targetId: uid,
            reason: reason,
            requestId: requestId,
            before: {'platformRole': before},
            after: {'platformRole': role},
          ),
        ),
      ]);
      return _present({...u, ...patch});
    });
  }

  /// Removes the platform role of [uid].
  Future<Map<String, Object?>> revoke(
    Actor actor,
    String uid, {
    required String reason,
    String? requestId,
  }) async {
    if (uid == actor.uid) {
      throw const ApiException.conflict('You cannot remove your own role.');
    }
    return _store.transaction((tx) async {
      final u = await tx.get('$users/$uid');
      final before = u?['platformRole'] as String?;
      if (u == null || before == null) {
        throw const ApiException.notFound('Administrator not found.');
      }
      if (before == PlatformRole.superAdmin.wireName &&
          await _activeSupers(tx, except: uid) == 0) {
        throw const ApiException.conflict(
          'The last super admin cannot be removed.',
        );
      }
      tx.write([
        UpdateOp('$users/$uid', {
          'platformRole': null,
          'updatedAt': _clock().toUtc(),
        }),
        _audit.op(
          AuditEntry(
            actor: actor,
            action: 'platform_admin.revoked',
            targetType: 'platform_user',
            targetId: uid,
            reason: reason,
            requestId: requestId,
            before: {'platformRole': before},
            after: {'platformRole': null},
          ),
        ),
      ]);
      return {..._present(u), 'platformRole': null};
    });
  }
}
