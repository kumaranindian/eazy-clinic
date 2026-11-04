# Phase 8 Implementation Plan

| Step | Work | Result |
|---|---|---|
| 1 | Assessment | `PHASE_8_ASSESSMENT.md` |
| 2 | Patient acting context, shared support | `PatientActingContext`, `PortalSupport` (subject, links, scope) |
| 3 | Clinic and doctor discovery | `portal_discovery.dart` |
| 4 | Appointments, check-in, queue | `portal_appointments.dart` |
| 5 | Records, summaries, prescriptions | `portal_records.dart`, consultation release |
| 6 | Billing views | `portal_billing.dart` |
| 7 | Notifications, devices, preferences | `portal_notifier.dart`, `portal_account.dart` |
| 8 | Profile, consent, deletion request, family list | `portal_account.dart` |
| 9 | Patient app screens | `apps/patient_mobile/lib/features/portal` |
| 10 | Security and automated tests | 53 portal tests, 27 app tests |
| 11 | Android hardening | manifest (INTERNET only, no backup, no release cleartext) |
| 12 | Documentation | this folder |

Every portal endpoint was written together with HTTP-level tests including identity, ownership, cross-patient, cross-clinic, relationship-scope and manipulation cases. The tests found and drove fixes for the queue lookup, the upcoming filter (clinic-local date) and the family projection.
