# Phase 10: Notifications, Communication and Operational Reports

Branch: `feature/phase-10-reports-notifications` (from `develop` at `6c05a01`). The Phase 10 prompt asked to continue on `feature/phase-0-foundation`; as in Phases 7 to 9 a dedicated branch was used. Nothing is pushed or merged. No real message was sent, no provider activated, no production Firebase change was made.

## What exists
| Area | Where |
|---|---|
| Event outbox, recipient resolution, templates, channel dispatch, delivery tracking, retries, reminders, worker tick | `backend/lib/features/notifications/notification_hub.dart`, `notification_core.dart` |
| Staff notification center, preferences, devices, template/delivery/channel/settings administration | `notification_service.dart`, `notification_module.dart` |
| Reports (6) and dashboard | `backend/lib/features/reports/report_service.dart` |
| CSV/PDF exports, secure download, audit | `export_service.dart`, `report_module.dart` |
| Existing modules emitting events | `portal_notifier.dart` (now the pipeline's front door), `scheduling_module.dart`, `clinical_module.dart`, `lab_orders.dart`, `lab_results.dart` |
| Clinic Web | `apps/clinic_web/lib/features/communications/` |
| Doctor Workspace | `apps/doctor_mobile/.../notifications_page.dart` |
| Patient app | notification page: mark all read and dismiss |

## Documents
`GAP_ASSESSMENT.md` · `ARCHITECTURE.md` · `EVENTS_AND_TEMPLATES.md` · `DELIVERY_AND_CHANNELS.md` · `REPORTING_DEFINITIONS.md` · `API_SPECIFICATION.md` · `DATABASE_SCHEMA.md` · `SECURITY.md` · `TESTING.md` · `IMPLEMENTATION_REPORT.md`

## Rules in one place
1. One pipeline: every notification is a durable event, then deliveries per recipient and channel. Callers never talk to a provider.
2. Provider acceptance is `sent`. `delivered` exists only for the in-app inbox (which the clinic itself stores).
3. A channel with no provider reports `configuration_required`. Nothing pretends to send.
4. Recipients come from clinic records, never from the request. Preferences, channel switches, pauses and appointment state are checked again at dispatch.
5. Push and email text is generic. No diagnosis, medicine, lab value or amount appears in a message; details are fetched after sign-in.
6. Reports use persisted records, document their formulas, and say when figures are incomplete. A rate with nothing to divide by is empty, not 0%.
7. Exports apply the same access rules as the screen, are limited in size, stay in private storage, and can be downloaded only by the person who asked, for six hours.
