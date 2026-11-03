# Implementation Progress

Legend: **Implemented** = code exists and was verified · **Documented** = design written, no code · **Planned** · **Not implemented** · **Blocked**

## Phase 0: Foundation (branch `feature/phase-0-foundation`)

| Item | Status | Evidence |
|---|---|---|
| Repository inspected, assessment written | Implemented | `docs/REPOSITORY_ASSESSMENT.md` |
| Official logo integrated (original preserved, app-ready + icon derived) | Implemented | `assets/branding/`, `EcBrandLogo`; asset test |
| Official mockup analysed | Implemented | `docs/design/UI_UX_REFERENCE_ANALYSIS.md` |
| Screen inventory + phase mapping | Documented | `docs/design/SCREEN_INVENTORY.md` |
| Monorepo structure | Implemented | `docs/architecture/REPOSITORY_STRUCTURE.md` |
| Shared packages (common_models, api_contracts, validation, utilities) | Implemented | unit tests |
| Design system (tokens, theme, reusable widgets, gallery) | Implemented | 14 widget/unit tests; web build; screenshot of gallery reviewed |
| clinic_web shell | Implemented | 4 tests; `flutter build web` OK |
| doctor_mobile shell (web + Android) | Implemented | 4 tests; web build + debug APK OK |
| patient_mobile shell (Android) | Implemented | 4 tests; debug APK OK |
| Backend foundation + `GET /health` | Implemented | 22 tests; manual `curl` smoke test |
| Firebase environment separation | Documented (+ deny-all rules, env templates) | not deployed |
| Multi-tenant architecture | Documented | `docs/architecture/MULTI_TENANT_ARCHITECTURE.md` |
| Firestore schema (36 collections) | Documented | `docs/database/` |
| API standards | Documented + envelope implemented | `docs/api/API_STANDARDS.md` |
| Security architecture + RBAC matrix | Documented | `docs/security/` |
| Authentication, any business module | Authentication implemented in Phase 1 (below); business modules **not implemented** | |
| Firebase integration / Admin SDK | Implemented in Phase 1 (ADR 012) | TD-01 resolved; TD-17 |
| CI pipeline | Not implemented | TD-06 |

## Test results (2026-11-03)

See `docs/testing/TESTING_STRATEGY.md` §6 for the exact commands and counts.

## Commits

See `git log feature/phase-0-foundation`.

## Phase 1: Authentication and security foundation (branch `feature/phase-1-authentication`)

Legend here: **Tested** = automated tests pass with test doubles; **Unverified live** = not run against real Firebase (TD-17).

| Item | Status | Evidence |
|---|---|---|
| ADR 012–017, TD-01 resolved | Implemented, documented | `MASTER_ARCHITECTURE.md` |
| `AccountStatus`, transitions, `Permission`, `PermissionPolicy`; auth DTOs and error codes | Implemented, tested | `common_models`, `api_contracts` tests |
| Backend Firebase ID-token verification (RS256, claims, key cache) | Implemented, **tested** (generated keys); unverified live | `backend/test/features/auth` |
| Revocation + disabled check, fail-closed | Implemented, tested; unverified live | same |
| `tokenAuthMiddleware` / `accountMiddleware` / `AuthModule.protect()` | Implemented, tested | same |
| `GET /auth/me`, `GET /auth/session`, `POST /auth/profile/initialize`, `PATCH /auth/me`, `POST /auth/logout`, `POST /auth/revoke-sessions` | Implemented, tested | `docs/authentication/API_AUTHENTICATION.md` |
| `POST /auth/account-status` | **Deferred** (no authorized use case) | |
| Account identity (`platform_users`), security events (`platform_audit_logs`) | Implemented; Firestore REST tested with mock HTTP **and against the Firestore emulator (7 tests)** | `ACCOUNT_IDENTITY_MODEL.md` |
| Rate limiting (IP on `/auth/*`, per-user on revoke) | Implemented, tested (per instance) | TD-16 |
| Shared Flutter `app_core` (Firebase repo, Dio client, controller, redirect, screens) | Implemented, tested | 72 tests |
| Clinic Web: login, register, forgot password, loading, unauthorized, suspended | Implemented, tested; web build OK | |
| Doctor: login, forgot password, loading, access denied (no self-registration) | Implemented, tested; web build OK; **Android build not run** | TD-18 |
| Patient: welcome, register, login, forgot password, loading | Implemented, tested; **Android build not run** | TD-18 |
| Route protection, deep links, post-login redirect, open-redirect guard | Implemented, tested | `auth_redirect_test.dart`, `auth_pages_test.dart` |
| Security tests: unauthenticated, spoofed uid/role/tenant/claims, revoked, suspended, no token in logs | Implemented, passing | `auth_routes_test.dart`, `auth_middleware_test.dart` |
| Registration grants no role/tenant/membership | Implemented, tested | |
| Email verification flow (pending → active) | Implemented, tested | |
| Firestore rules (deny-all, reviewed) tested on the emulator | Implemented, **tested** (13 tests + mutation check); rules not deployed | `firebase/rules-tests` |
| Password-reset confirmation screen, registration retry after partial failure | Implemented, tested | `auth_pages_test.dart`, `auth_controller_test.dart` |
| MFA, App Check, device sessions, Auth-emulator tests, CI | **Not implemented / deferred** | TD-06, TD-15, TD-20 |

