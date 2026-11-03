import 'package:api_contracts/api_contracts.dart';

import 'platform_user.dart';

/// Resolves which tenants/roles an account may act in, from trusted
/// server-side records only.
///
/// Phase 1 ships [NoMembershipsAccessResolver]. Phase 3 replaces it with a
/// Firestore-backed resolver reading `members`; callers do not change.
abstract interface class AccessResolver {
  Future<List<MembershipSummaryDto>> membershipsFor(PlatformUser user);
}

/// No membership model exists yet, so nobody has clinic access.
class NoMembershipsAccessResolver implements AccessResolver {
  const NoMembershipsAccessResolver();

  @override
  Future<List<MembershipSummaryDto>> membershipsFor(PlatformUser user) async =>
      const [];
}
