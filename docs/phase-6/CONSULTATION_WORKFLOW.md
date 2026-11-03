# Consultation Workflow

Lifecycle: `draft → in_progress → finalized → amended`. Only dedicated endpoints move it; there is no generic status endpoint.

| Step | Endpoint | Rules |
|---|---|---|
| Create | `POST /consultations` | Authoring doctor only (member has `doctorId`); patient in branch scope; patient must have `data_processing` consent; appointment (optional) must belong to the same doctor/branch/patient and not be cancelled/no-show; one consultation per appointment (`consultation_appointments/{appointmentId}`); optional `templateId` pre-fills sections |
| Edit | `PATCH /consultations/{id}` | draft/in_progress only; field-wise merge of sections; `expectedVersion` optimistic check (409 on mismatch) |
| Start | `POST …/start` | draft → in_progress; calls/starts the Phase 5 queue entry |
| Finalize | `POST …/finalize` | needs `chiefComplaint.reason` and a primary diagnosis; completes the queue entry; stores version `r0`; idempotent (replay returns `idempotentReplay: true`, one audit, one version) |
| Amend | `POST …/amend` | finalized/amended only; `reason` ≥ 5 chars; must change something; may carry `diagnosisChanges`; originals preserved in `consultation_versions`, change recorded in `consultation_amendments`; revision +1 |
| Read | `GET …/{id}`, `…/amendments` | detail read is audited (`consultation.viewed`) |

Sections: `chiefComplaint` (reason, symptoms[name, duration, onset, severity, notes], notes), `observations`, `assessment`, `treatmentPlan`, `followUp`. Nothing is auto-filled with medical content; templates carry only the clinic's own field defaults.

Access: only the author reads/edits a consultation. `consultations.view_all` (owner only) allows read, never authoring. Another doctor's consultation answers 404.
