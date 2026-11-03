# Tenant Provisioning, Lifecycle and Recovery

## Application lifecycle
```
(submit) ─► submitted ─► under_review ─► approved            (tenant provisioning starts)
               │  ▲            │ ├────► rejected              (final, reason mandatory)
               ▼  │            ▼ └────► additional_information_required ─► (applicant responds) ─► submitted
        additional_information_required                                                     withdrawn (final, by applicant)
```
`draft` exists in the status list but is never persisted: Phase 2 submits directly. Final states: `approved`, `rejected`, `withdrawn`. Every transition writes
`clinic_applications/{id}/history/{eventId}` and a `platform_audit_logs` entry in the **same atomic commit** as the status change.

### Submission and re-submission policy
| Situation | Result |
|---|---|
| Applicant already has a `submitted` / `under_review` / `additional_information_required` application | 409 (one open application per applicant) |
| Another open or approved application has the same clinic name + city + PIN (normalised) | 409, generic message (does not reveal who applied) |
| Applicant's last application was rejected less than 7 days ago | 409 with the date they may re-apply (cool-off) |
| After rejection (≥ 7 days) or withdrawal | A **new application with a new id** may be submitted; old records and history are kept untouched |
| After approval | A different clinic (different name/city/PIN) may be applied for |
| Phone or e-mail only | Never accepted as proof of ownership: the applicant is the verified Firebase account that submitted; owner details are informational |
Submitting requires an **active** (e-mail-verified) account, is rate limited (5/hour/user) and rejects `status`, `applicantUid`, `tenantId`, roles and any unknown field with 422.

## Approval and provisioning (two atomic phases)
Approval is a backend operation (`POST …/approve`, body `{confirm: true, planId?, startTrial?, note?}`); `confirm` must be `true`.
The actor must hold `platform.applications.review` **and must not be the applicant** (a Super Admin cannot approve their own application).

**Phase A: one atomic transaction** (`TenantService.approve`)
1. Read the application; if already `approved` → idempotent no-op; if status cannot reach `approved` → 409.
2. Choose a slug (see below).
3. Commit together: application → `approved` (+`tenantId`), `tenants/{tenantId}` (status `provisioning`), `tenant_slugs/{slug}`, `tenant_provisioning_jobs/{tenantId}` (`pending`), application history, audit (`application.approved`, `tenant.created`).
`tenantId` is **deterministic** (`ten_` + the application id suffix) and every document is created with a does-not-exist precondition, so repeated, concurrent or retried approvals cannot create a second tenant (verified: 5 concurrent approvals → one tenant, one membership, one subscription).

**Phase B: idempotent steps** (`_complete`, safe to run any number of times)
1. Owner membership `tenants/{tenantId}/members/{ownerUid}` (`clinic_owner`, `active`), created only if absent.
2. Optional initial subscription (plan chosen in the approval request) via the subscription service; skipped if the tenant already has one.
3. Tenant → `active`, job → `completed`, audit (`tenant.activated`), in one transaction. **The tenant becomes `active` only after steps 1 and 2 succeeded.**

### Failure and recovery
- A failure in phase B marks the job `failed` (`lastError` = error code only, `attempts`+1), writes `tenant.provisioning_failed` to the audit log and leaves the tenant `provisioning`. The approve response is `200` with `provisioningComplete:false`.
- A provisioning tenant is blocked everywhere (entitlements `tenant_provisioning`) and has **no** membership until step 1 succeeds.
- Recovery: a platform admin with `platform.tenants.manage` calls `POST /platform/tenants/{id}/retry-provisioning` (also available as a button on the tenant page). Repeating approval has the same effect. Retrying a tenant that is not `provisioning` → 409.
- Tested: injected failure on membership creation and on subscription creation → tenant stays `provisioning`, retry completes it, no duplicates.

### Slugs
Lower-case ASCII `[a-z0-9-]`, 3–40 chars (`clinic` if the name has no usable characters; reserved words such as `admin`, `api`, `www` are prefixed `clinic-`). Uniqueness is guaranteed by the reservation document `tenant_slugs/{slug}` created in phase A; collisions get a deterministic suffix from the application id. The slug is informational (no URL routing uses it yet).

## Tenant status transitions
`provisioning → active | closed`, `active → suspended | closed`, `suspended → active | closed`, `closed` final.
| Action | Rules | Effect |
|---|---|---|
| Suspend | `active` only; reason required | Status `suspended`; clinic **blocked** (see ENTITLEMENT_POLICY); data, memberships, subscription untouched |
| Reactivate | `suspended` only; reason required; tenant must have an active owner membership **and** a subscription that is effectively `trial`/`active`/`past_due` | A subscription change alone never reactivates a tenant |
| Close | any non-closed; reason + `confirm:true` | Final. The live subscription is cancelled (`tenant_closed`) in the same commit. **No data is deleted.** |
| Retry provisioning | `provisioning` only | See above |
There is no delete endpoint for tenants, applications, subscriptions or audit logs.
