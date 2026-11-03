# Database Schema (Cloud Firestore)

Status: **Documented only.** No collections, seed data or indexes exist yet.
Collections are created phase by phase, each with its indexes and tests.

## 1. Conventions

- **Path layout (ADR-006):** platform data at top level; tenant data as subcollections under `tenants/{tenantId}/…`; global patient identity at top level. The 36 logical collections in CLAUDE.md §9 map as below.
- **IDs:** stable, server-generated opaque IDs (auto-ID) unless noted (`members/{uid}`, `platform_subscriptions/{tenantId}`).
- **Common fields (all documents):** `createdAt`, `updatedAt` (server timestamps), `createdBy`, `updatedBy` (uid), `status` (explicit enum string), `schemaVersion`. Tenant documents also carry `tenantId`; branch-scoped ones carry `branchId`. Soft deletion via `status`/`deletedAt`; clinical and financial records are never hard-deleted by the app.
- **Writes:** all via backend; sensitive workflows use transactions/batched writes. Client access: none (deny-all rules).
- **Money:** integer minor units (paise) + currency code `INR`; never floating point.
- **Dates:** UTC timestamps; clinic-local day boundaries derived from `clinic_settings.timezone` (default `Asia/Kolkata`).
- **PII minimisation:** do not copy patient identity into other documents; store `patientId` references and fetch. Where a denormalised display name is unavoidable (e.g. queue display), document it and treat it as PII for logging/retention.
- **Audit:** every sensitive read/write also writes an `audit_logs` entry (append-only).

Legend for *Access*: **B** = backend only (always); roles listed are the ones the backend will allow, subject to RBAC and consent.

## 2. Platform-level collections

| Collection | Purpose | Important fields | Access | Query patterns / indexes | Retention |
|---|---|---|---|---|---|
| `platform_users/{uid}` | **Identity record of every account** (Phase 1, ADR 014): `uid`, `displayName`, `email`, `emailVerified`, `accountStatus` (pending, active, suspended, disabled), `createdAt`, `updatedAt`, `lastLoginAt?`, `phoneNumber?`, `profileImageUrl?`, `platformRole?` (super_admin, platform_support_admin; server-assigned only). See `docs/authentication/ACCOUNT_IDENTITY_MODEL.md` | as listed | B only (written by the backend; never by clients) | by uid (get) | Life of account + audit period |
| `tenants/{tenantId}` | Clinic organisation root | `name`, `legalName`, `status` (pending_approval, active, suspended, cancelled), `planId`, `ownerUid`, `contact`, `address`, `createdVia`, `approvedBy/At` | Platform roles; tenant owner/admin (own tenant, limited fields) | list by `status` + `createdAt desc` (platform dashboard) → composite index (status, createdAt) | Retain after cancellation per policy; export before deletion |
| `subscription_plans/{planId}` | Plan catalogue | `name`, `priceMinor`, `interval`, `limits{branches,doctors,staff}`, `features[]`, `active` | Read: any authenticated user via backend (pricing); write: platform | list active | Permanent (versioned) |
| `platform_subscriptions/{tenantId}` | Tenant's subscription state | `planId`, `status` (trialing, active, past_due, suspended, cancelled), `trialEndsAt`, `currentPeriodEnd`, `razorpaySubscriptionId?`, `limitsOverride` | Platform; tenant owner (read own) | get by tenantId; list by `status` + `currentPeriodEnd` (renewal job) → index | 8 years (financial) |
| `platform_audit_logs/{logId}` | Append-only audit of platform actions; Phase 1 writes authentication security events (`event`, `uid`, `actorUid`, `requestId`, `outcome`, `reason`, `timestamp`) | `actorUid`, `action`, `targetType/Id`, `tenantId?`, `ip?`, `userAgent?`, `before/after` (non-clinical) | Platform Super Admin read; never update/delete | by `tenantId` + `at desc`; by `actorUid` + `at desc` → indexes | ≥ 3 years, immutable |
| `clinic_invites/{inviteId}` | Invitations (staff/doctor) and patient-link codes before a membership exists | `tenantId`, `type` (staff, doctor, patient_link), `email/phoneHash`, `role`, `branchIds`, `tokenHash`, `expiresAt`, `status`, `invitedBy` | B; tenant owner/admin create | lookup by `tokenHash`; list by `tenantId` + `status` → index | Delete/expire after 30 days after use |

