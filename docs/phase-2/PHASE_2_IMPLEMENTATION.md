# Phase 2 Implementation Status

Status words: **IMPLEMENTED** (code exists), **TESTED** (automated tests executed and passing), **DOCUMENTED**, **DEFERRED**, **BLOCKED**.
Companion docs: `PHASE_2_ASSESSMENT.md`, `TENANT_PROVISIONING.md`, `ENTITLEMENT_POLICY.md`, `API_PLATFORM.md`, `docs/database/DATABASE_SCHEMA.md` (Phase 2 section).

| Brief module | Status | Evidence / notes |
|---|---|---|
| Platform roles (Super Admin, Support Admin) | IMPLEMENTED, TESTED | Permissions in `common_models`; 29-endpoint matrix test: unauthenticated 401, ordinary user 403, support read-only, role claims/headers/query ignored |
| A. Platform dashboard | IMPLEMENTED, TESTED | Counts from stored data (incl. date-evaluated expiry); MRR deliberately `available:false`; loading/empty/error/retry UI. Date filters not added (not meaningful yet) |
| B. Clinic application (submit, respond, withdraw, statuses, duplicates, cool-off) | IMPLEMENTED, TESTED | `draft` is reserved/unused |
| C. Application review (list/search/filter, detail, notes, request info, approve with confirmation, reject with reason, history) | IMPLEMENTED, TESTED | Backend + UI |
| D. Tenant provisioning (idempotent, recoverable, job, slug, owner membership, initial subscription) | IMPLEMENTED, TESTED | Service tests (incl. 5 concurrent approvals, injected failures) + HTTP tests + **Firestore emulator** end-to-end |
| E. Tenant management (list/detail, suspend, reactivate, close, retry) | IMPLEMENTED, TESTED | "Activate" is covered by reactivation/provisioning retry; no delete |
| F. Plans (create, edit+versions, activate/deactivate, detail, tenants on plan) | IMPLEMENTED, TESTED | Deactivation refused while live subscriptions exist |
| G. Subscription lifecycle (assign, trial, extend, renew, change plan, past due, suspend, cancel, history) | IMPLEMENTED, TESTED | Admin-controlled only; no payments |
| H. Entitlements (policy, `GET /tenants/current/entitlements`, overrides, assert helpers) | IMPLEMENTED, TESTED | No operational module calls `assertFeature` yet (none exists) |
| I. Platform audit (append-only, query + pagination) | IMPLEMENTED, TESTED | Written atomically with each change |
| Firestore rules, indexes | IMPLEMENTED; rules TESTED (18 emulator tests); indexes **not deployed**, not verifiable on the emulator | |
| Frontend (12 required screens + applicant screens) | IMPLEMENTED, TESTED (widget tests with a scripted backend); web build | Platform login/authorization reuses Phase 1 |
| Platform administrator management (grant/revoke platform roles) | **DEFERRED** (TD-22) | Not in the endpoint list; first Super Admin set manually |
| Payments / Razorpay, automatic renewal, e-mail notifications | **DEFERRED** (excluded by the brief / future phases) | |
| Live Firebase verification, Android builds | **BLOCKED** (TD-17, TD-18) | Unchanged from Phase 1 |

## Bootstrapping the first Super Admin (manual)
1. Register and verify an account in Clinic Web (creates `platform_users/{uid}`).
2. In the Firebase console (Admin access), set `platform_users/{uid}.platformRole` to `"super_admin"` (string). Sign out and in again.
3. Deploy `firebase/firestore.indexes.json` before staging use.

## Known limitations
- Search is by name **prefix** (and exact application id), not substring (Firestore). Audit viewer accepts one filter at a time.
- `GET /platform/dashboard` runs ~20 count queries per request (no caching).
- In-memory rate limiters are per instance (TD-16).
- The membership lookup (collection-group query) runs on every authenticated request (TD-23).
- Entitlement limit overrides can be set through the API; the UI edits feature overrides only.
- The applicant sees approval only after signing out/in if the cached session predates approval (session is re-read on startup).
