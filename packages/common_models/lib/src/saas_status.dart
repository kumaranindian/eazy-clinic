// Status enums and transition rules for the SaaS control plane (Phase 2).
// Transition tables are enforced by backend services; clients only display.

T? _parse<T extends Enum>(List<T> values, String Function(T) wire, String? v) {
  for (final e in values) {
    if (wire(e) == v) return e;
  }
  return null;
}

/// Clinic registration application.
///
/// `draft` is reserved: Phase 2 submits applications directly, so no draft is
/// ever persisted.
enum ApplicationStatus {
  draft('draft'),
  submitted('submitted'),
  underReview('under_review'),
  additionalInformationRequired('additional_information_required'),
  approved('approved'),
  rejected('rejected'),
  withdrawn('withdrawn');

  const ApplicationStatus(this.wireName);
  final String wireName;

  static const Map<ApplicationStatus, Set<ApplicationStatus>> _next = {
    draft: {submitted, withdrawn},
    submitted: {
      underReview,
      additionalInformationRequired,
      approved,
      rejected,
      withdrawn,
    },
    underReview: {additionalInformationRequired, approved, rejected, withdrawn},
    // The applicant answers → back to `submitted` for review.
    additionalInformationRequired: {submitted, rejected, withdrawn},
    approved: {},
    rejected: {},
    withdrawn: {},
  };

  bool canTransitionTo(ApplicationStatus to) => _next[this]!.contains(to);

  /// No further changes are possible.
  bool get isFinal => _next[this]!.isEmpty;

  /// The application is still being worked on (blocks a duplicate submission).
  bool get isOpen => !isFinal && this != draft;

  static ApplicationStatus? tryParse(String? v) =>
      _parse(values, (e) => e.wireName, v);
}

enum TenantStatus {
  provisioning('provisioning'),
  active('active'),
  suspended('suspended'),
  closed('closed');

  const TenantStatus(this.wireName);
  final String wireName;

  static const Map<TenantStatus, Set<TenantStatus>> _next = {
    provisioning: {active, closed},
    active: {suspended, closed},
    suspended: {active, closed},
    closed: {},
  };

  bool canTransitionTo(TenantStatus to) => _next[this]!.contains(to);

  static TenantStatus? tryParse(String? v) =>
      _parse(values, (e) => e.wireName, v);
}

enum SubscriptionStatus {
  trial('trial'),
  active('active'),
  pastDue('past_due'),
  expired('expired'),
  cancelled('cancelled'),
  suspended('suspended');

  const SubscriptionStatus(this.wireName);
  final String wireName;

  static const Map<SubscriptionStatus, Set<SubscriptionStatus>> _next = {
    trial: {active, expired, cancelled, suspended},
    active: {pastDue, expired, cancelled, suspended},
    pastDue: {active, expired, cancelled, suspended},
    expired: {active, trial, cancelled},
    suspended: {active, trial, cancelled},
    cancelled: {},
  };

  bool canTransitionTo(SubscriptionStatus to) => _next[this]!.contains(to);

  /// Counts as a live subscription (not ended or cancelled).
  bool get isLive =>
      this == trial || this == active || this == pastDue || this == suspended;

  static SubscriptionStatus? tryParse(String? v) =>
      _parse(values, (e) => e.wireName, v);
}

enum BillingInterval {
  monthly('monthly'),
  yearly('yearly');

  const BillingInterval(this.wireName);
  final String wireName;

  /// End of a period that starts at [start] (calendar months, UTC).
  DateTime periodEnd(DateTime start) {
    final s = start.toUtc();
    final months = this == monthly ? 1 : 12;
    final y = s.year + (s.month - 1 + months) ~/ 12;
    final m = (s.month - 1 + months) % 12 + 1;
    final lastDay = DateTime.utc(y, m + 1, 0).day;
    return DateTime.utc(
      y,
      m,
      s.day > lastDay ? lastDay : s.day,
      s.hour,
      s.minute,
      s.second,
    );
  }

  static BillingInterval? tryParse(String? v) =>
      _parse(values, (e) => e.wireName, v);
}

enum PlanStatus {
  active('active'),
  inactive('inactive');

  const PlanStatus(this.wireName);
  final String wireName;

  static PlanStatus? tryParse(String? v) =>
      _parse(values, (e) => e.wireName, v);
}

/// Feature keys that a plan can enable. Enforcement happens on the backend.
abstract final class FeatureKey {
  static const String appointments = 'appointments';
  static const String patientManagement = 'patient_management';
  static const String doctorWorkspace = 'doctor_workspace';
  static const String prescriptions = 'prescriptions';
  static const String billing = 'billing';
  static const String reports = 'reports';
  static const String laboratory = 'laboratory';
  static const String patientMobileApp = 'patient_mobile_app';
  static const String multipleBranches = 'multiple_branches';
  static const String advancedAnalytics = 'advanced_analytics';

  static const List<String> all = [
    appointments,
    patientManagement,
    doctorWorkspace,
    prescriptions,
    billing,
    reports,
    laboratory,
    patientMobileApp,
    multipleBranches,
    advancedAnalytics,
  ];
}

/// Numeric limit keys. `null` in a plan means unlimited.
abstract final class LimitKey {
  static const String maxBranches = 'max_branches';
  static const String maxDoctors = 'max_doctors';
  static const String maxStaff = 'max_staff';
  static const String maxPatients = 'max_patients';

  static const List<String> all = [
    maxBranches,
    maxDoctors,
    maxStaff,
    maxPatients,
  ];
}
