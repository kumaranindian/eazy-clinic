# Authentication API

Base path `/api/v1`. All responses use the standard envelope (`docs/api/API_STANDARDS.md`). All responses are `Cache-Control: no-store`.
Protected endpoints require `Authorization: Bearer <Firebase ID token>`.

| Method & path | Auth | Allowed account statuses | Purpose |
|---|---|---|---|
| `GET /auth/me` | token + profile | pending, active | Caller's verified profile (`AuthProfileDto`) |
| `GET /auth/session` | token + profile | all | Account/access status (`AuthSessionDto`); lets the UI explain suspended/disabled |
| `POST /auth/profile/initialize` | token only | all (no change to suspended/disabled) | Create the profile on first use (idempotent, no duplicates); sync e-mail; record login; activate if verified. Returns the session plus `profile`. Body optional: `{"displayName"?}` (used only if the token has no name) |
| `PATCH /auth/me` | token + profile | pending, active | Update `displayName`, `phoneNumber` (Indian mobile; `null` clears). Audit event `profile_updated` |
| `POST /auth/logout` | token + profile | all | Record logout; body `{"allDevices": bool}` optionally revokes all refresh tokens |
| `POST /auth/revoke-sessions` | token + profile | active | Revoke refresh tokens. Own account: any active user. Another user: needs `platform.users.revoke_sessions` (super admin). Body `{"targetUid"?: string}` |
| `POST /auth/account-status` | – | – | **Not implemented** (deferred). Returns 404. |

**Strict bodies:** `profile/initialize` and `PATCH /auth/me` accept only the fields listed above. Any other field (`uid`, `accountStatus`, `platformRole`, `role`, `tenantId`, `memberships`, `permissions`, `email`, `emailVerified`, ...) is rejected with 422 `validation_failed` / `not_allowed` and nothing is written; fields are never silently ignored.

`targetUid` names the **target**, never the caller; the caller is always the token's uid.

## Error codes (auth-related)

| HTTP | `error.code` | Meaning |
|---|---|---|
| 401 | `unauthenticated` | Missing/malformed header, invalid token, unknown key, wrong project, deleted user |
| 401 | `token_expired` | Token expired (client refreshes once and retries) |
| 401 | `session_revoked` | Token issued before refresh tokens were revoked |
| 403 | `account_not_provisioned` | Valid token, no `platform_users` record → call `profile/initialize` |
| 403 | `account_pending` / `account_suspended` / `account_disabled` | Status gate |
| 403 | `forbidden` | Missing permission |
| 422 | `validation_failed` | Bad body |
| 429 | `rate_limited` | Limiter (with `Retry-After`) |
| 503 | `unavailable` | Signing keys or revocation lookup unavailable (fail closed), or auth not configured |

Client-visible messages never include verification details, claim values or exception text.

## Rate limits (per instance, in memory)
60 requests/min per client address on all `/auth/*` routes; 5 per 15 min per user on `revoke-sessions`.
Behind a proxy set `TRUST_FORWARDED_FOR=true` (uses the last `X-Forwarded-For` entry). See TD-16 for the multi-instance limitation.

## Protecting a future router
```dart
router.mount('/api/v1/patients/', const Pipeline()
    .addMiddleware(auth.protect())          // token + active account
    .addHandler(patientsRouter.call).call);
// inside handlers: final ctx = authContextOf(request);  // ctx.user, ctx.memberships
```

## Backend configuration
`FIREBASE_PROJECT_ID` (required outside dev), `AUTH_CHECK_REVOKED` (default `true`; `false` only in dev), `TRUST_FORWARDED_FOR` (default `false`).
Credentials: Application Default Credentials only. Without a project id in dev, `/auth/*` answers 503.
