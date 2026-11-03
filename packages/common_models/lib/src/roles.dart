// Role identifiers. These are labels only. What each role may do is decided by
// backend authorization policies (see docs/security/RBAC_PERMISSION_MATRIX.md),
// never by client-side checks.

/// Platform-level roles (Avail404 staff).
enum PlatformRole {
  superAdmin('super_admin'),
  platformSupportAdmin('platform_support_admin');

  const PlatformRole(this.wireName);

  /// Stable value used in the API and in Firestore.
  final String wireName;

  static PlatformRole? tryParse(String? value) {
    for (final role in values) {
      if (role.wireName == value) return role;
    }
    return null;
  }
}

/// Clinic-level roles (tenant members).
enum ClinicRole {
  clinicOwner('clinic_owner'),
  clinicAdmin('clinic_admin'),
  doctor('doctor'),
  receptionist('receptionist'),
  nurse('nurse'),
  accountant('accountant'),
  labTechnician('lab_technician'),
  pharmacist('pharmacist');

  const ClinicRole(this.wireName);

  /// Stable value used in the API and in Firestore.
  final String wireName;

  static ClinicRole? tryParse(String? value) {
    for (final role in values) {
      if (role.wireName == value) return role;
    }
    return null;
  }
}

/// Patient-side roles on a global patient account.
enum PatientRole {
  patient('patient'),
  authorizedCaregiver('authorized_caregiver');

  const PatientRole(this.wireName);

  /// Stable value used in the API and in Firestore.
  final String wireName;

  static PatientRole? tryParse(String? value) {
    for (final role in values) {
      if (role.wireName == value) return role;
    }
    return null;
  }
}
