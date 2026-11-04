# Gap assessment (done before coding)

Inspected: the Phase 8 `PortalNotifier`, `patient_notifications`, `patient_devices`, `patient_notification_preferences`, call sites in billing, clinical, laboratory and portal modules, scheduling routes, bootstrap and `bin/server.dart`, the Phase 7 finance reports and the Phase 9 lab dashboard.

| Capability | Found | Gap closed in Phase 10 |
|---|---|---|
| In-app inbox for patients | Phase 8: written directly after a business commit; no archive, no read-all | Routed through the pipeline; archive and read-all added |
| Staff inbox | None | `tenants/{t}/notifications` + API + screens |
| Durable event record | None (fire-and-forget write) | `notification_events` outbox with lease, replay and dedupe |
| Templates | Text hard-coded at call sites | Built-in versioned templates + clinic templates + versions |
| Preferences | Patient only: push on/off, category on/off | Staff preferences; channels; promotional opt-in; essential rules |
| Devices | Patient tokens only (`patient_devices`) | Staff tokens (`notification_devices`) with lifecycle |
| FCM | Interface only (TD-67) | `HttpFcmSender` (unverified live) behind `NOTIFICATIONS_FCM_ENABLED`; token invalidation on provider answer |
| Email/SMS/WhatsApp | None | `MessageProvider` interface; unconfigured = `configuration_required` |
| Scheduler / jobs | **None** | A 60-second in-process worker tick (justified in `ARCHITECTURE.md`, TD-85) |
| Reminders | None | Appointment and follow-up reminders from existing data |
| Delivery tracking, retry, admin | None | Statuses, backoff with jitter, manual retry, pause/resume, health |
| Reports | Phase 7 finance reports, Phase 9 lab dashboard | Six operational reports, dashboard, exports; billing reuses Phase 7 field semantics |
| Audit | Per-module audit logs | `notification_audit_logs`, `report_audit_logs` |

Not verified at the start and still not verifiable here: live FCM, any email/SMS/WhatsApp provider, Android devices, Cloud Run behaviour of the timer.
