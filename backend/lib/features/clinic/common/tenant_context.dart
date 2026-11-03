import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';
import 'package:shelf/shelf.dart';

import '../../../core/errors/api_exception.dart';
import '../../auth/domain/auth_context.dart';
import '../../platform/entitlements/entitlement_service.dart';

/// Which branches a caller may act on. Comes from the trusted membership
/// record; a branch chosen in the UI never widens it.
class BranchScope {
  const BranchScope({required this.allBranches, required this.branchIds});

  final bool allBranches;
  final Set<String> branchIds;

  bool allows(String branchId) => allBranches || branchIds.contains(branchId);

  /// Throws 404 (existence of out-of-scope branches is not revealed).
  void require(String branchId) {
    if (!allows(branchId))
      throw const ApiException.notFound('Branch not found.');
  }

  /// Whether every id in [ids] is inside this scope.
  bool containsAll(Iterable<String> ids) =>
      allBranches || ids.every(branchIds.contains);
}

/// Everything the backend knows about the caller *in one tenant*, derived from
/// server-side records only.
class TenantContext {
  const TenantContext({
    required this.tenantId,
    required this.uid,
    required this.role,
    required this.scope,
    required this.entitlements,
  });

  final String tenantId;
  final String uid;
  final ClinicRole role;
  final BranchScope scope;
  final Entitlements entitlements;

  Set<String> get permissions => ClinicRolePolicy.permissionsFor(role);

  bool can(String permission) => permissions.contains(permission);

  void require(String permission) {
    if (!can(permission)) throw const ApiException.forbidden();
  }
}

/// Picks the membership the request acts in. `X-Tenant-Id` only *selects*
/// among the caller's own memberships; it never grants access.
MembershipSummaryDto selectMembership(AuthContext auth, Request request) {
  final memberships = auth.memberships;
  if (memberships.isEmpty) {
    throw const ApiException.forbidden('You do not have access to a clinic.');
  }
  final selector = request.headers['x-tenant-id']?.trim();
  if (selector != null && selector.isNotEmpty) {
    final match = memberships.where((m) => m.tenantId == selector);
    if (match.isEmpty) {
      throw const ApiException.forbidden(
        'You do not have access to this clinic.',
      );
    }
    return match.first;
  }
  if (memberships.length == 1) return memberships.first;
  throw const ApiException.conflict(
    'You belong to several clinics. Send X-Tenant-Id to choose one.',
  );
}

/// Builds the [TenantContext] for a request and applies the subscription /
/// tenant-status policy: blocked tenants answer 403, read-only tenants refuse
/// writes.
Future<TenantContext> resolveTenantContext({
  required AuthContext auth,
  required Request request,
  required EntitlementService entitlements,
  required bool write,
}) async {
  final m = selectMembership(auth, request);
  final role = ClinicRole.tryParse(m.role);
  if (role == null) throw const ApiException.forbidden();
  final ent = await entitlements.forTenant(m.tenantId);
  if (ent.accessLevel == AccessLevel.blocked) {
    throw ApiException.forbidden(
      'Your clinic account is restricted (${ent.reason}).',
    );
  }
  if (write && !ent.writesAllowed) {
    throw ApiException.forbidden(
      'Changes are not allowed right now (${ent.reason}).',
    );
  }
  return TenantContext(
    tenantId: m.tenantId,
    uid: auth.user.uid,
    role: role,
    scope: BranchScope(
      allBranches: m.allBranches,
      branchIds: m.branchIds.toSet(),
    ),
    entitlements: ent,
  );
}
