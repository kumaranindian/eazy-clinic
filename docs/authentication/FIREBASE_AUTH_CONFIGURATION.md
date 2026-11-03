# Firebase Authentication Configuration

No Firebase project was created or changed by Phase 1. Use the **existing** project of each environment. Never share a project between
dev, staging and production.

## Who does what

| Operation | Performed by |
|---|---|
| Register, sign in, password reset e-mail, e-mail verification e-mail, sign out, token refresh, session persistence | Firebase Authentication **client SDK** (in `app_core`) |
| Verify ID token, revocation/disabled check, profile creation and edits, account status gate, audit events, rate limiting | **Backend** |
| Revoke refresh tokens (`validSince`) | **Backend** via Identity Toolkit (`/auth/logout {allDevices}`, `/auth/revoke-sessions`) |
| Passwords | Firebase only; never stored or verified by EazyClinic code |

Firebase sign-out ends the local session only; it does **not** invalidate ID tokens already issued (they live up to 1 hour). Only revocation
(`validSince`) does, which the backend enforces per request.

## Manual setup (per environment, in the Firebase console)
1. Authentication → Sign-in method → enable **Email/Password**. Keep "Email link" off.
2. Authentication → Settings → **Password policy**: require ≥ 8 chars (the app enforces letter + digit); enable **Email enumeration protection** (recommended; makes reset and sign-in errors uniform).
3. Authentication → Settings → **Authorized domains**: add the clinic web / doctor web hostnames.
4. Authentication → Templates: customise verification and reset e-mails (EazyClinic branding, sender).
5. Register apps: Web (clinic web, doctor web), Android `com.avail404.doctor_mobile` and `com.avail404.patient_mobile` (add SHA-1/256 for release). Note each app's `appId`.
6. Backend service account (Cloud Run identity): roles **Firebase Authentication Admin** and **Cloud Datastore User**. Use Application Default Credentials; do not download keys.
7. Fill `environments/<env>/app.json` (one per app) with `FIREBASE_API_KEY`, `FIREBASE_APP_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_PROJECT_ID`, `FIREBASE_AUTH_DOMAIN` (web) and `backend.env` with `FIREBASE_PROJECT_ID`. Real files are git-ignored.
8. Deploy Firestore rules manually after review (not done by Phase 1): `firebase deploy --only firestore:rules --project <env>`.
9. Platform admins: set `platform_users/{uid}.platformRole` in the console (Admin credentials) until an admin workflow exists.

## Environments
| Env | `APP_ENV` | Firebase project | Notes |
|---|---|---|---|
| dev | `dev` | dev project | `AUTH_CHECK_REVOKED=false` allowed; HTTP API URL allowed |
| staging/UAT | `staging` | staging project | https only; revocation checks mandatory |
| production | `production` | production project | https only; no local API URL; revocation mandatory; no design-system gallery |

Config validation fails fast (and the apps show a configuration error screen) on missing/placeholder Firebase values, mismatched schemes or wildcard CORS.

## Local testing without any real project
`scripts/test_emulator.sh` starts the **Firestore emulator** (project id `demo-*`) and runs the rules tests and the backend store tests.
The Auth emulator is not used (emulator tokens are unsigned; the production verifier correctly rejects them). Requires Node 18+, Java 11+.

## Android notes
`firebase_auth` requires `minSdk 23` (set in both Android apps). Initialization is done in Dart from `--dart-define` values, so no
`google-services.json` is required for authentication; add it later for FCM. Android builds were **not run** in the Phase 1 environment (TD-18).

## Remember-session behaviour
Web: Firebase default `LOCAL` persistence (survives browser restarts, IndexedDB). Android: Firebase persists the refresh token in app-private storage.
The apps add no storage of their own and offer no "remember me" toggle in Phase 1 (sign-out is the control).
