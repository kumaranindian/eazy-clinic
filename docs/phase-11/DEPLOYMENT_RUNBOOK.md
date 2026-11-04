# Deployment runbook

**This phase deployed nothing.** The steps below are the procedure to follow after explicit approval, first in staging. Real project ids, buckets, domains and secrets are not in the repository; owners must supply them.

## Environments and configuration ownership
| Item | dev | staging | production | Owner |
|---|---|---|---|---|
| Firebase project, Firestore, Storage bucket, Auth | separate | separate | separate | Platform owner (to be named) |
| Backend env vars | `environments/dev/backend.env` | `.../staging/backend.env` | `.../production/backend.env` | Platform owner |
| App config (`app.json`) | dev | staging | production | Release manager |
| Secrets (service account, provider keys) | local only | secret manager | secret manager | Security owner |

Backend variables: `APP_ENV`, `PORT`, `LOG_LEVEL`, `FIREBASE_PROJECT_ID`, `STORAGE_BUCKET`, `CORS_ALLOWED_ORIGINS` (exact https origins), `AUTH_CHECK_REVOKED` (true), `TRUST_FORWARDED_FOR` (true only behind a trusted proxy), `NOTIFICATIONS_FCM_ENABLED` (false until FCM is verified), `NOTIFICATIONS_WORKER_ENABLED`. The backend refuses to start in staging/production when required values are missing or unsafe. Credentials come from Application Default Credentials (the runtime service account); no key file is baked into an image or repository.

**Isolation rule:** a staging service account must have no access to the production project and the reverse. The build script rejects a config whose `APP_ENV` does not match the target and any local/placeholder URL.

## Secret rotation (proposed)
Service accounts: rotate keys (prefer keyless runtime identity); provider keys (FCM, e-mail, SMS, payment): rotate on a schedule and on any suspicion, one environment at a time, then restart the backend; Android upload/signing keys: see below; record every rotation.

## Build (from a known commit)
```
git checkout <approved commit>        # clean tree required
scripts/check_all.sh                  # must pass
scripts/security_scan.sh --history    # must pass
scripts/build_release.sh staging      # then production, after UAT
```
`build_release.sh` writes `MANIFEST.txt` (commit, tool versions) and `SHA256SUMS` next to the artifacts. Android needs the Android SDK and `apps/patient_mobile/android/key.properties` (`keyAlias`, `keyPassword`, `storeFile`, `storePassword`); **without it the release build fails by design**.

## Deployment order (staging, then production after approval)
1. Take a backup/export of the target database (see `BACKUP_AND_RESTORE.md`).
2. Deploy Firestore **indexes** and wait until they are built (additive, backward compatible; 41 are pending from Phases 9-10).
3. Deploy Firestore/Storage **rules** (deny-all for clients; nothing depends on them from the apps).
4. Deploy the **backend** (Cloud Run or equivalent). Check `/health` and `/ready`; keep at least one instance running if the notification worker is on (TD-85).
5. Deploy **Clinic Web** and **Doctor Workspace** with the headers of `firebase/hosting.headers.example.json` (validated in staging first).
6. Roll out the **Android** app to a small staged percentage; widen only after smoke tests.
7. Run the smoke tests in `RELEASE_CHECKLIST.md`.

Backward compatibility: data changes are additive; apps tolerate unknown response fields; a new backend must keep serving the previous app version (apps from the store lag). Database migrations are not required for Phases 9-10; any future one must be written to run twice safely.

## Signing keys
Generate the Android upload key offline, store the keystore and passwords in the approved secret store with at least two custodians, keep an encrypted offline copy, and enrol in Play App Signing so the upload key can be reset. Never commit `key.properties` or a keystore (the scan checks).

## Not decided in this repository
Hosting target for the web apps (Firebase Hosting or other), backend runtime (Cloud Run assumed by the code, not verified), domains, OAuth authorized domains, monitoring product, secret manager. These need owner decisions before a runbook can be exact.
