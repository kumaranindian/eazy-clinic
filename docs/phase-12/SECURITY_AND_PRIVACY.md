# Security and Privacy (Phase 12)

| Requirement | Implementation | Evidence |
|---|---|---|
| Never trust client `countryCode`, tenant, role, tax profile, provider status or region | The applicant's code is validated against the master and then stored by the server on the tenant. After provisioning no tenant API accepts it. Platform routes require platform permissions derived server-side | `country_test.dart` ("spoofed…", "cannot smuggle", "settings and profile cannot set…") |
| Country spoofing rejected | `ZZ`, malformed and lower-case codes are rejected; paused/disabled countries rejected; branch/clinic addresses with another country → `country_mismatch` | tests above |
| No inference from phone, IP, browser, device | The phone is validated *for* the chosen country; a UAE number with country IN is invalid, never "re-detected". Backfill classification uses only what the applicant explicitly entered and only cross-checks it | "the phone number never decides the country" |
| Fail closed | Missing/invalid/disabled profile → 503 for tenant resolution; invalid stored profiles are hidden from onboarding and flagged for admins | "fails closed", "corrupted stored profile" |
| Immutability | Tenant `countryCode` has no tenant-facing write path. Change = platform migration with reason, `confirm`, current-value check, history record and audit | migration tests |
| No partial provisioning | Country is validated inside the approval transaction before any write | "country disabled after submission: approval fails atomically" |
| Tenant isolation | Resolver and settings use the caller's server-resolved tenant; `x-tenant-id` selector is checked against membership; branch ids must be in the caller's scope | "another clinic's owner cannot…" ; existing cross-tenant suites still pass |
| Least privilege | Three new permissions; support admin read-only; allow-list updated in the route-auth sweep (`/countries` self-service; `country-config` for members) | `route_auth_test.dart` |
| Audit | `country.seeded/created/updated`, `tenant.country_assigned` with actor, reason, versions | audit tests |
| Rules | Firestore/Storage remain deny-all; new paths added to the rules test list | (emulator test not run here) |
| Secrets | None added. `DEPLOYMENT_REGION` is non-secret | — |
| Sensitive data in logs | No new logging of request bodies. Country admin audit stores field *names* and versions, not clinical data | — |
| Privacy | Country is an organisation attribute (no patient data). The backfill report exposes clinic names to platform roles that can already read tenants. Phone numbers moved to E.164 are the same data, normalised | — |

## Open security notes
- Migration of a clinic's country can change which currency/phone/postal rules apply to *future* writes; existing stored values are not rewritten (see MIGRATION_AND_ROLLBACK).
- Per-instance 60 s cache means a just-disabled country can still be served by other instances for up to 60 s (TD-97). Onboarding/provisioning are unaffected (fresh reads).
- No regulatory compliance is claimed. Country metadata cites standards bodies only (see KNOWN_GAPS).
