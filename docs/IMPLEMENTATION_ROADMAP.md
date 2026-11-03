# Implementation Roadmap

Source of truth for scope: `CLAUDE.md` §6 (modules) and §18 (phases). This file
adds the Phase 0 inventory result and the prerequisites per phase.

| Phase | Scope | Main deliverables | Status |
|---|---|---|---|
| **0** | Foundation, architecture, design system | Monorepo, 3 app shells, backend skeleton, shared packages, design system, docs | **Implemented, pending approval** |
| 1 | Foundation and authentication | Firebase projects (dev), Admin SDK on backend, ID-token verification, login/sign-up flows, API client, error/logging plumbing, session handling, MFA design | Not started |
| 2 | Multi-tenant and clinic setup | Tenants, clinic registration + approval, branches, clinic settings, subscription foundation | Not started |
| 3 | Clinic setup, branches, doctors, staff, RBAC | Clinic profile/hours, branches, doctors + assignments, staff, invitations, centralized RBAC, branch-scoped access | **Implemented locally** (live Firebase, invitation delivery, custom roles, owner transfer deferred/unverified) |
| 4 | Patient management | Patient registry, patient accounts, linking, family, history, consent, documents | **Implemented locally** (vitals, merge, patient app, live Firebase deferred/unverified) |
| 5 | Appointments and queue | Availability, slots, booking, reschedule, cancel, tokens, queue | Not started |
| 6 | Clinical operations | Consultation lifecycle, diagnosis, templates, prescriptions, follow-ups | Not started |
| 7 | Billing and payments | Invoices, payments, Razorpay, receipts, refunds, expenses | Not started |
| 8 | Patient Android app | Onboarding, auth, discovery, booking, history, queue, Rx, reports, notifications | Not started |
| 9 | Laboratory and documents | Catalogue, orders, results, uploads, documents | Not started |
| 10 | Reports and notifications | Dashboards, reports, FCM, reminders, preferences | Not started |
| 11 | Production readiness | Security audit, tenant-isolation tests, performance, backup validation, monitoring, deploy | Not started |

## Phase 1 prerequisites (must be true before starting)

- [ ] Phase 0 reviewed and merged to `develop` (explicit approval).
- [ ] Firebase **dev** project created by the owner (no production project yet); project ID supplied.
- [ ] Spike result for F-1 (Admin SDK on Dart) agreed.
- [ ] Decisions on mockup conflicts: self-selected role, Google sign-in, patient login method (see UI_UX_REFERENCE_ANALYSIS §11).
- [ ] Decision on MFA scope for privileged users.
- [ ] Decision whether to upgrade Flutter/Dart first (TD-02).

## Cross-cutting rules per phase

Follow CLAUDE.md §16 (inspect → plan → design → implement → test → document → report). A phase is complete only when the end-to-end workflow works and is tested.
