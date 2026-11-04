# Phase 8 Assessment: Patient Android Application

Written before implementation (2026-11-04) from inspection of `develop` at `0f0eef9` (Phases 0–7 merged).

## Branch note
The Phase 8 prompt says to continue on `feature/phase-0-foundation`. That branch was merged long ago; the project owner asked for a new branch for this phase, so work is on `feature/phase-8-patient-app`, created from the latest `develop`. Nothing was pushed or merged.

## What existed
| Area | Finding |
|---|---|
| Patient app | A shell only: welcome, sign-in/registration (shared `app_core` Firebase flow, patient audience admits any active account), home with sign-out. |
| Patient identity | Complete in the backend (Phase 4): global `patient_accounts`, one per sign-in; clinic link codes issued by staff after identity checks and claimed by the patient (`patient_clinic_links`); family relationships with scopes and verification; consent catalogue. |
| Appointments, queue | Complete, but **staff-only** routes (tenant membership required). No patient-facing access. |
| Consultations, prescriptions | Complete (Phase 6), clinic-internal. **No concept of releasing a summary to the patient.** |
| Billing | Complete (Phase 7), staff-only. Payments are recorded offline; no gateway. |
| Notifications | None. No device registry, no inbox, no FCM wiring (Phase 10 is the notification phase). |
| Documents, laboratory | Patient documents are staff-uploaded (Phase 4) with no patient-visibility flag; laboratory (Phase 9) does not exist. |
| Firestore/Storage rules | Deny-all for clients. |
| Android SDK | **Not installed in this environment**: an APK cannot be built here. |

## Gaps and decisions
| Gap | Decision |
|---|---|
| No patient API | New `/patient/...` layer over the existing services (`backend/lib/features/portal`). No second identity, appointment or notification system. |
| Acting as a patient inside staff services | `PatientActingContext`: a fixed small permission set, audit label `patient`, used only after ownership/relationship checks. |
| Released summaries | New `releasedToPatient` flag set by the authoring doctor (`POST /consultations/{id}/release`, `/unrelease`); only finalized consultations can be released. |
| Notifications | In-app inbox + device registry + preferences + a single `PortalNotifier` interface; push delivery and reminders left to Phase 10. |
| Documents and reports | **Not exposed** (no release flag, no staff workflow, no laboratory module). The API answers honestly that they are unavailable. |
| Online payments | None; the app shows what is due and says to pay at the clinic. |

## Dependencies
No new Flutter or Dart dependency was added. FCM needs `firebase_messaging` and an environment `google-services.json` (release configuration); a token-source interface keeps the app ready without them.

## Out of scope (not built)
Clinic management features, a second booking or billing engine, video consultations, ABDM/ABHA, pharmacy, insurance, AI features, unapproved gateways or OTP providers.
