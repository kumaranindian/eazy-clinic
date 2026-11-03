# Phase 3 Security Review

| Control | Result |
|---|---|
| Tenant derived from trusted membership; header only a validated selector | Implemented, tested (cross-tenant tests for each resource) |
| Per-request permission check on every route | Implemented; route-by-route tests incl. each role |
| Branch scope (list filter, 404 outside, assignment bounds) | Implemented, tested |
| Role escalation: self-change, admin→admin, owner assignment/removal, last owner | Blocked, tested |
| Strict bodies; client-supplied tenantId/role/status/uid rejected | Tested |
| Invitation token: 256-bit, hash-only storage, expiry, single use, rotation, identity binding, generic errors | Tested |
| Subscription limits race-free | Seat slots; concurrency tested on the in-memory twin + create preconditions on the emulator |
| Logo upload: magic-byte sniffing, size cap, private bucket, authenticated read | Tested |
| Audit: atomic with change; no tokens/PII beyond identifiers | Tested |
| Rate limiting (writes, invites, accepts) | Per instance (TD-16) |
| Firestore/Storage rules deny-all | Emulator-tested (Firestore); Storage rules unchanged deny-all |

## Residual risks
- Live Firebase, deployed indexes/rules and a real object store are **unverified** (no production access).
- Invitation delivery is not configured; links are shared manually by the admin.
- Doctor registration numbers are not verified against councils.
- MFA for privileged clinic users, owner transfer, custom roles and a tenant-facing audit viewer are deferred.
- Rate limits are per instance.

No unresolved tenant-isolation, branch-authorization, invitation-security or RBAC defect is known.
