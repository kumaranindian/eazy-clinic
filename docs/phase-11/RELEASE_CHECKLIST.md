# Release checklist

Status key: **PASS** (evidence exists), **OPEN** (not done or not possible here), **N/A**. Production release needs every OPEN item closed or formally accepted by the named owner.

## Gate A: code quality (evidence in this repository)
| # | Gate | Status | Evidence |
|---|---|---|---|
| A1 | Format, analysis (fatal infos), all tests in all 10 projects | PASS | `scripts/check_all.sh` |
| A2 | Emulator integration and Firestore rules tests | PASS | `scripts/test_emulator.sh`: 24 + 30 |
| A3 | Every route requires a token; least-privilege, stranger, mass-assignment sweeps | PASS | `test/security/route_auth_test.dart` |
| A4 | Cross-tenant read/write regression | PASS | `test/security/cross_tenant_test.dart` |
| A5 | Production config fails closed | PASS | `test/config/app_config_test.dart` |
| A6 | No secrets in files or history; no TODO/debug leftovers | PASS | `scripts/security_scan.sh --history` |
| A7 | Backend and web release builds succeed | PASS | build output, `build_release.sh` |
| A8 | CI configured | PASS (file) / **OPEN** (first run on GitHub) | `.github/workflows/ci.yml` |

## Gate B: needs real environments (cannot be closed from this workspace)
| # | Gate | Status | Needed |
|---|---|---|---|
| B1 | Android release build, signed with the release key, staged rollout | OPEN | Android SDK, keystore, Play Console |
| B2 | Staging deployment of backend and web with production-like config | OPEN | staging Firebase project, domains, hosting |
| B3 | Indexes (41) and rules deployed to staging and verified | OPEN | staging project |
| B4 | UAT of all end-to-end workflows by named testers, sign-off | OPEN | staging, testers |
| B5 | Managed backup/PITR enabled; staging restore rehearsal with measured recovery | OPEN | project access; owner-agreed RPO/RTO |
| B6 | Monitoring, alerts and error reporting configured; on-call rota | OPEN | owner decisions |
| B7 | Web hosting headers (CSP etc.) validated in staging | OPEN | hosting target |
| B8 | Performance measured on Firestore, a low/mid-range Android device and browsers; budgets approved | OPEN | staging, devices |
| B9 | Live FCM verified end to end on a device (if push is in the release) | OPEN | Firebase config, plugin, device |
| B10 | A payment gateway is **not** enabled until approved and tested (webhook signature, idempotency, reconciliation) | N/A while no gateway | owner decision |
| B11 | Accessibility and browser-compatibility checks | OPEN | people and devices |
| B12 | Privacy/legal review (DPDP), retention and deletion policy, privacy disclosures, Play Data Safety | OPEN | qualified reviewer |
| B13 | Rollback rehearsed once in staging (backend and rules) | OPEN | staging |

## Smoke tests after any deployment
1. `/health` and `/ready` return 200. 2. Sign in to each app with a test account. 3. Create a patient, book, confirm, check in, call, finish a consultation. 4. Create and pay a small test invoice (cash). 5. Order, collect, enter, verify, publish a lab result; the patient sees it. 6. An in-app notification arrives and can be marked read. 7. Run and export a report. 8. A user of another test clinic cannot see any of the above. 9. Logs show request ids and no personal data.

## Approvals required before execution
Business owner (scope, RPO/RTO, budgets), security owner (accepted risks), release manager (go/no-go), and explicit written approval before any production deployment or store publication.
