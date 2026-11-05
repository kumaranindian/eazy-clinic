# Known issues and risks

Severity follows the Phase 11 definitions. "Open" means not resolved before a production release.

## Release-blocking (High, open)
| ID | Finding | Why it blocks | Needed to close |
|---|---|---|---|
| F-03 | **No staging/UAT and no live-Firebase verification**: indexes (41), rules, Cloud Storage adapter, FCM sender and the notification worker were never run against real services | Unknown production behaviour; missing indexes make queries fail | Staging project, deployment, UAT sign-off |
| F-04 | **Patient Android app not built or run** (no SDK); release signing needs a provisioned keystore (fail-closed Gradle change is unbuilt) | The artifact does not exist | SDK, keystore, build, device tests |
| F-05 | **Backup/restore not rehearsed on the managed service**; RPO/RTO not agreed | Data-loss and recovery time unknown | Enable PITR/exports, staging rehearsal, owner-agreed targets |
| F-06 | **No monitoring, alerting, error reporting or on-call** configured | Failures unnoticed | Owner decisions and configuration |
| F-07 | **Legal/privacy review not done** (DPDP duties, retention, deletion workflow, disclosures) | Compliance cannot be claimed | Qualified review; policy; account-deletion processing (TD-66) |

## Medium (open)
| ID | Finding |
|---|---|
| F-08 | Web security headers/CSP are an unverified draft; hosting target and domains undefined |
| F-09 | Dependency scanning is partial (`npm audit` on dev tooling: 34 advisories, 1 critical transitive `tar`, not shipped; no Dart advisory scanner) |
| F-10 | No MFA for privileged users |
| F-11 | Rate limits are per instance; several instances multiply the allowance |
| F-14 | Performance on Firestore, devices and browsers unmeasured; budgets are proposals |
| F-15 | Notification worker is an in-process timer that needs an always-on instance (TD-85); outbox write is not transactional with the business commit (TD-86) |
| F-16 | Accessibility not audited; browser/device matrix not tested |
| F-17 | CI has not run on GitHub; its Flutter/Java/Node setup is unverified until the first run |

## Low / informational
Push (FCM) and e-mail/SMS/WhatsApp are not live (TD-83/84); no online payments; PDFs are plain text (TD-73); reports compute on demand with a scan cap (TD-87); exports expire after 6 hours and files are not cleaned up (TD-88); several event types are not notified (TD-89). Dev-tooling advisories (S-08). Allow-listed self-service routes (S-09).

## Fixed in this phase
F-01 no CI (workflow added); F-02 release builds signed with the debug key (fails closed now); S-01 payment configuration visible to any member; S-02 local origins accepted in production CORS; no readiness probe; request logs without severity.

## Residual risk statement
Even after the open items are closed, the first production weeks carry the usual new-system risk: unmeasured load, unmeasured provider behaviour and real-world data shapes. Plan a pilot with one or two clinics, staged Android rollout, daily review of error logs and a named person on call.

## Acceptance of risk
No risk has been formally accepted by an authorised owner. Any acceptance must name the finding, the owner, the date and the expiry.
