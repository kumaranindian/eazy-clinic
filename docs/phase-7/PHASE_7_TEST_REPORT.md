# Phase 7 Test Report (2026-11-04)

| Suite | Result |
|---|---|
| `scripts/check_all.sh` (format, analyze, every package) | pass, no issues |
| Backend `dart test` | 664 passed, 22 emulator-only skipped. Phase 7 added 114 (arithmetic 17, invoices and catalogue 30, payments and credit 24, refunds 18, expenses 15, reports and end-to-end flow 10) |
| `common_models` | 21 passed (7 new: financial permission policy) |
| Clinic Web widget tests | 116 passed (25 new: navigation by permission, dashboard, invoices, payment dialog, receipt, patient account, refunds, expenses, services, reports) |
| Doctor and patient apps | 15 and 7 passed (unchanged) |
| Firestore emulator, rules | 27 passed (1 new: invoices, payments, refunds, expenses, credit, audit and numbering paths and collection-group reads denied) |
| Firestore emulator, backend integration | 22 passed (1 new: invoice, payment with replay, advance and credit, refund, expense, dashboard and tenant isolation on the real store) |
| `flutter build web --release` clinic_web | OK |

## What the tests cover
- **Invoices:** draft creation and recalculation, catalogue pricing (doctor fee, branch price, default), client price/total fields rejected, inclusive and exclusive tax, exemptions, discounts and role limits, finalization, duplicate and racing finalization (one number), 6 concurrent finalizations (INV-000001…6), cancellation (reason, paid invoices refused, visit released), credit and debit notes, one open invoice per visit, overdue display status, snapshot unchanged after a price change.
- **Payments:** full, partial, multiple and multi-invoice payments; overpayment and unallocated remainder rejected; method and reference validation (online/razorpay refused); server-only fields rejected; permissions; cross-patient, draft and cross-tenant invoices refused; same-key replay, key reuse with another body, missing key, 5 racing duplicates (one payment), 5 racing different payments (never overpaid), 5 concurrent receipts (unique numbers); receipts re-read without creating payments.
- **Credit:** advance, application, duplicate application, insufficient credit, other patient's invoice, over-invoice application, ledger always equals the balance and the sum of remainders, adjustments (reason, permission, never below zero).
- **Refunds:** partial and full, excess rejected (including pending), approval authorization, requester cannot approve (policy can allow), reject, failed then retried and abandoned, completing twice and racing completions apply once, original payment preserved, advance refund through the ledger, racing requests hold the amount once.
- **Expenses:** lifecycle and history, immutability after approval, unauthorized approval, self-approval policy, role limits, validation, other clinics, branch isolation and clinic-wide records.
- **Reports:** dashboard and report figures match known data, windows, ranges and filters, CSV permission and formula neutralization, branch and tenant scoping, and an appointment → invoice → payment → refund → dashboard flow whose totals reconcile with the stored records.

## Defects found by the tests and fixed
1. A branch-scoped user could create a clinic-wide expense (the all-branch check ran only when `branchId` was sent).
2. A failed refund released its amount, so a second refund could be requested while the first was still retryable; failed refunds now hold their amount and can be abandoned by rejection.
3. In the dialog, free-text dropdown labels were humanized (`₹1180.00` became `₹1180 00`).

## Not run
Live Firebase, Android builds, browser-level tests, load tests, payment gateway tests (no gateway exists), PDF output (none). Concurrency is tested against the in-memory store with `Future.wait`; the emulator test is sequential, so uniqueness on the real store relies on the same transaction and uniqueness-key mechanism that the store contract suite verifies.
