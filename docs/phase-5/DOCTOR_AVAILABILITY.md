# Doctor Availability (Module A)

`doctor_availability/{scheduleId}` — one schedule per doctor **and branch** for a date range:
`weeklyHours` {`"1"`..`"7"` (Mon..Sun): `{sessions:[{from,to}], breaks:[{from,to}]}`}, `defaultDurationMinutes` (5–240), `bufferMinutes` (0–120), `maxPerSlot` (1–10, default 1 = no capacity scheduling), optional `typeDurations` {typeId: minutes}, `effectiveFrom`, `effectiveTo?`, `status` (`active|inactive`), `timezone` (branch zone at creation), `version`.

Rules: the doctor must be **actively assigned to that branch**; times are `HH:MM` in the branch zone; ≤ 4 sessions per day, ≤ 6 breaks; sessions must not overlap; breaks must not overlap and must lie inside a session; at least one working session; two **active** schedules of the same doctor+branch cannot overlap in dates (409). Different branches can have different schedules. A doctor cannot be booked at two places at once (see double booking).

`PATCH` keeps the previous version in `availability_revisions`; `DELETE` only sets `status: inactive` (history kept). Permissions: `availability.manage` (owner, admin) for anyone; `availability.manage_own` (doctor) only for the doctor profile linked to their login; `availability.view` to read. The client cannot send ids, tenant or audit fields (422). Changes are audited in `platform_audit_logs`.

Endpoints: `GET/POST /doctors/{id}/availability`, `PATCH/DELETE /doctors/{id}/availability/{scheduleId}`.
UI: Clinic Web › Availability (weekly editor takes ranges like `09:00-13:00, 17:00-20:00`).
