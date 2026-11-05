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

  static const String readDashboard = 'platform.dashboard.read';
  static const String readApplications = 'platform.applications.read';
  static const String reviewApplications = 'platform.applications.review';
  static const String readTenants = 'platform.tenants.read';
  static const String manageTenants = 'platform.tenants.manage';
  static const String readPlans = 'platform.plans.read';
  static const String managePlans = 'platform.plans.manage';
  static const String readSubscriptions = 'platform.subscriptions.read';
  static const String manageSubscriptions = 'platform.subscriptions.manage';
  static const String overrideEntitlements = 'platform.entitlements.override';
  static const String readAuditLogs = 'platform.audit.read';

  /// Phase 12: country master (read), availability/configuration (manage) and
  /// the audited assignment of a legal country to an existing tenant.
  static const String readCountries = 'platform.countries.read';
  static const String manageCountries = 'platform.countries.manage';
  static const String migrateTenantCountry = 'platform.countries.migrate';
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
      Permission.readDashboard,
      Permission.readApplications,
      Permission.reviewApplications,
      Permission.readTenants,
      Permission.manageTenants,
      Permission.readPlans,
      Permission.managePlans,
      Permission.readSubscriptions,
      Permission.manageSubscriptions,
      Permission.overrideEntitlements,
      Permission.readAuditLogs,
      Permission.readCountries,
      Permission.manageCountries,
      Permission.migrateTenantCountry,
    },
    // Support can investigate (read) but cannot change anything sensitive and
    // has no access to audit logs or clinical data.
    PlatformRole.platformSupportAdmin: {
      Permission.readPlatformUsers,
      Permission.readDashboard,
      Permission.readApplications,
      Permission.readTenants,
      Permission.readPlans,
      Permission.readSubscriptions,
      Permission.readCountries,
    },
  };

  static Set<String> forPlatformRole(PlatformRole? role) =>
      role == null ? const {} : (_platform[role] ?? const {});

  static bool platformRoleHas(PlatformRole? role, String permission) =>
      forPlatformRole(role).contains(permission);

  static Set<String> forClinicRole(ClinicRole? role) => const {};

  static Set<String> forPatientRole(PatientRole? role) => const {};
}
