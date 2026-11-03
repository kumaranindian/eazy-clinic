# Platform and Onboarding API (Phase 2)

Base `/api/v1`. Standard envelope, `Authorization: Bearer <Firebase ID token>`, pagination via `?limit=` (1–100, default 25) and `?cursor=` (opaque), response `meta.page {limit, hasMore, nextCursor}`.
Unknown body fields on write endpoints → 422 `not_allowed`. Mutating platform endpoints are rate limited (120/min/user); application submission 5/hour/user.
Platform routes need an **active** account **and** the listed permission from the server-side `platformRole` (Super Admin: all; Support Admin: the read permissions only). Missing permission → 403 `forbidden` (also for non-existent ids, so existence is not revealed to unauthorised users).

## Applicant (active account)
| Method & path | Purpose |
|---|---|
| `POST /clinic-applications` | Submit `{clinic{name,type,registrationNumber?,email,phone,website?,description?}, address{line1,line2?,city,state,country,postalCode}, owner{fullName,email,phone,designation?}, expectations{doctors,staff,monthlyPatients}, preferredPlanId?}` → 201 |
| `GET /clinic-applications/my` | Own applications (paged) |
| `GET /clinic-applications/{id}` | Own application with status history (others: 404) |
| `POST /clinic-applications/{id}/respond` | `{message, clinic?/address?/owner?/expectations? (partial corrections)}` when information was requested |
| `POST /clinic-applications/{id}/withdraw` | Withdraw an open application |

## Platform
| Method & path | Permission | Notes |
|---|---|---|
| `GET /platform/dashboard` | `dashboard.read` | Counts, plan distribution, recents. `monthlyRecurringRevenue.available=false` |
| `GET /platform/clinic-applications` | `applications.read` | `?status=&q=` (name prefix, or exact `app_…` id) |
| `GET /platform/clinic-applications/{id}` | `applications.read` | Full detail, history, internal notes |
| `POST …/{id}/start-review` | `applications.review` | submitted → under_review |
| `POST …/{id}/request-information` | `applications.review` | `{message}` |
| `POST …/{id}/approve` | `applications.review` | `{confirm:true, planId?, startTrial?, note?}`; actor ≠ applicant |
| `POST …/{id}/reject` | `applications.review` | `{reason}` |
| `POST …/{id}/notes` | `applications.review` | `{note}` (internal, never shown to applicants) |
| `GET /platform/tenants`, `GET …/{id}` | `tenants.read` | `?status=&q=`; detail includes owner, application, subscription, provisioning job, last audit entries |
| `POST …/{id}/suspend`, `reactivate` | `tenants.manage` | `{reason}` |
| `POST …/{id}/close` | `tenants.manage` | `{reason, confirm:true}` |
| `POST …/{id}/retry-provisioning` | `tenants.manage` | |
| `GET/POST /platform/subscription-plans`, `GET/PATCH …/{id}` | `plans.read` / `plans.manage` | Create → `inactive`; PATCH bumps `version` |
| `POST …/{id}/activate`, `deactivate` | `plans.manage` | Deactivate refused (409) while live subscriptions use the plan |
| `GET /platform/subscriptions`, `GET …/{id}` | `subscriptions.read` | `?status=&tenantId=&planId=`; detail has history |
| `POST /platform/subscriptions` | `subscriptions.manage` | `{tenantId, planId, trial?, startDate?, reason?}` |
| `PATCH …/{id}` | `subscriptions.manage` (+`entitlements.override` for `overrides`) | `{planId?, overrides?, reason}` |
| `POST …/{id}/extend-trial`, `renew`, `mark-past-due`, `suspend`, `cancel` | `subscriptions.manage` | see ENTITLEMENT_POLICY |
| `GET /platform/audit-logs` | `audit.read` | One filter at a time: `tenantId`, `action`, `targetType` or `actorUid` (Super Admin only) |

## Tenant (active membership)
`GET /tenants/current/entitlements` (see ENTITLEMENT_POLICY).

## Error codes used
400 `bad_request`, 401 auth codes (Phase 1), 403 `forbidden`/account codes, 404 `not_found`, 409 `conflict` (invalid transition, duplicate, plan in use), 422 `validation_failed` (field issues), 429 `rate_limited`, 503 `unavailable`.
