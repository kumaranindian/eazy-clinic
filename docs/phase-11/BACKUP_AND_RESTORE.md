# Backup and restore

## What must be protected
Firestore (all clinical, financial, tenant data), Cloud Storage (lab reports, patient documents, report exports, logos), Firebase Auth users, the rules/indexes in Git, and secrets (held outside the repository).

## Proposed policy (for the business owner; **RPO and RTO are not agreed and must not be assumed**)
| Item | Proposal |
|---|---|
| Firestore | Managed point-in-time recovery enabled, plus a scheduled managed export to a separate, access-restricted bucket; retention to be set by the owner |
| Storage | Object versioning and soft-delete on the report/document bucket |
| Auth users | Periodic export of users (no passwords) under restricted access |
| Encryption | Provider-managed at rest; customer-managed keys only if the owner requires them |
| Access | A small named group; restore needs two approvers; every restore is a ticket |
| RPO / RTO | **To be agreed with the business owner.** The drill below gives a measured lower bound for the mechanics only |

## Restore procedure (production, to be rehearsed in staging first)
1. Declare the incident and freeze writes (maintenance mode or scale the backend to zero).
2. Choose the recovery point; for logical damage prefer restoring into a **new** database/project and comparing before switching.
3. Import the export (or use point-in-time recovery) into the target database.
4. Restore Storage objects if affected; check object counts and hashes (`sha256` is stored on lab reports and exports).
5. Redeploy the rules and indexes of the matching release (indexes rebuild takes time).
6. Run the smoke tests in `RELEASE_CHECKLIST.md`; compare record counts per collection.
7. Re-enable traffic; record the data-loss window for customer communication.

## Drill performed (non-production, emulator)
What was run: `backend/tool/restore_drill.dart` against the **local Firestore emulator**. It writes a deterministic data set, computes a SHA-256 over every document, exports the emulator, starts a **fresh** emulator that imports the export, reads everything back and compares.

| Measure | Result |
|---|---|
| Data set | 3,620 documents in 6 collections incl. a nested sub-collection, timestamps, nested maps and lists |
| Seed | 2.6 s |
| Export to disk | 1.3 MB; seed plus emulator start/stop wall time 37.5 s |
| Import into a fresh emulator plus full read-back | 2.7 s read-back; 8.2 s wall time including emulator start |
| Integrity | **3,620 of 3,620 documents, identical checksum (MATCH)** |

Limits of this evidence: it exercises the Firestore data model, serialization and export/import round trip, not Google's managed backup/PITR service, not Cloud Storage, not Auth, and not production-scale volumes. The measured seconds are **not** an RTO. A rehearsal of the managed procedure in a staging project is still required (F-05).
