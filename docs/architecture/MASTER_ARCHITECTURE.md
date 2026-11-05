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
| 041 | Double booking is prevented by per-cell reservation documents created atomically with the appointment (not only by transaction isolation) | Hard uniqueness on any store; tested under concurrency | Implemented |
| 042 | Booking and walk-in require an `Idempotency-Key`; a body fingerprint detects misuse | Safe retries | Implemented |
| 043 | Scheduling time zones are fixed-offset only; DST zones are refused | No tz database dependency yet | Implemented (limit TD-43) |
| 044 | Reschedule creates a new appointment and marks the old `rescheduled` | History preserved | Implemented |
| 045 | Schedule exceptions never cancel appointments; they flag `needsAttention` and list the affected ones | Explicit resolution | Implemented |
| 046 | Queue = branch + doctor + date; token counter on the queue doc with uniqueness keys; polling with a version field instead of push | Integrity first; no client Firestore access | Implemented (TD-44) |
| 047 | One tenant collection `appointment_audit_logs` serves appointment history and queue history | Fewer duplicate stores | Implemented |
| 048 | Only a `doctor` whose member record has `doctorId` may author clinical records; other doctors' records answer 404; owner reads with `consultations.view_all` | Clinical accountability, no existence leaks | Implemented (TD-49) |
| 049 | Consultation lifecycle by dedicated endpoints; finalization stores version r0; amendments keep originals and add versions; finalize idempotent | Records never silently overwritten | Implemented |
| 050 | Prescriptions are versioned drafts: amend creates a replacement draft, finalizing it supersedes the original and keeps the RX number (counter + uniqueness keys) | Auditable history | Implemented |
| 051 | Catalogues ship empty; codes need a code system; templates only pre-fill; no AI or suggestions | No fabricated clinical data | Implemented (TD-50, TD-53) |
| 052 | Laboratory boundary: investigation requests with `processing: not_available`; results wait for Phase 9 | Do not imply a lab workflow | Implemented |
| 053 | Clinical audit in `clinical_audit_logs` without clinical text; reads are audited | CLAUDE.md §16 | Implemented |
| 054 | Money is integer minor units with half-up rounding; remainders go to the largest part; only the server calculates | No floating point, deterministic totals | Implemented |
| 055 | Invoice lines are a bounded embedded array (≤ 50) with a price/tax snapshot; finalized invoices are immutable and corrected by credit/debit notes (credit ≤ outstanding) | Atomic snapshot; auditable corrections | Implemented |
| 056 | Payments are recorded offline by staff; online payments exist only as a gateway interface; money-moving requests need an Idempotency-Key with a body fingerprint | No simulated success; safe retries | Implemented (TD-58) |
| 057 | Patient credit is an append-only ledger; per-source remaining is derived from it; the balance document is a derived cache written in the same transaction | Auditable, no direct balance writes | Implemented |
| 058 | A refund holds its amount while requested, approved, processing, failed or completed; completion alone moves money; refunds do not re-open an invoice debt; self-approval is off unless policy allows | No double refund; retained failures | Implemented |
| 059 | Overdue is derived at read time; reports aggregate on demand with a scan cap and a truncated flag; collections are never presented as profit | Simplicity until scale needs counters | Implemented (TD-61, TD-63) |
| 060 | Invoice, receipt, credit and debit note numbers come from counters with uniqueness keys written in the same transaction | Concurrency-safe numbering | Implemented |
| 061 | The patient app uses a thin `/patient/...` layer over the existing services; patients act through `PatientActingContext` (fixed permissions, audit label `patient`) only after account, relationship-scope and clinic-link checks | No second identity or appointment engine | Implemented |
| 062 | Every patient response is an allow-listed projection; consultation summaries need an explicit doctor release (`releasedToPatient`); drafts, notes, alerts and staff data never leave the clinic | Medical privacy | Implemented |
| 063 | Patient-app bookings start `pending` and are confirmed by the clinic; the app never sets a status; policy is checked by the backend | No false success | Implemented (TD-65) |
| 064 | One notification interface (`PortalNotifier`) with an in-app inbox, device registry and preferences; push delivery and reminders are Phase 10 | One notification system | Implemented (TD-67) |
| 065 | The app stores no clinical data on disk and queues no offline writes | No unencrypted local records | Implemented |
| 066 | A lab order embeds bounded snapshots of its test definitions; later catalogue edits never alter an existing order or its flags | Reproducible reports | Implemented |
| 067 | A doctor's catalogue request creates a lab order and a linked Phase 6 `investigation_requests` record; the free-text endpoint stays | One request store, no duplicates | Implemented |
| 068 | Reference ranges are clinic configuration with mandatory source and unit; no range or a different unit yields `not_assessed` / `unit_mismatch` | No invented medical values | Implemented |
| 069 | The order lifecycle is a transition table; each move writes history and audit in one transaction | Auditable, race-safe | Implemented |
| 070 | The verifier must differ from the person who entered or amended the result | Laboratory quality practice | Implemented (TD-75) |
| 071 | Reports are PDF bytes from an in-repo writer, versioned, in private storage, served only through authenticated endpoints | No dependency, no public link | Implemented (TD-73, TD-80) |
| 072 | External reports are labelled external and counted as clinic-reviewed only after a second person verifies | No false verification claim | Implemented (TD-76) |
| 073 | Order, sample and report numbers use counters plus uniqueness keys; sample identifiers are unique per clinic | Concurrency-safe numbering | Implemented |
| 074 | One `NotificationHub` (event outbox, recipients, templates, deliveries, adapters); existing modules reach it through `PortalNotifier` and the scheduling hook | One notification system, no duplicated logic | Implemented (TD-86) |
| 075 | An event's type is its notification category; ids are derived from dedupe keys | Idempotent replay | Implemented |
| 076 | Recipients come from clinic records only; checked again at dispatch | No client-chosen recipients | Implemented (TD-89) |
| 077 | Provider acceptance is `sent`; only the in-app inbox is `delivered`; unconfigured channels say `configuration_required` | No false delivery claims | Implemented (TD-83, TD-84, TD-91) |
| 078 | Templates: versioned, variable allow-list without clinical data, single-pass rendering, HTML escaping | Safe, reproducible messages | Implemented (TD-90) |
| 079 | Essential messages always reach the inbox; promotional ones need explicit opt-in | Consent | Implemented |
| 080 | Reminders are derived by a worker scan with window-unique dedupe keys and re-checked before sending; the worker is an in-process timer | No new scheduler dependency | Implemented (TD-85) |
| 081 | Reports are computed on demand from persisted records with documented formulas, scan caps and clinic-local dates | Honest, simple, bounded | Implemented (TD-87) |
| 082 | Exports are generated server-side within limits, stored privately, requester-only, time-limited, audited, CSV-safe | Secure downloads | Implemented (TD-88) |
| 083 | Country, timezone, phone and currency metadata come from maintained libraries (`intl`, `timezone`, `phone_numbers_parser`) behind `country_config`; only India and UAE are seeded, others are added by platform admins | No hand-maintained global catalogue | Implemented |
| 084 | Country master is a platform collection (`countries/{ISO}`) with versioned snapshots; `code`, `callingCode`, `defaultCurrency` immutable; enabling onboarding needs review evidence | Auditable, effective-dated configuration | Implemented |
| 085 | The tenant's legal country is set once by the server (application → approval, or audited migration) and has no tenant-facing write path; never inferred from phone, IP, locale or device | Country spoofing and silent drift | Implemented |
| 086 | Configuration resolution is layered (country → tenant → branch → user locale → deployment); unknown or invalid configuration fails closed; tenants without a country are "not configured", not guessed | Safe compatibility with existing tenants | Implemented (TD-97) |
| 087 | Existing tenants are classified by a read-only dry-run report and assigned one by one by a super admin; no bulk apply | Safe migration | Implemented (TD-99, TD-100) |
| 088 | Locale is presentation only: user preference never changes country, currency or stored data; instants stay UTC and render in the branch zone; money is minor units + ISO code | Clinical/legal meaning unchanged | Implemented (TD-98) |
| 089 | UI strings use Flutter `gen-l10n` (ARB, generated code committed) in `app_core`; English is the template; a missing translation falls back to English, never a key | Standard Flutter mechanism, no new i18n dependency beyond `intl`/`flutter_localizations` | Implemented |
| 090 | A user's language is a presentation preference stored on the account (`preferredLanguage`), precedence user → clinic → country → English; it never feeds authorization, tenancy, country, currency or stored values | Locale must not change legal or clinical meaning | Implemented |
| 091 | One `RegionalDisplay` formats dates/times/numbers/money from the clinic's zone, country and currency (replacing three per-app formatters); money shows a symbol only for unambiguous currencies, else the ISO code | Correctness (clinic-local time, decimals) and consistency | Implemented |
| 092 | Design-system widget texts come from an `EcTextsScope` filled by the app, so the package stays free of app localization | Package independence | Implemented |
| 093 | Language changes refresh the whole tree while preserving widget state (no key-based rebuild) | "No data loss" on locale switch | Implemented |
| 094 | Template values are stripped of bidirectional controls and isolated in RTL languages; translated templates must match English placeholders and contain no clinical variables | Bidi-injection and layout safety | Implemented (TD-104) |

New decisions are appended here before implementation (CLAUDE.md §19 last paragraph).
