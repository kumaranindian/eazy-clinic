# Refund Workflow

Statuses: `requested → approved → processing → completed`, with `rejected` and `failed`. Allowed moves: requested → approved | rejected; approved → processing | completed | failed | rejected; processing → completed | failed; failed → processing | completed (retry) | rejected (abandon); completed is final.

## Request `POST /billing/refunds` (`refund.request`, Idempotency-Key)
`paymentId`, `invoiceId` (omit to refund an unapplied advance), `amountMinor`, `reason` (≥ 5). The payment must be completed and offline. **Eligible** = amount applied to that invoice by that payment (including credit applied from it) − refunds that hold amount (requested, approved, processing, failed, completed). Anything beyond is 409. A failed refund keeps holding its amount because it can be retried; rejecting it abandons it and releases the amount. Racing requests for the last amount: one wins (tested).

## Decide
`approve` / `reject` need `refund.approve` (owner, admin). The requester cannot approve their own refund unless the clinic sets `allowSelfApproval`. Reject needs a reason. Repeats replay.

## Complete `POST …/complete` (`refund.process`)
`outcome` completed | processing | failed, `method` (the actual method used), `reference` (required for non-cash completion), `failureReason`. The processor and method are recorded. Only on `completed`, in one transaction: the refund is completed; the invoice's `amountRefunded` and status are recomputed (partially_refunded, refunded); the payment's `refundedTotal` increases; an advance refund writes a `refund_out` ledger entry and lowers the balance. Completing again with the same method and reference is a replay; a different one is 409. Racing completions apply once (tested). Failed attempts stay in the refund's `history` and `attempts`.

## Guarantees
The original payment, its receipt and its allocations are never changed. Every request and decision is audited (`refund.requested|approved|rejected|processing|completed|failed`). Gateway refunds are refused until a gateway exists.
