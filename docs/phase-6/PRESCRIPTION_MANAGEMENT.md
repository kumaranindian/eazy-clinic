# Prescription Management

Status: `draft → finalized`; amendment creates a replacement draft.

- Create `POST /consultations/{id}/prescriptions` (≤ 5 non-amended per consultation, consultation must be open).
- Medicine fields: name, genericName, brandName, strength, dosage (must contain a letter or digit), route, frequency, `durationValue` 1–365 + `durationUnit` (days/weeks/months), quantity, foodRelation, instructions, warnings, notes, `catalogueId` (validated against `medicine_catalogue` when given). Catalogue ships empty. ≤ max medicines per prescription.
- Edit `PATCH /prescriptions/{id}` draft only, `expectedRev` optimistic check.
- Authorize `POST …/finalize`: requires `prescriptions.finalize` and being the authoring doctor; assigns number `RX-000001…` from `counters/prescription_number` with uniqueness keys in `prescription_numbers`; idempotent; audited.
- Amend `POST …/amend` with reason: creates a draft (`supersedesId`, `rootId`, `version+1`). Finalizing it marks the original `amended` atomically and keeps the same RX number.
- Detail returns the version chain, clinic name and the disclaimer "Issued by the treating doctor"; reading is audited.
- Doctor app: editor (add/edit/remove medicine), authorize confirmation, read-only preview, amend with reason, version list.
- Not built: PDF, signature, pharmacy dispensing, drug-interaction/allergy checks (the doctor sees the patient's allergies on the patient page; no automated check is claimed).
