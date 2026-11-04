# Patient Android Release Checklist

Status as of Phase 8: **not release-ready, nothing was published or deployed.** An Android SDK is not installed in the development environment, so **no APK was built here** (`flutter build apk` stops with "No Android SDK found"). The app compiles and passes analysis and 34 widget tests; the manifest changes below are unverified by a build.

| Item | State |
|---|---|
| App name / package | `EazyClinic Patient`, `com.avail404.patient_mobile` (confirm the final package id before the first upload; it cannot change later) |
| Version | `1.0.0+1` placeholder |
| Permissions | `INTERNET` only (done) |
| Network security | `usesCleartextTraffic=false` in release, `true` only in the debug manifest (done, unbuilt) |
| Backup | `allowBackup=false` (done) |
| Signing | **Release still uses the debug key.** Add a keystore through CI secrets or a local untracked `key.properties` before any upload; never commit it. |
| Build flavors / environments | `--dart-define-from-file=environments/<env>/app.json` for dev, staging, production; only `*.example.*` templates are committed. Production Firebase files are not in Git. |
| FCM | Needs `firebase_messaging`, `google-services.json` per environment, notification permission flow, background handler, token refresh (TD-67). |
| Deep links | Not set up (appointment and notification routes exist in the router). |
| Crash reporting | Not integrated (a privacy decision: no patient data in reports). |
| Icon and splash | Default launcher assets from earlier phases; replace with the approved brand assets for the store listing. |
| Store listing | Privacy policy and data-safety form must describe health data handling; consent screens are not a legal-compliance statement. |
| Size and startup | Not measured on a device. |
| Debug output | The app writes no logs of patient data; verify with a release build. |
| Play Store publication | **Not done and not authorized.** |
