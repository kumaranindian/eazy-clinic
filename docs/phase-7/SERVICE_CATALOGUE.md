# Service Catalogue

Collections: `service_catalogue`, `service_price_history`, `tax_rules`, `billing_settings/main`.

## Service
`serviceId`, `name`, `description`, `category` (consultation, follow_up_consultation, registration, procedure, diagnostic, laboratory, custom), `amountMinor`, `currency`, `taxRuleId`, `branchIds` (empty = all), `doctorIds` (empty = all), `branchPrices {branchId: minor}`, `doctorFees {doctorId: minor}` (consultation categories only), `effectiveFrom`, `status`, `version`, audit metadata.

- Create/edit/activate/deactivate: `service_catalogue.manage` (owner, admin). Everyone with `billing.view` can read.
- **Price resolution** (server): doctor fee, else branch price, else default. A service must be active, effective, and offered at the branch and by the doctor, or the line is refused (409).
- **History:** every create/update writes a `service_price_history` row (version, price, tax rule, status, reason, who, when); `GET …/price-history`.
- **Snapshots:** an invoice line copies description, category, unit price, tax rule name, rate components, inclusive flag and service version at the time the line is added. A later price or tax change never alters an existing line or any finalized invoice (tested).
- Catalogue lines cannot carry client prices, categories or tax rules (422).

## Tax rules
`name`, `components [{name, rateBps}]` (1–5, total ≤ 100%), `inclusive`. Only configuration: no rates ship, no compliance claim; the accountant validates them. Multiple components (for example CGST + SGST) and per-line exemption with a recorded reason are supported.

## Settings (`PUT /billing/settings`, `billing.settings.manage`)
`invoiceDueDays` (default 7), `customPaymentMethods` (built-in and gateway names cannot be redefined), `discountLimitsBps` per role (defaults: owner/admin 100%, accountant 10%, others none), `expenseApprovalLimits` per role, `allowSelfApproval` (default false).

Not built: the clinic option for *when* consultation charges are generated. Invoices are always created by staff, from an appointment, a consultation or manually; nothing is charged because an appointment was booked (TD-59).
