import 'package:api_contracts/api_contracts.dart';
import 'package:common_models/common_models.dart';

/// Which EazyClinic application is running.
///
/// The audience decides which *server-resolved* access facts open the app. It
/// is a UI routing hint only; the backend authorizes every request itself.
enum AppAudience {
  clinicWeb,
  doctor,
  patient;

  /// Whether [session] (as resolved by the backend) may enter this app.
  bool admits(AuthSessionDto session) {
    if (!session.accessGranted) return false;
    switch (this) {
      case AppAudience.clinicWeb:
        // Any active account may open Clinic Web: it is where a clinic
        // applies to join. What the account can then *do* depends on the
        // server-resolved platform role / memberships (and the backend
        // re-authorizes every request).
        return true;
      case AppAudience.doctor:
        return session.memberships.any(
          (m) => m.role == ClinicRole.doctor.wireName,
        );
      case AppAudience.patient:
        // Any active account may use the patient app; clinic data access is a
        // separate, consent-based decision made by the backend (Phase 4).
        return true;
    }
  }
}
