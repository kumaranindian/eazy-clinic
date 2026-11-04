# Schedule Exceptions and Holidays (Module B)

`doctor_schedule_exceptions/{id}`: `doctorId` (null = whole branch), `branchId`, `type`, `startDate`/`endDate` (local dates, ≤ 1 year), `fullDay`, `fromTime`/`toTime` (partial days), `sessions`/`breaks` (special days), `reason`, `status` (`active|cancelled`), `approval` (`approved|self_declared`), `approvedBy`, `createdBy`.

Types — doctor level: `doctor_leave`, `personal_leave`, `sick_leave`, `emergency_unavailability` (blocking), `special_working_day`, `schedule_modification` (open/replace hours). Branch level: `clinic_holiday`, `branch_closure`, `emergency_unavailability`.

**Precedence per date:** blocking exceptions (leave, holiday, closure, emergency; full-day closes the day, partial blocks a time range) win over everything; a special working day or schedule modification **replaces** the weekly sessions; otherwise the weekly schedule applies. A doctor with no schedule is closed.

**Existing appointments are never cancelled.** Creating or extending a blocking exception returns `affectedAppointments` and sets `needsAttention: true` (+ `attentionReason: schedule_exception:<id>`) on each open appointment in range, in the same commit. Staff resolve each explicitly (reschedule or cancel); cancelling the exception clears flags that were set only by it. `GET /appointments?needsAttention=true` lists the work; `GET /schedule-exceptions/{id}/affected-appointments` re-computes the list. New bookings in a blocked period are refused.

Permissions as for availability; a doctor's own leave is `self_declared` (still blocking) for an admin to review. Endpoints: `GET/POST /doctors/{id}/schedule-exceptions`, `PATCH/DELETE …/{exceptionId}`; branch-wide `GET/POST /schedule-exceptions`, `PATCH/DELETE /schedule-exceptions/{id}`. Everything is audited.
