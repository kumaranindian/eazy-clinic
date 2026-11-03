import 'roles.dart';

/// Permission identifiers (`<scope>.<resource>.<action>`).
///
/// Phase 1 defines only the platform-level permissions that backend code
/// already checks. Clinic and patient permissions are added with their modules
/// (Phase 2+), and the clinic owner will be able to configure the mapping.
abstract final class Permission {
  /// Revoke another user's Firebase sessions (security incident handling).
  static const String revokeUserSessions = 'platform.users.revoke_sessions';

  /// Read a platform user's account profile.
  static const String readPlatformUsers = 'platform.users.read';

  /// Change an account's status (deferred; no endpoint yet).
  static const String changeAccountStatus = 'platform.users.change_status';
}

/// Maps roles to permissions. Backend policies call this; apps must never use
/// it as an authorization decision (UI hints only).
///
/// Clinic and patient role mappings are intentionally empty in Phase 1: those
/// roles can only be granted through membership workflows that do not exist
/// yet, and unknown roles are denied by default.
abstract final class PermissionPolicy {
  static const Map<PlatformRole, Set<String>> _platform = {
    PlatformRole.superAdmin: {
      Permission.revokeUserSessions,
      Permission.readPlatformUsers,
      Permission.changeAccountStatus,
    },
    PlatformRole.platformSupportAdmin: {Permission.readPlatformUsers},
  };

  static Set<String> forPlatformRole(PlatformRole? role) =>
      role == null ? const {} : (_platform[role] ?? const {});

  static bool platformRoleHas(PlatformRole? role, String permission) =>
      forPlatformRole(role).contains(permission);

  static Set<String> forClinicRole(ClinicRole? role) => const {};

  static Set<String> forPatientRole(PatientRole? role) => const {};
}