## 3. Tenant-level collections (`tenants/{tenantId}/…`)

Access for all rows below also requires: valid token → active membership → branch scope → permission → (clinical data) relationship/consent → audit.

### 3.1 Configuration and people

| Collection | Purpose | Important fields | Roles (default, configurable) | Queries / indexes | Retention |
|---|---|---|---|---|---|
| `clinic_settings/{singleton "main"}` | Clinic profile and configuration | `profile` (logo path, contact, address), `timezone`, `workingHours`, `holidays[]`, `appointmentPolicy`, `invoiceConfig` (prefix, tax IDs, footer), `taxConfig`, `specialties[]`, `notificationPrefs` | Owner/Admin write; staff read | get | Life of tenant |
| `branches/{branchId}` | Physical locations | `name`, `code`, `address`, `phone`, `workingHours`, `status` | Owner/Admin write; members read their branches | list by `status`; | Life of tenant |
| `members/{uid}` | Membership of a user in the tenant | `uid`, `role`, `permissionOverrides`, `branchIds[]` (empty = all), `status` (invited, active, deactivated), `doctorId?`, `staffId?`, `lastLoginAt` | Owner/Admin manage; user reads own | **collection group** `members` where `uid == X` (tenant discovery) → collection-group index; list by `role`,`status` | Keep after deactivation (audit) |
| `roles/{roleId}` | Tenant role definitions with permission sets (extends platform defaults) | `key`, `label`, `permissions[]`, `system` (bool) | Owner | list | Life of tenant |
| `doctors/{doctorId}` | Doctor profile | `uid?`, `displayName`, `qualifications[]`, `registrationNo` + `council`, `specialties[]`, `consultationFeeMinor`, `branchAssignments[]`, `availability` (weekly rules), `slotMinutes`, `signaturePath`, `status` | Owner/Admin write; doctor edits own non-critical fields; staff read | by `branchId` + `status`; by specialty → indexes | Life of tenant |
| `staff/{staffId}` | Non-doctor staff profile | `uid?`, `displayName`, `role`, `phone`, `branchIds`, `status` | Owner/Admin | by `branchId`+`status` | Life of tenant |

### 3.2 Patients, family and consent

| Collection | Purpose | Important fields | Access | Queries / indexes | Retention |
|---|---|---|---|---|---|
| `patients/{patientId}` | **Clinic-specific** patient record (registration + demographics) | `uhid` (clinic-unique readable ID), `name`, `dob`/`ageApprox`, `sex`, `phone`, `email?`, `address?`, `emergencyContact?`, `patientAccountId?` (if linked), `registeredBranchId`, `status` | Reception/Admin/Doctor/Nurse per permission; Accountant limited (name, uhid, contact) | by `uhid` (exact); **search** by name prefix / phone: exact `phoneHash` + `nameLower` prefix (Firestore has no full-text; define search strategy in Phase 4); list by `registeredBranchId` + `createdAt` → indexes | Medical records: per Indian clinical-record retention guidance (confirm with counsel; assume ≥ 3 yrs, commonly longer); do not hard-delete |
| `patient_accounts/{accountId}` (**top-level**) | Global patient/caregiver identity (see MULTI_TENANT §6) | `uid` (Firebase), `phoneVerified`, `name`, `dob?`, `sex?`, `status`, `kyc?` (future ABHA reference, only once integrated) | Patient themself; B | by `uid`; by `phoneHash` (matching for *proposals only*, never authorization) → index | Until account deletion request; then anonymise |
| `patient_links/{linkId}` (**top-level**) | Verified link: account ↔ clinic patient record | `accountId`, `tenantId`, `patientId`, `status` (pending, active, revoked), `verification{method, verifiedBy, verifiedAt}`, `consentId` | B; patient sees own links; clinic staff see own tenant's | by `accountId`; by `tenantId`+`patientId` → indexes | Keep after revoke (audit) |
| `family_relationships/{id}` (**top-level**) | Guardian/caregiver ↔ dependent (account-level) | `guardianAccountId`, `dependentAccountId`, `relationship`, `scope[]`, `status`, `consentId`, `expiresAt?` | B; both parties see their own | by `guardianAccountId`; by `dependentAccountId` → indexes | Keep after revoke |
| `consents/{consentId}` | Recorded, revocable consents/authorizations. Clinic-facing consents live here; **account-level consents (family/caregiver) live in `patient_accounts/{accountId}/consents`** with the same shape | `subject{accountId|patientId}`, `grantee{tenantId|accountId}`, `purpose`, `scope[]`, `grantedAt`, `revokedAt?`, `textVersion`, `capturedBy` | B; patient can list/revoke own | by `subject` + `status` → index; collection-group by `accountId` | Immutable history; ≥ DPDP requirements |

