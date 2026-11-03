# Data Retention (as implemented in Phase 4)

Healthcare records are retained; this is the behaviour of the code, not a legal policy (the clinic's retention period must be set with legal advice).

| Data | Behaviour |
|---|---|
| Clinic patient records | Never deleted. `archived` keeps the record readable and releases the patient seat. |
| History, allergies, medications, alerts | Never deleted. Wrong entries become `entered_in_error`/`inactive`/`resolved`. Previous versions are kept in `patient_record_revisions`. |
| Documents | "Removal" hides a document and records who and why. The stored object and metadata are retained. |
| Consents | Decisions are kept after revocation (status `revoked`, `revokedAt/By/Reason`) as evidence. |
| Patient audit logs | Append-only; no API modifies or deletes them. |
| Link codes | Hash only; used/replaced codes are kept as records. |
| Global patient account | Holds identity only; deletion/erasure requests are **not implemented** (TD-38) and need a documented DPDP erasure process that respects clinic retention duties. |
| Backups / expiry jobs | Not implemented (Phase 11). |
