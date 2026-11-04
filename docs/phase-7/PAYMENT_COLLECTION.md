# Payment Collection

`POST /billing/payments` (`payment.collect`, `Idempotency-Key` required).

Body: `patientId`, `branchId`, `amountMinor`, `method`, `reference`, `receivedAt` (within the last 31 days), `notes`, `allocations [{invoiceId, amountMinor}]` (≤ 20, distinct), `advance`.

Rules (all enforced in one transaction):
- Methods: cash, upi, card, bank_transfer, cheque plus clinic-configured names. UPI, card, bank transfer and cheque need the transaction `reference`. `online`/`razorpay` are rejected: payments here are **recorded by staff for money actually received**; the receiver is the authenticated user. A client-reported result is never proof of payment.
- Each allocation needs a finalized invoice of the same patient, in scope, with an outstanding balance, and cannot exceed it (409). Allocating needs `payment.allocate`.
- Any remainder must be an explicit `advance: true` and needs `payment.record_advance`; it becomes patient credit (see PATIENT_CREDIT_LEDGER.md). Otherwise 422.
- One payment can settle several invoices; several payments can settle one invoice; partial payments move the invoice to `partially_paid`, then `paid`.
- A numbered receipt (`RCT-…`) is created in the same transaction.
- Repeating the key with the same body returns the first payment (`idempotentReplay`); another body is 409; a missing key is 400. Racing duplicates create one payment (tested); racing different payments never overpay (tested).

`GET /billing/payments` (filters: patient, branch, method, date range, cursor paging) · `GET …/{id}` (allocations and refunds) · `GET /billing/invoices/{id}/payments` · `POST …/{id}/allocations` applies what is left of that payment's advance to invoices.

## Receipts
Created with the payment: number, clinic name/address/phone, branch, patient and MRN, invoice references with the balance after payment, amount, method, reference, receiver role, date, currency. `GET /billing/receipts/{id}` and `GET /billing/payments/{id}/receipt` read it again; reading never creates or changes a payment and is audited (`receipt.viewed`). The response adds the patient's current total outstanding. PDF is not generated (TD-57).

Daily collection summaries come from the reports (FINANCIAL_REPORTS.md).
