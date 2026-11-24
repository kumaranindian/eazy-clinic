# API Contracts (Phase 15)

Standard envelope/errors. Platform routes under `/api/v1/platform`, clinic routes under `/api/v1`.

## Platform
| Method & path | Permission | Notes |
|---|---|---|
| `POST /tax/policies/seed-baseline` | `platform.tax.manage` | create-if-absent `in-gst`, `ae-vat` shells (no rates, unverified) |
| `GET /tax/policies?countryCode=` , `GET /tax/policies/{key}` , `GET …/{key}/versions` | `platform.tax.read` | Super Admin and Support Admin |
| `PATCH /tax/policies/{key}` | `platform.tax.manage` | `expectedVersion`, `reason` required; fields `title, mode, rounding, defaultSupply, components, exemptions, invoiceRequirements, source, status, taxType`; `409` stale; `422` invalid (overlapping periods, rate outside 0-10000, bad dates, missing source). A change to mode, rounding, supply default, components, exemptions, tax type or status **voids the verification** |
| `POST /tax/policies/{key}/verify` | `platform.tax.verify` | `{expectedVersion, decision: verify|withdraw, note}`; `409` if the version is stale or the policy has no rate |

## Clinic
| Method & path | Permission | Notes |
|---|---|---|
| `GET /billing/tax/policies` | `billing.view` | policies usable *today* for this clinic (verified, published, same country) with exemptions and the rate in force per component |
| `POST/PATCH /billing/invoices` lines | `billing.create/edit` | new line fields: `taxPolicyKey`, `taxExemptionKey`, `supply (any|intra|inter)`. `422` codes: `unverified`, `retired`, `wrong_country`, `no_rate`, `unknown_exemption`, `no_components`, `not_found`, `conflict` (policy together with a tax rule/exemption) |
| `POST /billing/invoices/{id}/finalize` | `billing.finalize` | `409` if a policy line's policy changed after the draft; response includes `issueSnapshot` |
| `PUT /billing/settings` | `billing.settings.manage` | new `legalName`, `taxRegistrationNumber` (5-30 letters/digits/space/hyphen, or null) |
| `POST /billing/invoices/{id}/adjustments` | `billing.adjust` | new optional `taxIncludedMinor` (≤ amount, ≤ invoice tax; `422`/`409`) |
| `GET /finance/reports/tax?from&to&branchId&groupBy=month&format=csv` | `finance.reports.view` | CSV needs `finance.reports.export`, audited |
| `GET /billing/invoices/{id}/e-invoice` | `billing.view` | `{submission: …|null}` |
| `POST /billing/invoices/{id}/e-invoice` | `billing.finalize` | `409` while no provider is enabled for the clinic's country (always, today) |
