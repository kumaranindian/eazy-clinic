# Appointment Lifecycle (Module G)

| From | To | Endpoint | Permission / rule |
|---|---|---|---|
| pending | confirmed | `POST …/confirm` | `appointments.manage` |
| pending, confirmed | cancelled | `POST …/cancel {reason}` | `appointments.manage`; reason 3–300; frees the slot |
| confirmed | checked_in | `POST …/check-in` | `appointments.check_in`; same local day; within the early/late window; creates the queue entry and token |
| checked_in | cancelled | `POST …/cancel` | also `appointments.cancel_checked_in` (reception, admin, owner); also cancels the queue entry |
| checked_in | in_progress | `POST …/start` | `appointments.consult` + queue entry must be `called`; doctors only their own patients |
| in_progress | completed | `POST …/complete` | same |
| confirmed | no_show | `POST …/mark-no-show` | `appointments.manage`; not before the start time; frees the slot |
| checked_in | no_show | queue action `no-show` | called/skipped patient who does not respond |
| pending, confirmed | rescheduled | `POST …/reschedule {date,startTime,reason,typeId?}` | creates a **new** confirmed appointment (same doctor and branch), links both, moves the reservation, old one is kept |

Everything else answers 409. No endpoint accepts a status from the client. `start`/`complete` delegate to the queue entry so appointment and queue never disagree. Every transition writes an audit record (before/after status, actor, reason, and for reschedules the previous and new date/time) readable at `GET /appointments/{id}/audit-logs` and in the detail history. Check-in window: clinic settings `checkInEarlyMinutes` (default 120) and `checkInLateMinutes` (default 60, after the appointment ends).
