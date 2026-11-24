# Architecture and Data Model

## Tax policy (`tax_policies/{key}`, platform level)
`key, title, countryCode, taxType (GST|VAT|…), mode (inclusive|exclusive), rounding (half_up|half_even|down), defaultSupply (any|intra|inter), status (published|retired), components[{name, supply, rates[{effectiveFrom, effectiveTo?, rateBps}]}], exemptions[{key,label,treatment exempt|zero_rated}], invoiceRequirements[], source{reference,note,fetched,draftedOn}, verification{status unverified|verified, by, at, reviewerNote, verifiedVersion}, version, createdAt, updatedAt, updatedBy`. Every version is copied to `tax_policies/{key}/versions/{n}` with its `reason`.

**Usable** = published AND verified AND same country as the clinic AND a rate in force on the invoice date for every applicable component.

Supply: components with `supply: any` always apply; `intra`/`inter` components apply when the line (or the policy default) names that supply. (India: CGST+SGST intra, IGST inter. UAE: a single `any` VAT component.)

Treatments: `exempt` → no components, no tax. `zero_rated` → components at 0 bps (the tax lines are visible on the invoice at zero).

## Invoice line (additions)
`taxPolicyKey, taxPolicyVersion, taxEffectiveOn, taxTreatment, taxSupply, taxRounding, taxType, taxExemptionKey` in addition to the existing `taxComponents`, `taxInclusive`, `taxParts`. A line uses either a policy **or** a clinic tax rule/manual exemption, never both.

## Invoice (additions)
`issueSnapshot{version, seller{legalName, tradeName, taxRegistrationNumber, countryCode, branchName, branchAddress}, customer{name, recordNumber}, currency, currencyExponent, taxPolicies{key→version}, taxRounding, numbering{counter,prefix,width,scope}, templateVersion}`, written once in the finalization transaction and never updated. All other invoice figures were already immutable after finalization; corrections are credit/debit notes.

## Adjustments (additions)
`taxIncluded` (minor units): how much of the note is tax. Credit notes reduce tax liability by it; debit notes increase it. Capped by the invoice's tax total.

## Calculation (unchanged order, new rounding parameter)
line gross → line discount → share of invoice discount (largest remainder) → tax on the remainder:
* exclusive: each component `percentOf(base, bps, rounding)`; total = base + Σ components;
* inclusive: `base = divRound(after×10000, 10000+Σbps, rounding)`; tax = after − base; the tax is split across components by largest remainder so parts always add up.
Integers only. A single invoice uses one rounding mode (lines with different modes are refused).

## Numbering
Counter document per clinic inside the finalization transaction + a unique key document per number. Concurrency test: 8 simultaneous finalizations yield INV-000001…000008 with no gaps or duplicates. Number series per country/branch/fiscal year and prefix configuration are **not** built (TD-117).

## E-invoice (`tenants/{t}/einvoice_submissions/{invoiceId}`)
`status (queued|submitted|accepted|rejected|failed|cancelled), idempotencyKey, attempts[{at, from, outcome, providerReference, errorCode, payloadSha256}], createdAt/updatedAt/By`. Accepted, rejected and cancelled are final; failed may retry up to 5 attempts. The payload is never stored or logged, only its SHA-256. `EInvoiceProvider` (`enabledFor(country)`, `submit(request)`) is the only integration point; the shipped `NotConfiguredEInvoiceProvider` is disabled for every country, so `POST …/e-invoice` returns 409.

## Tax summary (`GET /finance/reports/tax`)
Rows per `period|branch|taxType|component`. Definitions: **taxable value** (net of discounts, excluding tax); **tax charged** (invoices dated in the range); **tax credited/debited** (declared on notes created in the range); **net tax liability** = charged − credited + debited; **collected** = payments received (cash basis) — reported separately because tax is due on the invoice, not on payment; **revenue** = taxable value. Cancelled and draft invoices excluded. The report is a review aid, not a return.
