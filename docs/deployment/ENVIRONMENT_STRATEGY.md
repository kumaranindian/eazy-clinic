# Environment Strategy

Status: **Documented.** No Firebase project was created or modified, and nothing was deployed in Phase 0.

## 1. Environments

| | dev | staging (UAT) | production |
|---|---|---|---|
| Purpose | Daily development, emulators | Pre-release verification, demos, UAT | Real clinics and patients |
| Firebase project | own project (`<name>-dev`) | own project (`<name>-staging`) | own project (`<name>-prod`) |
| Data | Synthetic only | Synthetic/anonymised only | Real, regulated |
| Razorpay | Test keys | Test keys | Live keys |
| Who can deploy | Developers | Maintainers after review | **Only with explicit approval** (CLAUDE.md §19) |
| Android app id | `com.avail404.<app>.dev` (flavor, planned) | `.staging` | `com.avail404.<app>` |
| Config source | local `environments/dev/*` (git-ignored real files) | CI secrets / platform config | Secret manager / platform config |

Rules: environments never share projects, data, service accounts, API keys or buckets. Real patient data never enters dev/staging. Project names above are placeholders.

## 2. Configuration channels

| Consumer | Mechanism | Validation (implemented) |
|---|---|---|
| Backend | Environment variables (`environments/<env>/backend.env.example`) | `AppConfig.fromEnvironment`: `APP_ENV` required, `PORT` range, `LOG_LEVEL`, CORS origins (https and no wildcard outside dev), `FIREBASE_PROJECT_ID` required outside dev → exit 78 |
| Flutter apps | `--dart-define-from-file=environments/<env>/app.json` → `APP_ENV`, `API_BASE_URL` (+ Firebase client identifiers in Phase 1) | `ClientConfig.validated`: known env, absolute URL, https outside dev, no loopback in production; invalid → "Configuration error" screen |

Backend secrets (service account, Razorpay key/secret, webhook secret) are provided by the hosting platform, never in files in the repo and never in apps.

## 3. Firebase configuration (per environment)

| Area | Plan |
|---|---|
| Projects | One per environment, created by the owner; IDs placed in git-ignored files / secret manager. `firebase/.firebaserc.example` shows aliases `dev`, `staging`, `production`. |
| Authentication | Email/password (+ MFA for privileged roles), phone OTP for patients; authorised domains per environment; sign-in providers decided in Phase 1 (see UI analysis D-1…D-3). |
| Firestore | Native mode, one region (India, e.g. `asia-south1`; confirm with legal/data-residency review). Rules deny-all; indexes from `firebase/firestore.indexes.json`. |
| Storage | One bucket per environment, same region; deny-all rules; backend-issued signed URLs. |
| FCM | Per-environment Android apps; server key/credentials only in backend. |
| Web app config | Public Firebase web config per environment (client identifiers are not secrets) passed via `--dart-define-from-file`; no `firebase_options.dart` committed until Phase 1 decides (flavor-aware generation). |
| Android app config | `google-services.json` per flavor, **git-ignored**, supplied by CI/dev machine. |
| Backend | Application Default Credentials / workload identity; least-privilege service account per environment. |

## 4. Deployment targets (proposal, to be confirmed in Phase 1/11)

- Backend: container (Dockerfile, built from repo root) on Cloud Run per environment, min instances 0/1, HTTPS only, regional with Firestore.
- Web apps: Firebase Hosting (site per app per environment) or equivalent; build with the environment's define file.
- Android: internal testing track for staging; production via Play Console with signed bundles (keystore in a secret store).
- Backups: scheduled Firestore exports per environment (Phase 11).

## 5. Promotion flow

`feature/*` → PR → `develop` (deploys to dev) → release branch/tag → staging verification (smoke + security suite) → **explicit approval** → production.
Rollback: redeploy previous container/hosting release; data migrations must be backward compatible (expand → migrate → contract).

## 6. Checklist before the first deploy of any environment

- [ ] Project and billing created by owner · [ ] rules and indexes deployed to that project only · [ ] service accounts least-privilege · [ ] secrets in store ·
[ ] CORS origins exact · [ ] `APP_ENV` and project IDs verified in `/health`-independent config check · [ ] logging/monitoring and alerts on · [ ] backups configured (prod).
