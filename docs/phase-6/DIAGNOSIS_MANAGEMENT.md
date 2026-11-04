# Diagnosis Management

- A diagnosis is entered by the doctor: `kind` (primary/secondary/differential), `certainty` (provisional/confirmed), `label`, optional `description`, `notes`.
- `code` requires `codeSystem`. Codes are never suggested or generated. A catalogue entry (`diagnosis_catalogue`, clinic-managed, ships **empty**) may supply label/code via `catalogueId`.
- Exactly one primary per consultation (409 if another exists); at most 20 diagnoses.
- Draft/in-progress: `POST /consultations/{id}/diagnoses`, `PATCH …/diagnoses/{diagnosisId}`.
- Finalized: locked. Changes only through `amend.diagnosisChanges` (`add`/`update`/`remove`); a primary must remain.
- Catalogue management: `GET/POST/PATCH /diagnoses/catalogue` (`clinical_catalogue.manage`: owner/admin).
- No AI, no interaction or suitability checks.
