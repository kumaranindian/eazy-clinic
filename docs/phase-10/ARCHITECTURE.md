# Notification and reporting architecture

```
 business action (booking, payment, report publication, ...)
        |  PortalNotifier.publish / notifyDoctor / scheduling.onEvent
        v
 NotificationHub.emit  ->  tenants/{t}/notification_events   (status: pending)
        |
 processEvent (lease claim, transaction)
        |-- staleReason(): reminders re-checked against the live appointment / follow-up
        |-- recipients: patient account (from the patient record) / staff (members)
        |-- preferences + clinic channel list + templates
        v
 deliveries (deterministic ids) + in-app inbox entries   -> event: processed   (one write)
        |
 dispatch (claim, re-validate, pause check) -> adapter
        |-- in_app: delivered      |-- push: FcmSender -> sent / retry_scheduled / permanently_failed
        |-- email/sms/whatsapp: MessageProvider or configuration_required
```

## Decisions (ADR 074-082)
| # | Decision |
|---|---|
| 074 | One `NotificationHub` per backend; existing modules reach it through `PortalNotifier` and the scheduling `onEvent` hook, so no business logic was duplicated and no module calls a provider. |
| 075 | An event's `type` is the notification category (`appointment_reminder`, `report_available`, ...). The spec's event names map onto categories (table in `EVENTS_AND_TEMPLATES.md`). |
| 076 | Event, delivery and inbox ids are derived from the dedupe key and recipient, so a replay or a second worker creates nothing twice. Event processing and its deliveries commit in one write. |
| 077 | Recipients are resolved on the server from `patients.patientAccountId` and `members`; an event never carries an address or phone number. |
| 078 | Templates: built-in versioned set plus per-clinic overrides. Rendering is single-pass `{{name}}` substitution with a per-event variable allow-list containing nothing clinical; values are cleaned and, for email, HTML-escaped. An event with no variables carries its own fixed text. |
| 079 | Service messages ("essential") always create the in-app entry; opt-outs apply to extra channels. Promotional categories need an explicit opt-in. |
| 080 | Reminders have no schedule documents: a worker scan derives them from confirmed appointments and scheduled follow-ups, and the dedupe key (appointment, start time, lead) keeps each window to one reminder. A moved visit changes the key and the old event is suppressed. |
| 081 | Reports are computed on demand from the clinic's collections with a 5,000-record scan cap, clinic-local dates, and explicit definitions. No pre-aggregation. |
| 082 | Exports are generated server-side within hard limits, stored privately, downloadable by the requester only, for six hours. |

## Why an in-process worker
The repository has no scheduler, queue or Cloud Tasks wiring. A `Timer.periodic` (60 s) in `bin/server.dart` runs `NotificationHub.tick()`: reminder scan, outbox processing, due retries. It never overlaps itself, is safe on several instances (claims are transactional), and is switched off with `NOTIFICATIONS_WORKER_ENABLED=false`. It needs an always-running instance; a platform scheduler would be the better long-term answer (TD-85).

## Known structural limit
`emit` is called right after the business commit, not inside it (the existing services own their transactions). A crash between the two loses the notification, not the business action (TD-86). Everything after `emit` is durable.
