# Test Report (Phase 12)

Date: 2026-11-05 · Branch `feature/phase-12-country-configuration` · Machine: macOS, Flutter 3.32.8 / Dart 3.8.1.

## Commands run and outcomes

| Command | Result |
|---|---|
| `scripts/check_all.sh` (format check, `analyze --fatal-infos`/`flutter analyze`, tests for all 11 projects) | **exit 0** — formatting clean, analyzer clean, all tests passed |
| `flutter build web` in `apps/clinic_web` | ✓ built |
| `flutter build web` in `apps/doctor_mobile` | ✓ built |
| `flutter build apk --debug` in `apps/doctor_mobile` | ✓ built |
| `flutter build apk --debug` in `apps/patient_mobile` | ✗ first run failed on a **pre-existing** manifest merge conflict (`usesCleartextTraffic`, introduced in Phase 8, unrelated to this phase) → fixed in a separate commit (`tools:replace` in the debug manifest only) → ✓ built |
| `dart compile exe bin/server.dart` (backend) | ✓ compiled |

## Per-project results (`scripts/check_all.sh`)

| Project | Tests passed | Skipped | Notes |
|---|---|---|---|
| backend | 912 | 29 | +49 this phase (48 country, 1 config). Skipped tests are the existing emulator-dependent ones; they did **not** run |
| packages/common_models | 21 | – | |
| packages/api_contracts | 7 | – | |
| packages/validation | 5 | – | |
| packages/utilities | 8 | – | |
| packages/country_config (new) | 20 | – | |
| packages/design_system | 14 | – | |
| packages/app_core | 81 | – | +10 this phase (regional, strings, RTL) |
| apps/clinic_web | 161 | – | +16 this phase (+ existing apply-page tests adapted to the country selector) |
| apps/doctor_mobile | 21 | – | |
| apps/patient_mobile | 36 | – | |
| **Total** | **1286 passed, 29 skipped** | | |

## What the new tests cover

* **country_config (20):** baseline India/UAE profiles validate and round-trip; invalid profiles; completeness warnings; postal rules (IN PIN, UAE none); IANA zones/offsets; currency minor units (INR 2, AED 2, KWD 3, JPY 0); phone validation (national/international, wrong-country rejection); locale resolution and RTL flag; UTC → branch-time rendering; money formatting; Indian grouping; Arabic formatting.
* **backend country_test (48):** seeding idempotency; list/detail; permissions (support read-only, plain user, no token); create starts disabled; evidence required to enable; invalid profile; duplicate; immutable fields; stale version; disable guard with live clinics; audit; onboarding list; corrupted profile; country required/malformed/spoofed/paused; India PIN and E.164; UAE no postal + UAE phones; phone never decides country; approval persists country; UAE tenant; **atomic failure when the country is disabled between submission and approval**; paused onboarding does not block approval of a submitted application; legacy application needs a code and mismatches are refused; approval idempotent; tenant users cannot set/change country; settings defaults and read-only code; policy-aware currency/timezone/language; cross-tenant config access; branch timezone validation; UAE branch (E.164, Dubai, localized address); branch in another country refused; Indian rules preserved; invalid localized variants; legacy tenant unchanged; resolution for India/UAE, user locale (Arabic/RTL), malformed locale, branch time zone, unconfigured tenant, **fail-closed on missing profile**, deployment region; cache TTL/invalidation; backfill classification with **no writes**; orphan tenant unmapped; report permissions; assignment (privileged, confirmed, audited, idempotent); correction needs current value + history; unknown tenant.
* **backend config (1):** `DEPLOYMENT_REGION` validation. **Route-auth sweep (existing):** updated allow-list; the least-privilege and mass-assignment sweeps now also exercise the new routes and pass.
* **app_core (10):** DTO parsing, fallback config, formatter per time zone/currency, locale preference rules, resolution order, translations (en/hi/ar), fallback to English, **Arabic RTL smoke test** (navigation rail moves to the right edge, content mirrors, no overflow).
* **clinic_web (16):** country selector lists only backend-offered countries; UAE selection changes labels and payload (`countryCode: AE`, no `country`, optional postal omitted); India PIN still enforced; load failure shows retry and sends nothing; platform country list (status, version, clinics, warnings); disable inert with active clinics; pause onboarding needs a reason and sends `expectedVersion`; backend refusal shown; support admin has no change controls; seed action; empty/error states; backfill report summary/rows, assignment dialog validation and call, support admin cannot assign, empty report.

## Not run / not verified (honest list)

* Firestore **emulator** tests and **rules tests** (`firebase/rules-tests`) — not run here; the new paths were added to the list but are unexecuted.
* Live Firebase (Auth, Firestore, indexes, FCM, Storage) — not used; all backend tests use the in-memory store.
* Docker image build (the Dockerfile now copies `common_models` and `country_config`, which the previous file lacked) — not built.
* Visual/browser verification of the new screens beyond widget tests; RTL tested by widget smoke test only.
* Performance/load, accessibility audit, release APK signing.
* Backward-compat regression: covered by the pre-existing 863-test suite passing unchanged except for fixtures (country now required on applications) and one allow-list update.
