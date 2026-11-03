# Phase 4 Test Report (2026-11-03)

| Suite | Result |
|---|---|
| `scripts/check_all.sh` (format, analyze, all packages) | pass, no issues |
| Backend | 411 passed, 19 emulator-only skipped (73 Phase 4: patient management 24, clinical records 15, consent/documents/audit 16, identity/family 18) |
| Clinic Web widget tests | 62 passed (17 new patient tests) |
| Firestore emulator — backend integration | 19 passed (incl. patient flow: MRN counter, seat limit, queries, consent gating, collection-group claim, isolation) |
| Firestore emulator — rules | 24 passed (4 new, 17 patient paths) |
| `flutter build web --release` clinic_web | OK |

Not run: live Firebase, Android builds, browser-level tests, performance tests, concurrency tests for MRN/limits on the emulator (serialized transactions; covered by uniqueness keys and the in-memory store).
