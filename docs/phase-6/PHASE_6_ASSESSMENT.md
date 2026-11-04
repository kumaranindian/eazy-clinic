# Phase 6 Assessment — Doctor Workspace, Consultation, Diagnosis, Prescriptions, Follow-up

Written before implementation (2026-11-03) from inspection of the repository at commit `c939a5f`.

## What already existed (reused, not rewritten)
- Tenant/branch context (`TenantContext`, `BranchScope`), RBAC catalogue (`ClinicPermission`, `ClinicRolePolicy`), feature gating (`FeatureKey.doctorWorkspace`, `appointments`).
- Patient registry, allergies, medications, history, alerts, consent (`data_processing`) and patient audit (Phase 4).
- Appointments, queue and tokens (`AppointmentService`, `QueueService`) and doctor availability (Phase 5).
- Doctor app shell with sign-in only (`apps/doctor_mobile`), `app_core` `ApiClient`, design system.

## Gaps found
| Gap | Decision |
|---|---|
| No consultation, diagnosis, prescription, vitals, template or follow-up model | New `clinical` backend feature |
| Doctor member record carries `doctorId` but nothing used it for authorship | `requireDoctorSelf` / `requireAuthor` (ADR 048) |
| No clinical permissions; admin must not read clinical text by default | 15 new permissions, admin excluded (`_clinical` set) |
| No diagnosis/medicine catalogues | Ship empty; clinic-managed. No codes are invented |
| Laboratory (Phase 9) does not exist | Investigation *requests* only, `processing: not_available` |
| Doctor app had only a home page | Navigation shell + 8 workspace screens |

## Out of scope (not built)
Billing/payments, patient app, notifications, laboratory results, AI features, ABDM, PDF generation, e-signature.

## Risks accepted
See `TECHNICAL_DEBT.md` TD-49…TD-56.
