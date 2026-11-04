# Patient App Architecture

## Backend: `/api/v1/patient/...`
A thin layer in `backend/lib/features/portal` that reuses the existing modules:
- **Identity:** the caller is the verified Firebase user; the patient account is found by uid (`PatientAccountService`). Other people are reached only through an active, verified family relationship whose scope covers the action (`manage_appointments`, `view_records`, `give_consent`). A clinic record is reached only through an existing `patient_clinic_links` entry.
- **Acting in a clinic:** `PatientActingContext` (tenant from the link, never the request) with a fixed permission set. Shared services (slots, booking, cancel, reschedule, check-in, queue, consent) are reused; audit rows say `patient`.
- **Projections:** every response is built from allow-lists of fields. Drafts, observations, assessments, restricted notes, alerts, staff identities, expenses and reports are never included.
- **Gating:** the clinic must be active, not blocked, and have `patient_mobile_app` in its plan (discovery, availability, booking, everything). Read-only clinics refuse writes.

## App: `apps/patient_mobile`
Flutter Android, Riverpod 3, GoRouter, Dio via `app_core` `ApiClient`, Firebase Authentication via `app_core`.
- `data/portal_repository.dart`: thin HTTP wrapper (overridden in tests).
- `presentation/providers.dart`: request-keyed `FutureProvider`s, the selected-person selector, idempotency keys.
- `presentation/*_pages.dart`: screens; business rules stay on the backend.
- `push/push_service.dart`: `PushTokenSource` interface (default: no token), `PushRegistrar` (register after sign-in, deactivate on sign-out).
- Navigation: Home, Appointments, Records, Clinics, Profile; Family, Notifications and Privacy are reached from them.
- A person selector (me / family members the backend allows) adds `accountId` to requests. It is a selector only; the backend re-authorizes it.
- Nothing is cached on disk: data lives in memory for the session, so no sensitive record is stored unencrypted. Reads can be retried; writes are never queued offline.

## Not duplicated
Appointment engine, billing, consent, relationship and identity logic are Phase 4–7 code; the portal calls them.
