# API Contracts (Phase 12)

All responses use the standard envelope. `P` = platform permission. Errors: 401/403/404/409/422/503 as in `docs/api/API_STANDARDS.md`.

## Applicant / any signed-in user

### `GET /api/v1/countries`
Countries a new clinic may choose (status `supported` and `onboardingEnabled`). Client-safe fields only.
`200 { items: [ { code, name, nativeName, callingCode, defaultCurrency, locales[], defaultLocale, suggestedTimezones[], adminAreaLabel, postalCode{required,label,pattern}, configurationVersion } ] }`

### `POST /api/v1/clinic-applications` (changed)
`address.countryCode` **required** (`^[A-Z]{2}$`, must be in the master and onboardable). `address.country` optional and ignored (name is derived).
Phones are validated for that country and stored in E.164; the postal code follows the country rule (`required` per country).
Errors: `422` `address.countryCode` (`required` | `invalid_value` | `unsupported_country`), `address.postalCode`, `clinic.phone`/`owner.phone` (`invalid_phone`).
`POST …/respond` accepts the same fields; the merged address is re-validated.

## Clinic users (membership + `clinic.view`)

### `GET /api/v1/clinics/current/country-config?branchId=&locale=`
Resolved configuration (see ARCHITECTURE §2). `branchId` must be within the caller's branch scope. `locale` is a presentation preference (`^[A-Za-z]{2,3}([-_][A-Za-z]{2})?$`, else 400).
```json
{ "tenantId": "ten_x", "countryConfigured": true,
  "country": { "code": "AE", "name": "United Arab Emirates", "...": "client-safe fields" },
  "tenant": { "countryCode": "AE", "configurationVersionAtAssignment": 1 },
  "effective": { "timezone": "Asia/Dubai", "branchTimezone": "Asia/Dubai", "currency": "AED", "currencyMinorUnits": 2,
                 "language": "ar", "locale": { "tag": "ar", "rtl": true, "source": "user" } },
  "deployment": { "region": "asia-south1" } }
```
`countryConfigured:false` (no assigned country) → `country: null`, fallback presentation values. A tenant whose country profile is missing/invalid/disabled → `503 unavailable`.

### Changed existing endpoints
| Endpoint | Change |
|---|---|
| `PATCH /clinics/current` | `address.countryCode` must equal the clinic's country (`422 country_mismatch`); phones country-aware (E.164); optional `address.localized`; postal rule from the master |
| `GET/PATCH /clinics/current/settings` | `countryCode` read-only in GET; sending it in PATCH is `422` (unknown field); timezone must be a real IANA zone; currency/language/timezone must be allowed by the country policy (`not_overridable`, `unsupported`) |
| `POST/PATCH /branches` | `timezone` IANA-validated; address `countryCode` must equal the clinic's (`country_mismatch`); phone country-aware; `address.localized` (≤ 4 variants) |

## Platform administration

| Method & path | Permission | Purpose |
|---|---|---|
| `GET /platform/countries` | `platform.countries.read` | List with `configurationVersion`, `status`, `onboardingEnabled`, `isOnboardable`, `activeTenants`, `completenessWarnings[]`. A broken stored profile is listed as `{ invalid: true }` |
| `GET /platform/countries/{code}` | read | One country (full profile) |
| `POST /platform/countries/seed-baseline` | `platform.countries.manage` | Create India and UAE if absent (idempotent; never overwrites) |
| `POST /platform/countries` | manage | Create a country (always `disabled`, onboarding off, version 1). Body fields: `code,name,nativeName,callingCode,defaultCurrency,locales,defaultLocale,suggestedTimezones,adminAreaLabel,postalCode,policy,reviewedOn,sources` |
| `PATCH /platform/countries/{code}` | manage | Body: `expectedVersion` (required), `reason` (required), plus any of `status,onboardingEnabled,name,nativeName,locales,defaultLocale,suggestedTimezones,adminAreaLabel,postalCode,policy,reviewedOn,sources`. `code/callingCode/defaultCurrency` are immutable (422). Stale version → 409. Enabling onboarding needs `reviewedOn` and `sources` (`review_evidence_required`). Disabling a country with live clinics → 409 |
| `GET /platform/countries/backfill-report` | read | **Dry run**. `{ dryRun, alreadyAssigned, tenantsScanned, truncated, summary{verified,ambiguous,unmapped}, tenants[{tenantId,clinicName,status,classification,candidateCountry,reasons[]}] }` |
| `POST /platform/tenants/{id}/country` | `platform.countries.migrate` (super admin) | Body `{ countryCode, reason, confirm:true, expectedCurrent? }`. Idempotent for the same value; changing an existing value needs `expectedCurrent` equal to the stored one (else 409). Audited; writes `country_history` |
| `POST /platform/clinic-applications/{id}/approve` (changed) | review | Optional `countryCode` — required only when the application has none (legacy); mismatch with the application's own → 409; validated against the current master |

Role defaults: Super Admin has read/manage/migrate; Platform Support Admin has read only.

## Idempotency and concurrency
Seeding and assignment are idempotent; master edits use optimistic concurrency (`expectedVersion`); approval remains idempotent (a repeat never changes the stored country).
