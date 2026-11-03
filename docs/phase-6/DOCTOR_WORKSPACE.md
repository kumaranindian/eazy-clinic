# Doctor Workspace

App: `apps/doctor_mobile` (Flutter web/Android). Admits only sessions with a `doctor` membership.

| Route | Screen | Backend |
|---|---|---|
| `/` | Dashboard: counts (scheduled, waiting, checked in, in consultation, completed, cancelled, no-show), queues, upcoming, recent consultations | `GET /doctor/dashboard` |
| `/today` | Today's appointments | `GET /doctor/appointments/today` |
| `/queue` | Doctor queue, polls every few seconds with version guard; Call, Start/Open consultation | `GET /doctor/queue`, `POST /doctor/queue/{id}/call` |
| `/patients` | Patient search (debounced) | `GET /patients?q=` |
| `/patients/:id` | Clinical overview: alerts, allergies, medications, history, vitals (record), previous consultations, lab notice | `GET /clinical/patients/{id}/overview|history|vitals` |
| `/consultations/:id` | Consultation workspace | see CONSULTATION_WORKFLOW.md |
| `/prescriptions/:id` | Prescription editor / preview | see PRESCRIPTION_MANAGEMENT.md |
| `/followups` | Upcoming/overdue follow-ups, status actions, booking | `GET /doctor/followups` |
| `/account` | Signed-in identity, sign out (former home page) | – |

Rules
- Every screen reads from the backend; nothing is cached as truth. Sections the role may not see arrive as `null` and show "Not available for your role".
- Branch and doctor scope are applied on the server; the UI sends no tenant, branch-scope or doctor identity except the selected `branchId` for starting a consultation, which the server validates.
- States: loading, error with retry (403 shows "Not permitted"), empty, success/failure snackbars.
- Unsaved consultation edits trigger a discard confirmation.
- Known gaps: no offline mode, no queue push (TD-44), no printable prescription (TD-52).
