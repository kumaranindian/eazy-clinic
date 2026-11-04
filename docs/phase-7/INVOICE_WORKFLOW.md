# Invoice Workflow

1. **Create draft** `POST /billing/invoices` (`billing.create`): patient and branch in the caller's scope, optional `appointmentId` / `consultationId` (checked against the same patient and branch; no clinical content is read), `dueDate`, `lines`, `discount`. One open invoice per appointment or consultation (409 with the existing id); cancelling releases it. The doctor comes from the visit when linked.
2. **Edit draft** `PATCH …/{id}` (`billing.edit_draft`): replace `lines` (max 50), set/clear `discount`, `dueDate`, `notes`, with `expectedRev` for optimistic concurrency. The server recalculates and returns the totals.
3. **Discounts** (`billing.apply_discount`): fixed or percent, per line or invoice. The effective percentage of the subtotal must stay within the role's limit from settings, else 403.
4. **Finalize** `POST …/finalize` (`billing.finalize`): needs at least one line; recalculates from stored snapshots, assigns `INV-000001…`, sets `outstanding`. Idempotent: a repeat or a race returns the same invoice with `idempotentReplay` (one number, one audit entry).
5. **Cancel** `POST …/cancel` (`billing.cancel`): reason required (≥ 5 characters); refused when any payment was applied; releases the visit; idempotent.
6. **Adjust** `POST …/adjustments` (`billing.adjust`): `credit` or `debit`, amount, reason; numbered `CN-`/`DN-`. A credit note cannot exceed the outstanding balance (paid money is returned by refund). The original totals are never changed; `adjustedTotal` and `outstanding` are.
7. **Read** `GET …/{id}` returns lines, adjustments, allocations; lists filter by status (including derived `overdue`), patient, branch, date, and exact invoice number.

Finalized invoices cannot be edited (409). Not built: PDF download (TD-57); the invoice screen is the printable layout. Automatic charge generation (TD-59).
