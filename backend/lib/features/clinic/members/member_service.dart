import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../../core/data/document_store.dart';
import '../../../core/errors/api_exception.dart';
import '../../platform/audit/audit_service.dart';
import '../../platform/common/body_reader.dart';
import '../../platform/common/paging.dart';
import '../branches/branch_service.dart';
import '../common/clinic_deps.dart';
import '../common/tenant_context.dart';
import '../staff/staff_service.dart';

const Map<String, String> _roleDescriptions = {
  'clinic_owner':
      'Owns the clinic. Full access; ownership cannot be changed from the app.',
  'clinic_admin':
      'Runs the clinic day to day: branches, doctors, staff and settings.',
  'doctor': 'Clinician. Read access to clinic information in this phase.',
  'receptionist':
      'Front desk. Read access to clinic information in this phase.',
  'nurse': 'Nursing staff. Read access to clinic information in this phase.',
  'accountant':
      'Finance staff. Read access to clinic information in this phase.',
  'lab_technician':
      'Laboratory staff. Read access to clinic information in this phase.',
  'pharmacist':
      'Pharmacy staff. Read access to clinic information in this phase.',
};

/// Roles, permissions and member (membership) administration.
///
/// A membership is separate from the Firebase account: changing or removing
/// it never touches the account or other clinics. Effective permissions are
/// recomputed from the stored role on every request, so a role change takes
/// effect immediately.
class MemberService {
  MemberService(this._d, this._staff, this._branches);

  final ClinicDeps _d;
  final StaffService _staff;
  final BranchService _branches;

  FieldIssue _issue(String f, String c, String m) =>
      FieldIssue(field: f, code: c, message: m);

  // --------------------------------------------------------------- catalog

  List<Map<String, Object?>> roles(TenantContext t) {
    t.require(ClinicPermission.rolesView);
    return [
      for (final r in ClinicRole.values)
        {
          'role': r.wireName,
          'description': _roleDescriptions[r.wireName],
          'permissions': ClinicRolePolicy.permissionsFor(r).toList()..sort(),
          'assignableByYou': ClinicRolePolicy.canGrant(t.role, r),
          'custom': false,
        },
    ];
  }

  Map<String, Object?> permissionCatalog(TenantContext t) {
    t.require(ClinicPermission.permissionsView);
    final groups = <String, List<String>>{};
    for (final p in ClinicPermission.all) {
      groups.putIfAbsent(p.split('.').first, () => []).add(p);
    }
    return {
      'groups': groups,
      'matrix': {
        for (final r in ClinicRole.values)
          r.wireName: ClinicRolePolicy.permissionsFor(r).toList()..sort(),
      },
      'customRoles': 'deferred',
    };
  }

  Future<Map<String, Object?>> currentPermissions(TenantContext t) async {
    final branches = <Map<String, Object?>>[];
    if (t.can(ClinicPermission.branchesView)) {
      final rows = t.scope.allBranches
          ? await _d.store.query(
              DocQuery(
                _d.path(t, 'branches'),
                orderBy: const OrderBy('createdAt'),
                limit: 100,
              ),
            )
          : [
              for (final id in t.scope.branchIds.take(100))
                if (await _branches.find(t, id) case final b?)
                  StoredDoc(_d.path(t, 'branches', id), b),
            ];
      for (final b in rows) {
        branches.add({
          'branchId': b.data['branchId'],
          'name': b.data['name'],
          'code': b.data['code'],
          'status': b.data['status'],
        });
      }
    }
    return {
      'tenantId': t.tenantId,
      'role': t.role.wireName,
      'permissions': t.permissions.toList()..sort(),
      'allBranches': t.scope.allBranches,
      'branchIds': t.scope.branchIds.toList(),
      'branches': branches,
      'accessLevel': t.entitlements.accessLevel.wireName,
      'writesAllowed': t.entitlements.writesAllowed,
    };
  }

  // ----------------------------------------------------------------- list

  Future<Paged> list(
    TenantContext t,
    Request request, {
    String? role,
    String? status,
  }) async {
    t.require(ClinicPermission.staffView);
    if (role != null && ClinicRole.tryParse(role) == null) {
      throw const ApiException.badRequest('role has an unsupported value.');
    }
    final page = await runPaged(
      _d.store,
      DocQuery(
        _d.path(t, 'members'),
        filters: [
          if (role != null) QueryFilter('role', FilterOp.eq, role),
          if (status != null) QueryFilter('status', FilterOp.eq, status),
        ],
        orderBy: const OrderBy('createdAt', descending: true),
      ),
      request,
    );
    if (t.scope.allBranches) return page;
    return Paged(
      page.docs
          .where(
            (d) =>
                d.data['allBranches'] != true &&
                ((d.data['branchIds'] as List?) ?? const []).cast<String>().any(
                  t.scope.allows,
                ),
          )
          .toList(),
      page.meta,
    );
  }

