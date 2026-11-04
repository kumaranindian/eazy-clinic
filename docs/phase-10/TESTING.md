# Phase 10 test report

Run with `scripts/check_all.sh` (format, analyze, tests) and `scripts/test_emulator.sh` (local Firestore emulator only). No real message was sent and no real provider was called: FCM and email/SMS/WhatsApp are mocks in every test.

## Results
| Suite | Result |
|---|---|
| `scripts/check_all.sh` | **All checks passed** |
| backend | 849 passed, 24 skipped (emulator-tagged, run in the emulator suite) |
| common_models / api_contracts / validation / utilities | 21 / 7 / 5 / 8 passed |
| design_system / app_core | 14 / 71 passed |
| clinic_web | 145 passed |
| doctor_mobile | 21 passed |
| patient_mobile | 36 passed |
| Emulator: backend integration | 24 passed (includes the notification pipeline test) |
| Emulator: Firestore rules | 30 passed (includes the new collections) |

## New tests
| File | Covers |
|---|---|
| `backend/test/features/notifications/notification_test.dart` (34) | event to inbox and tracked delivery; replay and concurrent workers create one; lease recovery after a dead worker; unresolvable recipient; push accepted is `sent`; unconfigured push; transient failure then success after backoff; bounded retries; invalid token deactivates the device; no device; several devices; preferences (push off, re-check at dispatch, promotional opt-in, essential categories); staff preferences and audit; patient read-all and archive; staff inbox (unread count, read, read-all, archive, pagination, other users and other clinics see nothing); device ownership, no token leak, refresh, staff push to own device only; template administration permissions, validation, versions, preview without sending, clinic template used and versioned, missing variable fails safely, injection and escaping, generic push text, English fallback; email: unconfigured vs mock provider with address from the clinic record |
| `reminders_admin_test.dart` (20) | no reminder before the window; one per window; second lead time; one reminder when booked inside the nearest window; unconfirmed, cancelled, moved and past visits; lead-time settings; follow-up reminder; worker tick; failures listed without content; permissions; manual retry audited and not repeated; clinic isolation; pause keeps records queued and resume sends; channel status honesty; health |
| `event_integration_test.dart` (8) | staff confirm, cancel, check-in and call reach only that patient's account; unlinked patient not notified; a failing notification never fails the business action; sample rejection reaches the requesting doctor without the reason; report publication reaches patient and doctor, not other staff; links grant no access; follow-up text is generic |
| `backend/test/features/reports/report_test.dart` (26) | appointments (counts, moved visit once, empty rates, validation, doctor scope, branch scope), per-section permissions, plan gating, clinic isolation, 401, queue wait times, patients new vs returning, consultations without clinical content, laboratory figures, billing measures kept apart and no profit, dashboard availability, CSV and PDF exports (ready, download, audit, same access rules, validation, requester-only, expiry, isolation, concurrency, rate limit), CSV formula neutralisation |
| `test/integration/notification_flow_emulator_test.dart` | outbox, concurrent workers, retry and report queries on the Firestore emulator |
| `firebase/rules-tests` | every new collection denies client reads, writes, collection-group queries and audit deletion |
| `apps/clinic_web/test/communications_test.dart` (16) | notification centre, preferences, admin (retry after confirmation, template preview, channel pause, permission-driven entry), dashboard, empty rates, freshness, invalid dates, report table and definitions, incomplete flag, export and download, export history |
| doctor and patient apps (+2 and +1) | inbox, mark/dismiss, preferences |

## Bugs the tests found
* A constant set was mutated when reading clinic channels (every booking returned 500).
* A built-in template replaced the fixed text of one-off messages and failed them for lack of variables (follow-up "recommended" message).
* Stale-checks suppressed one-off messages that share a category with reminders.
* Payments are keyed by `receivedAt`, not `completedAt` (billing report read zero).
* A confirmation dialog popped the page instead of itself (Clinic Web).

## Not tested
Live FCM or any live provider, Android devices and push receipt, a real browser download, the worker under a real scheduler, performance with large clinics, accessibility audit.
