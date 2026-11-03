# Account Identity Model

## `platform_users/{uid}` (document id = Firebase uid)
Written **only** by the backend (client rules are deny-all).

| Field | Type | Notes |
|---|---|---|
| `uid` | string | Firebase uid |
| `displayName` | string | From the verified token `name` claim at creation; may be empty |
| `email` | string | From the verified token; re-synced on login |
| `emailVerified` | bool | From the verified token |
| `accountStatus` | string | `pending` \| `active` \| `suspended` \| `disabled` |
| `createdAt`, `updatedAt` | timestamp | |
| `lastLoginAt` | timestamp? | Set by `POST /auth/profile/initialize` for pending/active accounts |
| `phoneNumber`, `profileImageUrl` | string? | Reserved; no write path yet |
| `platformRole` | string? | `super_admin` \| `platform_support_admin`. **Never** set by registration or any API; assigned out-of-band until a platform admin workflow exists |

Supersedes the Phase 0 description (`role`, `mfaEnrolled`, `status`). `mfaEnrolled` is deferred.

## Account status transitions (`AccountStatus.canTransitionTo`)
```
pending ──► active ──► suspended ──► active
   │          │            │
   └──────────┴────────────┴──► disabled (terminal)
```
`pending → active` happens automatically when a verified token proves `email_verified`. All other transitions are reserved for
authorized administrative workflows (deferred with `POST /auth/account-status`); ordinary clients can never change status.
Unknown stored values are treated as `disabled`. Only `active` may use protected features.

## `platform_audit_logs/{autoId}` (security events)
`event` (`user_provisioned`, `profile_updated`, `login_recorded`, `login_denied`, `account_activated`, `logout`, `sessions_revoked`), `uid`, `actorUid`,
`requestId`, `outcome`, `reason`, `timestamp`. Rejections (`token_rejected`, `access_denied`, `rate_limited`) go to the structured log only.
No tokens, e-mail addresses or names are recorded. Persistence is best-effort; the log line is the fallback.

## Identity resolution contract (for Phase 2/3)
`AuthContext { identity: VerifiedIdentity, user: PlatformUser, memberships: List<MembershipSummaryDto> }` is attached to each request.
Tenant/branch/role must come from `memberships` (server-resolved), never from request input.
Patient identity (`patient_accounts`) is a separate entity linked later (Phase 4); phone number never grants access to records.