### 3.3 Appointments and queue

| Collection | Purpose | Important fields | Roles | Queries / indexes | Retention |
|---|---|---|---|---|---|
| `appointment_slots/{slotId}` | Generated bookable slots (or derived on demand) | `doctorId`, `branchId`, `start`, `end`, `status` (open, held, booked, blocked), `appointmentId?` | Reception/Doctor write via backend | by `doctorId`+`branchId`+`start` range+`status` → composite index | 90 days after date |
| `appointments/{appointmentId}` | Appointment | `patientId`, `doctorId`, `branchId`, `slotId?`, `start`, `type`, `status` (booked, confirmed, checked_in, in_consultation, completed, cancelled, no_show, rescheduled), `source` (reception, patient_app), `cancelReason?`, `idempotencyKey` | Reception, Doctor (own), Admin; patient via app for own | by `doctorId`+`start`; by `branchId`+`start`+`status`; by `patientId`+`start desc` → indexes | Same as clinical records |
| `queue_entries/{entryId}` | Daily token/queue row | `date` (clinic-local), `branchId`, `doctorId`, `tokenNo`, `appointmentId?`, `patientId`, `status` (waiting, in_consultation, completed, cancelled, no_show), `calledAt`, `displayName` (denormalised for display screen) | Reception, Nurse, Doctor | by `branchId`+`doctorId`+`date`+`status` ordered by `tokenNo` → index; token counters use a transaction on `queue_counters/{date_branch_doctor}` | 90 days |

### 3.4 Clinical

