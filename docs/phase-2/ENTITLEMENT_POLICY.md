# Subscription Lifecycle and Entitlement Policy

## Subscription statuses and transitions
`trial → active | expired | cancelled | suspended`, `active → past_due | expired | cancelled | suspended`, `past_due → active | expired | cancelled | suspended`,
`expired → active | trial | cancelled`, `suspended → active | trial | cancelled`, `cancelled` final.
Every change writes `platform_subscriptions/{id}/history/{eventId}` + an audit entry atomically.

| Admin action | Endpoint | Notes |
|---|---|---|
| Assign / start trial | `POST /platform/subscriptions` | Plan must be `active`; trial needs `trialDays > 0`; tenant must not be `closed` or already have a live subscription; `startDate` within −30 days / +1 year |
| Change plan | `PATCH …/{id} {planId, reason}` | Old subscription becomes `cancelled` (`plan_changed`), a **new** subscription with a fresh plan snapshot continues the same status/dates; old price/limits stay on record |
| Extend trial | `POST …/extend-trial {days 1–90, reason}` | Only `trial`; adds days from the later of current end and now |
| Renew | `POST …/renew` | Extends a running period, or restarts from now if it lapsed; sets `active` |
| Mark past due | `POST …/mark-past-due` | `active` only |
| Suspend / cancel | `POST …/suspend`, `…/cancel` (reason) | |
| Entitlement overrides | `PATCH …/{id} {overrides, reason}` | Needs `platform.entitlements.override` (Super Admin) **and** a reason; replaces the override set; audited with before/after |
Plan data is **copied** into the subscription (`planId`, `planVersion`, name, interval, price, currency, limits, features); editing a plan creates a new version and never changes existing subscriptions.

**Expiry is evaluated, not scheduled.** A `trial` past its trial end or an `active` subscription past its end date is treated as `expired` everywhere (entitlements, dashboard, UI) even if an admin has not recorded it. There is no background job in Phase 2 and **no automatic renewal or payment**.

## Access policy (`evaluateAccess`)
| Tenant status | Subscription (effective) | Access level | Reason code |
|---|---|---|---|
| provisioning | – | **blocked** | `tenant_provisioning` |
| suspended | – | **blocked** | `tenant_suspended` |
| closed | – | **blocked** | `tenant_closed` |
| active | none | **blocked** | `no_subscription` |
| active | trial, active | **full** | – |
| active | past_due | **read_only** | `subscription_past_due` |
| active | expired | **blocked** | `subscription_expired` |
| active | cancelled | **blocked** | `subscription_cancelled` |
| active | suspended | **blocked** | `subscription_suspended` |
- **full**: features/limits as entitled; **read_only**: features reported as enabled but `writesAllowed:false` (future write endpoints must refuse); **blocked**: every feature `false`.
- Blocked tenants keep all data; only the entitlement explanation endpoint answers.

## `GET /api/v1/tenants/current/entitlements`
Response: `{tenantId, tenantStatus, accessLevel, writesAllowed, reason, subscription{subscriptionId, planId, planName, status, endsAt, trialEndsAt}, features{key:bool}, limits{key:int|null}}` (`null` = unlimited).
Effective value = subscription override if present, else the plan snapshot. The tenant comes from the caller's **server-side memberships**: one membership → used; several → the caller must send `X-Tenant-Id`, which is only a *selector* validated against their own memberships (non-member → 403); none → 403. Query parameters and bodies are ignored.

## Enforcement contract for future modules
Every business endpoint must (1) resolve the tenant from membership, (2) call `EntitlementService.assertFeature(tenantId, FeatureKey.x, write: …)` and for creations `assertWithinLimit(tenantId, LimitKey.x, currentCount)`. UI hiding is never enforcement. Phase 2 implements and tests the evaluator; no operational module exists yet to call it.
