# Phase 14 – Country Compliance Framework: Implementation Plan

Branch `feature/phase-14-compliance-framework` (stacked on `feature/phase-13-internationalization`, which is stacked on Phase 12). Date: 2026-11-05.
Specification: `EazyClinic_Phase_14_Implementation_Prompt.docx`.

> **Branch note.** As in Phases 12–13, this phase has its own branch and is delivered by pull request (user instruction); the prompt's "stay on `feature/phase-0-foundation`" rule was not followed for that reason. Merge 12 → 13 → 14 in order.

> **Not legal advice.** EazyClinic organises *evidence*. The registers delivered here are working drafts by the product team. They have **not** been validated by counsel or any regulator. The product never states that a clinic is compliant, licensed, certified or approved, and contains no live ABDM or UAE exchange integration.

## 1. Pre-flight findings

| Area | Finding |
|---|---|
| Country foundation | Phase 12 gives each tenant a server-set legal country; compliance can key off it |
| Existing credentials | Doctors have a registration number (Phase 3) but no authority, validity, evidence or verification; there is no facility licence record |
| Documents | Secure upload/download patterns exist (base64 JSON, magic-byte checks, private object storage, authenticated download); patient documents, lab reports and the clinic logo use them |
| Events | Notification hub with event outbox, dedupe keys, staff recipients and a worker `tick` per active clinic |
| Platform admin | Role-gated platform area; permission catalogue; audit service |
| Nothing existed for | requirements registers, applicability, evidence review, expiry alerts, credential verification |

## 2. Design principles (from the prompt)

1. **No false compliance badge.** There is no "compliant" value. A requirement can only be `approved` after a *platform reviewer* accepts evidence; an approval stops counting when it expires or when the requirement it approved changes. Overall readiness is described in words that never claim compliance, and an unvalidated register caps readiness at "awaiting legal validation".
2. **Safe defaults.** Unknown applicability = nothing applies. A requirement with no record is `not_assessed`. A profile is a draft (`legalReview: pending`, `confidence: low`) until counsel review is recorded with reviewer and date.
3. **Applicability is configurable, never assumed.** Registers are per country, jurisdiction, authority and (optionally) facility type; the UAE is *not* hard-coded to DHA.
4. **Separation of duties.** Clinics upload; platform reviewers approve. A clinic owner cannot approve its own evidence.
5. **Versioned and traceable.** Every register change is a new version with reason, snapshot and a tenant impact report.

## 3. Delivered

* Compliance domain model, statuses, transition table, effective-status logic, expiry thresholds (60/30/7/expired).
* India and UAE baseline registers (8 profiles, 30 requirements) with source, owner, confidence, review fields; ABDM readiness checklist marked "no integration".
* Platform API: register list/read/versions/impact/update/seed, overview, review queue, per-clinic dashboard, applicability, evidence review, requirement status, credential verification.
* Clinic API: dashboard, evidence upload/list/download, credentials create/update/archive/document, history.
* Practitioner and facility credential register with authority, number, validity, evidence, verification, expiry state.
* Expiry alerts via the notification hub worker (owners and admins, generic text, deduplicated).
* Clinic Web: clinic Compliance page; platform Compliance overview, review queue and per-clinic reviewer screen.
* Governance: legal-review checklist, requirements registers document, tests, ADRs 095–100, TD-109…TD-115.

## 4. Exclusions (per the prompt)
Legal advice; certification; regulator submissions; live ABDM or UAE exchange integration; automatic legal interpretation; replacing counsel review.

## 5. Test plan
Unit (status logic, thresholds, mime detection, baseline content), API (permissions, validation, workflow, tenant isolation, audit, expiry), widget (clinic and platform screens), full regression. Results: `TEST_REPORT.md`.
