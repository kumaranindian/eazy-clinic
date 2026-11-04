# Phase 6 Test Report (2026-11-03)

| Suite | Result |
|---|---|
| `scripts/check_all.sh` (format, analyze, every package) | pass, no issues |
| Backend `dart test` | 550 passed, 21 emulator-only skipped (54 new: consultation 26, records/prescriptions/vitals/templates/follow-ups 28) |
| Doctor app widget tests | 15 passed (8 new: dashboard, patient search/overview, draft save with version, finalize confirmation, finalized read-only, prescription draft/preview, queue call) |
| Clinic Web widget tests | 91 passed (unchanged) |
| Firestore emulator — rules | 26 passed |
| Firestore emulator — backend integration | 21 passed (includes clinical flow on the real REST store) |
| `flutter build web --release` doctor_mobile | OK |

Covered: authorization matrix, cross-tenant/branch isolation, finalization idempotency, amendment preservation, prescription versioning and numbering, vitals validation, catalogue code rules, follow-up booking and duplicate prevention, queue integration.

Not run: live Firebase, Android builds, browser-level tests, load tests, UI tests for amend/diagnosis dialogs and follow-up booking (TD-55).
