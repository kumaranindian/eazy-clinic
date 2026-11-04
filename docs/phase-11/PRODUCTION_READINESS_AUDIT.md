# Production readiness audit

Scope: commit range `6c05a01..HEAD` of this phase plus the existing code of Phases 0-10 (`fc07a24`). Method: read the code, run it, try to break it. Prompts and documents were not treated as evidence.

## 1. Repository and build integrity
| Check | Result | Evidence |
|---|---|---|
| Toolchain | Flutter 3.32.8, Dart 3.8.1, Node 22, Java 17 (CI pins the same Flutter) | `ci.yml`, command output |
| Format, analysis, tests | Green: format check, `--fatal-infos` analysis, all tests in all 10 projects | `scripts/check_all.sh`, counts in `FINAL_RELEASE_READINESS_REPORT.md` |
| Backend release build | `dart compile exe` succeeds (about 18 s, 12.5 MB) | this phase |
| Clinic Web and Doctor Workspace release builds | `flutter build web --release` succeed (about 52 s / 39 s); no source maps emitted | this phase |
| Patient Android build | **Not built: no Android SDK in this environment** | open |
| CI | **Did not exist.** Added; has not yet run on GitHub | finding F-01 |
| Reproducibility | Lockfiles committed for apps and backend; release script records commit and tool versions and refuses a dirty tree | `build_release.sh` |
| Debug code / placeholders | None in app or backend code (`security_scan.sh`); the Android template TODOs and debug-key signing were found and fixed | F-02 |
| Dependencies | `dart pub outdated`: only transitive dev packages behind; `npm audit` of the rules-test tooling: 0 runtime vulnerabilities, 34 in dev tooling (firebase-tools etc., 1 critical transitive `tar`), none shipped | F-09 |

## 2. Feature and integration completeness (traceability)
| Requirement | Implementation | Test / evidence | Status |
|---|---|---|---|
| Clinic application, approval, tenant provisioning | Phase 2 | platform API tests | Verified in tests; not in staging |
| Branches, doctors, staff, roles | Phases 2-3 | clinic tests, RBAC tests | Verified in tests |
| Patients, consent, identity linking, dependants | Phase 4, 8 | patient and portal tests | Verified in tests |
| Appointments, queue | Phase 5 | scheduling tests incl. races, `perf_baseline_test` | Verified in tests |
| Consultation, prescriptions, amendments | Phase 6 | clinical tests | Verified in tests |
| Billing, payments, refunds | Phase 7 | billing tests incl. races | Verified in tests; **no online payments (gateway not configured)** |
| Laboratory | Phase 9 | lab tests, emulator flow | Verified in tests |
| Notifications, reports, exports | Phase 10 | notification and report tests | Verified in tests; push/e-mail/SMS/WhatsApp **not live** |
| Patient app | Phase 8 | widget tests | Widget level only; no device run |
| All of the above end to end in staging/UAT | | | **Not done: no staging** |

Mock data in production paths: none found. Fake success: none found; unconfigured channels and gateways answer `configuration_required` / "not available".

## 3. Environment and configuration
| Check | Result |
|---|---|
| Env templates for dev, staging, production | present (`environments/*/`); real files git-ignored |
| Backend fails closed in staging/production | tested: missing project id, bucket, non-https or wildcard origins, disabled revocation checks are rejected |
| Production cannot list local origins | added and tested this phase |
| App configuration | `ClientConfig.validated` rejects non-https and loopback hosts in production |
| Staging/production isolation | the release script refuses an `APP_ENV` mismatch, local or placeholder URLs; **actual Firebase project ids, buckets and domains are not present in the repository, so isolation of real projects could not be verified** |
| Secrets in Git, history, client bundles | none found by pattern scan of all tracked files and all history |
| Secret management and rotation | documented in `DEPLOYMENT_RUNBOOK.md`; the secret store itself is not configured here |

## 4. Findings summary
Severity counts after remediation are in `KNOWN_ISSUES_AND_RISKS.md`; the security view is in `SECURITY_ASSESSMENT.md`.
