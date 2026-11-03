# Follow-up Management

Statuses: `scheduled`, `completed`, `missed`, `cancelled`; *overdue* is computed from the clinic time zone (scheduled and date before today).

- Create `POST /consultations/{id}/followups` (date, reason, instructions); needs `followups.manage`; own consultation.
- `PATCH /followups/{id}` status transitions only from `scheduled`.
- `GET /doctor/followups?upcoming|overdue|from|to|status|branchId`.
- `POST /followups/{id}/appointment` books through Phase 5 `AppointmentService.book` with an `Idempotency-Key`; duplicate booking is prevented and the follow-up links to the appointment.
- Reason/instructions are hidden from roles without `consultations.view` (nurse/receptionist see date and status).
- No reminders (Phase 10, TD-47).
