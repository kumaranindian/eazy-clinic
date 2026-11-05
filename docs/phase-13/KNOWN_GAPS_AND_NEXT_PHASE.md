# Known Gaps and Next Phase

| ID | Gap | Impact / plan |
|---|---|---|
| TD-102 | Most screen text is still English (≈ 296 `Text` literals + labels/hints). Only auth/status screens, navigation, status words, selectors and design-system texts use resources | Needs a rolling migration per feature (prioritise appointment booking, billing, patient-facing screens) |
| TD-103 | Backend messages (validation issues, error messages) are English | Return stable codes + localize on the client, or accept `Accept-Language` |
| TD-104 | Arabic/Hindi/Tamil are machine-assisted starter packs, unreviewed, uncertified | Professional/native review before release; legal/clinical/consent wording out of scope |
| TD-105 | RTL not audited screen-by-screen for tables, calendars, pickers, dialogs in clinic screens | Visual QA in Arabic per feature |
| TD-106 | 8 hand-padded time helpers remain (slot labels) | Replace with `RegionalDisplay.time` |
| TD-107 | Numeral system (Arabic-Indic vs Western) is whatever platform data gives; no clinic/user setting | Add preference if clinics ask |
| TD-108 | Inter has no Arabic/Devanagari/Tamil glyphs; fallback fonts are platform-specific | Bundle Noto/IBM Plex fonts per script and test on devices |
| – | Language preference is stored on the account; the clinic default language can be changed in settings but is not surfaced in a language-specific UI | — |
| – | Document (PDF) localization is a hook only | Phase 19 / per-document work |
| – | Relative-time and plural messages exist in resources but no screen uses them yet | adopt when screens are migrated |

## Release risks
Do not describe the product as "available in Arabic/Hindi/Tamil" until reviewed translations cover the flows users actually need; keep legal text (terms, privacy, consent) in reviewed language only.

## Next phase
**Phase 14 – Country Compliance Framework** (policy and evidence per country). It can rely on: country master + versioned config (Phase 12), `supportedUiLanguages`, document-locale hook (Phase 13). Prerequisites: counsel/regulatory input per country; decision on how compliance evidence is stored and reviewed.
