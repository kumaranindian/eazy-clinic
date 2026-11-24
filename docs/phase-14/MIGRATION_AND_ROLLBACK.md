# Migration and Rollback

## Data
All collections are new and additive; no existing document changes. Clinics start with nothing applicable. There is no migration of existing doctor registration numbers into credentials (clinics add credentials; TD-114).

## Rollout (per environment, when approved)
1. Deploy `firestore.indexes.json` (two collection-group indexes: `compliance_applicability(profileKey,status)`, `compliance_evidence(status,uploadedAt)`) and wait for them to build.
2. Deploy backend and Clinic Web.
3. Super admin runs **Seed baseline registers** (create-if-absent) — the registers are *drafts*.
4. **Counsel reviews each register** (see `LEGAL_REVIEW_CHECKLIST.md`) and a super admin records the review through `PATCH …/profiles/{key}` (`legalReview`, requirement `confidence`/`reviewedOn`).
5. For each clinic, a reviewer confirms which registers apply; clinics then upload evidence.

## Rollback
* Redeploy the previous backend/apps: the new collections are ignored.
* To stop a register being used, set it `retired` (existing confirmed applicabilities keep it visible; new clinics do not see it).
* Wrong applicability: set it back with a reason (audited).
* No destructive action exists; evidence and history are retained.

## Known migration caveats
* Registers edited after clinics' approvals automatically invalidate approvals of *changed* requirements (by design) — plan reviewer capacity when publishing a new version, and read the impact report first.
