# Financial Architecture

## Principles
1. **The server calculates.** Clients send quantities, service ids and typed amounts for *payments received*; they never send totals, tax, balances, status, tenant, branch scope, receiver or timestamps. Bodies reject unknown fields.
2. **Integer minor units.** Every amount is an `int` in paise (`currencyExponent` per currency). No floating point exists in money code. The currency code is stored on every record; INR is the only supported currency today (clinic setting), nothing hardcodes the symbol.
3. **Immutable money records.** Finalized invoices, payments, allocations, receipts, refunds' original payments and ledger entries are never overwritten. Corrections are new records: credit/debit notes, refunds, ledger entries.
4. **Transactions.** Allocation, refund completion, numbering and ledger updates run in one transaction together with their audit entries.
5. **Idempotency.** Payment, advance, credit application, credit adjustment and refund requests require an `Idempotency-Key`. A repeat returns the first result (`idempotentReplay: true`); the same key with a different body is a 409.
6. **Separate entities.** Invoice, adjustment, payment, allocation, receipt, credit ledger entry, refund, expense, category, tax rule, service, price history and audit event are separate collections.

## Calculation (`billing_math.dart`)
Order per line: `gross = quantity × unit` → line discount (fixed, capped at gross, or percent in basis points) → invoice discount shared across lines in proportion to their net amounts (largest remainder, so shares sum exactly) → tax.
- **Exclusive tax:** each component = `round(base × rate / 10000)`; total = base + tax.
- **Inclusive tax:** `base = round(price × 10000 / (10000 + Σrate))`; tax = price − base; components split proportionally (remainder to the largest). The total stays the entered price.
- **Rounding:** half up on every division. Splits give the remainder to the largest part (ties: first), so parts always sum to the whole.
- Tax exemption (per line, reason required) removes tax. Rates are clinic configuration; no rate ships with the product and nothing here claims tax compliance. The clinic's accountant must validate the configuration.

## Balances
`adjustedTotal = grandTotal + debit notes − credit notes`; `outstanding = max(0, adjustedTotal − amountPaid)`. Refunds return money that was paid and do **not** re-open the debt. Status: `draft`, `finalized`, `partially_paid`, `paid`, `partially_refunded`, `refunded`, `cancelled`; `overdue` is derived at read time (`displayStatus`) for finalized/partially paid invoices past their due date with a balance.

### Invoice transitions
`draft → finalized` (finalize) · `draft|finalized(no payments) → cancelled` · `finalized → partially_paid → paid` by allocations · `paid → partially_refunded → refunded` by completed refunds · debit/credit notes recompute the balance (a debit on a paid invoice makes it `partially_paid`). No endpoint accepts a status.

## Numbering
`INV-`, `RCT-`, `CN-`, `DN-` + 6 digits from `counters/<name>` with a uniqueness key document, both written in the same transaction as the document, so concurrent requests cannot receive the same number. Tested with 5–6 racing requests. Numbers can have gaps only if a transaction aborts (no number is consumed then).

## Payment gateway boundary
`gateway.dart` defines `PaymentGateway` (order creation, signature verification, webhook verification) and `NotConfiguredGateway`, which answers 503. No gateway is approved or configured, so nothing simulates success and online/Razorpay methods are rejected (`method` validation). The interface documents the required behavior: backend-only secrets, amount taken from the invoice, signature and webhook verification over the raw body, duplicate-event protection, same transactional recording path, reconciliation.

## Decisions (ADR 054–060 in MASTER_ARCHITECTURE.md)
Integer paise and half-up rounding; embedded bounded invoice lines with a price/tax snapshot; offline-only payments with a gateway interface; append-only credit ledger with derived per-source remaining; refunds hold their amount until completed or abandoned; derived overdue and on-demand aggregation; counter-plus-key numbering.
