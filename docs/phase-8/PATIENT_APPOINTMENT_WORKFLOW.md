# Patient Appointment Workflow

All through the Phase 5 engine; the portal adds identity, ownership and the patient policy.

| Step | Endpoint | Rules |
|---|---|---|
| Availability | `GET /patient/clinics/{c}/availability?branchId&doctorId&date&typeId` | Same slot engine as staff. A hint: booking recalculates. |
| Book | `POST /patient/appointments` (`Idempotency-Key`) | Body: `clinicId, branchId, doctorId, typeId, date, startTime` (+ `accountId` for a family member). The patient must be linked; ids, status, tenant and patient are never accepted from the client (422). Status is **pending** until the clinic confirms; source `patient_app`. The engine rejects a taken slot (409, tested with racing patients: one wins). |
| List | `GET /patient/appointments?filter=` | `upcoming` (clinic-local date), `completed`, `cancelled`, `rescheduled`, `no_show`; across linked clinics. |
| Detail | `GET /patient/clinics/{c}/appointments/{a}` | Own appointments only (404 otherwise). |
| Cancel | `POST …/cancel` | Pending or confirmed only; at least 2 hours before the visit; idempotent; audited; notifies. |
| Reschedule | `POST …/reschedule {date, startTime}` | Same notice rule and a 60-day window; creates the new appointment and marks the old `rescheduled` (history kept). |
| Check-in | `POST …/check-in` | Confirmed visit, on the clinic-local day; issues a token; repeats are replays. |

Policy defaults (not configurable per clinic yet, TD-65): book from today up to 60 days ahead; change at least 2 hours before. The backend enforces them; the app shows the backend's message. No false success is ever shown: the confirmation appears only after a 201, and a conflict clears the chosen time and refreshes availability. The app keeps one idempotency key per unchanged choice and drops it when the choice changes.
