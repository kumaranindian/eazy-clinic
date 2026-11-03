# Patient Account Linking

1. **Clinic identifies the person.** Staff with `patients.link_account` call `POST /patients/{id}/link-account` with a `verificationMethod` (`government_id_sighted`, `other_document_sighted`, `known_patient_in_person`) and `identityConfirmed: true`. The patient must be active, unlinked, and — for a minor — have a **verified guardian**.
2. The server returns a one-time code `ECL-XXXX-XXXX-XXXX` (60 bits, shown once). Only its SHA-256 is stored (`tenants/{t}/patient_link_codes`), valid 24 h; issuing a new code revokes earlier pending codes.
3. **The account holder claims it:** `POST /patient-accounts/me/link-clinic-record {code[, forAccountId]}` — requires a patient account and a **verified e-mail**; rate limited (10/h per user). The code is found by a collection-group lookup on `codeHash`; every failure (unknown, malformed, expired, used, replaced) returns the same message.
4. In one transaction: the code is marked used, the record gets `patientAccountId`, an identity link, the global pointer and the account holder's **`account_linking` consent** are created, and audit entries are written. The response contains no demographics or clinical data.
5. One account ↔ one record per clinic; a record can have one account. A dependent is claimed by its guardian (`forAccountId`), only with a code issued for a minor record with a verified guardian, and only for a dependent that guardian created.

**Unlinking:** clinic (`POST /patients/{id}/unlink-account` with a reason) or the account holder / their guardian (`POST /patient-accounts/me/clinic-links/{linkId}/unlink`). The record is kept; both pointers become `unlinked`; audited.

**What never links:** matching phone, e-mail or name; a code for another person's record; an unverified e-mail; someone else's dependent.
