# Phase 5 Test Report (2026-11-03)

| Suite | Result |
|---|---|
| `scripts/check_all.sh` (format, analyze, all packages) | pass, no issues |
| Backend | 496 passed, 20 emulator-only skipped (85 new: availability/exceptions/slots/types 28, booking/lifecycle/walk-in/lists 36, queue/tokens 21) |
| Clinic Web widget tests | 91 passed (29 new) |
| Firestore emulator — backend integration | 20 passed (incl. scheduling flow on the real Firestore REST store) |
| Firestore emulator — rules | 25 passed (10 new paths + collection-group denial) |
| `flutter build web --release` clinic_web | OK; doctor_mobile tests 7 passed |

Concurrency tests executed against the in-memory store with `Future.wait`: 6 racing bookings → 1 success; 5 racing bookings with capacity 2 → 2; 4 racing duplicates with one key → 1 appointment; 6 racing check-ins → tokens 1–6 unique. The emulator test is sequential (the emulator serializes transactions); uniqueness relies on reservation/token keys, which the store contract suite also verifies for concurrent creates.

Not run: live Firebase, Android builds, browser-level tests, load tests, DST zones (unsupported by design).
