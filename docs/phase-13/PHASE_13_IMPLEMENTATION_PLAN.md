# Phase 13 – Internationalization & Localization: Implementation Plan

Branch `feature/phase-13-internationalization` (stacked on `feature/phase-12-country-configuration`). Date: 2026-11-05.
Specification: `EazyClinic_Phase_13_Implementation_Prompt.docx`.

> **Branch note.** The prompt says to stay on `feature/phase-0-foundation`; at the user's later instruction each phase has its own branch and is delivered by pull request. Phase 13 builds on Phase 12 (country configuration), so merge Phase 12 first.

## 1. Pre-flight audit (before any change; details in `LOCALIZATION_AUDIT.md`)

| Area | Finding |
|---|---|
| Strings | ~300 hard-coded English `Text('…')` literals in the three apps, plus labels/hints; only Phase 12's 6 representative strings were localized |
| Dates / numbers / money | Three hand-written formatters (one per app): fixed month abbreviations, `HH:mm`, no thousands grouping, `₹` hard-coded, **device-local time** (wrong for clinic events when the device zone differs from the branch zone), two decimals assumed; `₹` in 7 form labels |
| Layout direction | 9 left/right assumptions (`EdgeInsets.only(left…)`, `Alignment.centerLeft/Right`, a left `Border`) |
| Design-system widgets | Hard-coded English tooltips/labels (password toggle, search, error state, back, loading) |
| Validation / errors | English messages from `validation` and `AuthFailure` |
| Notifications | Template language already per recipient (Phase 10) but English-only built-ins; template values were not protected against bidirectional-control characters |
| Accounts | No per-user language preference |

## 2. Impact and risks

| Risk | Mitigation |
|---|---|
| Money text changes (`₹1200.00` → `₹1,200.00`, Indian grouping, ISO code for non-symbol currencies) | Intended; 10 test expectations updated; documented |
| Time text changes (24 h → locale style, clinic zone) | Intended; correctness fix; tests added |
| Machine-assisted translations may be wrong or inappropriate | Labelled starter packs everywhere; **not** used for legal, clinical or consent text; completeness report states this; professional review is a release gate (TD-104) |
| A re-render on language switch could lose user input | Rebuild preserves `State`; tests type text, switch language, and assert the text is kept |
| New template languages could leak data or break layout in RTL | Placeholder-parity test, bidi-control stripping, isolates for RTL |

## 3. Delivered

1. **Resources and generation:** Flutter `gen-l10n` (ARB) in `packages/app_core`: English template + Arabic, Hindi, Tamil (116 keys), generated classes committed; plural forms (incl. Arabic's six); completeness tooling (`tool/l10n_report.dart`, run by `scripts/check_all.sh`).
2. **Locale resolution and preference:** documented precedence; per-user language stored on the account (`PATCH /auth/me`), applied after sign-in, reset on sign-out; language menu in all three apps; presentation only.
3. **RTL:** directional fixes (9), edge accents, Arabic layout tests, LTR data fields, `EcLtrText` for identifiers, Unicode input tests.
4. **Formatting:** one `RegionalDisplay` (date, time, number, money; clinic/branch zone; currency minor units) replacing three formatters; `₹` removed from touched flows.
5. **Translated critical flows (representative):** sign-in/registration/reset/verification/status screens, validation and sign-in failure messages, navigation labels (patient, doctor, clinic, platform), appointment/billing status words, design-system widget texts, appointment and follow-up reminder templates (Arabic/Hindi/Tamil, in-app and push).
6. **Template safety:** bidi-control stripping, RTL isolates, placeholder parity tests; document-language resolver hook.
7. Docs, ADRs 089–094, TD-102…TD-108, tests.

## 4. Explicitly not done (per prompt)
Professional translation or certification; translation of every screen (most screen bodies remain English: see `KNOWN_GAPS_AND_NEXT_PHASE.md`); legal translation approval; country-specific clinical content; changing stored dates or financial values.
