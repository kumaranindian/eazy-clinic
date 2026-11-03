# Account Status Policy

Status is stored in `platform_users/{uid}.accountStatus` and read from the server on every protected request.
**Login proves identity; it never grants clinic, doctor, staff, patient or platform permissions.** Access additionally needs an
active account **and** an authorization source (platform role or clinic membership). No membership system exists yet (Phase 3), so
`memberships` is always empty and nobody is given default clinic access.

## Behaviour per status (as implemented and tested)

| | `pending` | `active` | `suspended` | `disabled` |
|---|---|---|---|---|
| Firebase sign-in | allowed | allowed | allowed (Firebase user still enabled) | blocked by Firebase if the Firebase user is disabled; otherwise allowed |
| `POST /auth/profile/initialize` | creates/returns profile | returns profile, records login | returns status, **no** login recorded, `login_denied` event | same as suspended |
| `GET /auth/session` | 200, `accessGranted:false` | 200, `accessGranted:true` | 200, `accessGranted:false` | 200 (or 403 `account_disabled` if the Firebase user is disabled) |
| `GET /auth/me`, `PATCH /auth/me` | allowed | allowed | 403 `account_suspended` | 403 `account_disabled` |
| `POST /auth/logout` | allowed | allowed | allowed | allowed |
| `POST /auth/revoke-sessions` and all future business routes (`protect()` default) | 403 `account_pending` | allowed, then RBAC | 403 `account_suspended` | 403 `account_disabled` |
| App screen | "Verify your email" | home if the app admits the account, else "Access not available" | "Account suspended" | "Account disabled" |

`/auth/session` deliberately answers for every status so the app can explain *why* access is denied; it returns no profile data.

## Transitions (`AccountStatus.canTransitionTo`)
```
pending ─► active ─► suspended ─► active
   └─────────┴───────────┴──────► disabled   (terminal)
```
- `pending → active`: automatic, server-side, when a verified token proves `email_verified` (event `account_activated`).
- All other transitions: reserved for authorized administrative workflows (deferred; no endpoint). Clients can never change status:
  `PATCH /auth/me` and `profile/initialize` reject `accountStatus`, and Firestore rules deny all client writes.
- Unknown stored values are read as `disabled`.

## Disabled vs suspended
*Suspended* = reversible hold (security/billing/admin). *Disabled* = closed account. Disabling an account in Firebase additionally
stops new sign-ins and makes the backend answer 403 `account_disabled` even for still-valid tokens (revocation check).
