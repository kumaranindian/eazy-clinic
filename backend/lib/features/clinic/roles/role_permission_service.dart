import 'package:common_models/common_models.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../platform/audit/audit_service.dart';
import '../../platform/common/body_reader.dart';
import '../common/clinic_deps.dart';
import '../common/tenant_context.dart';

/// Per-clinic adjustments of what each role may do.
///
/// A clinic starts from the built-in defaults (`ClinicRolePolicy`). The owner
/// can grant a role extra permissions or take default ones away; the effective
/// set is `(defaults + granted) - revoked`, read from the server on every
/// request, so a change applies at once and a client can never widen it.
///
/// Guard rails that no configuration can remove:
///  * the owner role always holds every permission and cannot be edited;
///  * `roles.manage` cannot be granted to another role (no hand-over of the
///    power to change permissions, so no self-escalation path);
///  * only known clinic permissions are accepted (no platform permissions);
///  * clinical authoring still requires the doctor role with a linked doctor
///    profile, whatever a role is granted (enforced by the clinical services);
///  * every change needs a reason and is written to the audit log.
class RolePermissionService {
  RolePermissionService(this._d);

  final ClinicDeps _d;

  static const String collection = 'role_permissions';

  /// Permissions only the owner may ever hold.
  static const Set<String> ownerOnly = {ClinicPermission.rolesManage};

  String _path(String tenantId, ClinicRole role) =>
      'tenants/$tenantId/$collection/${role.wireName}';

  static Set<String> _apply(ClinicRole role, DocData? doc) {
    final base = ClinicRolePolicy.permissionsFor(role);
    if (doc == null || role == ClinicRole.clinicOwner) return base;
    final grant = ((doc['grant'] as List?) ?? const []).cast<String>();
    final revoke = ((doc['revoke'] as List?) ?? const []).cast<String>();
    return {
      ...base,
      // stale keys (a permission that no longer exists) are ignored
      ...grant.where(
        (p) => ClinicPermission.isKnown(p) && !ownerOnly.contains(p),
      ),
    }..removeAll(revoke);
  }

  /// The effective permissions of [role] in a clinic, or null when the clinic
  /// has not changed that role (the caller then uses the defaults).
  Future<Set<String>?> effective(String tenantId, ClinicRole role) async {
    if (role == ClinicRole.clinicOwner) return null;
    final doc = await _d.store.get(_path(tenantId, role));
    return doc == null ? null : _apply(role, doc);
  }

  /// Every role with its effective permissions and its adjustments.
  Future<
    Map<
      ClinicRole,
      ({Set<String> permissions, List<String> grant, List<String> revoke})
    >
  >
  matrix(String tenantId) async {
    final rows = await _d.store.query(
      DocQuery('tenants/$tenantId/$collection', limit: 50),
    );
    final byRole = {for (final r in rows) r.id: r.data};
    return {
      for (final role in ClinicRole.values)
        role: (
          permissions: _apply(role, byRole[role.wireName]),
          grant: role == ClinicRole.clinicOwner
              ? const <String>[]
              : ((byRole[role.wireName]?['grant'] as List?) ?? const [])
                    .cast<String>(),
          revoke: role == ClinicRole.clinicOwner
              ? const <String>[]
              : ((byRole[role.wireName]?['revoke'] as List?) ?? const [])
                    .cast<String>(),
        ),
    };
  }

  ClinicRole _editable(String raw) {
    final role = ClinicRole.tryParse(raw);
    if (role == null) throw const ApiException.notFound('Role not found.');
    if (role == ClinicRole.clinicOwner) {
      throw const ApiException.conflict(
        'The owner role always has every permission and cannot be changed.',
      );
    }
    return role;
  }

