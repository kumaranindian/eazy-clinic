# Phase 4 Firestore Schema

All collections are backend-only (rules deny clients; rules tests cover every path).

**Global** (no clinical data): `patient_accounts/{pa_…}`, `patient_account_uids/{uid}`, `patient_clinic_links/{tenantId}_{patientId}` (accountId, tenantId, patientId, mrn, clinicName, status), `family_relationships/{fr_…}`.

**Tenant** (`tenants/{t}/…`): `patients/{pt_…}` (branchId, mrn, demographics, guardian, patientAccountId, status, search keys `nameLower/phoneNorm/alternatePhoneNorm/emailNorm`, seatSlot, version); `patient_mrns/{mrn}` (uniqueness); `counters/patient_mrn`; `patient_consents`; `patient_history_entries`; `patient_allergies`; `patient_medications`; `patient_alerts`; `patient_emergency_contacts/{patientId}`; `patient_documents`; `patient_link_codes` (codeHash only); `patient_identity_links`; `patient_duplicate_reviews`; `patient_record_revisions` (previous versions); `patient_audit_logs` (actor, role, branch, patient, action, resource, reason, requestId, minimal before/after, timestamp).

Not created (and why): separate `patient_conditions/surgeries/family_histories/immunizations` (one `patient_history_entries` with `category`), `medical_histories`, `patient_consents` global copy. Retention: nothing is physically deleted; see `docs/security/DATA_RETENTION.md`.

Indexes: 29 composite indexes + a `patient_link_codes.codeHash` collection-group override in `firebase/firestore.indexes.json` (**not deployed**, not enforced by the emulator).
