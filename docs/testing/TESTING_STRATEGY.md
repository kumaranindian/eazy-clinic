# Testing Strategy

Rules: CLAUDE.md §15 and §19.9, "never mark a feature complete merely because the screen renders". Tests are written with the feature, and only what exists is claimed.

## 1. Pyramid and tools

| Level | Tool | Scope |
|---|---|---|
| Unit (Dart) | `package:test` | Validators, redaction, config, envelope/error contracts, policies, status transitions, calculations |
| Unit/widget (Flutter) | `flutter_test` | Design-system components, app shell, providers (overridden), routing config |
| API (backend) | `package:test` + `shelf` handler invoked directly (no network) | Auth, authz, validation, response format, tenant isolation, errors |
| Integration | Firebase emulators (Firestore/Auth/Storage) from Phase 1 | Repositories, transactions, rules (deny-all verified), payments webhooks with fakes |
| End-to-end UI | `integration_test` (Flutter) from Phase 5 | Login, registration, booking → token → consultation → billing |
| Security | Dedicated suites per phase | Unauthorized, cross-tenant, role escalation, patient access, document access, payment tampering, invalid tokens |

## 2. Conventions

- Test files mirror source paths: `lib/src/x.dart` → `test/x_test.dart`. Descriptive names stating behaviour.
- Backend tests build the real app (`buildApp`) with a capturing logger (`test/core/helpers.dart`).
- Flutter app tests override `clientConfigProvider` and pump `EazyClinicApp`; avoid `pumpAndSettle` on screens with looping animations (advance time explicitly).
- No network, no real Firebase in unit/API tests. Time and IDs injected where logic depends on them.
- Every endpoint (Phase 1+) must have: 401 without token, 403 wrong role, **cross-tenant 403/404**, validation 422, happy path, response-shape assertion.
- Table-driven RBAC tests generated from `RBAC_PERMISSION_MATRIX.md` (Phase 3).
- Golden tests for key design-system components may be added once the visual design is signed off.
- Coverage is reported (`--coverage`) but not used as a pass criterion by itself.

## 3. Gate before merging a module

Format clean (`dart format --set-exit-if-changed`) → `analyze --fatal-infos` clean → all tests pass → build verification (web build / debug APK / backend `dart compile exe`) → docs updated.
Local entry point: `scripts/check_all.sh`. CI (GitHub Actions) is planned (TD-06).

## 4. Phase 0 test inventory (what actually exists)

| Project | Tests | What they check |
|---|---|---|
| `packages/common_models` | 2 | Role wire names unique; parse round-trips; unknown → null |
| `packages/api_contracts` | 3 | Envelope serialize/round-trip (success & failure), error code uniqueness/status |
| `packages/validation` | 5 | required, email, Indian mobile, password, compose |
| `packages/utilities` | 6 | Environment parsing, `ClientConfig` validation (https outside dev, no loopback in prod, malformed), redaction (nested) |
| `packages/design_system` | 14 | Palette values equal the approved hex codes; breakpoints; Inter; tap-target size; button loading/disabled; password toggle; search clear; empty/error states; confirm dialog result; adaptive nav (bottom bar vs side nav); gallery renders; logo assets bundled with original proportions; logo not stretched |
| `backend` | 22 | `/health` envelope, no infra leakage, 404 envelope, request-id + security headers, logs without query string; error handler hides internals; validation 422; CORS allow-list/preflight; config validation (all problems reported); request validator (content type, size, JSON); logger redaction/levels |
| `apps/clinic_web`, `doctor_mobile`, `patient_mobile` | 4 each (12) | Shell renders logo/name/environment; gallery reachable in dev; hidden in production; configuration error screen |

Total: **64 tests**.

## 5. Not covered yet (honest gaps)

Authentication, authorization, tenant isolation (no such code yet) · Firebase/emulator integration · UI integration tests on real devices/browsers ·
visual/golden tests · accessibility audit · performance/load tests · Docker image build · web logo rendering confirmed only by asset tests, not by a browser screenshot (TD-10).