  List<String>? _list(BodyReader r, String field) {
    if (!r.has(field)) return const [];
    final v = r.body[field];
    if (v is! List || v.length > 200 || v.any((e) => e is! String)) {
      r.addIssue(field, 'invalid_value', 'Give a list of permission keys.');
      return null;
    }
    final keys = v.cast<String>().toSet();
    for (final k in keys) {
      if (!ClinicPermission.isKnown(k)) {
        r.addIssue(field, 'unknown_permission', '$k is not a permission.');
      }
    }
    return keys.toList()..sort();
  }

  Map<String, Object?> _present(ClinicRole role, DocData? doc) => {
    'role': role.wireName,
    'permissions': _apply(role, doc).toList()..sort(),
    'grant': ((doc?['grant'] as List?) ?? const []).cast<String>(),
    'revoke': ((doc?['revoke'] as List?) ?? const []).cast<String>(),
    'custom': doc != null,
  };

  /// Replaces the adjustments of one role.
  Future<Map<String, Object?>> set(
    TenantContext t,
    String roleName,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.rolesManage);
    final role = _editable(roleName);
    final r = BodyReader(body)..rejectUnknown({'grant', 'revoke', 'reason'});
    final grantIn = _list(r, 'grant');
    final revokeIn = _list(r, 'revoke');
    final reason = r.str('reason', min: 5, max: 300);
    if (grantIn != null && revokeIn != null) {
      if (grantIn.any(revokeIn.contains)) {
        r.addIssue(
          'revoke',
          'conflict',
          'A permission cannot be both granted and revoked.',
        );
      }
      for (final p in grantIn.where(ownerOnly.contains)) {
        r.addIssue('grant', 'owner_only', '$p can only be held by the owner.');
      }
    }
    r.throwIfInvalid();
    final base = ClinicRolePolicy.permissionsFor(role);
    // keep only what differs from the defaults
    final grant = grantIn!.where((p) => !base.contains(p)).toList();
    final revoke = revokeIn!.where(base.contains).toList();
    final path = _path(t.tenantId, role);
    return _d.store.transaction((tx) async {
      final cur = await tx.get(path);
      final now = _d.now;
      final doc = <String, Object?>{
        'role': role.wireName,
        'tenantId': t.tenantId,
        'grant': grant,
        'revoke': revoke,
        'version': ((cur?['version'] as int?) ?? 0) + 1,
        'updatedBy': t.uid,
        'updatedAt': now,
      };
      tx.write([
        cur == null
            ? CreateOp(path, {...doc, 'createdAt': now})
            : UpdateOp(path, doc),
        _d.audit.op(
          AuditEntry(
            actor: _d.actorOf(t),
            action: 'role.permissions_changed',
            targetType: 'role',
            targetId: role.wireName,
            tenantId: t.tenantId,
            reason: reason,
            requestId: requestId,
            before: {
              'grant': cur?['grant'] ?? const <String>[],
              'revoke': cur?['revoke'] ?? const <String>[],
            },
            after: {'grant': grant, 'revoke': revoke},
          ),
        ),
      ]);
      return _present(role, doc);
    });
  }

  /// Returns one role to the built-in defaults.
  Future<Map<String, Object?>> reset(
    TenantContext t,
    String roleName,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.rolesManage);
    final role = _editable(roleName);
    final r = BodyReader(body)..rejectUnknown({'reason'});
    final reason = r.str('reason', min: 5, max: 300);
    r.throwIfInvalid();
    final path = _path(t.tenantId, role);
    return _d.store.transaction((tx) async {
      final cur = await tx.get(path);
      if (cur == null) {
        return {..._present(role, null), 'idempotentReplay': true};
      }
      tx.write([
        DeleteOp(path),
        _d.audit.op(
          AuditEntry(
            actor: _d.actorOf(t),
            action: 'role.permissions_reset',
            targetType: 'role',
            targetId: role.wireName,
            tenantId: t.tenantId,
            reason: reason,
            requestId: requestId,
            before: {'grant': cur['grant'], 'revoke': cur['revoke']},
            after: const {'grant': <String>[], 'revoke': <String>[]},
          ),
        ),
      ]);
      return _present(role, null);
    });
  }
}
