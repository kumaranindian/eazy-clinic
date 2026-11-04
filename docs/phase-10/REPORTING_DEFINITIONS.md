# Reporting definitions

Common rules: dates are clinic-local calendar dates in the clinic's time zone (default Asia/Kolkata), inclusive at both ends; timestamps are converted with the same zone; default period is the current month to today; at most 366 days; the caller's branch scope always applies (a branch outside it is 404); at most 5,000 records are read per query, and `truncated: true` says figures are incomplete; a rate with a zero denominator is `null`, shown as "Not enough data". Each report returns summary, table, definitions, notes, `generatedAt`.

Access: the plan needs `reports` (and `laboratory` / `billing` for those sections); the caller needs `reports.view` plus the module permission shown. Doctors are limited to their own appointments, queues and consultations and cannot request the patients report.

| Report | Permission | Figures |
|---|---|---|
| appointments | `appointments.view` | **total**: appointments with a visit date in range, excluding status `rescheduled` (a moved visit counts once, at its new slot); by status and date; `rescheduledAway`; `noShowRate` = no-show / (completed + no-show); `cancellationRate` = cancelled / total; by doctor; by source |
| queues | `queue.view` | tokens by queue date; completed, skipped, no-show, cancelled; **wait minutes** = called time minus check-in time, only for tokens with both (`measured` of `of`); peak hours = clinic-local hours with most check-ins |
| patients | `patients.view` (not doctors) | registrations by day; `activePatients` = status active today; new vs returning among distinct patients with a completed visit in range (new = record created in range); gender and age-band counts of registrations |
| consultations | `consultations.view` (own work, or `view_all`) | counts by day, status and doctor; no clinical content |
| laboratory | `lab.dashboard.view` | orders created; open orders now; reports first published in range; rejected samples; turnaround hours = publication minus creation for orders published in range (`measured` shown) |
| billing | `finance.reports.view` | **grossBilled** = adjusted totals of invoices dated in range, excluding drafts and cancelled; **collected** = payments received in range by received date; **refunded** = completed refunds by completion date; **netCollected** = collected - refunded; **outstandingOnInvoicesInRange** = amount still unpaid today on those invoices. All in paise. They are separate measures, never added, and none is profit. |

Dashboard (`GET /reports/dashboard`): the same figures as headline tiles per section, "not permitted" for sections the caller cannot see, one trend (appointments per day) when there are at least two days, and the time it was computed. It does not draw charts.

Not supported because the data is not reliable or not stored: profit, expenses in these reports, clinical outcomes, waiting time for tokens without timestamps, per-doctor waiting time.
