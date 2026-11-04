# Laboratory security and privacy

| Control | Where enforced |
|---|---|
| Authentication, tenant membership, branch scope, role permission on every route | `m.secured` + `TenantContext`; each service calls `t.require(...)`; branch checks via `scopeFilters` and `load` |
| Plan gating | `LabSupport.requireFeature` on every route |
| Tenant isolation | all data under `tenants/{tenantId}/`; tenant from membership, never from the request; test: another clinic gets 404 on orders, reports and tests |
| Doctor scope | a doctor without lab-desk rights sees only orders they requested; reports only their own and only once published; results only once verified |
| Admin separation | `clinic_admin` has no `lab.results.*`, `lab.reports.*` or `lab.audit.view` (clinical set), mirroring Phase 6 |
| Separation of duty | verifier != enterer/amender; uploader != verifier of an external report |
| Identity at collection | patient number must match the order's patient; failures return 422 and are not stored |
| No invented medical values | no built-in ranges; unit mismatch and missing range are flagged, not compared |
| Immutable history | status `history[]`, `revisions[]`, superseded report versions, `lab_audit_logs` (append-only; rules deny client writes) |
| Report files | private object storage; streamed through authenticated routes; `Cache-Control: private, no-store`; `X-Content-Type-Options: nosniff`; SHA-256 stored; `storagePath` never returned |
| Uploaded files | size limit 8 MB; type decided from the bytes (`%PDF-` or image signature), not from the name or declared type; no malware scanning (TD-76) |
| Patient access | account -> verified clinic link -> relationship scope for dependents; only current published reports; allow-listed fields (no `internalComment`, `enteredBy`, `verifiedBy`, `revisions`, `history`, `storagePath`); every view/download is audited in `patient_audit_logs` |
| Audit content | `lab_audit_logs` and the patient audit trail hold ids, actions and reasons, **not** test names or values (test asserts this) |
| Logging | no clinical values are logged |
| Firestore / Storage rules | still deny-all for clients; rules tests cover every new collection |
| Concurrency | all state changes in transactions; races covered by tests (identifier claim, duplicate requests, double verify/publish) |

## Residual risks (see TD list)
Reports are not signed or watermarked; no malware scan; uploads are base64 JSON; critical results have no acknowledgement workflow; audit retention is undefined; GCS adapter and indexes are unverified against live Firebase.
