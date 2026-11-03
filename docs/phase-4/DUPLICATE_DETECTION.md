# Duplicate Detection (Module C)

Candidates are gathered **inside the caller's tenant and branch scope** with equality queries on date of birth, normalised phone and e-mail, then scored by name similarity (Levenshtein, word-order independent):

| Level | Rule |
|---|---|
| high | (same date of birth, phone or e-mail) and name similarity ≥ 0.85 |
| medium | (same birth date or phone) and similarity ≥ 0.6, or same e-mail |
| low | same phone only |

`POST /patients/duplicate-check` returns matches (id, MRN, name, date of birth, **masked** phone, level, reasons) and `requiresReview`. `POST /patients` answers **409 `duplicate_review_required`** when a high/medium candidate exists unless the body carries `duplicateReview {decision: "confirmed_distinct", reason, reviewedPatientIds}` that covers every blocking candidate. The review is stored in `patient_duplicate_reviews` and audited. `GET /patients/{id}/possible-duplicates` lists matches for an existing record.

**Never automatic.** Nothing is merged, linked or blocked on a phone match alone (low level shows but never blocks).

**Merge: not implemented.** A safe merge must re-point every dependent record (history, allergies, medications, documents, consents, links), keep both ids/MRNs, mark the source `merged`, and be audited and reversible; that touches data created in later phases (appointments, billing), so it is deferred (TD-37). The UI offers no merge action.

Limitation: matching starts from birth date, phone or e-mail; two records for the same person with different birth date, phone and e-mail are not found.
