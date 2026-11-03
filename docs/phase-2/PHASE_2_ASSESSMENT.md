# Phase 2 Assessment

Date: 2026-11-03 · Branch: `feature/phase-0-foundation` (9 Phase 1 commits on top of Phase 0; clean tree).

## 1. Verified starting point
`scripts/check_all.sh` was re-run before any Phase 2 change: **exit 0** (backend 126 + 7 emulator tests skipped without the emulator; common_models 5; api_contracts 7;
validation 5; utilities 8; design_system 14; app_core 72; each app 7). `scripts/test_emulator.sh` (13 rules + 7 store tests) passed at the end of Phase 1.
Phase 1 is **unverified against live Firebase** (TD-17) and Android builds are blocked (TD-18). Neither blocks Phase 2 work, but every Phase 2 flow inherits that limitation.

## 2. Reusable components
| Need | Existing | Reuse |
|---|---|---|
| Token verification, account gating | `AuthModule.protect()`, `AuthContext` | Wrap every new router |
| `platformRole` on `platform_users` | server-assigned, `PermissionPolicy` | Extend with platform permissions |
| Error envelope, validation, pagination model | `responses.dart`, `RequestValidator`, `PageMeta` | Reuse |
| Rate limiter, security events | `RateLimiter`, `SecurityEventRecorder` | Reuse; add platform audit |
| Access resolution contract | `AccessResolver` (empty impl) | Implement membership-backed resolver (owner membership) |
| Firestore access | `FirestorePlatformUserStore` (REST: get/create/update/append) | **Insufficient**: no queries, counts, transactions → new generic `DocumentStore` |
| Emulator tests | `scripts/test_emulator.sh` | Extend |
| Flutter | `app_core` auth/router, design system, clinic_web shell | Add platform + onboarding features to `clinic_web` (no new app) |

## 3. Missing prerequisites / defects found
1. **No query/aggregation/atomic-write layer.** Needed for lists, dashboard counts, idempotent provisioning. Built as `DocumentStore` (REST) with an in-memory twin for tests and a shared contract test run against both (memory + emulator).
2. **Clinic Web admits only `platformRole`/membership holders** (Phase 1). Applicants have neither, so they could not even open the clinic-registration form. Change: Clinic Web admits any *active* account; screens/routes then depend on server-resolved platform role / memberships (backend still authorizes everything). Phase 1 "Access not available" tests are updated accordingly.
3. **Platform role bootstrap:** no way to create the first Super Admin except editing Firestore by hand. Documented manual procedure; a role-assignment endpoint is **deferred** (see §7) — this is a documented gap against "manage platform administrators".
4. **Schema docs conflict with the Phase 2 brief** (tenant statuses `pending_approval/cancelled`, subscription statuses `trialing`, `platform_subscriptions/{tenantId}`): the brief wins; ADRs 018–024 record the changes.
5. Phase 1 `platform_audit_logs` stores authentication events with a different shape; the Phase 2 audit shape (`actorUid`, `actorRole`, `action`, `targetType`, `targetId`, `tenantId`, `reason`, `requestId`, `before/after`) is added alongside; the viewer lists both.

## 4. Security risks (and mitigations)
| Risk | Mitigation |
|---|---|
| Applicant approves own application / forges status | Status only changes in backend services; platform endpoints require platform permission; approval also rejects `applicantUid == actor` |
| Duplicate tenants on repeated/concurrent approval | Deterministic ids (`tenantId` derived from `applicationId`), atomic commits with `notExists` preconditions, slug reservation docs |
| Partial provisioning | Two-phase provisioning with `tenant_provisioning_jobs`; tenant stays `provisioning` until all steps succeed; retry endpoint resumes |
| Cross-tenant leakage via client tenant id | Tenant resolved from the caller's server-side membership; `X-Tenant-Id` is only a selector validated against memberships; non-members get 404-style denial |
| Support admin escalation | Separate read-only permissions; mutating endpoints require Super Admin permissions |
| Entitlement bypass | Backend `EntitlementService` is the single evaluator; suspended/expired states documented and tested |
| Audit tampering | Append-only interface (no update/delete), deny-all rules, ids server-generated |
| Platform data exposure | Dashboard returns counts only; no clinical data exists yet |

## 5. Schema changes
New/changed collections (full field tables in `docs/database/DATABASE_SCHEMA.md` §Phase 2): `clinic_applications`, `tenants` (+ `tenant_slugs`, `tenant_provisioning_jobs`,
`tenants/{id}/members`), `subscription_plans` (+ immutable `versions`), `platform_subscriptions` (+ `history`), `platform_audit_logs` (extended).
Indexes: composite and collection-group (`members` by `uid`) — `firebase/firestore.indexes.json`. Rules stay deny-all (tested).

## 6. Implementation plan
1. Shared enums, transitions, permissions (`common_models`).
2. `DocumentStore` + REST + in-memory + contract tests (emulator).
3. Audit service → plans → subscriptions → applications → provisioning/tenants → entitlements → dashboard → membership resolver.
4. Platform and onboarding UI in `clinic_web`.
5. Docs, rules/index review, commits (separate per concern).

## 7. Scope notes and explicit deferrals
- No payments (Razorpay), no automatic renewals/expiry job (status changes are admin-driven; expiry is *evaluated* from dates by the entitlement service), no e-mail notifications.
- Platform administrator management endpoints (grant/revoke `platformRole`) are not in the brief's endpoint list and need a safe bootstrap/MFA design → deferred, documented.
- The brief text received for this phase was **truncated in section 19**; items after it (remaining test list, documentation list, exclusions, commit plan, acceptance criteria, final report) were not available. This work follows sections 1–19 as received and Phase 0/1 conventions for the rest.

## 8. External configuration needed
Firestore composite and collection-group indexes must be deployed (`firebase deploy --only firestore:indexes`) before staging use (not done here). First Super Admin: set `platformRole` manually (Admin credentials). Live Firebase verification remains TD-17.
