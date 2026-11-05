# Incident response, monitoring and alerts

Owners, rotas and contact details are **placeholders to be assigned by the business**; nothing here names a person.

## Severity
| Level | Meaning | Examples | Response target (proposed) |
|---|---|---|---|
| SEV1 | Patient safety, data exposure, loss or corruption; full outage | tenant isolation failure, leaked secret, wrong prescription shown, database unavailable | start at once, 24x7 |
| SEV2 | Major function down or degraded for many clinics | booking or payments failing, reports not publishing | within 1 hour in service hours |
| SEV3 | Single clinic or minor function | one clinic's reminders failing | next business day |

## Roles
Incident commander (decides, communicates), technical lead (diagnoses), security lead (any SEV1 involving data), clinic communications owner, scribe. Customers hear from one voice.

## Steps
1. Detect (alert, clinic report, audit anomaly). 2. Triage severity and open an incident record with a timeline. 3. Contain: pause channels or features, revoke sessions (`POST /auth/revoke-sessions` for a user; platform suspension for a clinic), rotate exposed secrets. 4. Eradicate and recover (`ROLLBACK_AND_RECOVERY.md`). 5. Communicate. 6. Review within 5 working days with actions tracked in `KNOWN_ISSUES_AND_RISKS.md`.

## Personal-data incidents
Treat any suspected exposure of patient data as SEV1. Preserve logs and audit records (per-module audit logs, `report_audit_logs`, `notification_audit_logs`, patient audit trail). Decide notification duties to the regulator and affected people **with qualified legal advice**, under the Digital Personal Data Protection Act 2023 and its rules as applicable; this repository makes no legal claim. Customers (clinics) are the data fiduciaries for their patients in the usual SaaS model: agree the contractual notification timeline with them.

## What can be monitored today
| Signal | Source |
|---|---|
| API errors and latency | request log lines (`request` at ERROR for 5xx, `request_slow` at WARNING at 2 s) with request ids |
| Liveness / readiness | `GET /health`, `GET /ready` (503 until the data store answers) |
| Notification backlog and failures | `GET /admin/notification-health` (per clinic); delivery statuses |
| Worker failures | log event `notification_worker_failed` |
| Authentication anomalies | security-event records and rate-limit rejections (HTTP 429 in logs) |
| Storage/Firestore errors | surface as 5xx and `StoreException`, plus cloud provider metrics |

## Proposed alerts (thresholds to be agreed; none is configured)
5xx rate over 1% for 5 min (SEV2); p95 latency over 1 s for 10 min; `/ready` failing for 2 min (SEV1); `notification_worker_failed` more than 3 in 15 min; retry backlog growing for 30 min; permanently failed deliveries above a clinic-specific rate; a spike of 401/403 from one client; any export or document download volume anomaly.

## Gaps
No error-monitoring or crash-reporting service is integrated (deliberately: privacy review first); no dashboards or alert rules exist; no on-call rota exists; no payment webhook monitoring exists because no gateway is connected.
