# Multi-Tenant Architecture

Status: **Documented** (Phase 0). Implementation starts in Phase 2.

## 1. Concepts

| Concept | Definition |
|---|---|
| **Tenant** | One clinic organisation (single doctor up to multi-branch group). Document `tenants/{tenantId}`. Owns all its clinical, financial and configuration data. |
| **Branch** | A physical location of a tenant. `tenants/{t}/branches/{branchId}`. |
| **User** | A Firebase Auth identity (`uid`). Users are global; they are not owned by a tenant. |
| **Membership** | Server-written record that a user belongs to a tenant with a role and branch scope: `tenants/{t}/members/{uid}`. |
| **Platform user** | Avail404 staff (`platform_users/{uid}`), roles Super Admin / Support Admin. |
| **Patient account** | Global identity of a patient or caregiver (`patient_accounts/{accountId}`), independent of any clinic. |
| **Clinic patient record** | The clinic's own record `tenants/{t}/patients/{patientId}`. Medical data lives here. |
| **Patient link** | Verified, consented relationship between a patient account and a clinic patient record. |

## 2. Tenant identification

- `tenantId` is a server-generated opaque ID (Firestore auto-ID), never derived from user input.
- The client **may send** a tenant identifier as a *selector* (e.g. a user in several clinics picks one: `X-Tenant-Id` header or path `/clinics/{tenantId}/...`). The backend treats it only as a **request to act in that tenant** and authorizes it against the caller's membership. It is never trusted by itself.
- A user with exactly one membership needs no selector.

## 3. Resolving tenant context (every protected request)

```
1. Verify Firebase ID token → uid (reject if invalid/expired/revoked)
2. Load platform_users/{uid}? → platform roles (only for /platform routes)
3. Load memberships for uid (collection-group query on members where uid == …; cached briefly)
4. Select membership for requested tenant (or the only one)
   → none: 403 (do not reveal whether the tenant exists)
5. Check tenant.status == active and subscription allows the feature
6. Check membership.status == active; read role + permission set from server records
7. Check branch scope: requested branchId ∈ membership.branchIds (or role is tenant-wide)
8. Check resource relationship (e.g. doctor accessing a patient: appointment/consultation relationship or explicit permission)
9. Patient data: verify consent / link where the data is cross-clinic or patient-facing
10. Write an audit log for sensitive reads/writes
```

Role, permissions, tenant and branch come **only** from server-side records, never
from request bodies, query strings, headers (other than the selector) or token
claims set by clients. Custom claims, if used later, are a cache written by the
backend and are re-checked against Firestore for sensitive operations.

## 4. Permission boundaries

| Boundary | Rule |
|---|---|
| Tenant | Every tenant-scoped query includes `tenants/{tenantId}` as its root; there is no query that spans tenants except platform admin routes and the membership lookup. |
| Branch | Branch-scoped roles (receptionist, nurse…) only see documents with their `branchId`. Owners/admins are tenant-wide. |
| Role | Permission sets per role, configurable by the clinic owner within limits defined by the platform (see RBAC matrix). |
| Patient | A clinic sees only its own `patients/{id}` data. Cross-clinic access is impossible by default (§6). |
| Platform | Platform roles manage tenants/subscriptions; they do **not** get blanket access to clinical data. Break-glass access (if ever needed) requires a documented, audited, time-boxed process. |

## 5. Cross-tenant isolation guarantees

1. Storage layout mirrors Firestore: `tenants/{tenantId}/…`; signed URLs are issued per object after authorization.
2. Firestore rules deny all client access, so isolation is enforced in one place (backend) and tested there.
3. Repository interfaces take `TenantContext` (resolved, immutable) as a mandatory argument. There is no repository method that accepts a raw tenant ID string from a request.
4. Automated **cross-tenant tests** are mandatory for every endpoint: user of Clinic A calling every route with Clinic B resource IDs must get 403/404 (CLAUDE.md §15).
5. IDs of resources are not guessable secrets: authorization never relies on ID obscurity.

## 6. Patient identity across clinics

```
patient_accounts/{accountId}        (global: name, verified phone, DOB, ... minimal identity)
        │   patient_links/{linkId}  (accountId ↔ tenantId + clinicPatientId, status, verifiedBy, consent ref)
        ▼
tenants/{A}/patients/{pidA}         (Clinic A's own record + medical data)
tenants/{B}/patients/{pidB}         (Clinic B's own record + medical data)
```

- A clinic never reads another clinic's records. The patient may *choose* to share
  a specific summary (future feature) via a recorded, revocable consent.
- **Phone number alone never links or authorizes access.** Linking requires: a
  verified patient account (OTP-verified phone *plus* identity confirmation
  step), a clinic staff action or invitation code issued by the clinic, and a
  recorded consent. All steps are audited.
- Dependents/family: `family_relationships` between accounts with explicit
  relationship type, scope and consent; revocable.

## 7. Subscription gating

`platform_subscriptions/{tenantId}` holds plan, status (`trialing`, `active`,
`past_due`, `suspended`, `cancelled`), limits (branches, doctors, seats) and
feature flags. The backend checks it in step 5 above; suspended tenants become
read-only or blocked per policy. Never gated by client.

## 8. Lifecycle

Registration → `pending_approval` → (platform approval) → `active` → `suspended`/`cancelled` → export → retention period → deletion (policy in PATIENT_DATA_PRIVACY, Phase 4). Production data is never deleted without explicit approval.

## 9. Open questions (decide in Phase 2)

- Can one doctor user belong to several tenants with different roles? (Design allows it.)
- Is a user's active tenant stored server-side (session) or sent per request?
- Do we use custom claims as a cache for membership? (Default: no in v1.)
