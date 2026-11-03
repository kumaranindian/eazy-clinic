# Global Patient Identity (Module B)

Two separate things:

| | Global patient account | Clinic patient record |
|---|---|---|
| Location | `patient_accounts/{accountId}` | `tenants/{t}/patients/{patientId}` |
| Owner | the person | the clinic |
| Contents | display name, e-mail, unverified phone, optional date of birth, kind (`self`/`dependent`), status | demographics, contact, history, allergies, medications, documents, consents |
| Medical data | **never** | yes, inside the clinic's boundary |

`patient_account_uids/{uid}` is a uniqueness key (one account per sign-in). A person may have an account and no clinic record, or a record and no account. The same account can be linked to independent records at several clinics (`patient_clinic_links/{tenantId}_{patientId}`: account, tenant, patient id, MRN, clinic name, status — pointers only). A clinic never reads the global account or other clinics' records, and **no endpoint resolves one clinic's record from another's**.

Identity verification level in Phase 4: `email_verified` (from the signed ID token) or `unverified`; `managed_by_guardian` for dependents. Phone numbers are stored unverified and are never used to authorize or match anything. ABDM/ABHA is not implemented and no compliance is claimed.

Endpoints: `POST /patient-accounts` (create own), `GET /patient-accounts/me`, `GET /patient-accounts/me/clinic-links[?accountId=]`.
