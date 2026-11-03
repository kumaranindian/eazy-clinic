import 'package:api_contracts/api_contracts.dart';

import 'platform_user.dart';
import 'verified_identity.dart';

/// Request-scoped, server-derived authorization context.
class AuthContext {
  const AuthContext({
    required this.identity,
    required this.user,
    required this.memberships,
  });

  final VerifiedIdentity identity;
  final PlatformUser user;

  /// Clinic memberships resolved from trusted records (empty until Phase 3).
  final List<MembershipSummaryDto> memberships;
}