| Collection | Purpose | Important fields | Roles | Queries / indexes | Retention |
|---|---|---|---|---|---|
| `consultations/{id}` | Consultation lifecycle Draft → In Progress → Finalized → Amended | `patientId`, `appointmentId?`, `doctorId`, `branchId`, `status`, `chiefComplaint`, `symptoms`, `examination`, `observations`, `treatmentPlan`, `doctorNotes`, `followUpAdvice`, `templateId`+`templateVersion`, `finalizedAt/By`, `amendments[]` (or subcollection `revisions/{rev}` preserving originals with `reason`, `author`, `at`) | Doctor (author) write; Nurse limited (vitals); others per permission | by `patientId`+`createdAt desc`; by `doctorId`+`status`+`updatedAt` → indexes | Long-term; immutable after finalize except via amendment |
| `diagnoses/{id}` | Coded/free-text diagnoses per consultation | `consultationId`, `patientId`, `code?` (e.g. ICD-10), `label`, `type` (provisional/final), `recordedBy` | Doctor | by `consultationId`; by `patientId` | As consultation |
| `prescriptions/{id}` | Prescription authorised by a doctor | `consultationId`, `patientId`, `doctorId`, `items[{medicineId?, name, dose, frequency, duration, route, instructions}]`, `status` (draft, issued, cancelled), `issuedAt`, `pdfPath?`, `authorizedBy` | Doctor write; Pharmacist/Reception read (issued); patient via link | by `patientId`+`issuedAt desc`; by `consultationId` | As consultation |
| `medicine_catalogue/{id}` | Clinic medicine list (seeded from a vetted source; clinic-editable) | `name`, `genericName`, `form`, `strength`, `defaultRoute`, `active`, `source` | Doctor read; Admin manage | prefix search on `nameLower` → index | Life of tenant |
| `clinical_templates/{id}` | Configurable consultation templates (General Medicine, Paediatrics, Dentistry, Dermatology, Gynaecology, Physiotherapy) | `specialty`, `version`, `fields[{key,label,type,required,options}]`, `status` | Admin manage; Doctor read | by `specialty`+`status` | Versions kept forever (consultations reference them) |
| `medical_histories/{patientId}` | Clinic's longitudinal history summary | `allergies[]`, `chronicConditions[]`, `pastSurgeries[]`, `familyHistory`, `medications[]`, `updatedBy` | Doctor/Nurse write; Reception restricted | get | As patient |
| `vitals/{id}` | Vitals entries | `patientId`, `consultationId?`, `recordedAt`, `bp`, `pulse`, `tempC`, `spo2`, `weightKg`, `heightCm`, `recordedBy` | Nurse/Doctor | by `patientId`+`recordedAt desc` | As patient |
| `followups/{id}` | Follow-up tracking | `patientId`, `doctorId`, `consultationId`, `dueDate`, `status` (scheduled, reminded, completed, missed, cancelled), `appointmentId?` | Doctor/Reception | by `branchId`+`status`+`dueDate` → index (reminder job) | 1 year after completion (or as patient) |

### 3.5 Laboratory and documents

| Collection | Purpose | Important fields | Roles | Queries / indexes | Retention |
|---|---|---|---|---|---|
| `lab_orders/{id}` | Lab test orders | `patientId`, `consultationId?`, `tests[{code,name}]`, `status` (ordered, sample_collected, in_progress, resulted, reviewed, cancelled), `orderedBy`, `chargeRef?` | Doctor order; Lab tech update | by `status`+`createdAt`; by `patientId` → indexes | As patient |
| `lab_results/{id}` | Results and uploaded reports | `orderId`, `patientId`, `values[{test,value,unit,refRange,flag}]`, `reportDocumentId?`, `enteredBy`, `reviewedBy/At` | Lab tech write; Doctor review; patient via link after review | by `orderId`; by `patientId` | As patient |
| `documents/{id}` | Metadata for stored files | `patientId?`, `consultationId?`, `kind` (report, prescription_pdf, certificate, upload), `storagePath` (`tenants/{t}/…`), `mime`, `sizeBytes`, `sha256`, `uploadedBy`, `visibility` | B issues signed URLs after checks; every access audited | by `patientId`+`createdAt` | As patient |

### 3.6 Finance

| Collection | Purpose | Important fields | Roles | Queries / indexes | Retention |
|---|---|---|---|---|---|
| `invoices/{id}` | Invoice (**immutable once finalized**; corrections via credit/adjustment notes, stored with `type`) | `number` (sequential per tenant/branch/FY via transaction), `patientId`, `consultationId?`, `lines[{kind,desc,qty,unitMinor,taxMinor,discountMinor}]`, `totals`, `status` (draft, finalized, partially_paid, paid, void, credited), `type` (invoice, credit_note), `finalizedAt/By`, `pdfPath?` | Reception/Accountant create; Doctor optional | by `status`+`createdAt`; by `patientId`; outstanding: `status in (finalized, partially_paid)` → index | 8 years |
| `payments/{id}` | Payment records | `invoiceId`, `method` (cash, upi, card, online), `amountMinor`, `status` (initiated, captured, failed, refunded_partial, refunded), `gateway{razorpayOrderId, paymentId, signatureVerified}`, `idempotencyKey` (unique), `receivedBy`, `receiptNo` | Reception/Accountant; online via verified backend flow only | by `invoiceId`; by `createdAt` range+`method` (reconciliation) → indexes; unique `idempotencyKey` enforced via document ID = key hash | 8 years |
| `refunds/{id}` | Refunds, recorded separately | `paymentId`, `invoiceId`, `amountMinor`, `reason`, `status`, `gatewayRefundId?`, `approvedBy`, `performedBy` | Accountant/Admin with approval permission | by `paymentId` | 8 years |
| `expenses/{id}` | Clinic expenses | `date`, `categoryId`, `amountMinor`, `vendor{name,gstin?}`, `method`, `branchId?`, `receiptDocId?`, `status` | Accountant/Admin | by `date` range+`categoryId` → index | 8 years |

