# Phase 5 Firestore Schema

All under `tenants/{tenantId}/`, backend-only (rules deny clients; rules tests cover every path).

| Collection | Key fields |
|---|---|
| `doctor_availability/{sch_…}` | doctorId, branchId, weeklyHours, defaults, maxPerSlot, typeDurations, effectiveFrom/To, status, timezone, version |
| `availability_revisions` | previous schedule snapshots |
| `doctor_schedule_exceptions/{exc_…}` | doctorId?, branchId, type, startDate, endDate, fullDay, from/toTime, sessions, breaks, reason, status, approval |
| `appointment_types/{aty_…}`, `appointment_type_names/{key}` | name, duration, buffer, fee, specialities, status; uniqueness key |
| `appointments/{apt_…}` | reference, branchId, patientId (+name/MRN snapshot), doctorId (+name), typeId (+name), localDate, startTime, endTime, startUtc, endUtc, timezone, durationMinutes, source, status, notes, queueEntryId, tokenDisplay, needsAttention, attentionReason, reschedule/cancel/no-show/check-in fields, lane, version |
| `appointment_references/{ref}` | uniqueness key |
| `appointment_idempotency/{hash}` | fingerprint, appointmentId |
| `appointment_slot_reservations/{doctor_date_cell_lane}` | doctorId, branchId, localDate, cell, lane, appointmentId |
| `queues/{q_hash}` | branchId, doctorId, queueDate, prefix, nextToken, version, lastEventAt |
| `queue_entries/{qe_…}` | queueId, appointmentId, patientId/name, tokenNumber, displayToken, priority, status, queuedAt, checkInAt, calledAt, startedAt, completedAt, recallCount, version |
| `queue_tokens/{queueId_n}` | uniqueness key |
| `appointment_audit_logs` | appointment **and** queue events: action, resourceType, resourceId, appointmentId, queueEntryId, branchId, actor uid/role, reason, requestId, before/after, timestamp |

Not created: separate `clinic_holidays` (branch exceptions cover them), `appointment_history`/`queue_history` (served by `appointment_audit_logs`), `queue_counters` (counter on the queue document). Indexes: 20 composite indexes added (78 in total) — **not deployed**. Retention: nothing is deleted except reservations (released slots) and idempotency keys are kept.
