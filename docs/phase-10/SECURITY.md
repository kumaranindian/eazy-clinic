# Notification and reporting security

| Control | How |
|---|---|
| Authentication and tenant | Every route is behind `m.secured` (token verified, membership from server records). The tenant never comes from the request. |
| Own data only | Inbox, read, archive, preferences and devices are keyed by the caller's uid; someone else's id is 404. |
| Device tokens | Owner is always the authenticated caller; only the owner can remove; tokens are stored in a backend-only collection, never returned, never logged. A provider "invalid token" answer deactivates the device. Registration is rate limited. |
| Recipient resolution | From `patients.patientAccountId` and `members`; events cannot name an address, phone or arbitrary account for a clinic user. A patient who has not linked an account is simply not notified. |
| Another patient's data | A message goes to the account linked to that patient record only (tests: a second patient's account receives nothing). A guardian is not copied. |
| Preferences and consent | Re-read at dispatch; promotional categories need explicit opt-in; essential messages keep the in-app entry. |
| Stale messages | Reminders are re-checked against the live appointment or follow-up at processing and again at dispatch. |
| Content | Push and in-app text is fixed or template-rendered from a variable allow-list with nothing clinical; the lab rejection reason, follow-up reason and instructions are never sent. Delivery records hold generic text only; the administration list hides even that. |
| Template safety | Single-pass `{{name}}` substitution, unknown names rejected on save, values cleaned of control characters and braces, HTML-escaped for email. |
| Administration | Templates, deliveries, retry, pause/resume, settings and health need `notifications.manage`; the platform has no route into clinic notification data. |
| Deep links | A notification names a resource, nothing more. The screen and API check access again (tests: receptionist and another doctor are refused the report a notification points to). |
| Reports | Plan feature + `reports.view` + the module's own permission; branch scope on every query; doctors limited to their own work; filters validated (dates, range, branch); no clinical content. |
| Exports | Same checks as the screen, re-run server-side; size and row limits; private storage; requester-only download for 6 hours; `no-store`, `nosniff`; audited with filters, not data; creation rate limited; CSV neutralises `=`, `+`, `-`, `@`, tab and carriage-return cells. |
| Logging | Structured logs carry ids and error codes; provider responses are reduced to a code; no token, address or message body is logged. |

## Residual risks
No malware or content scanning of anything; exports are not signed; an export file lives until storage lifecycle removes it (TD-88); push reliability depends on FCM; the in-process worker stops if the instance does.
