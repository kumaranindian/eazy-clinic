# Phase 8 Test Report (2026-11-04)

| Suite | Result |
|---|---|
| `scripts/check_all.sh` (format, analyze, every package) | pass, no issues |
| Backend `dart test` | 717 passed, 22 emulator-only skipped. Phase 8 added 53 (`test/features/portal`: discovery and appointments 24, records and billing 13, account, notifications, consent, family and security 16) |
| Patient app widget tests | 34 passed (27 new in `portal_test.dart`; the 7 earlier shell tests adapted to the new navigation) |
| Doctor app widget tests | 17 passed (2 new: share summary with patient) |
| Clinic Web, `common_models`, design system, `app_core` | unchanged and green (116, 21, 14, 71) |
| Firestore emulator, rules | 28 passed (1 new: notifications, devices, preferences and deletion requests closed to clients, incl. collection-group queries) |
| Firestore emulator, backend integration | 22 passed (unchanged; no portal emulator test yet) |
| Android APK / app bundle | **not built: no Android SDK in this environment.** The patient app has no web platform either, so no compile check beyond analysis and tests was possible. |

## Covered
- **Access:** every portal route needs a signed-in patient account (401, 403/404); staff routes answer 403 to patients; invalid token 401.
- **Discovery:** only active, app-enabled clinics; suspended or plan-removed clinics disappear; public fields only; doctors without registration, e-mail or phone; discovery grants no records.
- **Identity and linking (existing Phase 4 tests, plus portal use):** records appear only after a clinic-issued code is claimed; unlinked clinic, tampered clinic id and unknown `accountId` answer 404.
- **Appointments:** availability; booking (pending, `patient_app`, audited, generic notification); idempotency (same key once, other body 409, missing key 400); racing patients for one slot (one 201, three 409); taken slot refused; past date, beyond 60 days, bad input, forbidden fields; cancel (replay, audit, slot freed), 2-hour notice for cancel and reschedule, reschedule keeps history; another patient cannot cancel, move or check in; check-in needs a confirmed visit on the day and is not repeated.
- **Queue:** token, position and patients-ahead only; the response is searched for another patient's name and phone; before check-in `not_in_queue`; others get 404.
- **Caregivers:** a scoped relationship books for the patient; records and billing stay closed without `view_records`; revoking ends access at once.
- **Records:** overview allow-listed (no clinic remarks or restricted notes); summaries only after release, never drafts, observations or assessments; only the author can release (other doctor 404, receptionist 403, in-progress 409); prescriptions finalized only, current vs superseded, disclaimer, no write routes; cross-patient and cross-clinic isolation; documents and reports unavailable.
- **Billing:** drafts hidden; own invoices, payments, receipts and refunds only; another patient's ids 404; staff finance routes 403; no staff fields leaked.
- **Notifications:** device register / refresh / unregister; token moves to the latest user and nobody can deactivate another's device; inbox created once per event and owner-only; generic text (no diagnosis, medicine or amount); events for unlinked records notify nobody; preferences validated.
- **Profile, consent, family:** completion and linked clinics; only low-risk fields editable, identity and server fields refused; clinic record unchanged; deletion request recorded once and deletes nothing; consent catalogue, grant, duplicate refused, outdated wording refused, withdrawal, other person's consent 404; family list names only.
- **App:** account setup, home, clinics and linking (code only), unlinked clinic view, filters, cancel confirmation, check-in, queue display and refresh, booking review and confirmation (ids only plus an idempotency key), conflict handling (no success shown, choice cleared), records tabs read-only, bills and receipt preview with no pay button, family approve/revoke/add child, person selector adds `accountId`, notification routing and read marking, settings, device registration and removal on sign-out, profile edit allow-list, deletion request confirmation, per-purpose consent.

## Defects found by the tests and fixed
1. The "upcoming" filter used the server's real clock instead of the clinic's local date.
2. The queue lookup assumed a summary field that does not exist (found by the queue test).
3. The specialities list (plain strings) crashed the app's list parser; a string-list reader was added.
4. Booking, cancel and similar bodies were first validated before ownership in one path; ownership answers 404 in all tested cases.

## Not run
Android build, device or emulator tests, push delivery, load tests, live Firebase, accessibility audit with a screen reader, performance and startup measurement.
