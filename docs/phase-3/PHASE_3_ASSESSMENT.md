# Phase 3 Assessment

Date: 2026-11-03 · Branch `feature/phase-0-foundation` (clean; 16 commits ahead of origin, unpushed) · Input: `EazyClinic_Phase_3_Implementation_Prompt.docx` (read in full).

## 1. Verified starting point
`backend` 237 tests pass (+16 emulator tests, 18 rules tests passed at the end of Phase 2). Prior phases are implemented as documented; Phase 1/2 limitations stand (no live Firebase, Android SDK blocked, indexes not deployed).

## 2. What exists and is reused
| Need | Existing | Use |
|---|---|---|
| Auth, account gate, `AuthContext` with server-resolved memberships | Phase 1 `AuthModule.protect()`, `MembershipAccessResolver` | All Phase 3 routes sit behind it |
| Tenant owner membership | `tenants/{id}/members/{uid}` (role `clinic_owner`, `branchIds: []`) created by provisioning | Becomes the single source of truth for role + branch scope |
| Tenant + subscription state, limits, features | Phase 2 `EntitlementService` (`assertFeature`, `assertWithinLimit`, access levels) | Gate every tenant route; enforce max branches/doctors/staff |
| Storage of documents, queries, paging, audit | `DocumentStore`, `runPaged`, `BodyReader`, `AuditService` | Reused unchanged (+ one addition below) |
| Clinic roles | `ClinicRole` enum, empty `PermissionPolicy.forClinicRole` | Filled with the clinic permission catalog |
| UI | design system, `ListScreen`, `Section`, `KeyValues`, `ApiClient`, shell/redirect hooks | Clinic administration screens in Clinic Web |

## 3. Gaps / prerequisites resolved here (minimum only)
1. **Memberships carry no permissions or "all branches" flag.** Add `allBranches` (explicit) and role/status handling; owner memberships created by Phase 2 (`branchIds: []`) are read as all-branches (backward compatible, no migration).
2. **Limits cannot be enforced race-free with count-then-create.** Add atomic *seat slots* (see §5) and a `DeleteOp` to `DocumentStore` (used only for seat release).
3. **No object storage client** for the logo. Add a small `ObjectStorage` interface (Cloud Storage JSON API via ADC, in-memory double for tests); bucket from `STORAGE_BUCKET`.
4. **No mail/SMS channel.** Invitations are fully implemented (hashed single-use tokens, expiry, identity binding), but **delivery is a documented blocker**: the API returns the one-time link to the authorized admin for manual sharing and reports `delivery: "not_configured"`. No fake delivery success.

## 4. Key decisions (ADRs 026–032 in MASTER_ARCHITECTURE)
- **026 Roles:** predefined roles only. Custom roles are **deferred** (documented); permission catalog is an allow-list of tenant permissions, platform permissions can never appear in it.
- **027 Permission source of truth:** `ClinicPermission` catalog + role matrix in `common_models` (one place). Membership stores the role (and later overrides); effective permissions are computed server-side per request.
- **028 Authority rules:** nobody changes their own role/branches; only the owner assigns/removes `clinic_admin`; admins manage non-admin roles; the owner role is immutable through APIs (ownership transfer **deferred**), which also guarantees the last-owner invariant (still checked defensively).
- **029 Branch scope:** `allBranches` or an explicit `branchIds` list on the membership. A scoped actor sees/changes only resources in their branches; out-of-scope ids answer 404 (existence hidden). The selected branch in the UI is a hint only.
- **030 Seats:** `tenants/{id}/seats/{kind}_{n}` slot documents created with a does-not-exist precondition in the **same atomic commit** as the entity; limit = number of slots; race → retry. Releasing a seat deletes the slot.
- **031 Invitations:** top-level data under `tenants/{id}/invitations/{id}` holding only `tokenHash` (SHA-256 of a 256-bit secret). Acceptance finds the invitation by collection-group query on `tokenHash`, requires an authenticated, e-mail-verified account whose e-mail equals the invitation's, and is single-use inside a transaction.
- **032 Doctor ≠ branch:** one `doctors/{id}` profile, relationship rows in `doctor_branch_assignments`.

## 5. Security risks and mitigations
| Risk | Mitigation |
|---|---|
| Cross-tenant access | Tenant derived from the caller's membership (`X-Tenant-Id` selector validated); every document path is built from that tenant id; cross-tenant ids are never looked up |
| Branch bypass via ids in query/body | Scope check in the service layer on every read/write; list queries filtered server-side |
| Privilege escalation (self-grant, admin→owner, platform perms) | Authority rules above; catalog excludes platform permissions; request bodies reject unknown fields |
| Invitation takeover/replay | Hashed secret, expiry, single use (transaction), e-mail binding, scope fixed at creation, generic failure message |
| Limit bypass by concurrency | Seat slots with create preconditions |
| Account/membership confusion | Membership changes never touch Firebase accounts; deactivation sets member status only (+ session revoke of that user is optional/deferred) |
| Suspended/expired tenants operating | Tenant guard maps access level: blocked → 403 for all, read-only → writes refused |
| Logo abuse | Type sniffing (PNG/JPEG/WebP magic bytes), size cap, tenant-scoped object path, no public URL, served through an authenticated endpoint |

## 6. Implementation breakdown (commit plan)
1. Catalog, role matrix, `DeleteOp`, seat service, tenant guard, `allBranches`. 2. Clinic profile + settings + operating hours + logo. 3. Branches. 4. Doctors + assignments. 5. Staff. 6. Invitations (+ doctor association). 7. Members/roles/permissions APIs. 8. Security tests. 9. Clinic administration UI. 10. Docs.

## 7. Testing strategy
Service tests on the in-memory store; HTTP-level tests with real signed tokens and several tenants/roles (matrix test over every route, negative security suite from §15 of the brief); Firestore-emulator tests for the new store primitives (`DeleteOp`, seats, collection-group `tokenHash`) and the full flow; rules tests for new collections; widget tests for screens. Nothing is claimed that is not executed.

## 8. External configuration
`STORAGE_BUCKET` (Cloud Storage bucket per environment); indexes in `firestore.indexes.json` must be deployed; mail/SMS provider for invitation delivery (not configured); live Firebase verification still pending (TD-17).
