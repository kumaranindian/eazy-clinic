# Patient Billing

Read-only view of Phase 7 data for the patient's linked record (or a family member with `view_records`).

- `GET /patient/invoices` (drafts hidden), `/clinics/{c}/invoices/{i}` (lines, totals, payments applied, `onlinePayment: {available: false}`), `/payments` (amount, method, reference, receipt number, refunded), `/clinics/{c}/receipts/{r}`, `/refunds` (status and amount only), `/billing-summary` (amount due and advance credit per clinic).
- Hidden from patients: staff ids, notes, internal history, other patients' data, expenses, services, reports and every staff route (403).
- Matching by linked patient id: a different patient's invoice, receipt or refund id answers 404 (tested).
- **No online payment:** no gateway is configured (TD-58). The invoice screen says to pay at the clinic and the app has no *Pay* button, so it can never show a payment that was not received. If a gateway is approved later, orders and verification stay on the backend.
- **PDF:** invoices and receipts are on-screen previews; PDF download is not built (TD-57).
- Generic notifications for new invoices, payments and refund changes; no amounts in the text.
