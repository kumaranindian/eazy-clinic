# Appointment Slots and Booking (Modules C, E)

## Slots — `GET /appointments/available-slots?branchId&doctorId&date[&typeId][&includeFull]`
Calculated on the backend: schedule for the branch and date → exceptions → sessions → remove breaks and blocked ranges → step by `duration + buffer` → drop past times → drop slots with no free lane. Returns `day` (sessions, breaks, blocked, closed + reason) and slots `{startTime,endTime,startUtc,endUtc,available}` in the branch zone. Checks tenant, branch scope, active branch, doctor assignment, active type and the `appointments` feature. Past dates and dates > 365 days ahead → 409.

## Booking — `POST /appointments` (header `Idempotency-Key` required)
Body: `patientId, doctorId, branchId, typeId, date, startTime, notes?, status? (pending|confirmed)`. Anything else (source, status values, ids, tenant) is rejected (422). The **source is derived from the role** (`reception`, `clinic_admin`, `doctor`).

Server steps: permission + feature → idempotency check → active patient (tenant/branch scoped) → active branch, assigned doctor, active type → slot must be one the backend offers (422 `not_available` if not; outside hours, break, leave, closed day, off-grid) → **transaction**: patient still active, free lane re-read from the reservation documents (409 "just taken" if none), patient has no overlapping open appointment (409) → writes appointment + reference + reservations + idempotency key + audit atomically. Appointment fields: id, `APT-YYYYMMDD-XXXX` reference, tenant, branch, patient (id, name, MRN snapshot), doctor (id, name), type, local date/start/end, UTC start/end, zone, status, source, notes, `needsAttention`, versions and actor fields. Clinical data is never stored here.

`GET /appointments` filters: `date` or `from`/`to` (≤ 62 days), `doctorId`, `branchId`, `status`, `reference`, `q` (patient name/MRN/reference within the window), `needsAttention`; cursor pagination; branch-scoped users only get their branches. `GET /appointments/{id}` returns the appointment with its history. `PATCH` only edits `notes` of an open appointment. `GET /patients/{id}/appointments` is the patient timeline (no consultation data).
