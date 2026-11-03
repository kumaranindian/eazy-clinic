# Authentication Workflows

## 1. Sign in
1. User enters email/password (validated locally: email format, password present).
2. Firebase SDK signs in (`signInWithEmailAndPassword`). Errors map to one generic message for wrong password / unknown user.
3. App calls `POST /auth/provision` (creates the profile on first use, records the login).
4. Backend returns the session (`accountStatus`, `accessGranted`, `platformRole?`, `memberships`).
5. `AuthController` decides: `Authenticated` | `AccessDenied(reason)` | error. Router redirects accordingly.

## 2. Registration (Clinic Web, Patient)
Fields: full name, email, password, confirm password, terms/privacy checkbox. Firebase creates the identity → display name set →
token refreshed → verification e-mail sent → `POST /auth/provision` → status `pending` → "Verify your email" screen.
After the user clicks the link: "I've verified my email" reloads the user, force-refreshes the token and re-asks the backend, which
activates the account (`pending → active`) from the verified token claim.
Doctor app: no self-registration (staff are invited, Phase 3).

## 3. Forgot password
Email → Firebase `sendPasswordResetEmail`. The UI always shows the same confirmation; Firebase errors for rate limiting / invalid e-mail are shown.

## 4. Session restoration (app start)
State is `AuthResolving` (loading screen; **all** routes held, deep link remembered). If Firebase has a stored user →
`GET /auth/session` (a missing profile triggers one `provision`). Result → `Authenticated`/`AccessDenied`/`AuthFailed` (offline → retry screen)
or `Unauthenticated` for dead sessions (`session_revoked`, `token_expired`, `unauthenticated`), which also calls Firebase sign-out.
Passwords are never stored; Firebase persists its own refresh token in platform storage; the app keeps no tokens.

## 5. Logout
`POST /auth/logout` (best effort, optional `allDevices` → revokes refresh tokens) → Firebase `signOut` → state cleared → router closes protected routes.
If the SDK sign-out fails the local state is still cleared and the failure is reported.

## 6. Deep links
Protected location while signed out → `/login?from=<path>`. After sign-in the user returns to `from` only if it is an internal path
(not `//host`, `://`, backslashes, or an auth screen).

## 7. Manual verification checklist (needs a dev Firebase project)
1. Create a dev Firebase project, enable Email/Password, set `FIREBASE_PROJECT_ID`, run backend with ADC (service account with Firebase Auth Admin + Datastore User).
2. Register → verify email arrives → `platform_users/{uid}` exists as `pending` → verify → "I've verified" → `active`.
3. Set `platformRole: super_admin` manually in the console for a test user → Clinic Web admits.
4. Call `POST /auth/revoke-sessions`, confirm old token → 401 `session_revoked`.
5. Disable the user in the console → 403 `account_disabled`.
6. Confirm `platform_audit_logs` entries contain no tokens or e-mails.
