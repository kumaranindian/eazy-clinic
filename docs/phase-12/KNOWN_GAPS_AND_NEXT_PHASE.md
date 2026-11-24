# Known Gaps and Next Phase

## Known gaps / technical debt (see also `docs/TECHNICAL_DEBT.md` TD-95…TD-101)

| # | Gap | Impact |
|---|---|---|
| TD-95 | Verification is test-double/in-memory only for Firestore; emulator, rules tests and live Firebase unexecuted | Unverified against real services; new index undeployed |
| TD-96 | Country master baseline is reviewed against standards bodies (ISO, IANA, CLDR/libphonenumber via packages) only. Legal/regulatory requirements per country (UAE entity/data rules, India DPDP specifics) are **not** assessed here — that is Phase 14 | No compliance claim is made |
| TD-97 | Country profile cache is per instance (60 s TTL); invalidation is local | A change can take ≤ 60 s to reach other instances |
| TD-98 | Locale preference is in memory (not persisted per user); only en/hi/ar with representative strings; most UI text is English; date pickers follow Material locale data | Full i18n is Phase 13 |
| TD-99 | Existing tenants stay unassigned until a super admin assigns them; there is no bulk-apply (by design) and no UI to assign from the tenant page (only from the backfill report) | Manual migration effort |
| TD-100 | `assignTenantCountry` changes the legal country but does not convert/validate existing stored phones, currency or amounts | Possible inconsistency after a *correction* |
| TD-101 | Branch `localized` address is stored and returned but not yet shown in any UI; `adminAreaLabel`/postal label drive only the application form | Presentation follow-up |
| – | Multi-country legal groups (one owner, several legal entities) are not modelled; a tenant has exactly one legal country | Product decision for Phase 20 |
| – | `timezone` package adds tz data to web bundles through `app_core` | Bundle size to be measured in Phase 21 |
| – | One pre-existing build defect (patient debug manifest) was fixed in a separate commit; the previous Dockerfile also lacked `common_models` | Fixed, noted for transparency |

## Release risks
Do not enable a country in production without recording review sources/date and legal sign-off; do not assign countries to existing production tenants without reviewing the dry-run report.

## Next phase
**Phase 13 – Internationalization & Localization** builds on: `AppStrings`/delegates, `LocalePreference` (persist per user), `RegionalFormatter`, `resolveLocale`, RTL smoke test, `address.localized`.
Prerequisites: decide ARB/gen-l10n approach, translation review workflow, supported language list per country, and persistence of user language (account profile).
