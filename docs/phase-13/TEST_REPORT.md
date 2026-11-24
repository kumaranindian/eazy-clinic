# Test Report (Phase 13)

Date: 2026-11-05 · Branch `feature/phase-13-internationalization` · Flutter 3.32.8 / Dart 3.8.1.

## Commands and outcomes

| Command | Result |
|---|---|
| `scripts/check_all.sh` (format check, analyze, all tests, translation completeness) | **exit 0** |
| `dart run tool/l10n_report.dart --check` | OK: 4 locales × 116 keys, 0 missing / empty / placeholder mismatches |
| `flutter build web` (clinic_web, doctor_mobile) | ✓ both |
| `flutter build apk --debug` (patient_mobile, doctor_mobile) | ✓ both |
| `dart compile exe bin/server.dart` | ✓ |

Environment note: the disk filled up during the run (Android build folders ≈ 2.6 GB each), which made one `check_all.sh` run fail with *No space left on device*; build outputs (git-ignored) were deleted and the full run was repeated from the start and passed.

## Results per project

| Project | Passed | Skipped | Δ vs Phase 12 |
|---|---|---|---|
| backend | 928 | 29 (emulator-dependent, not run) | +16 |
| common_models | 21 | – | 0 |
| api_contracts | 7 | – | 0 |
| validation | 5 | – | 0 |
| utilities | 8 | – | 0 |
| country_config | 20 | – | 0 (currency assertions tightened) |
| design_system | 19 | – | +5 |
| app_core | 102 | – | +21 |
| clinic_web | 164 | – | +3 (+10 expectations updated for grouped money) |
| doctor_mobile | 23 | – | +2 |
| patient_mobile | 40 | – | +4 |
| **Total** | **1337 passed, 29 skipped** | | **+51** |

## What the new tests prove

* **Backend (16):** translated reminder templates exist for ar/hi/ta and use exactly the English placeholders and no clinical variables; RTL values are isolated; bidi controls in values are stripped; Unicode names (Arabic, Tamil, Hindi) are accepted; HTML still escaped; missing/disallowed variables still fail; document-language resolver order; `preferredLanguage` set/read/clear, allow-list validation, cannot be combined with forbidden fields, does not change roles/tenant/country, audit stores names not values.
* **design_system (5):** e-mail/phone fields stay LTR inside an RTL screen; Arabic/Hindi/Tamil/mixed text accepted and kept; identifiers stay LTR; navigation rail mirrors; localized texts through `EcTextsScope`.
* **app_core (21):** generated strings in en/ar/hi/ta; fallback to English; no-localization fallback; plural rules (incl. Arabic dual/few); sign-in screen translated in ar/hi/ta; design-system widgets translated (password field, tooltip); Arabic RTL with no overflow; **200% font scale in all four languages without overflow**; **language switch keeps typed text**; localized validation messages and sign-in failures; account language applied after sign-in and reset on sign-out; preference persistence only when asked; unsupported language never stored; `RegionalDisplay` clinic-zone times, money minor units and decimals, defaults, per-language styles, invalid input; completeness report and ICU argument extraction; tap-target/label accessibility guidelines in all four languages.
* **Apps (9):** patient: navigation in ar/hi/ta, RTL rail on the right edge, language menu switch, status chips, clinic-zone appointment times; doctor: menu-driven switch to Hindi/Arabic with RTL; clinic web: Arabic registration form (typed data survives the switch), Tamil platform navigation, `Fmt` zone/money/grouping.

## Not run / not verified
* Firestore emulator and rules tests; live Firebase; Docker build (as in Phase 12).
* **No native-speaker review of any translation.**
* RTL was verified with widget tests; tables, calendars, date pickers and dialogs in the large clinic screens were not exercised in Arabic (TD-105).
* Real-device rendering of Arabic/Tamil/Hindi fonts (the bundled Inter font has no Arabic, Devanagari or Tamil glyphs; platform fallback fonts are used) — TD-108.
* No screen reader session (TalkBack/VoiceOver); only Flutter's automated guidelines.
