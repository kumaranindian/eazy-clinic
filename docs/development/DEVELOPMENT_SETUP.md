# Development Setup

## Prerequisites

| Tool | Version used in Phase 0 |
|---|---|
| Flutter | 3.32.8 (stable) · Dart 3.8.1 |
| Android SDK | 36 (for `doctor_mobile`, `patient_mobile`) |
| Chrome | for Flutter Web |
| Docker | optional (backend image; not yet exercised) |
| Firebase CLI | not needed in Phase 0 |

## Get the code

```bash
git clone https://github.com/kumaranindian/eazy-clinic.git && cd eazy-clinic
git checkout develop        # feature work happens on feature/* branches
```

Branching: `master` (releases) ← `develop` ← `feature/<phase-or-topic>`. No direct pushes to `master`; merges to `develop` after review/approval.

## One-shot verification (format, analyze, test for every project)

```bash
scripts/check_all.sh
```

## Backend

```bash
scripts/run_backend.sh dev          # APP_ENV=dev, port 8080
curl -s localhost:8080/health       # {"success":true,"data":{"status":"ok",...}}
cd backend && dart test
```
Config is read from environment variables; copy `environments/dev/backend.env.example` to `backend.env` (git-ignored) to customise. Invalid
config exits with code 78 and a message.

## Apps

Each app needs two defines (see `environments/*/app.example.json`). Copy to `app.json` (git-ignored):

```bash
cp environments/dev/app.example.json environments/dev/app.json
cd apps/clinic_web
flutter run -d chrome --dart-define-from-file=../../environments/dev/app.json
cd ../doctor_mobile  && flutter run -d chrome --dart-define-from-file=../../environments/dev/app.json   # or an Android device
cd ../patient_mobile && flutter run -d <android-device> --dart-define=APP_ENV=dev --dart-define=API_BASE_URL=http://10.0.2.2:8080
```
`10.0.2.2` is the Android emulator's alias for the host machine. Without valid defines the app shows a "Configuration error" screen by design.

Non-production builds expose the component gallery at `/design-system` (Flutter Web: `/#/design-system`).

## Builds

```bash
flutter build web --dart-define-from-file=../../environments/dev/app.json     # in apps/clinic_web or apps/doctor_mobile
flutter build apk --debug --dart-define-from-file=../../environments/dev/app.json   # apps/doctor_mobile, apps/patient_mobile
```
Release Android builds need a signing keystore (never committed; `*.jks`, `key.properties` are git-ignored). Release signing is configured in a later phase.

## Brand assets and fonts

Edit sources in `assets/`, then `scripts/sync_brand_assets.sh` to copy into `packages/design_system`. Never modify `assets/branding/original/`.

## Troubleshooting

- *"Waiting for another flutter command to release the startup lock"*: a previous Flutter process is still running; stop it.
- Android first build can be slow/flaky while Gradle downloads dependencies: re-run (TD-07).
- `flutter test` for an app that depends on `design_system` loads fonts/assets from the package automatically.
