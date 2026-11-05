# Implementation Roadmap

Source of truth for scope: `CLAUDE.md` §6 (modules) and §18 (phases). This file
adds the Phase 0 inventory result and the prerequisites per phase.

| Phase | Scope | Status (see IMPLEMENTATION_PROGRESS.md) |
|---|---|---|
| 0 | Foundation, architecture, design system | Merged into `develop` |
| 1 | Authentication and security foundation | Merged into `develop` |
| 2 | SaaS platform and multi-tenant management | Merged into `develop` |
| 3 | Clinic setup, branches, doctors, staff, RBAC | Merged into `develop` |
| 4 | Patient management, identity, family, consent | Merged into `develop` |
| 5 | Appointments, availability, queue | Merged into `develop` |
| 6 | Doctor workspace, consultation, prescriptions, follow-ups | Merged into `develop` |
| 7 | Billing, payments, refunds, expenses | Merged into `develop` (PR #4) |
| 8 | Patient Android application | Merged into `develop` (PR #5) |
| 9 | Laboratory management | Merged into `develop` (PR #6) |
| 10 | Notifications and operational reports | Merged into `develop` (PR #7) |
| 11 | Production readiness | Merged into `develop`; production **NOT READY** (open release gates) |
| 12 | Global architecture and country configuration | Implemented on `feature/phase-12-country-configuration`; PR pending |
| 13 | Internationalization and localization | Implemented on `feature/phase-13-internationalization` (stacked on 12); PR pending |
| 14 | Country compliance framework | Not started |
| 15 | Tax, invoicing and e-invoicing foundations | Not started |
| 16 | International payments | Not started |
| 17 | Healthcare integrations and national ecosystems | Not started |
| 18 | International identity and communications | Not started |
| 19 | Clinical localization and country workflows | Not started |
| 20 | Global SaaS administration and commercial operations | Not started |
| 21 | Regional hosting, data residency and security | Not started |
| 22 | Global release readiness and country launch certification | Not started |

Detailed per-phase scope for 12–22 lives in the phase prompts (`EazyClinic_Phase_NN_Implementation_Prompt.docx`).

## Phase 1 prerequisites (must be true before starting)

- [ ] Phase 0 reviewed and merged to `develop` (explicit approval).
- [ ] Firebase **dev** project created by the owner (no production project yet); project ID supplied.
- [ ] Spike result for F-1 (Admin SDK on Dart) agreed.
- [ ] Decisions on mockup conflicts: self-selected role, Google sign-in, patient login method (see UI_UX_REFERENCE_ANALYSIS §11).
- [ ] Decision on MFA scope for privileged users.
- [ ] Decision whether to upgrade Flutter/Dart first (TD-02).

## Cross-cutting rules per phase

Follow CLAUDE.md §16 (inspect → plan → design → implement → test → document → report). A phase is complete only when the end-to-end workflow works and is tested.

## Phase 6: Doctor workspace and clinical operations (branch `feature/phase-0-foundation`)
Implemented (see `docs/phase-6/`): doctor workspace, consultation lifecycle with amendments, diagnosis, vitals, prescriptions, templates, follow-ups, investigation-request boundary. Awaiting approval before Phase 7 (billing and payments).

## Phase 7: Billing, payments, refunds and expenses (branch `feature/phase-7-implementation`)
Implemented (see `docs/phase-7/`): service catalogue and tax rules, invoices with server-side paise arithmetic, payment collection and allocation, advance credit ledger, receipts, refunds, expenses, finance dashboard and reports, Clinic Web screens. Online payments (Razorpay), PDF output and patient-facing billing are deferred. Awaiting approval before Phase 8 (patient Android application).

## Phase 8: Patient Android application (branch `feature/phase-8-patient-app`)
Implemented (see `docs/phase-8/`): patient portal API, patient app screens, doctor-side summary release. Push delivery, documents and reports, online payment, PDF and release signing are deferred. Awaiting approval before Phase 9 (laboratory and documents).

## Phase 9: Laboratory management (branch `feature/phase-9-laboratory`)
Implemented (see `docs/phase-9/`): catalogue, orders, samples, results, verification, amendment, report publication, external reports, dashboard, audit, and screens in Clinic Web, Doctor Workspace and the patient app. Critical-value call-back, lab billing, barcodes, PDF layout and non-laboratory documents are deferred. Awaiting approval before Phase 10 (reports and notifications).

## Phase 10: Notifications and operational reports (branch `feature/phase-10-reports-notifications`)
Implemented (see `docs/phase-10/`): notification pipeline, templates, preferences, device tokens, reminders, administration, in-app centres, operational reports, dashboard and exports. Live FCM, external channels, an external scheduler, charts and several event types are deferred. Awaiting approval before Phase 11 (production readiness).

## Phase 11: Production readiness (branch `feature/phase-11-production-readiness`)
Audit, release gates as tests, CI, runbooks and a risk register are done (see `docs/phase-11/`). Verdict: **not ready**; the open gates need staging, an Android toolchain and keystore, managed backups, monitoring and a legal review. Release execution needs a separate explicit approval.
