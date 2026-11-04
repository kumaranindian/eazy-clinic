# Financial Data Schema (under `tenants/{tenantId}/`)

Clients have **no** access to any of these (rules deny; collection-group reads denied; tested). Every amount is an integer in minor units with a `currency` code. `createdAt`/`updatedAt` are server timestamps.

| Collection | Key | Purpose |
|---|---|---|
| `billing_settings` | `main` | due days, custom methods, discount and expense limits, self-approval policy |
| `tax_rules` | `tx_…` | named tax configuration (components, inclusive) |
| `service_catalogue` | `svc_…` | services/charges, version |
| `service_price_history` | auto | one row per service change |
| `invoices` | `inv_…` | invoice with bounded `lines` (≤ 50, snapshot), totals, balance, status, `rev`, source ids |
| `invoice_numbers` | `INV-000001` | uniqueness key → invoice |
| `invoice_sources` | `appointment_<id>` / `consultation_<id>` | one open invoice per visit |
| `invoice_adjustments` | `adj_…` | immutable credit/debit notes (`CN-`/`DN-` numbers) |
| `payments` | `pay_…` | immutable payment (method, reference, receiver, allocated and advance amounts, receipt) |
| `payment_allocations` | `{paymentId}_{invoiceId}` or `al_…` | amount applied to an invoice (`source`: payment or credit) |
| `receipts` | `rct_…` | immutable receipt snapshot (clinic, patient, invoices, amounts) |
| `patient_credit_ledger` | `cr_<paymentId>` / `le_…` | append-only credit entries |
| `patient_credit_balances` | patientId | derived balance cache |
| `refunds` | `rf_…` | refund with `history`, attempts, decisions |
| `expense_categories` | `ecat_…` | clinic categories |
| `expenses` | `exp_…` | expense with `history`, `rev` |
| `counters` | `invoice_number`, `receipt_number`, `credit_note_number`, `debit_note_number` | sequence counters |
| `receipt_numbers`, `credit_note_numbers`, `debit_note_numbers` | number | uniqueness keys |
| `billing_idempotency` | hash of user, scope, key | `fingerprint` of the body and the resulting resource |
| `financial_audit_logs` | auto | append-only audit: action, actor, role, amount, reason, ids (no clinical text) |

Notes: invoice lines are embedded (bounded) so an invoice and its price/tax snapshot change atomically; there is no separate line collection (ADR 055). Mutable fields on otherwise immutable documents are limited to derived balances (`invoices.amountPaid|amountRefunded|outstanding|status|rev`, `payments.refundedTotal`, `patient_credit_balances.balance`) and the workflow fields of refunds and expenses. Indexes: 22 composite indexes added to `firebase/firestore.indexes.json` (114 total), not deployed (TD-61).

Relationships: invoice → patient, branch, optional appointment/consultation/doctor; allocation → payment, invoice, optional source credit; refund → payment (+ invoice); ledger entry → patient, optional payment/invoice/allocation, `creditId` for consuming entries; expense → category, optional branch.
