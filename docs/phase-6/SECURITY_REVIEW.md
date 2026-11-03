# Phase 6 Security Review

| Requirement | Result |
|---|---|
| Authorship only by a doctor linked via `doctorId` | Tested; owner/admin/nurse/receptionist → 403 |
| Another doctor's consultation/prescription | 404 (existence not revealed) |
| Owner `view_all` reads but cannot author | Tested |
| Tenant A vs tenant B; branch scope | Lists empty, ids 404, header spoofing refused (tested) |
| Client-supplied tenant/doctor/status/authorship | Rejected as unknown fields |
| Consent | Consultation requires `data_processing` consent |
| Finalized records | Immutable; PATCH → 409; amendments preserved with reason/author/time (tested) |
| Finalize/authorize idempotent | One audit, one version, one RX number |
| Optimistic concurrency | `expectedVersion` / `expectedRev` → 409 |
| Prescription authorization | Separate `prescriptions.finalize`, audited |
| Vitals | Append-only; unit/range validation |
| Admin default | No clinical read/write permissions |
| Audit | Reads and changes audited; logs hold no clinical text |
| Firestore | All Phase 6 paths and collection-group queries denied to clients (rules tests) |
| No fabricated medical content | Catalogues empty; no AI; no suggested codes/doses; lab results never shown |

## Residual risks
No MFA (TD-20/38); per-instance rate limits (TD-16); indexes/live Firebase unverified (TD-54); custom roles missing so `view_all` is owner-only (TD-29); allergy/interaction checks not performed (TD-52).
