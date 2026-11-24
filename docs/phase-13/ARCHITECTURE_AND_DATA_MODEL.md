# Architecture and Data Model

## 1. Concepts kept separate

| Concept | Source | Effect |
|---|---|---|
| Legal country | tenant record (Phase 12) | policy, currency, phone/postal rules |
| Clinic default language | `clinic_settings/operations.language` (limited by country policy) | default UI/template language for the clinic |
| Country default language | country master `defaultLocale` | fallback |
| **User language** | `platform_users/{uid}.preferredLanguage` | **presentation only** |
| Device language | OS | used only when the user has no preference |
| Branch time zone | branch / clinic settings | how instants are displayed |

A language is never an input to authorization, tenancy, legal country, currency, stored dates or any clinical/financial value.

## 2. Locale resolution order

`user preference → clinic default (if the country policy allows that language) → country default → English`.
Matching: exact tag, then same language, against the app's supported list (`en, ar, hi, ta`, shared `supportedUiLanguages` in `common_models`). The device language is used when there is no stored preference; an unsupported device language resolves to English (the MaterialApp's own resolution).
Backend: `CountryConfigResolver` (Phase 12) uses the same order and the same shared list; `GET /clinics/current/country-config?locale=` returns the resolved tag and `rtl`.

## 3. Resources

```
packages/app_core/
  l10n.yaml                       gen-l10n options (generated code committed)
  lib/l10n/app_{en,ar,hi,ta}.arb  116 keys (English is the template)
  lib/l10n/generated/             generated AppLocalizations (+ per-language classes)
  tool/gen_arb.py                 source table for the four ARB files (single place to review translations)
  tool/l10n_report.dart           completeness + placeholder report (`--check` fails the build)
```
* Missing key or locale → generated code falls back to English (never a raw key). A test asserts that unknown device languages resolve to English and that `context.l10n` works with no localization installed.
* Dynamic values go through ICU placeholders (`{email}`, `{field}`), never string concatenation; placeholder parity with English is verified for every locale.
* Plurals use ICU (`appointmentsCount`, `minutesAgo`); Arabic has zero/one/two/few/many/other forms.
* Server-supplied messages (validation text from the backend, some error messages) are still English (TD-103).

## 4. App wiring

`MaterialApp.router(locale: appLocaleProvider, supportedLocales, localizationsDelegates, builder: localizedAppBuilder)` in every app. `localizedAppBuilder` (`LocalizedAppScope`):
1. installs `EcTextsScope` (design-system texts from the active language);
2. applies the account's language after sign-in and clears it on sign-out;
3. keeps `RegionalDisplay` (language, country, time zone, currency) in step with the clinic's configuration (only for users with a clinic membership);
4. when language/region changes, marks the tree dirty so every visible string and formatted value refreshes **while preserving widget state** (typed text, scroll, selections).

`LanguageSelector` (popup menu) is available on auth screens, the clinic and platform shells, the doctor shell and the patient profile.

## 5. Formatting (`RegionalDisplay`, `country_config`)
* Instants → clinic/branch zone (IANA) when known; the device zone only for platform-level screens without a clinic.
* Locale for formatting = language + clinic country (`ar-AE`, `en-IN`, `hi-IN`); clinics not yet assigned a country default to India formatting (the pre-Phase-12 behaviour).
* Money = minor units + ISO code; decimals per currency; symbol only for unambiguous currencies (₹ $ € £ ¥), otherwise the ISO code with a no-break space (`AED 1,200.00`).
* Numbers use the locale's grouping (`12,34,567` for India).
* Arabic numerals: the platform's CLDR data decides digit shapes (Arabic-Indic in some Arabic contexts); identifiers, phone numbers and e-mail are kept left-to-right (TD-107).

## 6. Data model change

`platform_users/{uid}.preferredLanguage` — optional string in {`en`,`ar`,`hi`,`ta`}; `null`/absent = follow the device. Read in the session and profile DTOs; written only by the owner through `PATCH /auth/me`; invalid stored values are ignored. No other collections change. Notification templates already carry `locale` (Phase 10); built-in templates were added for `ar`, `hi`, `ta`.

## 7. Notification and document hooks
* `renderTemplate(..., rtl:)` isolates every value with U+2068…U+2069 for RTL templates; bidi control characters in values are removed (see SECURITY).
* Built-in reminders (appointment, follow-up) in `ar`/`hi`/`ta` for in-app and push; generic wording only, no clinical detail. Template choice prefers the recipient's language, then English.
* `resolveDocumentLocale` (backend `core/localization/document_locale.dart`): recipient → clinic → country → English, restricted to the languages a given document kind actually has. Hooks only: invoices, prescriptions, reports and consent forms are unchanged and not translated.
