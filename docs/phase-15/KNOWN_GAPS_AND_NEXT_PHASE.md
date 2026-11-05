# Known Gaps and Next Phase

| ID | Gap | Plan |
|---|---|---|
| TD-116 | **No tax content**: India GST and UAE VAT are shells; rates, thresholds, exemptions, place-of-supply rules and mandatory invoice fields must come from qualified local tax specialists | Release gate before any production invoice uses policies; sources are authority home pages, **not fetched** (2026-11-05) |
| TD-117 | Numbering: one `INV-` series per clinic; no per-branch/fiscal-year/country series, prefix configuration or gap policy; no draft-number reservation | Country rules first (Phase 19/22) |
| TD-118 | **No Clinic Web UI** for policies, invoice-line policy/exemption/supply selection, legal name/tax number, note tax part, tax report | Next UI pass; API is complete |
| TD-119 | Tax report has JSON/CSV only (no PDF); no filing-format export | PDF via existing report export pipeline |
| TD-120 | Refunds do not carry a tax part; liability changes only through credit/debit notes with a declared tax part (declared by the issuer, capped, not recomputed) | Compute note tax from invoice lines when countries' rules are known |
| TD-121 | Supply (intra/inter) is chosen per line by the biller; place-of-supply logic is not implemented | Country pack work |
| TD-122 | E-invoicing: contract and state machine only; no provider, no payload mapper, no signing, no cancellation window logic, no scheduler for retries (manual `POST` retry) | Requires country requirements, provider contract, credentials, certification, sandbox |
| TD-123 | Existing invoices have no `issueSnapshot`/policy fields; PDF/templates do not yet render the snapshot or country-specific fields; `branchAddress` is null when the branch has none | Template work |
| – | One rounding mode per invoice; line-level rounding variants refused | By design |
| – | Firestore index `invoice_adjustments(branchId, createdAt)` and rules tests not deployed/run | TD-95 |

## Release risks
Do not describe invoices as GST- or VAT-compliant. Do not enable policies for clinics until a specialist has supplied and a verifier has approved rates. Treat the verify permission as highly privileged.

## Next phase
**Phase 16 – International Payments.** It can reuse the policy/verification pattern, the invoice snapshot, the payment verification rules (Phase 7) and country configuration (Phase 12). Prerequisite: provider choices and per-country payment rules; foreign exchange stays out of scope.
