# Patient Profile and Identity

- **Global identity vs clinic records:** the profile lives in `patient_accounts`; clinic records stay under each tenant. A profile edit never changes a clinic's record (tested).
- **View:** `GET /patient/profile`: name, e-mail, mobile, date of birth, identity verification state, language, address, emergency contact, linked clinics (id, name, patient number), profile completion (name, phone, date of birth, address, emergency contact) and any deletion request.
- **Edit:** `PATCH /patient/profile` accepts only `preferredLanguage`, `address`, `emergencyContact`. Name, date of birth, mobile and e-mail changes, and server fields (status, ids, kind), are rejected (422). Changing identity fields needs a verified change request, which is not built (TD-66). Photo upload is not built (TD-66).
- **Dependents:** managed accounts (`kind: dependent`) are created and revoked through the existing family routes; their identity is `managed_by_guardian`.
- **Never editable by patients:** diagnoses, consultations, prescriptions, invoices, payments: no write route exists for them in the portal, and the Firestore rules deny clients.
