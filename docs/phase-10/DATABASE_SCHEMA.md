# Phase 10 data

All under `tenants/{tenantId}/` unless noted. Written only by the backend; Firestore and Storage rules still deny every client (rules tests cover each collection).

| Collection | Id | Purpose / key fields |
|---|---|---|
| `notification_events` | `ev_<hash of dedupe key>` | `type`, `dedupeKey`, `branchId`, `patientId`/`accountId`/`staffDoctorId`/`staffUid`, `resourceType/Id`, `variables` (non-clinical strings), `data` (reminder match values), fallback text, `status` (`pending`, `processing`, `processed`, `suppressed`), `leaseUntil`, `attempts`, `suppressedReason` |
| `notification_deliveries` | `dl_<hash>` | `eventId`, `type`, `channel`, `recipientType`, `recipientRef`, rendered `title`/`body` (generic text), `templateRef`, `templateVersion`, `status`, `attempts`, `nextAttemptAt`, `providerMessageId`, `error` (code only), `manualRetries` |
| `notifications` | `n_<hash>` | staff inbox entry: `recipientUid`, `category`, `title`, `body`, `resourceType/Id`, `read`, `archived` |
| `notification_templates` | `tpl_<hash of event/channel/locale>` | clinic template: `eventType`, `channel`, `locale`, `subject`, `body`, `version`, `active` |
| `notification_template_versions` | `{templateId}_v{n}` | previous versions |
| `notification_preferences` | uid | staff: `pushEnabled`, `channels`, `categories` |
| `notification_settings` | `main` | `channels`, `reminderLeadMinutes`, `followupLeadDays`, `locale` |
| `notification_channel_configs` | channel | `paused`, `updatedBy` (no secrets) |
| `notification_audit_logs` | auto | template, preference, device, retry, pause/resume and settings actions: ids and reasons only |
| `report_exports` | `rx_...` | job and file record: `report`, `format`, `filters`, `status` (`processing`, `ready`, `failed`), `rows`, `sizeBytes`, `sha256`, `storagePath`, `requestedBy`, `expiresAt` |
| `report_audit_logs` | auto | `report.export_requested`, `_ready`, `_failed`, `_downloaded` with filters and counts |

Top-level: `notification_devices/{dev_<hash of token>}`: `uid`, `tenantId`, `deviceId`, `token` (never returned), `tokenHash`, `platform`, `active`. Existing and extended: `patient_notifications` gains `archived`, `archivedAt`; `patient_devices` and `patient_notification_preferences` are reused.

Object storage: `{tenantId}/report_exports/{id}.csv|pdf`, private.

Prompt model items **not** created as separate collections: `notification_schedules` (reminders are derived by the worker and made unique by dedupe keys, ADR 080) and `report_jobs` (the export record is the job; generation is synchronous within limits, TD-88).

## Indexes
20 composite indexes added to `firebase/firestore.indexes.json` for the staff inbox, delivery queue and administration lists, export history, and the report queries (appointments, queues, patients, consultations, lab orders and samples, invoices, payments, refunds). **Not deployed.**
