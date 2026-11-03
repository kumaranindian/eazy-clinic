# Phase 4 Security and Privacy Review

| Requirement | Result (tests) |
|---|---|
| Clinic A cannot read Clinic B patients, history, documents, consents, audit | Tested for every sub-resource; spoofed `X-Tenant-Id` → 403 |
| Receptionist/admin/accountant cannot read clinical history, allergies, medications, documents | Tested (403) |
| User cannot link someone else's record | Code needs in-person ID check; wrong/used/expired/replaced → same 400; unverified e-mail 403 |
| Patient cannot reach another patient's record by changing an id | Patient accounts have no clinic API access (403); ids from other patients/tenants → 404 |
| Family relationship grants nothing beyond scope; revoked/unverified/expired/pending grant nothing | Tested |
| Phone/e-mail match never links or merges | Tested (low match, no auto-merge, no merge route) |
| Clinic cannot see another clinic through global identity | Account/links hold pointers only; tested with one person at two clinics |
| Revoked consent respected | Writes and uploads blocked (409) |
| Client cannot modify audit or reach other Storage paths | No write routes; rules tests; object path built server-side |
| Staff cannot change ownership/tenant identity | Immutable fields rejected (422) |
| Sensitive data not logged/audited | Audit holds references; test asserts no allergen/reaction text |

## Residual risks and gaps
- Live Firebase/Storage, deployed indexes: unverified. Rate limits per instance.
- Guardian verification is a **staff attestation**, not legal proof; patient-account phone is unverified; no MFA for clinic users.
- Duplicate search finds only birth-date/phone/e-mail candidates. Merge is not implemented.
- Documents are streamed through the backend (no signed URLs); upload ≤ 3 MB JSON.
- Clinical reads are audited best-effort in the same request (a failed audit write fails the request).
- Staff can issue link codes for records in their branch scope only.
No unresolved tenant-isolation, consent, family-authorization or document-access defect is known.
