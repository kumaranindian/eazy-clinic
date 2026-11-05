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

## Phase 5: Appointments, availability, scheduling and queue (branch `feature/phase-0-foundation`)

| Item | Status | Evidence |
|---|---|---|
| A Doctor availability (sessions, breaks, per branch, versions) | Implemented, tested (+emulator) | `availability_test.dart`, `DOCTOR_AVAILABILITY.md` |
| B Exceptions, holidays, special days, affected-appointment workflow | Implemented, tested | `SCHEDULE_EXCEPTIONS.md` |
| C Backend slot generation | Implemented, tested; fixed-offset zones only (TD-43) | `APPOINTMENT_BOOKING.md` |
| D Appointment types | Implemented, tested | `APPOINTMENT_TYPES.md` |
| E Booking with reservation-based double-booking prevention and idempotency | Implemented, tested incl. concurrency | `DOUBLE_BOOKING_PREVENTION.md` |
| F Walk-ins (never overbook) | Implemented, tested | `WALK_IN_MANAGEMENT.md` |
| G Lifecycle (confirm, cancel, reschedule, check-in, start, complete, no-show) | Implemented, tested | `APPOINTMENT_LIFECYCLE.md` |
| H Calendar (day, week, month, list, doctor/branch filters, availability) | Implemented, widget-tested; simple grid, no drag-and-drop | `scheduling_test.dart` |
| I-K Queue, tokens, check-in, live dashboard | Implemented, tested; polling not push (TD-44) | `QUEUE_AND_TOKEN_MANAGEMENT.md` |
| L Patient appointment timeline | Implemented, tested | |
| M Audit | Implemented, tested | `SECURITY_REVIEW.md` |
| Firestore rules/indexes | Rules tested (25); indexes undeployed (TD-46) | `FIRESTORE_SCHEMA.md` |
| Live Firebase, Android, notifications, payments, consultation | **Deferred / unverified** | TD-43…TD-48 |

Test counts: `docs/phase-5/TEST_REPORT.md`.

## Phase 6: Doctor workspace, consultation, diagnosis, prescriptions, follow-up (branch `feature/phase-0-foundation`, not pushed)

| Item | Status | Evidence |
|---|---|---|
| A Doctor workspace (dashboard, today, queue, patients, follow-ups) | Implemented, widget-tested | `docs/phase-6/DOCTOR_WORKSPACE.md` |
| B Appointment/queue integration (call, start, complete drive Phase 5 queue) | Implemented, tested | `consultation_test.dart` |
| C Patient clinical view (overview, history) | Implemented, tested | `VITALS_AND_PATIENT_CLINICAL_VIEW.md` |
| D Vitals (append-only, unit-validated, calculated BMI) | Implemented, tested | `clinical_records_test.dart` |
| E Consultation lifecycle with amendments and versions | Implemented, tested (+emulator) | `CONSULTATION_WORKFLOW.md` |
| F Diagnosis (manual entry, optional empty catalogue, codes need a system) | Implemented, tested | `DIAGNOSIS_MANAGEMENT.md` |
| G Prescriptions (draft, authorize, numbering, amend, versions) | Implemented, tested; no PDF (TD-52) | `PRESCRIPTION_MANAGEMENT.md` |
| H Clinical templates (pre-fill only) | Implemented, tested; no shipped content (TD-53) | `CLINICAL_TEMPLATES.md` |
| I Laboratory boundary (requests only) | Implemented as a boundary | `LABORATORY_BOUNDARY.md` |
| J Follow-ups with booking | Implemented, tested | `FOLLOWUP_MANAGEMENT.md` |
| Audit (`clinical_audit_logs`, read audits) | Implemented, tested | `SECURITY_REVIEW.md` |
| Firestore rules/indexes | Rules tested (26); indexes undeployed (TD-54) | `FIRESTORE_SCHEMA.md` |
| Live Firebase, Android build, billing, patient app, notifications, lab results, PDF | **Deferred / unverified** | TD-49…TD-56 |

Test counts: `docs/phase-6/TEST_REPORT.md`.

## Phase 7: Billing, payments, refunds, expenses and finance reports (branch `feature/phase-7-implementation`, not pushed)

| Item | Status | Evidence |
|---|---|---|
| Service catalogue, tax rules, price history, billing settings | Implemented, tested | `docs/phase-7/SERVICE_CATALOGUE.md` |
| Invoices (draft, discounts, taxes, finalize, cancel, credit/debit notes) | Implemented, tested | `INVOICE_WORKFLOW.md`, `billing_math_test.dart` |
| Payment collection, partial/multiple payments, allocation, idempotency, numbering | Implemented, tested incl. races | `PAYMENT_COLLECTION.md` |
| Advance payments and patient credit ledger | Implemented, tested | `PATIENT_CREDIT_LEDGER.md` |
| Receipts | Implemented (data + screen); **no PDF** (TD-57) | |
| Refunds (request, approve, reject, complete, retry) | Implemented, tested | `REFUND_WORKFLOW.md` |
| Expenses and categories with approval policy | Implemented, tested; no evidence upload (TD-60) | `EXPENSE_MANAGEMENT.md` |
| Finance dashboard and 6 reports, CSV API | Implemented, tested; on-demand aggregation (TD-61) | `FINANCIAL_REPORTS.md` |
| Clinic Web finance screens | Implemented, widget-tested | `apps/clinic_web/lib/features/finance/` |
| Payment gateway (Razorpay) | **Interface only, not configured** (TD-58) | `gateway.dart` |
| Firestore rules/indexes | Rules tested; 22 indexes undeployed (TD-61) | `FINANCIAL_DATA_SCHEMA.md` |
| Charge-generation policy, patient billing views, PDF, live Firebase | **Deferred / unverified** | TD-57…TD-64 |

