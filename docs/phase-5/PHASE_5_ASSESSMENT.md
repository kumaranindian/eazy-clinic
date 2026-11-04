# Phase 5 Assessment

Date: 2026-11-03 · Branch `feature/phase-0-foundation` (clean at start; Phases 0–4 merged to `develop` via PR #2) · Input: `EazyClinic_Phase_5` prompt.

## 1. Verified starting point
`scripts/check_all.sh` green (backend 411, Clinic Web 62); emulator suites green (24 rules, 19 backend) after Phase 4. Known limits unchanged: no live Firebase, indexes undeployed, Android builds not run.

## 2. Reused
| Need | Reused |
|---|---|
| Tenant/branch authorization | Phase 3 `TenantContext`, `BranchScope` (404 outside scope) |
| Doctors and branch assignments | Phase 3 `doctors` and the `doctor_branch_active/{doctorId_branchId}` uniqueness key (= "assigned and active") |
| Patients | Phase 4 `PatientSupport.load` (tenant + branch scoped) |
| Entitlements | `FeatureKey.appointments`, suspended/read-only gating in `resolveTenantContext` |
| Paging, strict bodies, atomic ops, audit | `runPaged`, `BodyReader`, `CreateOp/UpdateOp/DeleteOp`, platform audit (config changes) |
| UI | `ListScreen`, `Section`, shell, `showRecordDialog`, design system |

## 3. Prerequisites resolved (minimum)
1. **Time zones.** The backend has no tz database. Branch `timezone` (or the clinic setting, default `Asia/Kolkata`) is used with a **fixed-offset table**; zones with daylight-saving changes are refused with a clear 409 instead of guessing (TD-43). India has no DST.
2. **Settings:** `queueTokenPrefix`, `queueOrdering`, `checkInEarlyMinutes`, `checkInLateMinutes` added to clinic settings.
3. **Client:** `ApiClient.post` and the repository accept headers (Idempotency-Key).

## 4. Key decisions (ADRs 041–047)
- **Reservation documents** guard double booking (see `DOUBLE_BOOKING_PREVENTION.md`).
- Reschedule creates a **new appointment** and marks the old one `rescheduled` (history preserved).
- Schedules are versioned by effective dates; ending one keeps it.
- Exceptions never cancel appointments: they flag `needsAttention` and return the affected list.
- Token counters live on the queue document with per-token uniqueness keys.
- Live updates use **polling with version checks** (Firestore client access is deny-all by design) — TD-44.
- Appointment and queue audit use one tenant collection `appointment_audit_logs` (serves "appointment_history" and "queue_history").

## 5. Risks considered
Concurrent booking and token allocation (reservation + token keys, transactions, retries); a doctor in two branches at once (reservations are per doctor, not per branch); leave added over booked visits; check-in windows; role scoping (doctors act only on their own queue); idempotent retries; DST zones.

## 6. Testing strategy
In-memory backend tests (incl. `Future.wait` concurrency), Firestore-emulator integration test, rules tests, widget tests incl. polling. See `TEST_REPORT.md`.
