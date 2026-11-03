# Phase 4 Assessment

Date: 2026-11-03 · Branch `feature/phase-0-foundation` · Input: `EazyClinic_Phase_4_Implementation_Prompt.docx`.

## 1. Verified starting point
Phases 0–3 present and green: `scripts/check_all.sh` passed (backend 338 tests, Clinic Web 45) and the Firestore emulator suite passed (20 rules, 18 backend) before any Phase 4 change. Known earlier limits still stand: no live Firebase, Android builds blocked, indexes undeployed, invitation delivery not configured.

## 2. Reused (not duplicated)
| Need | Reused |
|---|---|
| Auth, account gate, memberships | Phase 1 `AuthModule.protect()`; Phase 3 `TenantContext` (tenant from trusted membership, `X-Tenant-Id` only a selector) |
| Branch scope | Phase 3 `BranchScope` (404 outside scope) |
| Limits | Phase 3 seat slots (`SeatKind.patients`, new) with `max_patients` |
| Storage of records, paging, audit ops, strict bodies | `DocumentStore`, `runPaged`, `BodyReader`, atomic ops |
| Private objects | Phase 3 `ObjectStorage` (documents) |
| RBAC | Phase 3 `ClinicPermission` / `ClinicRolePolicy` extended |
| UI | Phase 3 `ListScreen`, `Section`, `KeyValues`, shell, design system |

## 3. Existing patient models
None: `PermissionPolicy`/`Permission` (platform) have no patient concepts and `patients` only appeared as a denied path in rules tests. No model was duplicated.

## 4. Prerequisites resolved (minimum)
1. **Clinical vs administrative permissions.** Phase 3 gave the clinic admin "all but roles.manage". Medical history, allergies, medications and documents are now a separate clinical group that the admin does **not** hold by default (documented in the RBAC matrix).
2. `SeatKind.patients` (one enum value) for the patient limit.
3. A clinic setting `minorAgeYears` (default 18) so no legal age is hard-coded.

## 5. Key decisions (ADRs 034–040 in MASTER_ARCHITECTURE)
Global identity holds no clinical data; clinic-issued, hashed, single-use link codes; guardian verification is a staff attestation recorded with method, not legal proof; consent is an append-only backend service; revisions instead of overwrites; documents retained (soft removal); patient audit is tenant-scoped.

## 6. Risks found while designing
- Phone/e-mail similarity must never link or merge: linking needs an in-person identity check **and** a one-time code claimed by a verified-e-mail account.
- A family relationship must not become a back door: no clinic endpoint reads relationships and no relationship grants clinic access.
- Receptionists need contact data but not clinical data: lists are masked and clinical lists need clinical permissions.
- Search must not scan: identifier lookups are single equality queries; name search is a prefix range query.
- Firestore composite indexes (29 added) are not deployed or exercised on the emulator.

## 7. Testing strategy and dependencies
Backend tests with an in-memory store (privacy, isolation, escalation, consent, identity, family), a Firestore-emulator integration test, rules tests for every new collection, widget tests. No external service is needed. Live Firebase/Storage remain unverified.
