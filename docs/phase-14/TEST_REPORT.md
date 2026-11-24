# Test Report (Phase 14)

Date: 2026-11-05 · Branch `feature/phase-14-compliance-framework` · Flutter 3.32.8 / Dart 3.8.1.

## Commands and outcomes

| Command | Result |
|---|---|
| `scripts/check_all.sh` (format, analyze, all tests, translation completeness) | **exit 0** |
| `flutter build web` (clinic_web) | ✓ |
| `dart compile exe bin/server.dart` | ✓ |
| `flutter build apk --debug` (doctor, patient) | **not re-run**: neither app changed (only the shared `common_models` permission list); disk space was short (≈ 4.7 GB free), and Android builds were verified in Phase 13 |

## Results

| Project | Passed | Skipped | Δ vs Phase 13 |
|---|---|---|---|
| backend | 985 | 29 (emulator-dependent, not run) | +57 |
| common_models | 21 | – | 0 |
| api_contracts | 7 | – | 0 |
| validation | 5 | – | 0 |
| utilities | 8 | – | 0 |
| country_config | 20 | – | 0 |
| design_system | 19 | – | 0 |
| app_core | 102 | – | 0 |
| clinic_web | 184 | – | +20 |
| doctor_mobile | 23 | – | 0 |
| patient_mobile | 40 | – | 0 |
| **Total** | **1414 passed, 29 skipped** | | **+77** |

## What the new tests prove

**Rules (15, `compliance_core_test`):** no record = not assessed; approvals expire at the instant of expiry with no write; an approval of a changed requirement stops counting; transition table (nothing jumps to approved; approved needs review); no status contains "complian…"; credential validity bands; alert thresholds 60/30/7/expired; file type from bytes (PDF/PNG/JPEG; HTML/EXE rejected); baseline covers India and UAE, UAE has DHA, DoH and MOHAP as separate registers each stating applicability is per clinic, every profile `pending` and every requirement `low` confidence with source/owner/draft note, ABDM is optional-integration only and states no integration, no text claims compliance or certification, unique requirement keys.

**API (42, `compliance_api_test`):**
* *Registers:* seed once, never overwrite; list/filter/read/versions; permissions (support read-only, strangers refused, 401); update publishes a version with snapshot, reason and impact (added/removed/changed, tenants affected); stale version, missing reason/version, fixed scope fields; invalid content (no source, high confidence without review, reviewed without reviewer, duplicates, empty); legal review recorded and audited.
* *Applicability:* nothing applies by default (honest empty dashboard); reviewer confirms; other-country register refused; clinic/support/strangers refused; UAE vs India registers; clinic without a country.
* *Evidence:* needs confirmed applicability; upload moves to under review, no storage path/hash leaked; file checks (HTML, MZ, bad base64, empty, oversized); expiry rules; unknown register/requirement, unsupported kind, smuggled fields; **clinic owner cannot approve own evidence**; accept starts the expiry clock; reject needs a reason and the clinic can resubmit (rejected file keeps its status); newer upload supersedes and voids approval; not-applicable needs reviewer + reason and blocks uploads, reopen works; **downloads are tenant-scoped, audited, with generic names and safe headers**; review queue across clinics for reviewers only, overview counts.
* *No false badge:* approved-but-unvalidated register is not "ready"; ready state only after legal validation and never says compliant; changed requirement voids approval; expired approval shows expired with no job; approval impossible once the document expired during review.
* *Credentials:* validity states and attention list; validation (practitioner exists, facility has none, number format, dates, kinds, smuggled fields); only a reviewer verifies, only with a document and end date; changes void verification; verified credential stops counting at expiry; archived hidden and immutable; other clinic cannot see or edit.
* *Access and alerts:* owners/admins only; history of every change; alerts to owners and admins at each threshold with stable dedupe keys and no document details; scan persists expiry once; works without a notifier; the notification worker runs the scan for every active clinic.

**Clinic Web (20):** clinic page says "not legal advice" and never "compliant/certified"; unconfirmed state; real statuses, expiry text, reviewer notes, changed-requirement warning; validated vs not validated labels; upload dialog validation, base64 payload without status/tenant fields; backend refusal shown; view-only users get no write buttons; authenticated download with a generic name; credentials add/archive; country-missing and error/retry states; navigation permission gating; platform overview/queue/registers, support-admin limits, seed, queue → review page, applicability needs a reason, approve/reject flow with reason, controls only for evidence under review, support admin has no review controls, download and verify.

A real layout defect was found and fixed by these tests (buttons with unbounded minimum width inside a `Row` and a `ListTile`).

## Not run / not verified
* Firestore emulator and rules tests (new paths added to the list, unexecuted); live Firebase; the two new collection-group indexes are undeployed.
* A real notification delivery end to end (the hub is exercised through a recording notifier and the worker hook).
* Browser rendering beyond widget tests; Android builds this phase; Arabic/RTL review of the new screens (English-only strings, TD-110).
* **No counsel or regulator has validated any register.**
