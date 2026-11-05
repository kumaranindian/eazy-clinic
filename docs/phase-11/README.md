# Phase 11: Production readiness, security, performance and release

Branch: `feature/phase-11-production-readiness` (from `develop` at `fc07a24`). The prompt asked to continue on `feature/phase-0-foundation`; as in earlier phases a dedicated branch was used. **Nothing was deployed, published, pushed or merged. No production, staging or live-provider system was touched.** There is no staging environment or production Firebase project in this workspace, so every statement below is about what was verified *here* (in-memory store, local Firestore emulator, local builds).

## Verdict: **NOT READY for production**
See `FINAL_RELEASE_READINESS_REPORT.md`. No Critical finding was found by the tests that exist, and the High findings that can be fixed in code were fixed. The release gates that need real environments (staging/UAT, live Firebase, signing key, managed backups, monitoring, owner-agreed RPO/RTO, legal review) are open and cannot be closed from this workspace.

## Documents
| File | Purpose |
|---|---|
| `PRODUCTION_READINESS_AUDIT.md` | Evidence, traceability, findings by area |
| `SECURITY_ASSESSMENT.md` | Security review, test evidence, findings |
| `PERFORMANCE_BASELINE.md` | Measured numbers, budgets, what is not measured |
| `BACKUP_AND_RESTORE.md` | Scope, procedure, the emulator drill and its results |
| `DEPLOYMENT_RUNBOOK.md` | Build and deploy steps, order, configuration |
| `ROLLBACK_AND_RECOVERY.md` | Rollback and forward-fix |
| `INCIDENT_RESPONSE.md` | Severity, escalation, privacy incidents, monitoring and alert proposals |
| `RELEASE_CHECKLIST.md` | Gates with status and evidence |
| `KNOWN_ISSUES_AND_RISKS.md` | Register of open items and risks |
| `FINAL_RELEASE_READINESS_REPORT.md` | The recommendation |

## What this phase added to the repository
* `.github/workflows/ci.yml` and `scripts/security_scan.sh` (the repository had **no CI**).
* `scripts/build_release.sh`: clean-tree, environment-checked, recorded release build (never deploys).
* Release gates as tests: `test/security/route_auth_test.dart` (every route needs a token; least-privilege and stranger sweeps; mass-assignment sweep), `cross_tenant_test.dart`, `test/config/app_config_test.dart`.
* `test/perf/perf_baseline_test.dart` (`PERF=1`) and `tool/restore_drill.dart` for the emulator drill.
* Fixes: Android release signing fails closed; production CORS may not list local origins; `/billing/gateway` needs a billing permission; `/ready` readiness probe; severity-aware request logs.
* `firebase/hosting.headers.example.json`: draft web headers (unverified).
