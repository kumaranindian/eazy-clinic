# Phase 5 API (`/api/v1`)

Every route: token, tenant membership, entitlement (suspended/blocked → 403; read-only → no writes; plan must include `appointments`), permission, branch scope; strict bodies; 404 for out-of-scope resources; audited writes; rate-limited writes.

| Route | Permission |
|---|---|
| GET/POST `/doctors/{id}/availability`; PATCH/DELETE `…/{scheduleId}` | availability.view / manage / manage_own |
| GET/POST `/doctors/{id}/schedule-exceptions`; PATCH/DELETE `…/{exceptionId}` | same |
| GET/POST `/schedule-exceptions`; PATCH/DELETE `/schedule-exceptions/{id}`; GET `…/{id}/affected-appointments` | availability.view / manage |
| GET/POST `/appointment-types`; PATCH `…/{id}`; POST `…/{id}/activate|deactivate` | appointment_types.view / manage |
| GET `/appointments/available-slots` | appointments.view |
| GET `/appointments`; GET/PATCH `/appointments/{id}`; GET `…/audit-logs` | appointments.view / manage |
| POST `/appointments` and `/appointments/walk-in` (Idempotency-Key) | appointments.book |
| POST `/appointments/{id}/confirm|cancel|reschedule|mark-no-show` | appointments.manage (+cancel_checked_in for checked-in) |
| POST `/appointments/{id}/check-in` | appointments.check_in |
| POST `/appointments/{id}/start|complete` | appointments.consult (own patients for doctors) |
| GET `/patients/{id}/appointments` | appointments.view + patient in scope |
| GET `/queues`, `/queues/current`, `/queues/{id}`, `/queues/{id}/summary|entries|history` | queue.view |
| POST `/queues/{id}/entries` (check in an appointment), `/queues/{id}/call-next` | appointments.check_in / queue.operate |
| POST `/queue-entries/{id}/call|recall|skip|restore|cancel|no-show` | queue.operate |
| POST `/queue-entries/{id}/start|complete` | queue.consult |
| POST `/queue-entries/{id}/priority` | queue.priority |

There is no endpoint to edit audit records, tokens, statuses or reservations.
