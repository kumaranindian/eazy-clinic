# Phase 8 Completion Report

Status: **implemented and tested at API and widget level; not release-ready; not pushed.** Branch `feature/phase-8-patient-app` (created from `develop` at the owner's request). No production Firebase change, deployment, Play Store action or secret.

## Definition of done
| Requirement | State |
|---|---|
| Register and log in | Done (Phase 1 flow) plus patient account setup |
| Manage profile | Partly: view, language, address, emergency contact; identity changes and photo deferred (TD-66) |
| Discover clinics, link records securely | Done (code-based linking, Phase 4 rules) |
| Discover doctors | Done (public fields only) |
| Book, cancel, reschedule, check in; queue status | Done through the Phase 5 engine |
| Released summaries, prescriptions | Done |
| Laboratory reports, medical documents | **Not available** (TD-68) |
| Family and dependents | Done on Phase 4 relationships |
| Invoices, payments, receipts, refunds | Done read-only; no online payment, no PDF |
| Notifications | Inbox, devices, preferences done; **push delivery not wired** (TD-67) |
| Consent and privacy | Done per purpose, versioned |
| Cross-patient and cross-clinic access prevented | Done, tested |
| Android build passes | **Not verified: no Android SDK here** (TD-70) |
| Phases 0–7 functional | Yes (full suite green) |

## Open blockers and decisions for the owner
- Android SDK, signing key and per-environment Firebase files are needed to build, sign and test on a device.
- FCM wiring needs the plugin and `google-services.json` (and Phase 10 for reminders).
- A release workflow for documents (and Phase 9) is needed before any document or report is shown.
- Booking policy values (60 days, 2 hours) are product defaults awaiting your decision.

## Commits
`fcec1a5` portal API (with tests, rules tests, indexes) · `20d806c` patient application and doctor release button · docs commit (this folder, README and shared docs).

## Next step
Approval to push and merge, then Phase 9 (laboratory and documents), which also unblocks documents and reports in the app.