Test counts: `docs/phase-7/PHASE_7_TEST_REPORT.md`.

## Phase 8: Patient Android application (branch `feature/phase-8-patient-app`, not pushed)

| Item | Status | Evidence |
|---|---|---|
| Authentication, account setup | Implemented (Phase 1 flow + account creation) | `PATIENT_AUTHENTICATION.md` |
| Profile (view, low-risk edits, completion, deletion request) | Implemented; identity changes and photo deferred (TD-66) | `PATIENT_PROFILE_AND_IDENTITY.md` |
| Clinic and doctor discovery, linking with a clinic code | Implemented, tested | `CLINIC_DISCOVERY_AND_LINKING.md` |
| Booking, appointments, cancel, reschedule, check-in | Implemented, tested incl. races | `PATIENT_APPOINTMENT_WORKFLOW.md` |
| Queue status | Implemented, polling; no other patients exposed | `PATIENT_QUEUE_WORKFLOW.md` |
| Overview, released summaries, prescriptions | Implemented, tested | `PATIENT_MEDICAL_RECORDS.md` |
| Documents, lab reports | **Not available** (TD-68) | |
| Family and dependents | Implemented on Phase 4 relationships | `PATIENT_FAMILY_AND_DEPENDENTS.md` |
| Bills, payments, receipts, refunds | Implemented read-only; no online payment, no PDF | `PATIENT_BILLING.md` |
| Notifications inbox, devices, preferences | Implemented; **push delivery not wired** (TD-67) | `PATIENT_NOTIFICATION_WORKFLOW.md` |
| Consent and privacy | Implemented per purpose with versions | `PATIENT_PRIVACY_AND_SECURITY.md` |
| Android build | **Not built here (no SDK)**; hardening in the manifest unverified (TD-70) | `PATIENT_ANDROID_RELEASE_CHECKLIST.md` |

Test counts: `docs/phase-8/PHASE_8_TEST_REPORT.md`.

## Phase 9: Laboratory management (branch `feature/phase-9-laboratory`, not pushed)

| Item | Status | Evidence |
|---|---|---|
| Test catalogue, categories, clinic-configured ranges with source | Implemented, tested; UI creates single-parameter tests only (TD-72) | `docs/phase-9/` |
| Doctor requests linked to Phase 6 investigation requests | Implemented, tested | `WORKFLOWS.md` |
| Order lifecycle, samples with identity check, recollection | Implemented, tested incl. races | `ARCHITECTURE.md` |
| Structured results, server-computed flags | Implemented, tested | `lab_evaluation.dart` |
| Verification (separation of duty), return, amendment with versions | Implemented, tested | `SECURITY.md` |
| Report PDF, private storage, versions, authenticated download | Implemented, tested; plain text layout (TD-73); GCS unverified live (TD-80) | |
| External laboratory reports | Implemented, tested; no malware scan (TD-76) | |
| Lab dashboard, audit trail | Implemented, tested | `API_SPECIFICATION.md` |
| Clinic Web, Doctor Workspace, Patient app | Implemented, widget-tested; patient app shows structured results, no PDF viewer | |
| Critical-value workflow, lab billing, barcodes, other documents | **Deferred** | TD-74, TD-78, TD-79, TD-68 |

Test counts: `docs/phase-9/TESTING.md`.

## Phase 10: Notifications and operational reports (branch `feature/phase-10-reports-notifications`, not pushed)

| Item | Status | Evidence |
|---|---|---|
| Event outbox, recipients, templates, deliveries, retries, pause, manual retry, health | Implemented, tested incl. races and lease recovery | `docs/phase-10/` |
| In-app notification centres (Clinic Web, Doctor Workspace, patient app) | Implemented, widget-tested | |
| Preferences, essential vs promotional rules | Implemented, tested | `EVENTS_AND_TEMPLATES.md` |
| Appointment and follow-up reminders (clinic-configurable, suppressed when stale) | Implemented, tested; 60 s in-process worker (TD-85) | `ARCHITECTURE.md` |
| FCM push | **Sender and token APIs only; not live, no app registers tokens** (TD-83) | `DELIVERY_AND_CHANNELS.md` |
| Email, SMS, WhatsApp | **Adapter interface only; no provider** (TD-84) | |
| Six operational reports and dashboard | Implemented, tested; on-demand with scan cap, no charts (TD-87) | `REPORTING_DEFINITIONS.md` |
| CSV / PDF exports with secure download and audit | Implemented, tested; synchronous (TD-88) | |
| Not notified: staff bookings, failed payments, new lab orders, security events | **Deferred** (TD-89) | |

Test counts: `docs/phase-10/TESTING.md`.

## Phase 11: Production readiness (branch `feature/phase-11-production-readiness`, not pushed)

| Item | Status | Evidence |
|---|---|---|
| Readiness audit, security assessment, performance baseline, backup drill, runbooks, checklist, risk register | Done | `docs/phase-11/` |
| CI workflow, secret/release-blocker scan, release build script | Added; CI not yet run on GitHub | `.github/workflows/ci.yml`, `scripts/` |
| Release-gate tests (every route authenticated, least privilege, mass assignment, cross-tenant, production config, concurrency) | Passing | `backend/test/security`, `test/config`, `test/perf` |
| Fixes: Android signing fails closed, billing gateway permission, production CORS, `/ready`, log severity | Done (Android change unbuilt) | |
| Emulator backup/restore drill | 3,620 documents, checksums match | `BACKUP_AND_RESTORE.md` |
| **Production readiness** | **NOT READY**: staging/UAT, live Firebase, Android build, managed backup rehearsal, monitoring, legal review open | `FINAL_RELEASE_READINESS_REPORT.md` |