  Future<Map<String, Object?>> present(
    TenantContext t,
    Map<String, Object?> m,
  ) async {
    var name = m['displayName'] as String?;
    var email = m['email'] as String?;
    if (name == null || name.isEmpty || email == null) {
      final u = await _d.store.get('platform_users/${m['uid']}');
      name = (name?.isNotEmpty ?? false) ? name : u?['displayName'] as String?;
      email ??= u?['email'] as String?;
    }
    return {
      'memberId': m['uid'],
      'uid': m['uid'],
      'role': m['role'],
      'status': m['status'],
      'allBranches':
          m['allBranches'] ?? ((m['branchIds'] as List?)?.isEmpty ?? true),
      'branchIds': m['branchIds'] ?? <String>[],
      'staffId': m['staffId'],
      'doctorId': m['doctorId'],
      'displayName': name,
      'email': email,
      'isYou': m['uid'] == t.uid,
      'createdAt': jsonSafe(m['createdAt']),
    };
  }

  // ------------------------------------------------------- role / branches

  Future<Map<String, Object?>> _loadManageable(
    TenantContext t,
    String uid,
  ) async {
    final m = await _d.store.get(_d.path(t, 'members', uid));
    if (m == null) throw const ApiException.notFound('Member not found.');
    if (uid == t.uid) {
      throw const ApiException.forbidden('You cannot change your own access.');
    }
    final role = ClinicRole.tryParse('${m['role']}');
    if (role == null || !ClinicRolePolicy.canManageMember(t.role, role)) {
      throw const ApiException.forbidden(
        'You are not allowed to manage this member.',
      );
    }
    final all = m['allBranches'] == true;
    final ids = ((m['branchIds'] as List?) ?? const []).cast<String>();
    if (!t.scope.allBranches) {
      if (all || !ids.any(t.scope.allows)) {
        throw const ApiException.notFound('Member not found.');
      }
      if (!t.scope.containsAll(ids)) {
        throw const ApiException.forbidden(
          'This member also works outside your branches.',
        );
      }
    }
    return m;
  }

  Future<Map<String, Object?>> updateRole(
    TenantContext t,
    String uid,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.staffAssignRole);
    final r = BodyReader(body)..rejectUnknown({'role'});
    r.str('role', max: 30);
    r.throwIfInvalid();
    final scope = await _staff.validateRoleAndScope(
      t,
      role: body['role'],
      allBranches: null,
      branchIds: null,
      requireRole: false,
    );
    final newRole = scope['role']! as String;
    final now = _d.now;
    final cur = await _loadManageable(t, uid);
    if (cur['role'] == newRole) {
      throw const ApiException.conflict('The member already has this role.');
    }
    final patched = await _d.store.transaction((tx) async {
      final m = await tx.get(_d.path(t, 'members', uid));
      if (m == null) throw const ApiException.notFound('Member not found.');
      if (m['role'] == ClinicRole.clinicOwner.wireName) {
        throw const ApiException.forbidden();
      }
      final patch = {'role': newRole, 'updatedAt': now, 'updatedBy': t.uid};
      final staffId = m['staffId'] as String?;
      tx.write([
        UpdateOp(_d.path(t, 'members', uid), patch),
        if (staffId != null)
          UpdateOp(_d.path(t, 'staff', staffId), {
            'role': newRole,
            'updatedAt': now,
            'updatedBy': t.uid,
          }),
        _d.audit.op(
          AuditEntry(
            actor: _d.actorOf(t),
            action: 'member.role_changed',
            targetType: 'member',
            targetId: uid,
            tenantId: t.tenantId,
            requestId: requestId,
            before: {'role': m['role']},
            after: {'role': newRole},
          ),
        ),
      ]);
      return {...m, ...patch};
    });
    return present(t, patched);
  }

  Future<Map<String, Object?>> updateBranches(
    TenantContext t,
    String uid,
    Map<String, Object?> body, {
    String? requestId,
  }) async {
    t.require(ClinicPermission.staffAssignBranch);
    final r = BodyReader(body)..rejectUnknown({'allBranches', 'branchIds'});
    r.throwIfInvalid();
    final scope = await _staff.validateRoleAndScope(
      t,
      role: null,
      allBranches: body['allBranches'],
      branchIds: body['branchIds'],
      requireRole: false,
    );
    if (!scope.containsKey('allBranches')) {
      throw ApiException.validation([
        _issue('branchIds', 'required', 'Provide branchIds or allBranches.'),
      ]);
    }
    final now = _d.now;
    final cur = await _loadManageable(t, uid);
    if (cur['doctorId'] != null) {
      throw const ApiException.conflict(
        "A doctor's branches follow their branch assignments. Change them from the doctor's profile.",
      );
    }
    final patched = await _d.store.transaction((tx) async {
      final m = await tx.get(_d.path(t, 'members', uid));
      if (m == null) throw const ApiException.notFound('Member not found.');
      final patch = {...scope, 'updatedAt': now, 'updatedBy': t.uid};
      final staffId = m['staffId'] as String?;
      tx.write([
        UpdateOp(_d.path(t, 'members', uid), patch),
        if (staffId != null)
          UpdateOp(_d.path(t, 'staff', staffId), {
            ...scope,
            'updatedAt': now,
            'updatedBy': t.uid,
          }),
        _d.audit.op(
          AuditEntry(
            actor: _d.actorOf(t),
            action: 'member.branches_changed',
            targetType: 'member',
            targetId: uid,
            tenantId: t.tenantId,
            requestId: requestId,
            before: {
              'allBranches': m['allBranches'],
              'branchIds': m['branchIds'],
            },
            after: {
              'allBranches': scope['allBranches'],
              'branchIds': scope['branchIds'],
            },
          ),
        ),
      ]);
      return {...m, ...patch};
    });
    return present(t, patched);
  }
}
