# Session Management

| Aspect | Implementation |
|---|---|
| Identity & credentials | Firebase Auth client SDK. Passwords go straight to Firebase and are never stored by app or backend. |
| Local persistence | Managed by the Firebase SDK (platform storage). The app stores no tokens or passwords of its own. |
| Token lifetime/refresh | Firebase ID tokens last 1 h; the SDK refreshes them. `DioAuthApi` reads a fresh token per request and retries once with a forced refresh on `token_expired`. |
| Startup | `AuthResolving` holds every route until the backend answers; deep link remembered. |
| Server verification | Every protected request: signature, `exp/iat/auth_time`, `aud`, `iss`, `sub`, provider ≠ anonymous. |
| Revocation | Identity Toolkit `accounts:lookup` per request: `validSince` > token `auth_time` → `session_revoked`; Firebase `disabled` → `account_disabled`; deleted user → 401. Fails closed (503). |
| Revoking | `POST /auth/revoke-sessions` (self, or super admin for another user) and `POST /auth/logout {allDevices:true}` set `validSince = now`. Existing ID tokens die on the next request. |
| Status changes | Stored `accountStatus` is read on every request, so suspension takes effect immediately. |
| Logout | See `AUTHENTICATION_WORKFLOWS.md` §5. |
| Dead session in app | Any 401 `session_revoked` / `token_expired` after refresh → Firebase sign-out + login screen with a notice. |

Known gap: other devices that are *not* calling the backend keep a cached Firebase user until their next request; the backend rejects them then.
Privileged-user MFA and App Check are deferred.