## 6. Results (2026-11-03, branch `feature/phase-0-foundation`)

Command: `scripts/check_all.sh` → format check, `analyze` (backend/packages with `--fatal-infos`), tests for all 9 projects:
**all passed (64/64), analyzer clean, formatting clean.**

Builds: `flutter build web` (clinic_web ✓, doctor_mobile ✓) · `flutter build apk --debug` (patient_mobile ✓ on retry, doctor_mobile ✓; see TD-07) · backend run + `curl /health` ✓, and `APP_ENV=production` without project ID exits 78 ✓.
Not built: backend Docker image, release APKs.

## 7. Phase 1 results (`scripts/check_all.sh`, exit 0)

| Project | Tests |
|---|---|
| backend | 126 passed + 7 emulator tests (skipped unless the emulator runs) (token verification, revocation, status gates, routes, spoofing, logging, Firestore/Identity Toolkit REST with mock HTTP, rate limiter, config) |
| common_models | 5 |
| api_contracts | 7 |
| validation | 5 |
| utilities | 8 |
| design_system | 14 |
| app_core | 72 (controller, redirect rules, pages, Dio client, Firebase error mapping) |
| clinic_web / doctor_mobile / patient_mobile | 7 each |

Also run: `flutter build web` for clinic_web and doctor_mobile (OK, placeholder Firebase values); a one-off check that a real `openssl`-generated X.509 certificate and RS256 token pass `FirebaseTokenVerifier`; a live `dart run bin/server.dart` smoke test (`/health` 200, `/api/v1/auth/me` 503 when unconfigured, `/auth/account-status` 404).
**Not run:** Android builds (SDK download blocked), anything against a live Firebase project (TD-17/18), emulator tests (TD-15).

Emulator suite (`scripts/test_emulator.sh`, local Firestore emulator, project `demo-eazyclinic`): 13 Firestore rules tests + 7 backend store tests pass. A mutation check (rules loosened to `request.auth != null`) made 11 of 13 rules tests fail, then the rules were restored.

## 8. Phase 2 results

`scripts/check_all.sh` (exit 0): backend 237 passed (+16 emulator tests that run in `scripts/test_emulator.sh`), common_models 14, api_contracts 7, validation 5, utilities 8, design_system 14, app_core 71, clinic_web 35, doctor_mobile 7, patient_mobile 7.
`scripts/test_emulator.sh` (exit 0, Firestore emulator): 18 rules tests; 16 backend tests = DocumentStore contract (15) run against the real REST store + the full control-plane flow (submit → approve → membership → entitlements → lifecycle → audit pagination).
Backend coverage areas: application validation/rules, review workflow, idempotent and concurrent approval, injected provisioning failures + retry, tenant lifecycle, plan versioning, subscription lifecycle, entitlement policy matrix, HTTP-level authorization matrix over all 29 platform endpoints, spoofing (role claims/headers/query, tenant id), self-approval, support-admin read-only, audit integrity, log secrecy, rate limiting, pagination.
Builds: `flutter build web` for clinic_web and doctor_mobile OK. **Not run:** Android builds, live Firebase.
Emulator findings fixed along the way: transactions that threw were not rolled back (locks leaked), and aggregation queries must not carry an explicit ordering.

## Phase 4
Privacy/isolation tests run against the in-memory store (`backend/test/features/patients`), the Firestore emulator (`test/integration/patient_flow_emulator_test.dart`, rules tests) and Clinic Web widget tests. Counts: `docs/phase-4/TEST_REPORT.md`.

## Phase 5
Scheduling and concurrency tests: `backend/test/features/scheduling` (in-memory store, `Future.wait` races), `test/integration/scheduling_flow_emulator_test.dart`, rules tests, Clinic Web `scheduling_test.dart` (incl. queue polling with out-of-order snapshots). Counts: `docs/phase-5/TEST_REPORT.md`.