Commands and counts: see the Phase 1 completion report and `docs/testing/TESTING_STRATEGY.md` (run `scripts/check_all.sh`).

## Phase 2: SaaS platform and multi-tenant management (branch `feature/phase-0-foundation`)

Detailed status per brief module: `docs/phase-2/PHASE_2_IMPLEMENTATION.md`. Summary: backend control plane (applications, provisioning, tenants, plans, subscriptions, entitlements, dashboard, audit), the Firestore document store, indexes, rules tests and the Clinic Web platform/onboarding UI are **implemented and tested** with test doubles and the Firestore emulator. **Deferred:** platform-admin management API, payments, notifications. **Blocked/unverified:** live Firebase, deployed indexes, Android builds.

## Phase 3: Clinic setup, branches, doctors, staff and RBAC (branch `feature/phase-0-foundation`)

| Item | Status | Evidence |
|---|---|---|
| A Clinic profile + private logo | Implemented, tested | `clinic_config_test.dart`, `CLINIC_CONFIGURATION.md` |
| B Operating hours, breaks, holidays, special days, time zone, branch override | Implemented, tested | same |
| C Branches (limit, no delete, last-active protection) | Implemented, tested (+emulator) | `branch_test.dart` |
| D Doctors + `doctor_branch_assignments` | Implemented, tested (+emulator) | `doctor_test.dart` |
| E Staff + secure invitations | Implemented, tested (+emulator); **delivery not configured** (TD-28) | `staff_invitation_test.dart` |
| F/G Centralized RBAC, branch-scoped access | Implemented, tested | `RBAC_PERMISSION_MATRIX.md` |
| H Membership lifecycle | Implemented; owner transfer deferred (TD-29) | |
| Firestore model/rules/indexes | Implemented; rules emulator-tested (20); indexes undeployed (TD-32) | `FIRESTORE_SCHEMA.md` |
| Clinic Web UI (setup, branches, doctors, staff, invitations, roles/access, branch selector, accept page) | Implemented, widget-tested (45); web build OK | `clinic_admin_test.dart` |
| Custom roles, owner transfer, live Firebase, Android builds, tenant audit viewer | **Deferred / unverified** | TD-29, TD-31, TD-32 |

Details and test counts: `docs/phase-3/TEST_REPORT.md`.

## Phase 4: Patient management, identity, family, history and consent (branch `feature/phase-0-foundation`)

| Item | Status | Evidence |
|---|---|---|
| A Patient registration/directory/status (MRN, branch scope, search, limits) | Implemented, tested (+emulator) | `patient_management_test.dart`, `PATIENT_MANAGEMENT.md` |
| B Global patient identity (accounts separate from clinic records) | Implemented, tested | `GLOBAL_PATIENT_IDENTITY.md` |
| Account linking (clinic-issued hashed one-time codes) | Implemented, tested (+emulator) | `PATIENT_ACCOUNT_LINKING.md` |
| C Duplicate detection | Implemented, tested; **merge not implemented** (TD-37) | `DUPLICATE_DETECTION.md` |
| D Family / dependents (account-level, scoped, revocable) | Implemented (API), tested; no clinic UI by design | `FAMILY_AND_DEPENDENT_MANAGEMENT.md` |
| E-G History, allergies, medication history, alerts, emergency contacts | Implemented, tested | `MEDICAL_HISTORY.md`, `ALLERGY_AND_MEDICATION_HISTORY.md` |
| I Consent service (grant/reject/revoke, enforcement) | Implemented, tested | `CONSENT_MANAGEMENT.md` |
| J Patient documents (private, audited, retained) | Implemented, tested; no download button (TD-39) | `PATIENT_DOCUMENT_MANAGEMENT.md` |
| L Patient audit trail | Implemented, tested | `SECURITY_AND_PRIVACY_REVIEW.md` |
| Firestore rules/indexes | Rules tested (24); indexes undeployed (TD-35) | `FIRESTORE_SCHEMA.md` |
| Clinic Web patient UI | Implemented, widget-tested (62 total); web build OK | `patients_test.dart` |
| Live Firebase, Android, profile photo, merge, patient app | **Deferred / unverified** | TD-35…TD-42 |

Test counts: `docs/phase-4/TEST_REPORT.md`.
