# Patient Medical Records

All reads need a linked clinic record (own, or a family member with the `view_records` scope) and return allow-listed fields, grouped per clinic. Each view writes an audit entry (`portal.*_viewed`).

| Screen | Endpoint | Content |
|---|---|---|
| Overview | `GET /patient/medical-records` | allergies (allergen, category, reaction, severity), history entries (conditions, surgery, immunization, …: title, description, dates, status), recorded medicines. Not shown: restricted notes, alerts, clinic remarks, entries marked in error. |
| Visits | `GET /patient/consultations` | only **finalized or amended consultations the authoring doctor released**: date, doctor, diagnoses (label, kind, certainty), advice (recommendations, lifestyle, diet, procedures, instructions), follow-up, prescription numbers. Never: chief complaint, observations, assessment, doctor notes, drafts. |
| Prescriptions | `GET /patient/prescriptions` | finalized prescriptions: number, date, doctor, medicines (name, strength, dosage, route, frequency, duration, food relation, instructions, warnings), `current` vs `superseded` (older versions stay as history), and the disclaimer "Issued by your doctor". |
| Documents, reports | `GET /patient/documents`, `/reports` | `available: false`. No release flag or staff workflow exists and laboratory is Phase 9. |

The release flag: `POST /consultations/{id}/release` and `/unrelease` (author doctor, finalized only, idempotent, audited; releasing notifies the patient with generic text). The doctor app has *Share summary with patient*. Patients cannot create, edit or delete anything here: no write route exists, and the app has no edit controls (tested). Records of other patients, other clinics, and relationships without the scope answer empty or 404.
