# Financial Dashboard and Reports

All figures are aggregated on the backend (`report_service.dart`) in clinic-local dates, within the caller's branch scope. Collections are **not** profit; no profit or accounting result is calculated.

## Metric definitions
| Metric | Definition |
|---|---|
| Collected | Completed payments received in the period |
| Refunded | Refunds completed in the period |
| Net collected | Collected − refunded |
| Invoiced | Adjusted totals of finalized, non-cancelled invoices dated in the period |
| Outstanding | Money still owed on finalized invoices now |
| Overdue | Outstanding on invoices past their due date |
| Expenses | Approved and paid expenses dated in the period (shown separately) |
| Doctor revenue | Consultation lines of invoices dated in the period, by the doctor on the line (billed, not collected) |

## Endpoints (`finance.reports.view`)
`GET /finance/dashboard`: today, last 7 days, month to date, outstanding and overdue, payment-method breakdown, branch-wise and doctor-wise, plus the definitions.
`GET /finance/reports/{collections|outstanding|refunds|expenses|branch-wise|doctor-wise}` with `from`, `to` (< 366 days), `branchId`, `method`, `status`, `groupBy=month` (collections). Outstanding includes ageing buckets. `format=csv` returns a CSV and needs `finance.reports.export`; cells starting with `= + - @` are prefixed with a quote against formula injection; the export is audited.

## Limits
Each report reads up to 5,000 documents per source per period and reports `truncated: true` beyond that (the UI asks to narrow the dates). There are no pre-aggregated counters (TD-61). Report rows are not paginated; lists elsewhere are. The Clinic Web screens show the six reports with a date range; the CSV is an API feature without a download button yet (TD-57).
