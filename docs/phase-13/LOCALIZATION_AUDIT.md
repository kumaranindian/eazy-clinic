# Localization Audit (2026-11-05)

Method: repository search of `apps/*/lib`, `packages/app_core/lib`, `packages/design_system/lib` before and after the phase.

| Check | Before | After | Notes |
|---|---|---|---|
| `Text('…')` English literals: clinic_web / doctor / patient | 190 / 53 / 53 | 190 / 53 / 53 | **Unchanged**: screen bodies were not translated in this phase |
| `Text('…')` English literals: app_core / design_system | 8 / 8 | 0 / 8 | app_core fully localized; design-system literals are the English defaults of `EcTexts` (overridden by the app scope) |
| Strings read from generated resources (`l10n.`) | 0 | 67 call sites | auth, navigation, status, selectors |
| Left/right layout assumptions | 9 | 0 | converted to `EdgeInsetsDirectional`, `AlignmentDirectional`, `BorderDirectional` |
| Hand-written date/time/money formatters | 3 (one per app) | 0 (all delegate to `RegionalDisplay`) | 8 `padLeft(2…)` uses remain in unrelated time-slot helpers (TD-106) |
| `toLocal()` (device zone) for clinic events | 6 | 0 outside `RegionalDisplay`'s explicit platform fallback | |
| `₹` hard-coded in UI text | 10 | 0 (labels use the clinic currency; amounts via formatter) | |
| Pluralization / relative time | none | ICU plurals in resources (`appointmentsCount`, `minutesAgo`) | not yet used by screens |
| Layout checked at 200% font scale | not done | sign-in screen in en/ar/hi/ta | |

## Findings carried forward
1. Most screen text is English (TD-102).
2. Backend error/validation messages are English (TD-103).
3. Time-slot helpers still pad digits by hand (TD-106).
4. Arabic-Indic vs Western digits is decided by platform locale data; no per-clinic numeral setting (TD-107).
5. Tables, calendars and dialogs were not individually RTL-audited beyond the shared widgets (TD-105).
