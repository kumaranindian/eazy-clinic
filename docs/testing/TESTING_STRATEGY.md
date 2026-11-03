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
