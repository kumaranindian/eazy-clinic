# Patient Management (Modules A, H, K)

**Registration** (`POST /patients`, `patients.create`): branch (must be active and in the caller's scope), full/preferred name, date of birth (valid, not future), gender (`male|female|other|undisclosed`), optional blood group, primary/alternate phone, e-mail, preferred language/contact method, address, occupation, restricted notes (read only with `history.view`), guardian (minors), optional emergency contacts, **required consent**, optional duplicate review. The server assigns `patientId` (`pt_…`), the clinic MRN (`MRN-000001…`, tenant counter updated in the same atomic commit as a uniqueness key document, so collisions cannot occur), tenant, status and audit fields. Any attempt to send ids, tenant, MRN, status, account or creator fields is rejected (422).

**Statuses:** `active`, `inactive`, `archived` (`merged` is reserved; merge is not implemented). `active↔inactive` and `→archived` need `patients.status` and a reason; archived records cannot be changed or reactivated and release their patient seat. There is **no delete** endpoint.

**Updates** (`PATCH /patients/{id}`): demographics only. `branchId`, `mrn`, `tenantId`, `patientAccountId` and `status` are immutable here. Every change stores the previous values in `patient_record_revisions` and an audit entry.

**Directory** (`GET /patients`): `q` detects the type — `pt_…` id, `MRN-…`, e-mail, phone digits, otherwise a **name prefix**. Filters: `status`, `gender`, `branchId`, `from`/`to` (registration date). Cursor pagination. Rows contain identification and **masked** phone/e-mail only. Branch-scoped users only ever get their branches (404 for others). Identifier lookups apply other filters after the single-equality query, so they need no extra indexes.

**Detail** (`GET /patients/{id}`): audited access; shows active alerts (clinical alerts only to clinical roles) and active allergies (only to roles with `allergies.view`).

**Emergency contacts:** 1–5 contacts (one preferred), replaced as a set (`PUT`), previous set kept as a revision.

**Alerts:** categories `medical`, `allergy` (clinical — need clinical permissions to create/edit/see), `special_assistance`, `communication`, `administrative`, `other`. Alerts are resolved, never deleted.

Limits: `max_patients` is enforced with the Phase 3 seat slots.
