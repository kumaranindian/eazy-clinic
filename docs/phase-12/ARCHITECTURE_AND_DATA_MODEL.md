# Architecture and Data Model

## 1. Distinct concepts (never conflated)

| Concept | Where it lives | Who sets it | Can a client change it? |
|---|---|---|---|
| **Country** (master + policy) | `countries/{ISO}` | Platform admins | No |
| **Tenant legal country** | `tenants/{id}.countryCode` | Approval (from the applicant's validated choice) or an audited migration | No (tenant users); platform migration only |
| **Legal entity** | tenant (`clinicName`, registration) | Application/approval | n/a (not modelled further in this phase) |
| **Branch** | `tenants/{t}/branches/{b}` (`timezone`, `address`, `phone`) | Clinic users with branch permission | Yes, within the clinic's country |
| **User display locale** | in-memory preference in the app (Phase 13 persists) | The user | Yes; presentation only |
| **Deployment region** | `DEPLOYMENT_REGION` env | Operators | n/a; informational |

## 2. Layers and resolution (`CountryConfigResolver`)

```
1 country master + policy (versioned, platform-managed)
2 tenant legal country (tenant doc, server-side)
3 tenant overrides allowed by policy (clinic_settings/operations: timezone, language, currency)
4 branch settings (branch timezone)
5 user display preference (?locale=)
6 deployment configuration (region)
```
Rules: a lower layer can never change a higher one; unknown or invalid configuration **fails closed** (503 `unavailable`, no guessed defaults);
a tenant with no `countryCode` resolves as `countryConfigured: false` (pre-Phase-12 behaviour, nothing inferred).

Effective values: `timezone` = tenant override if policy allows and valid, else first suggested zone; `currency` = tenant override if policy allows and in the supported list, else country default;
`locale` = `resolveLocale(user → tenant language → country default → en)`; `branchTimezone` = valid branch zone else clinic zone.

Cache: `CountryDirectory` keeps profiles for 60 s; administrative changes invalidate the local cache; other instances converge within the TTL (TD-97). Onboarding, provisioning and migration read the master fresh (inside the transaction).

## 3. Data model

### `countries/{ISO 3166-1 alpha-2}` (platform-level, new)
`code`, `name`, `nativeName`, `status` (`supported`|`disabled`), `onboardingEnabled`, `callingCode` (`+91`), `defaultCurrency` (ISO 4217), `locales[]` (BCP-47), `defaultLocale`,
`suggestedTimezones[]` (IANA), `adminAreaLabel`, `postalCode{required,label,pattern}`, `policy{allowedTenantOverrides[], supportedCurrencies[]}`, `configurationVersion`, `effectiveFrom`,
`reviewedOn`, `sources[]`, `updatedAt`, `updatedBy`.
Immutable after creation: `code`, `callingCode`, `defaultCurrency`.
`countries/{code}/versions/{n}`: full snapshot per version + `reason`, `snapshotAt` (effective-dated history).

### `tenants/{id}` (new fields)
`countryCode`, `countryConfigVersion` (master version at assignment), `countrySource` (`application`|`approval`|`migration`), `countrySetAt`, `countrySetBy`.
`tenants/{id}/country_history/{ts}`: `from`, `to`, `configurationVersion`, `reason`, `actorUid`, `at` (only on migration/correction).

### `clinic_applications/{id}`
`address.countryCode` (required for new submissions), `address.country` (derived name; supplied value ignored), `countryConfigVersion`. Phones stored in E.164 when a country is given.

### Branch / clinic profile address
`address{line1,line2,city,state,countryCode,country,postalCode,localized{<lang>:{line1,line2,city,state}}}` (≤ 4 variants; presentation only), `phone` (E.164 for clinics with a country), `timezone` (IANA).

### Clinic settings
Defaults for a clinic with a country: currency = country default, language = country default language. `GET …/settings` also returns read-only `countryCode`.

### Indexes
New: `countries(onboardingEnabled ASC, code ASC)` (onboarding list). Active-clinic counts use equality + `in` filters on `tenants` (no composite index needed). Nothing deployed.

### Rules
`firestore.rules` is deny-all for clients and already covers `countries/**` and `tenants/**/country_history/**`; paths added to the emulator rules test list (not run here, see TEST_REPORT).

## 4. Shared packages

`packages/country_config` (pure Dart): `CountryProfile` (+validation, completeness warnings, client DTO), `BaselineCountries` (IN, AE), `PhoneNumbers` (phone_numbers_parser), `Timezones` (timezone/tz database), `Currency` (minor units via intl),
`resolveLocale`, `LocaleFormatter`. Used by the backend and `app_core`.
`packages/app_core/src/regional`: `RegionalConfig`, `RegionalFormatter`, `LocalePreference`, `AppStrings` (en/hi/ar, representative), `appLocalizationDelegates`.

## 5. Backend components

| Component | Role |
|---|---|
| `countries/country_directory.dart` | Read/cache the master; fail-closed parsing; tenant country lookup |
| `countries/country_service.dart` | Admin list/create/update/seed, disable guard, version snapshots, backfill report, audited assignment |
| `countries/country_resolver.dart` | Layered resolution + safe DTO |
| `countries/country_rules.dart` | Country-aware phone/postal/address helpers; localized address reader |
| `ApplicationService` | Validates `countryCode` against the master (inside the transaction); derives name; stores master version |
| `TenantService.approve` | Re-validates country in the same transaction before any write; writes tenant country fields |
| `BranchService`, `ClinicService` | Country-aware phone/postal/address; IANA timezone; policy-aware settings |
| `AppConfig` | `DEPLOYMENT_REGION` (optional, validated) |
