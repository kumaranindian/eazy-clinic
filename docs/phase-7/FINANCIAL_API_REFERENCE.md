# Financial API Reference

Base `/api/v1`, standard envelope. Every route requires authentication, a tenant derived from the caller's membership, the `billing` plan feature (403 otherwise), the permission shown, and branch scope. Money amounts are integers in minor units. `Idempotency-Key` (8–64 letters, digits, `-`, `_`) is required where marked **K**. Errors: 400 header/filter, 401, 403 permission/feature, 404 not found *or out of scope*, 409 state/limit/duplicate, 422 validation with `issues[]`. Bodies reject unknown fields.

| Method | Path | Permission |
|---|---|---|
| GET, PUT | /billing/settings | billing.view / billing.settings.manage |
| GET | /billing/gateway | billing.view (gateway status, accepted methods) |
| GET, POST, PATCH | /billing/tax-rules, /billing/tax-rules/{id} | billing.view / service_catalogue.manage |
| GET, POST, PATCH | /billing/services, /billing/services/{id} | billing.view / service_catalogue.manage |
| GET | /billing/services/{id}/price-history | billing.view |
| POST, GET | /billing/invoices | billing.create / billing.view |
| GET, PATCH | /billing/invoices/{id} | billing.view / billing.edit_draft |
| POST | /billing/invoices/{id}/finalize | billing.finalize |
| POST | /billing/invoices/{id}/cancel | billing.cancel |
| POST | /billing/invoices/{id}/adjustments | billing.adjust |
| GET | /billing/invoices/{id}/payments | payment.view |
| POST **K**, GET | /billing/payments | payment.collect / payment.view |
| GET | /billing/payments/{id} | payment.view |
| POST **K** | /billing/payments/{id}/allocations | payment.allocate |
| GET | /billing/payments/{id}/receipt, /billing/receipts/{id} | payment.view |
| POST **K** | /billing/patient-credits (`kind` advance or adjustment) | payment.record_advance / billing.adjust |
| POST **K** | /billing/patient-credits/{creditId}/allocations | payment.allocate |
| GET | /billing/patients/{id}/credits | payment.view |
| POST **K**, GET | /billing/refunds | refund.request / refund.request, approve, process or payment.view |
| GET | /billing/refunds/{id} | same |
| POST | /billing/refunds/{id}/approve, /reject | refund.approve |
| POST | /billing/refunds/{id}/complete | refund.process |
| GET, POST, PATCH | /expenses/categories, /expenses/categories/{id} | expense.view / billing.settings.manage |
| GET, POST | /expenses | expense.view / expense.create |
| GET, PATCH | /expenses/{id} | expense.view / expense.edit |
| POST | /expenses/{id}/submit | expense.create |
| POST | /expenses/{id}/approve, /reject | expense.approve / expense.reject |
| POST | /expenses/{id}/pay | expense.pay |
| GET | /finance/dashboard | finance.reports.view |
| GET | /finance/reports/{collections,outstanding,refunds,expenses,branch-wise,doctor-wise} (`format=csv`) | finance.reports.view (+ export for CSV) |

## Payloads (summary)
- **Invoice create:** `{patientId, branchId, appointmentId?, consultationId?, doctorId?, dueDate?, notes?, lines?, discount?}`; line `{serviceId, quantity}` (price and tax from the catalogue; `unitMinor`, `category`, `taxRuleId` refused) or `{description, unitMinor, quantity, category?, taxRuleId?}`; optional `discount {type: fixed|percent, value}` (percent in basis points), `taxExempt` + `taxExemptReason`.
- **Payment:** `{patientId, branchId, amountMinor, method, reference?, receivedAt?, notes?, allocations?, advance?}`.
- **Credit application:** `{allocations: [{invoiceId, amountMinor}]}`. **Adjustment:** `{kind: "adjustment", patientId, branchId, direction, amountMinor, reason, creditId?}`.
- **Refund request:** `{paymentId, invoiceId?, amountMinor, reason}`; **complete:** `{outcome, method, reference?, notes?, failureReason?}`.
- **Expense:** `{branchId?, categoryId, description, amountMinor, expenseDate, vendor?, method?, receiptReference?, evidenceNote?}`; edits take `expectedRev`.

Replays return the original resource with `idempotentReplay: true`. Not provided: PDF endpoints, gateway order/verification/webhook endpoints, patient-facing billing endpoints.
