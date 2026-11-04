# Expense Management

Collections: `expenses`, `expense_categories`.

- **Categories:** clinic-defined (none ship); create/edit needs `billing.settings.manage` (owner, admin); names unique; inactive categories take no new expenses.
- **Expense:** branch or clinic-wide (no branch needs all-branch access, also on create), category, description, `amount`, `expenseDate`, vendor/payee, optional method, `receiptReference`, `evidenceNote`, status, `history`, `rev`, creator, submitter, approver, payer.
- **Lifecycle:** draft → submitted → approved | rejected → paid. Create/edit (`expense.create`, `expense.edit`; own drafts, or an approver), submit (creator only), approve (`expense.approve`), reject (`expense.reject`, reason), pay (`expense.pay`, method). A rejected expense returns to draft when edited. Approved and paid expenses are immutable (409). Each step is idempotent and audited.
- **Policy:** the submitter or creator cannot approve unless `allowSelfApproval`; per-role approval limits (`expenseApprovalLimits`, absent = unlimited) refuse approval above the limit (403).
- **Reads:** list filters (status, category, branch, dates), detail with history; branch-scoped users see only their branches' expenses.
- **Reports:** by category, status and month (FINANCIAL_REPORTS.md).

Not built: uploading evidence files (a reference and note are stored; TD-60), payroll, vendor management, recurring expenses.
