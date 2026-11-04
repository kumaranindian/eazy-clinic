# Patient Credit Ledger

Advance payments become credit that can be applied to invoices later.

## Entries (`patient_credit_ledger`, append-only)
| type | direction | created by |
|---|---|---|
| `advance_in` | in | payment with an advance remainder (id `cr_<paymentId>`) |
| `adjustment_in` | in | reasoned adjustment (`billing.adjust`) |
| `applied` | out | credit applied to an invoice (links source credit, allocation and invoice) |
| `refund_out` | out | completed refund of an unapplied advance |
| `adjustment_out` | out | reasoned adjustment that reduces a named credit |

Each entry records `amount`, `balanceAfter`, `currency`, who and when. `patient_credit_balances/{patientId}` holds the current balance as a **derived cache** written in the same transaction as the entry; the ledger is the truth. A balance is never overwritten on its own.

## Rules
- Per-source remaining = entry amount − outstanding "out" entries that reference it. Applying more than the remaining is 409; the sum of remainings always equals the balance (tested).
- Apply: `POST /billing/patient-credits/{creditId}/allocations` (`payment.allocate`, Idempotency-Key) or `POST /billing/payments/{id}/allocations`. Each application also creates a payment allocation on the invoice, which cannot exceed the invoice's balance, and must be the same patient (404 otherwise).
- Duplicate application: the same key replays; a new key is checked against the remaining amount, so the credit can never be used twice.
- No negative balance: any out entry that would take the balance below zero is 409.
- Adjustments: `POST /billing/patient-credits {kind: "adjustment"}` needs `billing.adjust`, a reason ≥ 5 characters; a reduction must name the credit it consumes.
- Advance: `POST /billing/patient-credits {kind: "advance"}` (`payment.record_advance`) is a payment with no allocations and a receipt.
- View: `GET /billing/patients/{id}/credits` returns the balance, sources with remaining, and the ledger.

Cash refunds of credit are handled by the refund workflow (REFUND_WORKFLOW.md).
