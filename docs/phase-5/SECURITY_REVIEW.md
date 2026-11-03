# Phase 5 Security Review

| Requirement | Result |
|---|---|
| Clinic A cannot see Clinic B appointments or queues | Tested (lists empty, ids 404, actions 404, header spoofing refused) |
| Doctor/receptionist at another branch | Branch scope → 404 for appointments, queues, entries, check-in |
| Receptionist cannot change availability | 403; doctors only their own; accountants nothing |
| Doctor not assigned to the branch / outside availability / during leave | 409 / 422 / 422 |
| Concurrent overbooking | One winner (6 racers), capacity respected (5 racers, 2 lanes) |
| Duplicate requests | Idempotency replay; key reuse with other body 409 |
| Cancelled appointment cannot check in; invalid transitions | 409; no endpoint takes a status |
| Unauthorized completion | Reception, nurse, other doctors → 403 |
| Token duplication | Concurrent check-ins produce unique tokens; uniqueness keys |
| Queue priority | Only `queue.priority` (owner/admin); only waiting entries |
| Trusted fields | PATCH accepts `notes` only; create rejects source/status/ids |
| Suspended tenant / missing feature | 403 for reads and writes |
| Audit | All lifecycle, queue and schedule changes; no clinical data; append-only (no write routes) |
| Firestore | Rules deny every new path; collection-group queries denied (rules tests) |

## Residual risks
- Live Firebase and deployed indexes unverified; rate limits per instance.
- Fixed-offset zones only (no DST) — TD-43. Queue refresh is polling — TD-44. Capacity lanes are not per branch — TD-45.
- A doctor user is linked to a profile through the member record (`doctorId`), set by the invitation flow; if absent a doctor role cannot act on a queue.
- Reads of appointment lists are not individually audited (the patient record access audit of Phase 4 is unchanged).
No unresolved tenant-isolation, branch-authorization, concurrency or token-integrity defect is known.
