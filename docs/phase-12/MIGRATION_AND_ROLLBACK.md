# Migration and Rollback

Nothing in this phase migrates or deploys production data. Everything is additive.

## 1. What changes in stored data

| Collection | Change | Backward compatible? |
|---|---|---|
| `countries/**` | New (created by the seed action) | Yes |
| `tenants/{id}` | New optional fields (`countryCode` …) | Yes: absent = legacy behaviour |
| `clinic_applications/{id}` | New `address.countryCode`, `countryConfigVersion` | Yes: old applications still readable |
| Branch / profile / settings | New optional fields; existing values untouched | Yes |

No existing document is rewritten. Existing phone numbers remain in their stored form; only new writes by clinics **with a country** are normalised to E.164.

## 2. Rollout order (per environment, when approved)
1. Deploy `firestore.indexes.json` (adds `countries(onboardingEnabled, code)`); wait until built.
2. Deploy the backend and apps.
3. Platform admin runs **Seed India and UAE** (idempotent).
4. Review the **backfill report** (read-only).
5. For each existing tenant, a super admin assigns the country (`POST /platform/tenants/{id}/country`) — or leaves it unassigned (legacy behaviour continues).
6. Open in-flight applications: approval requires `countryCode` (supplied by the admin or by the applicant through "respond").

## 3. Backfill report semantics (dry run)
`verified`: the applicant's own country entry maps to exactly one known country **and** postal code and both phone numbers are consistent with it.
`ambiguous`: a candidate exists but evidence conflicts (or several countries match).
`unmapped`: no application record, no country entered, or unrecognised text.
The report never writes, and nothing is applied in bulk: each assignment is an individual audited admin action. (A tenant is never classified from IP, browser locale, device time zone or phone prefix alone.)

## 4. Rollback
| Situation | Action |
|---|---|
| Wrong country assigned | `POST /platform/tenants/{id}/country` with the right code and `expectedCurrent` (history is kept) |
| Bad master edit | `PATCH` back to previous values (each version is snapshotted in `countries/{code}/versions/{n}`); onboarding can be paused instantly |
| Backend regression | Redeploy the previous backend. New fields are ignored by the old code; applications created without `countryCode` by old clients are blocked at approval until a code is supplied |
| Remove the feature | Stop using the endpoints; stored `countries/**` and tenant fields are inert. No data deletion is required (and none is performed) |

## 5. Known migration caveats
- Applications created by pre-Phase-12 clients (no `countryCode`) are rejected at submission; open ones need a code at approval.
- Changing a clinic's country does not convert currency, phone formats, or stored amounts (no FX; out of scope).
- Production Firebase, data and deployment were not touched.
