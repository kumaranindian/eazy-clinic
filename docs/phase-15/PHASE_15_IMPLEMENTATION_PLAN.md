# Phase 15 – Tax, Invoicing & E-Invoicing Foundations: Implementation Plan

Branch `feature/phase-15-tax-invoicing` (stacked on Phase 14 → 13 → 12). Date: 2026-11-05. Spec: `EazyClinic_Phase_15_Implementation_Prompt.docx`.

> **Not tax or legal advice.** The product ships **no tax rates, thresholds or exemptions**. India GST and UAE VAT exist only as empty *policy shells*. A policy cannot be used on an invoice until a tax specialist has entered its rates and a platform user with the verify permission has recorded a verification. Nothing is filed, and no e-invoice is ever transmitted.

## 1. Pre-flight findings
| Area | Finding |
|---|---|
| Money | Integer minor units, half-up rounding, deterministic `calculateInvoice` (Phase 7); no floats |
| Tax today | Clinic-defined `tax_rules` (components in basis points, inclusive/exclusive); line snapshots store the components; rates are entered by clinics with no verification or effective dates |
| Numbering | Transaction-safe counter plus unique key documents (`INV-`, `CN-`, `DN-`); gapless per clinic |
| Adjustments | Credit/debit notes exist as lump amounts without a tax part |
| Reports | Finance reports (collections, outstanding, refunds, …) with CSV export audited |
| Missing | Verified, effective-dated policies; rounding modes; supply (intra/inter) and exemptions; seller/customer/numbering snapshot on the invoice; tax summary; e-invoice contract |

## 2. Delivered
* **Tax policy engine** (`backend/lib/features/billing/tax/tax_policy.dart`): effective-dated rate periods per component and supply, inclusive/exclusive mode, exemption and zero-rating, rounding mode, validation (no overlaps, 0-10000 bps, strict dates). Resolution **fails instead of guessing** (unverified, retired, other country, no rate in force, unknown exemption).
* **Platform policy service** (`tax_policy_service.dart`): versioned policies, verification by a tax specialist, **material edits void the verification**, stale verification refused, audit, baseline shells (`in-gst`, `ae-vat`, no rates).
* **Invoice integration:** a line may carry `taxPolicyKey` (+ `taxExemptionKey`, `supply`); rates are resolved on the invoice date in the clinic's time zone and frozen on the line (policy key, version, effective date, treatment, supply, rounding, tax type). Finalization is refused if the policy changed after the draft.
* **Invoice integrity:** `issueSnapshot` written once at finalization (seller legal name, trade name, tax registration number, country, branch; customer; currency and exponent; policies and versions; rounding; numbering policy; template version). New billing settings `legalName`, `taxRegistrationNumber`.
* **Credit/debit notes** carry an optional declared tax part (`taxIncludedMinor`, capped by the invoice's tax).
* **Rounding:** `Rounding` (half_up default, half_even, down) used for all tax divisions; stored on the invoice.
* **Tax summary report** `/finance/reports/tax` (JSON/CSV): taxable value, tax charged, credited, debited, net liability by period/branch/tax type/component, with revenue and cash collections shown separately; audited export.
* **E-invoice adapter contract** (`einvoice.dart`): provider interface, state machine, per-invoice submission record (attempt log with payload digest only), idempotency, retry cap, **live provider disabled**.
* ADRs 101–105; TD-116…TD-123.

## 3. Exclusions (per prompt)
Tax or legal advice; GST/VAT filing; live e-invoice submission; accounting-ledger replacement; payroll; foreign exchange; production tax migration. Also not delivered: a Clinic Web UI for policies/lines/tax report and PDF export of the tax report (TD-118, TD-119).

## 4. Test plan
Unit (rounding, calculation, resolution, validation, state machine, baseline), API (permissions, verification lifecycle, invoice resolution, snapshots, concurrency, notes, report, e-invoice disabled). Results: `TEST_REPORT.md`.
