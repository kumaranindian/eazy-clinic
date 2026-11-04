# Phase 6 API Reference

Base `/api/v1`; standard envelope; every route is authenticated, tenant-resolved from membership, feature-gated (`doctorWorkspace` for `/doctor/*`, `appointments` for follow-up booking) and permission-checked. A suspended tenant gets 403.

| Method | Path | Permission |
|---|---|---|
| GET | /doctor/dashboard · /doctor/appointments/today · /doctor/queue · /doctor/followups | consultations.view / followups.view |
| POST | /doctor/queue/{entryId}/call | queue.operate (own queue, doctor) |
| GET | /clinical/patients/{id}/overview · /history | consultations.view |
| GET, POST | /clinical/patients/{id}/vitals | vitals.view / vitals.record |
| POST | /consultations | consultations.manage |
| GET, PATCH | /consultations/{id} | consultations.view / manage |
| POST | /consultations/{id}/start · /finalize · /amend | manage / finalize / manage |
| GET | /consultations/{id}/amendments · /audit-logs · /investigations | view / clinical_audit.view / view |
| POST, PATCH | /consultations/{id}/diagnoses · …/diagnoses/{did} | manage |
| POST | /consultations/{id}/prescriptions · /followups · /investigations | prescriptions.manage / followups.manage / investigations.request |
| GET, PATCH | /prescriptions/{id} | prescriptions.view / manage |
| POST | /prescriptions/{id}/finalize · /amend | prescriptions.finalize / manage |
| GET, POST, PATCH | /diagnoses/catalogue · /medicines/catalogue (search `q`) | consultations.view / clinical_catalogue.manage |
| GET, POST, PATCH | /clinical/templates | clinical_templates.view / manage |
| PATCH | /followups/{id} | followups.manage |
| POST | /followups/{id}/appointment (`Idempotency-Key`) | followups.view + the booking permission enforced by `AppointmentService.book` |

Errors: 400/422 validation with `issues[]`, 403 permission, 404 not found *or* not yours, 409 conflict (version mismatch, state, duplicate), 429 limits. Bodies reject unknown fields; no endpoint accepts `tenantId`, `doctorId`, `status`, authorship or timestamps.