### 3.6b Notifications and audit

| Collection | Purpose | Important fields | Roles | Queries / indexes | Retention |
|---|---|---|---|---|---|
| `notifications/{id}` | In-app notification records + delivery state | `recipient{uid|accountId}`, `type`, `templateKey`, `payloadRef` (no PHI in push payload), `channels[]`, `status`, `sentAt`, `readAt` | B; recipient reads own | by recipient+`createdAt desc`; undelivered scan → index | 90 days |
| `audit_logs/{id}` | Append-only tenant audit trail | `actorUid`, `actorRole`, `action`, `resourceType/Id`, `patientId?`, `branchId?`, `outcome`, `requestId`, `at`, `diff` (field names only for clinical data), `ip?` | Owner/Admin read (filtered); never update/delete (B only appends) | by `at desc`; by `patientId`+`at`; by `actorUid`+`at`; by `action`+`at` → indexes | ≥ 3 years (confirm) |

## 4. Additional supporting documents (introduced when needed)

`queue_counters`, `invoice_counters`, `idempotency_keys` (booking/payment), `login_history`, `device_tokens` (FCM). Each will be documented here when its phase begins.

## 5. Index policy

- Indexes are defined in `firebase/firestore.indexes.json` **in the same change** as the query that needs them; none exist yet.
- The "Queries / indexes" column is the planning list; it is confirmed during each phase's design step.
- Collection-group indexes are required for `members` (by `uid`) and `consents` (by `accountId`).

## 6. Security-rule posture

Deny-all for clients (`firebase/firestore.rules`). If a realtime client read is ever introduced (e.g. queue display), it needs a dedicated, reviewed design and rules that read server-written membership records.

## Phase 2 collections (SaaS control plane)

All are **backend-only** (deny-all rules, verified by emulator tests). Timestamps are Firestore timestamps. `*` = required. Ids: opaque random (`app_…`, `plan_…`, `sub_…`) except `tenantId` (`ten_` + application id suffix, deterministic for idempotent provisioning).

