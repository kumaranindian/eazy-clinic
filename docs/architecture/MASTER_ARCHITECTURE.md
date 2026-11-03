# Master Architecture

Normative requirements are in `CLAUDE.md`. This document records how they are realised.

## 1. System context

```
 Clinic Web (Flutter Web) ─┐
 Doctor Workspace (Web/Android) ─┼──HTTPS /api/v1──► Shelf backend (Dart) ──Admin SDK──► Firestore / Storage / Auth / FCM
 Patient App (Android) ────┘                                   │
                                                                └──► Razorpay (verify signatures + webhooks)
```

- All three clients use the **same** API, rules and data model.
- Clients authenticate with Firebase Authentication (ID token) and send it as
  `Authorization: Bearer`. The backend verifies it on every protected request.
- Clients **never** access Firestore or Storage directly for protected data (rules are deny-all).
- Only the backend holds privileged credentials (Firebase Admin, Razorpay secret).

## 2. Layers

| Layer | Responsibility |
|---|---|
| Flutter presentation | Widgets, layout, form UX. No business rules, no tenant logic. |
| Flutter domain/data | Riverpod providers/notifiers, API client (Dio, Phase 1), mapping DTOs. |
| API contracts | Envelope, error codes, pagination, header names (shared package). |
| Backend routes | HTTP concerns: routing, parsing, validation, response shape. |
| Backend services (modules) | Business rules, authorization policy calls, transactions. |
| Backend repositories | Firestore access behind interfaces (testable with fakes). |

## 3. Request pipeline (backend, implemented)

Phase 1: authentication is applied per route group via `AuthModule.protect()` (token verification → account gate); public routes such as `/health` stay open. See `docs/authentication/`.

`request id → CORS → security headers → request logging → error handler → router`

Phase 1 inserts **authentication** and **tenant-context resolution** middleware
before the router, then per-route **authorization policies**.

## 4. Environments

dev / staging / production, each with its own Firebase project, data and
credentials. See `deployment/ENVIRONMENT_STRATEGY.md`.

## 5. Architecture decision records

