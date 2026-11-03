# Phase 3 Firestore Schema

All under `tenants/{tenantId}/`. Client access is denied by rules; only the backend (service credentials) reads/writes.

| Collection | Key fields |
|---|---|
| `profile`/clinic doc | name, type, specialities, contact, address, logo metadata, status, version |
| `settings/config` | timeZone, weeklyHours, holidays, specialDays, durations |
| `branches/{branchId}` | name, code, type, address, contact, weeklyHours?, status, createdBy/updatedBy, timestamps |
| `branch_codes/{code}` | uniqueness key (branchId) |
| `doctors/{doctorId}` | profile fields, status, accountUid? (set only via invitation), version |
| `doctor_branch_assignments/{id}` | doctorId, branchId, status, uniqueness key doc |
| `staff/{staffId}` | profile, intendedRole, branchIds, status, accountUid? |
| `members/{uid}` | role, status, allBranches, branchIds, doctorId?/staffId? |
| `invitations/{id}` | kind, email, role, branch scope, `tokenHash`, expiresAt, status, acceptedBy? (no plaintext token) |
| `seats/{kind}_{n}` | slot documents enforcing subscription limits atomically |
| audit | `platform_audit_logs` entries with `tenantId`, written atomically with each change |

Indexes (13 added) are in `firebase/firestore.indexes.json`, incl. a collection-group field override for `invitations.tokenHash`. **Not deployed** (no production Firebase access). Rules: deny-all; emulator tests cover every Phase 3 collection, invitation lookup, and member self-edit.
