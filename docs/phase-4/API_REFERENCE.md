# Phase 4 API (`/api/v1`)

Clinic routes need a token, tenant membership, entitlement level, permission, branch scope. Patient-account routes need only an authenticated active account. Strict bodies; 404 for out-of-scope resources; 409 for consent/limit/duplicate conflicts; writes rate limited, linking 10/h, family 60/h.

| Route | Permission |
|---|---|
| GET/POST `/patients`, GET/PATCH `/patients/{id}`, POST `…/activate|deactivate|archive` | patients.view / create / update / status |
| POST `/patients/duplicate-check`, GET `/patients/{id}/possible-duplicates` | patients.duplicates |
| POST `/patients/{id}/link-account`, `/unlink-account` | patients.link_account |
| GET/POST `/patients/{id}/medical-history`, PATCH `…/{entryId}` | history.view / manage |
| GET/POST `/patients/{id}/allergies`, PATCH `…/{allergyId}` | allergies.view / manage |
| GET/POST `/patients/{id}/medications`, PATCH `…/{medicationId}` | medications.view / manage |
| GET/PUT `/patients/{id}/emergency-contacts` | patients.view / update |
| GET/POST `/patients/{id}/alerts`, PATCH `…/{alertId}` | alerts.view / manage (+ clinical rights for medical/allergy) |
| GET `/consent-catalog`; GET/POST `/patients/{id}/consents`; POST `…/{id}/revoke` | consents.view / manage |
| GET/POST `/patients/{id}/documents`, GET `…/{id}`, GET `…/{id}/content`, DELETE `…/{id}?reason=` | patient_documents.view / manage |
| GET `/patients/{id}/audit-logs` | patient_audit.view |
| POST `/patient-accounts`; GET `/patient-accounts/me`; GET `…/me/clinic-links[?accountId]` | own account |
| POST `/patient-accounts/me/link-clinic-record`; POST `…/clinic-links/{linkId}/unlink` | own account |
| GET/POST `/patient-accounts/me/family`; GET/PATCH `/family-relationships/{id}`; POST `…/verify`, `…/revoke` | party to the relationship |

No endpoint merges patients, edits audit records, or deletes patient data.
