# Phase 7 Assessment: Billing, Payments, Refunds and Expenses

Written before implementation (2026-11-04) from inspection of `develop` at `036a339` (Phases 0–6 merged).

## Branch note
The Phase 7 prompt says to continue on `feature/phase-0-foundation`. That branch was already merged to `develop` (PR #3), and the project owner created `feature/phase-7-implementation` from `develop` immediately before attaching the prompt. Work therefore continues on `feature/phase-7-implementation`. Nothing was pushed or merged.

## Existing financial functionality
| Area | Finding |
|---|---|
| Clinic billing, invoices, payments, expenses | **None.** No collection, route or screen existed. |
| SaaS subscription billing (platform) | Exists (`platform_subscriptions`, plans). **Out of scope** and untouched: it bills clinics, not patients. |
| Razorpay | No integration, configuration or secrets anywhere in the repository. |
| `FeatureKey.billing` | Existed as a plan feature; unused. Phase 7 uses it to gate every billing route. |
| Clinic `currency` setting | Existed (`clinic_settings/operations.currency`, only `INR` supported). Used as the clinic currency. |
| Patient, appointment, consultation | Complete from Phases 4–6; billing links to them by id only. |
| PDF generation | No dependency or implementation. |

## Reusable components
Tenant/branch context and RBAC (`TenantContext`, `ClinicRolePolicy`), `BodyReader` validation, cursor paging, transactional `DocumentStore` and its in-memory twin, numbering by counter + uniqueness key (as for prescriptions), idempotency pattern (as for appointments), audit pattern, `ClinicZone` for clinic-local dates, design system, `ListScreen`, `RowCard`, `showRecordDialog`, `runAction` in Clinic Web.

## Gaps
- Permissions: none for money. Added 24 (see FINANCIAL_RBAC.md).
- Data model and APIs: all new (FINANCIAL_DATA_SCHEMA.md, FINANCIAL_API_REFERENCE.md).
- Security: money paths need transactional, idempotent, audited writes and immutable records; rules deny all client access to the new collections.
- Dependencies: no dependency was added. PDF output and a payment gateway are not available (see Known limitations).

## Decisions needed and taken
- Payments are **offline only** (staff record money received). No simulated gateway success.
- The accountant does not get `patients.view` (a Phase 4 test and decision); billing resolves patients server-side.
- Refunds do not re-open an invoice's debt; a debit note does.

## Out of scope (not built)
Payroll, general ledger, tax filing or GST returns, pharmacy inventory, insurance, ABDM, SaaS subscription billing, production Razorpay credentials, AI financial decisions, patient-facing billing screens (Phase 8).
