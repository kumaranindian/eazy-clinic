# Phase 9 test report

Run with `scripts/check_all.sh` (format, analyze, tests) and `scripts/test_emulator.sh` (local Firestore emulator only; no real Firebase project).

## Results
| Suite | Result |
|---|---|
| `scripts/check_all.sh` | **All checks passed** (format, analysis, tests) |
| backend | 761 passed, 23 skipped (the skipped ones are emulator-tagged and run in the emulator suite) |
| common_models / api_contracts / validation / utilities | 21 / 7 / 5 / 8 passed |
| design_system / app_core | 14 / 71 passed |
| clinic_web | 129 passed |
| doctor_mobile | 19 passed |
| patient_mobile | 35 passed |
| Emulator: backend integration | 23 passed (includes the laboratory flow below) |
| Emulator: Firestore rules | 29 passed (includes the new laboratory collections) |

## New tests
| File | Tests | Covers |
|---|---|---|
| `backend/test/features/laboratory/lab_logic_test.dart` | 9 | flags by sex/age, unit mismatch, no invented ranges, qualitative options, optional critical limit, PDF validity/wrapping/determinism |
| `backend/test/features/laboratory/lab_flow_test.dart` | 30 | catalogue (uniqueness, range validation, permissions, plan gating, prefix search); order lifecycle to a stored, versioned PDF; invalid transitions; idempotent creation; sample identity check, unique identifier, rejection and recollection; **concurrent identifier claim**; server-computed flags and `not_assessed`; value validation; incomplete submission; separation of duty; return for correction; idempotent verify/publish; role checks; amendment versions; doctor request linking and duplicate prevention; doctor visibility of unverified results and history; external upload, review and publish; content-based file checks; cross-clinic isolation; branch scope; audit without clinical values; dashboard |
| `backend/test/features/portal/portal_lab_test.dart` | 5 | nothing before publication; allow-listed projection; other patient gets 404; superseded versions hidden; single notification |
| `backend/test/integration/lab_flow_emulator_test.dart` | 1 | the whole flow on the Firestore emulator including the identifier race and tenant isolation |
| `firebase/rules-tests` | 1 (29 total) | every laboratory collection denies client reads, writes, collection-group queries and audit deletion |
| `apps/clinic_web/test/lab_test.dart` | 13 | navigation by permission, dashboard figures, order list, accept, role without rights, sample collection payload, result entry payload and validation, flags and verify/return, publish, external upload, report download |
| `apps/doctor_mobile/test/workspace_test.dart` | +2 | orders with status and only-ready results; ordering tests from the catalogue |
| `apps/patient_mobile/test/portal_test.dart` | +1 | lab reports list, external label, results with flags |
| existing tests adjusted | | `/patient/reports` now lists lab reports; doctor history `laboratory` reports `available: true` with published reports |

## Bugs the tests found
- Item ids shorter than the route id pattern (`i1`) were refused by routes; ids are now `it1`.
- The catalogue prefix search used an empty range (`>= q` and `< q`); fixed with an upper bound and a test.

## Not tested
- Android build (no SDK here), real device, real browser download, live Firebase/GCS, load or performance, accessibility audit.
- PDF appearance beyond structural validity (parsed bytes, not rendered).
