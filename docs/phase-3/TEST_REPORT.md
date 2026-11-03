# Phase 3 Test Report (2026-11-03)

| Suite | Command | Result |
|---|---|---|
| Backend unit/API (incl. Phase 3 config, branch, doctor, staff/invitation, RBAC, cross-tenant, escalation, invitation abuse) | `scripts/check_all.sh` | 338 passed, 18 skipped (emulator-only) |
| common_models / api_contracts / validation / utilities | same | all passed |
| design_system | same | 14 passed |
| app_core | same | 71 passed |
| Clinic Web widget tests | same | 45 passed |
| Doctor / Patient apps | same | 7 / 7 passed |
| Firestore emulator: backend integration | `scripts/test_emulator.sh` | 18 passed |
| Firestore emulator: rules tests | same | 20 passed, 0 failed |
| Format + `flutter analyze`/`dart analyze` | `scripts/check_all.sh` | no issues |
| Web builds | `flutter build web --release` | clinic_web OK, doctor_mobile OK |

## Not run / limits
- Live Firebase, deployed indexes, real Storage bucket: not available (no production/staging access).
- Android builds: SDK unavailable (TD-18).
- Concurrency of seats verified on the in-memory twin and via create preconditions on the emulator; Firestore emulator transaction locking prevents concurrent-transaction tests.
- No browser-level (integration) UI tests; widget tests cover forms, permission-based visibility, loading/empty/error states and invitation acceptance.
