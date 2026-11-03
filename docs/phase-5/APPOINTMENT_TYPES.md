# Appointment Types (Module D)

`appointment_types/{id}`: `name` (unique per tenant, case-insensitive, via `appointment_type_names` keys), `description`, `durationMinutes` (5–240), `bufferMinutes` (0–120), `defaultFeeMinor?` (informational; no payment in Phase 5), `specialities[]`, `status` (`active|inactive`). Tenant-specific; managed with `appointment_types.manage` (owner/admin), readable by booking staff.

Duration precedence when computing slots: the doctor schedule's `typeDurations[typeId]` → the type's duration → (no type) the schedule's default; buffer: type buffer → schedule buffer. An inactive type cannot be used for slots or bookings. Endpoints: `GET/POST /appointment-types`, `PATCH /appointment-types/{id}`, `POST …/activate|deactivate`.
