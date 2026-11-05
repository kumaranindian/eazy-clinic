# Architecture and Data Model

## 1. Concepts

| Concept | Meaning |
|---|---|
| **Register (profile)** | A versioned list of requirements for one *country + jurisdiction + authority/domain* (e.g. `ae-dha-dubai`). Platform-managed. Says what to evidence, never that a clinic complies |
| **Requirement** | One item in a register: category (`statutory`, `contractual`, `platform_control`, `optional_integration`), subject (`facility`, `practitioner`, `platform`), evidence rules (required, kinds, expiry tracked), go-live-blocking flag, source, owner, confidence, draft/review dates |
| **Applicability** | Whether a register applies to a given clinic: `unknown` (default), `applies`, `not_applicable`. Set only by a platform reviewer, only for registers of the clinic's country |
| **Item** | A clinic's record for one requirement (status, evidence link, expiry, reviewer) |
| **Evidence** | A file a clinic uploads for a requirement (or credential), with its own status |
| **Credential** | A facility or practitioner licence/registration record with authority, number, validity, document, verification |

## 2. Collections

Platform:
* `compliance_profiles/{key}` — `key, title, countryCode, jurisdiction, authority{code,name,url}, domain, facilityTypes[], appliesWhenNote, requirements[], status (published|retired), version, effectiveFrom, legalReview{status (pending|reviewed), reviewedBy, reviewedOn, notes}, updatedBy/At`.
* `compliance_profiles/{key}/versions/{n}` — full snapshot + `reason` + `impact{added[], removed[], changed[], tenantsAffected, generatedAt}`.

Per clinic (`tenants/{t}/…`):
* `compliance_applicability/{profileKey}` — `status, reason, setBy, setAt, profileVersionAtSet`.
* `compliance_items/{profileKey}__{requirementKey}` — `status, evidenceId, expiresAt, profileVersion, requirementHash, reviewedBy/At, note`.
* `compliance_evidence/{evidenceId}` — `profileKey/requirementKey` **or** `credentialId`, `kind, title, documentNumber, issuerName, validFrom, validTo, mime, sizeBytes, sha256, storagePath, status (submitted|accepted|rejected|superseded), uploadedBy/At, reviewedBy/At, reviewNote`.
* `compliance_credentials/{id}` — `subjectType (facility|practitioner), subjectName, doctorId?, kind, authorityCode/Name, jurisdiction, number, issuedOn, validFrom, validTo, evidenceId, verification{status (unverified|verified|rejected), by, at, note}, status (active|archived)`.
* `compliance_history/{auto}` — append-only log of actions (`type, actorUid, actorRole, profileKey, requirementKey, evidenceId, credentialId, detail, at`), including every evidence file view.

Files: `tenants/{t}/compliance/{evidenceId}` in the private bucket. Clients never see `storagePath` or `sha256`.

## 3. Status model

`not_assessed → pending_evidence → under_review → approved | rejected`; `approved → expired`; `any → not_applicable` (reviewer, with reason); `not_applicable → pending_evidence` (reviewer).
* A clinic upload always puts the requirement `under_review` (even if it was approved: the old approval no longer counts).
* **Effective status** (computed on every read): an approval whose `expiresAt` has passed is `expired`; an approval whose requirement changed since (hash differs) is `pending_evidence` with `requirementChanged`. Nothing needs to run for an expiry to show, and no stale approval can render.
* The expiry scan persists `expired` and records it once.

## 4. Readiness (never "compliant")

Per clinic, over registers whose applicability is `applies`:
`applicability_unconfirmed` (none confirmed) → `awaiting_legal_validation` (any applicable register not marked reviewed) → `incomplete` (any non-N/A requirement not approved) → `all_required_evidence_approved`. Also `country_not_assigned`. The last value is the best state; it is worded "all required evidence has been approved by a reviewer; this is not a certification and not legal advice". There is no boolean or label meaning "compliant".

## 5. Versioning and impact

A register update (`PATCH`) needs `expectedVersion` and a `reason`, bumps the version, snapshots it and computes: requirements `added`, `removed`, `changed` (by meaning hash) and the number of clinics where the register applies. `GET …/impact` returns the live list of affected clinics and the last change. `key`, `countryCode` and `jurisdiction` are fixed (a different scope is a different register). Marking a register `reviewed` requires reviewer and date; a `high`-confidence requirement requires a `reviewedOn` date.

## 6. Credentials and expiry
`valid` / `expiring` (≤ 60 days) / `expired` / `noExpiry`. `verifiedAndValid` is true only while a reviewer's verification stands **and** the credential is within its validity. Changing what was verified (kind, authority code, number, dates, jurisdiction) voids the verification; so does attaching a new document. Alerts at 60, 30, 7 days and expiry, to active owners and admins, through `NotificationHub.emit` (event type `compliance_expiry`, essential category) with the dedupe key `compliance:{cred|item}:{id}:{threshold}:{validTo}:{uid}`. Alert text is generic and contains no licence number or name. The worker `tick` calls `compliance.scanExpiries(tenantId)` for every active clinic through `hub.tenantScans`.

## 7. Components
`backend/lib/features/compliance/`: `compliance_core.dart` (pure rules), `compliance_baseline.dart` (draft registers), `compliance_profile_service.dart` (platform registers), `tenant_compliance_service.dart` (applicability, evidence, items, credentials, scan, overview), `compliance_routes.dart` (clinic routes; platform routes live in `PlatformModule`).
Clinic Web: `features/compliance/` (clinic page, platform overview and reviewer pages, labels, providers).

## 8. Permissions
Clinic: `compliance.view` (read), `compliance.manage` (upload/credentials) — owner and admin by default (receptionist, nurse, accountant, lab tech, pharmacist, doctor: none). Platform: `platform.compliance.read` (Super Admin, Support), `platform.compliance.manage` (registers; Super Admin), `platform.compliance.review` (applicability, evidence, credentials, evidence files; Super Admin).