| ADR | Decision | Reason | Status |
|---|---|---|---|
| 001 | Monorepo with `apps/ backend/ packages/` and path dependencies | One repo for three apps + backend; shared contracts without publishing | Accepted |
| 002 | Pure-Dart shared packages (`api_contracts`, `validation`, `utilities`, `common_models`) usable by backend and Flutter | No logic duplication (CLAUDE.md §2) | Accepted |
| 003 | `design_system` is a Flutter package bundling Inter and brand assets; tokens are `const` Dart, theme built from tokens; no third-party font/UI package | Offline-safe fonts, no extra dependency | Accepted |
| 004 | Riverpod 3.x + GoRouter 17 | Mandated by CLAUDE.md; latest resolvable versions | Accepted |
| 005 | Cursor-based pagination; single response envelope; machine-readable error codes | Fits Firestore, consistent clients | Accepted |
| 006 | Tenant data as **subcollections under `tenants/{tenantId}`**; global `patient_accounts`; membership lookup via collection-group query on `members` | Strong isolation, simple per-tenant export/deletion | Accepted (documented, not built) |
| 007 | Firestore/Storage rules deny all client access; backend is the only data path | Never trust the client; one authorization point | Accepted |
| 008 | Client config via `--dart-define-from-file`; backend via env vars; both validated at startup, fail-fast | No silent wrong-environment | Implemented |
| 009 | Phase 0 adds **no** Firebase packages | Admin-SDK-on-Dart choice unresolved (TD-01) | Superseded by 012 |
| 010 | Light theme, red primary actions / navy structure; red active-state accents on mobile nav allowed; red full-width headers not used | CLAUDE.md §11 vs mockup (see UI analysis §11) | Accepted |
| 011 | Query strings are excluded from request logs; log fields pass a redaction filter | Patient search may carry PII (CLAUDE.md §19.16) | Implemented |
| 012 | Backend verifies Firebase ID tokens itself (RS256 + Google certs via `dart_jsonwebtoken`) and uses Identity Toolkit/Firestore REST via `googleapis_auth` ADC; no unofficial Admin SDK | No official Dart Admin SDK exists (TD-01) | Implemented |
| 013 | Shared Flutter package `packages/app_core` for authentication, session and API client | No duplicated auth logic across apps | Implemented |
| 014 | `platform_users/{uid}` is the identity record of every account; `platformRole` is server-assigned | One trusted record per Firebase user | Implemented |
| 015 | `POST /auth/profile/initialize` creates the profile from the verified token; client SDK does sign-in/up/reset/out | Backend must hold a trusted profile before protected calls | Implemented |
| 016 | Revocation checked on every request outside dev | Immediate suspension/revocation | Implemented |
| 017 | No Firebase Emulator; test doubles + generated RSA key | Emulator tooling unavailable here | Accepted |
| 018 | Clinic applications live in a top-level `clinic_applications` collection with history and internal-notes subcollections | Applicants are not members of any tenant yet; internal notes must be separable from applicant-visible data | Implemented |
| 019 | Tenant provisioning is two-phase: atomic phase A (application, tenant `provisioning`, slug, job, audit) and idempotent phase B (membership, subscription, activation); deterministic ids + create preconditions give idempotency | Firestore transactions cannot span retries/timeouts; a durable job makes recovery explicit | Implemented |
| 020 | Subscriptions copy the plan (snapshot) and plan edits create immutable versions | Historic price/limits must never be rewritten | Implemented |
| 021 | One `platform_subscriptions/{subscriptionId}` document per plan period; `tenants.subscriptionId` points to the current one (supersedes `platform_subscriptions/{tenantId}`) | Preserves history across plan changes | Implemented |
| 022 | Subscription expiry is *evaluated* from dates (no scheduler); no payments in Phase 2 | Correct without background jobs; payment gateway is a separate approved phase | Implemented |
| 023 | Entitlements are evaluated only on the backend (`evaluateAccess` + `EntitlementService`); tenant comes from server-side memberships, `X-Tenant-Id` is a selector | CLAUDE.md §4 tenant isolation | Implemented |
| 024 | Generic `DocumentStore` (Firestore REST + in-memory twin, one contract suite incl. emulator); failed REST transactions are rolled back | Queries/counts/transactions needed; emulator caught lock-leak and aggregation-ordering bugs | Implemented |
| 025 | Clinic Web admits every active account; platform/clinic/applicant screens depend on server-resolved role/memberships (UI hint only) | Applicants must reach the registration form | Implemented |
| 026 | Predefined clinic roles only; custom roles deferred | Safe default; catalog/policy ready for overrides | Implemented |
| 027 | `ClinicPermission` catalog and role matrix live in `common_models`; effective permissions computed server-side | Single source of truth | Implemented |
| 028 | Authority rules: no self-change, owner-only admin management, immutable owner (last-owner protection), owner transfer deferred | Prevent privilege escalation | Implemented |
| 029 | Branch scope = `allBranches` or `branchIds` on the membership; out-of-scope → 404; UI branch selector is a hint | CLAUDE.md §4 | Implemented |
| 030 | Subscription limits via atomic seat-slot documents (does-not-exist preconditions) | Race-free without transactions across queries | Implemented |
| 031 | Invitations store only a SHA-256 token hash; single-use transactional acceptance bound to verified e-mail; delivery not faked | Secure onboarding | Implemented (delivery blocked) |
| 032 | Logo in private object storage (`STORAGE_BUCKET`), magic-byte validated, served via authenticated endpoint | No public PHI-adjacent assets | Implemented |
| 033 | Clinic Web adds `file_selector` (official Flutter plugin) for logo selection | No equivalent in the SDK; first-party package | Implemented |
| 034 | Global patient accounts hold identity only; clinical data stays in tenant collections; `patient_clinic_links` are pointers | Prevent cross-clinic record sharing | Implemented |
| 035 | Account linking = in-person identity check + hashed single-use clinic-issued code claimed by a verified-e-mail account | Phone/e-mail similarity must never authorize | Implemented |
| 036 | Family relationships are account-level, scoped, revocable and never grant clinic-record access; dependents are verified by the clinic at linking | CLAUDE.md §7 | Implemented |
| 037 | Clinical permissions (history, allergies, medications, documents) are separate from administrative ones; admins lack them by default | Least privilege | Implemented |
| 038 | Consent is an append-only backend service; staff are never the grantor; revocation blocks new processing, evidence retained | DPDP-oriented consent | Implemented |
| 039 | Changes keep previous versions (`patient_record_revisions`); verification resets on content change; no deletion | No silent overwrite | Implemented |
| 040 | Duplicate detection is advisory (never auto-merge); merge deferred | Safety | Implemented (merge deferred) |

New decisions are appended here before implementation (CLAUDE.md §19 last paragraph).