| Collection / path | Fields | Relationships / notes |
|---|---|---|
| `clinic_applications/{applicationId}` | `applicationId*`, `applicantUid*`, `applicantEmail*`, `status*` (submitted, under_review, additional_information_required, approved, rejected, withdrawn), `clinic*{name,type,registrationNumber?,email,phone,website?,description?}`, `address*{line1,line2?,city,state,country,postalCode}`, `owner*{fullName,email,phone,designation?}`, `expectations*{doctors,staff,monthlyPatients}`, `preferredPlanId?`, `clinicNameLower*`, `dupKey*`, `submittedAt*`, `createdAt*`, `updatedAt*`, `decidedAt?`, `decisionReason?`, `infoRequest?{message,requestedAt}`, `infoResponses[]`, `reviewedBy?`, `reviewedAt?`, `tenantId?` | `applicantUid` → `platform_users`; `tenantId` → `tenants` after approval. Subcollections: `history/{id}` (`fromStatus`,`toStatus`,`actorUid`,`actorRole`,`reason`,`at`), `internal_notes/{id}` (`note`,`authorUid`,`at`, never shown to applicants). Retention: permanent (history is the record). |
| `tenants/{tenantId}` | `tenantId*`, `clinicName*`, `clinicNameLower*`, `slug*`, `ownerUid*`, `applicationId*`, `status*` (provisioning, active, suspended, closed), `clinicType`, `city`, `createdAt*`, `updatedAt*`, `approvedAt*`, `approvedBy*`, `subscriptionId?`, `configurationVersion*` (=1), `statusReason?`, `statusChangedAt?`, `statusChangedBy?` | Supersedes the Phase 0 sketch (`pending_approval`, `cancelled`, `planId`). Never deleted. |
| `tenants/{tenantId}/members/{uid}` | `uid*`, `role*` (`clinic_owner` created by provisioning), `status*` (active, deactivated), `branchIds[]`, `permissionOverrides{}`, `source`, `createdAt*`, `createdBy*` | Only the provisioning service writes in Phase 2 (Phase 3 adds management). Collection-group index on `uid`+`status` resolves a user's memberships. |
| `tenant_slugs/{slug}` | `tenantId*`, `createdAt*` | Uniqueness reservation. |
| `tenant_provisioning_jobs/{tenantId}` | `tenantId*`, `applicationId*`, `status*` (pending, completed, failed), `attempts*`, `initialPlanId?`, `startTrial`, `steps{membership,subscription}`, `lastError?` (code only), `startedBy*`, `createdAt*`, `updatedAt*` | Durable recovery record (see TENANT_PROVISIONING). |
| `subscription_plans/{planId}` | `planId*`, `name*`, `description`, `billingInterval*` (monthly, yearly), `priceMinor*` (paise), `currency*` (INR), `trialDays*`, `limits*{max_branches,max_doctors,max_staff,max_patients}` (`null`=unlimited), `features*{<featureKey>:bool}`, `status*` (active, inactive), `version*`, `createdAt/By`, `updatedAt/By` | Subcollection `versions/{n}`: immutable full snapshot per version. |
| `platform_subscriptions/{subscriptionId}` | `subscriptionId*`, `tenantId*`, `status*` (trial, active, past_due, expired, cancelled, suspended), snapshot `planId*`,`planVersion*`,`name*`,`billingInterval*`,`priceMinor*`,`currency*`,`limits*`,`features*`, `startDate*`, `trialEndDate?`, `endDate*`, `overrides{features?,limits?}`, `cancellationReason?`, `previousSubscriptionId?`, `replacedBy?`, `createdAt/By`, `updatedAt/By` | **ADR 021:** one document per subscription *period/plan* (a plan change creates a new document), replacing the Phase 0 sketch `platform_subscriptions/{tenantId}`. `tenants.subscriptionId` points to the current one. Subcollection `history/{id}` (`type`,`fromStatus`,`toStatus`,`reason`,`actorUid`,`actorRole`,`details`,`at`). Retention ≥ 8 years (financial). |
| `platform_audit_logs/{id}` | Phase 2 shape: `action*`, `actorUid*`, `actorRole*`, `targetType*`, `targetId*`, `tenantId?`, `reason?`, `requestId?`, `before?`, `after?`, `timestamp*`. Phase 1 authentication events keep `event`,`uid`,`outcome` and are mapped by the viewer | Append-only: the service has no update/delete; rules deny clients. `before/after` hold statuses/plan ids/limits only, no personal data or tokens. |

Indexes: `firebase/firestore.indexes.json` (16: applications by applicant/status/submittedAt/decidedAt/name; tenants and plans by status; subscriptions by status/tenant/plan/endDate; audit by tenant/action/targetType/actor; collection-group `members`). Not deployed.

## Phase 3 additions
Branches, branch codes, doctors, doctor_branch_assignments, staff, members (role/allBranches/branchIds), invitations (token hash only) and seats under `tenants/{tenantId}/`. Full field list: `docs/phase-3/FIRESTORE_SCHEMA.md`.

## Phase 4 additions
Global: `patient_accounts`, `patient_account_uids`, `patient_clinic_links`, `family_relationships`. Tenant: `patients`, `patient_mrns`, `counters`, `patient_consents`, `patient_history_entries`, `patient_allergies`, `patient_medications`, `patient_alerts`, `patient_emergency_contacts`, `patient_documents`, `patient_link_codes`, `patient_identity_links`, `patient_duplicate_reviews`, `patient_record_revisions`, `patient_audit_logs`. Details: `docs/phase-4/FIRESTORE_SCHEMA.md`.
