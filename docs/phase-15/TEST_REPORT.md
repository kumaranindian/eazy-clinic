# Test Report (Phase 15)

Date: 2026-11-05 · Flutter 3.32.8 / Dart 3.8.1.

| Command | Result |
|---|---|
| `scripts/check_all.sh` (format, analyze, all tests, translation completeness) | **exit 0** |

| Project | Passed | Skipped |
|---|---|---|
| backend | 1014 (+29 new in `tax_test.dart`) | 29 (emulator) |
| common_models 21 · api_contracts 7 · validation 5 · utilities 8 · country_config 20 | all pass | – |
| design_system 19 · app_core 102 · clinic_web 184 · doctor 23 · patient 40 | all pass (unchanged) | – |

## What `tax_test.dart` proves (29)
* **Rounding/precision:** half-up, half-even and down divisions; exclusive tax differs by mode with parts adding to the total; inclusive keeps the total and the split adds up in every mode; invoice discount shared before tax with no drift; integers only.
* **Policy resolution:** intra vs inter components; effective-dated periods incl. boundary days and "no rate in force"; exempt (no tax) and zero-rated (0 bps lines); refuses unverified, retired, other-country, missing and unknown-exemption cases; baseline shells have no rate, are unverified, valid, and cannot resolve.
* **Validation:** overlaps, out-of-range or negative rates, impossible dates (`2020-13-45`), empty components, bad mode/rounding, missing source.
* **E-invoice:** final states cannot move; failed can retry; shipped provider disabled for IN and AE; the API returns 409 and stores nothing; nurse refused.
* **API:** permission split (support read-only, owner refused, 401); seed create-if-absent; no rates → cannot verify; verification lifecycle, voiding by rate change, stale verification refused, metadata edit keeps verification, 4 versions recorded; update validation (version, reason, unknown fields, mode); invoice lines refuse unverified/unknown policy; policy line taxed 18% on the invoice date and **unchanged after the policy later changes**; exempt/zero-rated/inter-state/unknown exemption/policy-with-manual-exemption/orphan supply; another country's clinic sees no policies; finalization refused when the policy changed after the draft and works after re-saving; usable list shows only verified with today's rates; issue snapshot retained after settings change and bad tax number refused; **8 concurrent finalizations → 8 unique gapless numbers**; credit note tax part recorded and capped; tax summary separates revenue/liability/collections, nets credit-note tax, CSV works, receptionist/nurse refused.

## Not run / not verified
Firestore emulator and rules tests; real concurrency on Firestore (in-memory store serializes transactions); live providers (none); Clinic Web UI (none built); PDF export; browser rendering. **No tax specialist has validated any rate or rule.**
