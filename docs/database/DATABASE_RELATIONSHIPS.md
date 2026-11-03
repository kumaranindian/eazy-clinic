# Database Relationships

Status: Documented. Arrows point from the referencing document to the referenced one.

## 1. Entity map

```
platform_users            tenants ──► subscription_plans (via platform_subscriptions.planId)
                             │
                             ├─ platform_subscriptions/{tenantId}
                             ├─ clinic_invites ──► tenants
                             │
                             └─ tenants/{t}/
                                  clinic_settings (1:1)
                                  branches ◄──────────────┐
                                  members (uid) ──► roles, branches (branchIds)
                                  doctors ─► members (uid), branches
                                  staff ───► members (uid), branches
                                  patients ──► branches (registeredBranchId)
                                      ▲   ▲
        patient_accounts (global)     │   │ patient_links (global) ──► tenants + patients + consents
              ▲                       │
              └ family_relationships (global, account↔account) ──► consents
                                  appointments ──► patients, doctors, branches, appointment_slots
                                  queue_entries ──► appointments?, patients, doctors, branches
                                  consultations ──► patients, appointments?, doctors, clinical_templates(version)
                                      ├ diagnoses ──► consultations
                                      ├ prescriptions ──► consultations, doctors, medicine_catalogue(optional)
                                      ├ vitals ──► patients, consultations?
                                      ├ lab_orders ──► consultations?, patients ──► lab_results ──► documents
                                      └ followups ──► consultations, appointments?
                                  medical_histories (1:1 with patients)
                                  documents ──► patients?, consultations?
                                  invoices ──► patients, consultations?
                                      └ payments ──► invoices ──► refunds ──► payments
                                  expenses ──► branches?, documents?
                                  notifications, consents, audit_logs
```

## 2. Cardinalities

| Relationship | Cardinality | Notes |
|---|---|---|
| tenant → branches | 1 : N | ≥ 1 branch (a single-doctor clinic has one default branch) |
| user → memberships | 1 : N | A user can belong to several tenants |
| membership → branches | N : M | `branchIds` empty ⇒ tenant-wide |
| doctor → branches | N : M | `branchAssignments` with per-branch availability |
| patient account → clinic patient records | 1 : N | One per clinic, through `patient_links`; never merged |
| patient (clinic) → appointments / consultations / invoices | 1 : N | |
| appointment → queue entry | 1 : 0..1 | Walk-ins have a queue entry without appointment |
| appointment → consultation | 1 : 0..1 | |
| consultation → diagnoses / prescriptions / vitals / lab orders / follow-ups | 1 : N | |
| invoice → payments | 1 : N | Partial payments |
| payment → refunds | 1 : N | Refunds are separate records |
| guardian account → dependent accounts | 1 : N, N : M | explicit `family_relationships` with scope + consent |

## 3. Referential rules

- Firestore has no foreign keys. The backend validates every reference **within the same tenant** before writing (a reference to a document in another tenant is rejected).
- Deleting referenced documents is disallowed for clinical/financial data; use `status` transitions (`cancelled`, `void`, `deactivated`).
- Denormalised copies (e.g. `queue_entries.displayName`) are listed in DATABASE_SCHEMA and refreshed by the backend when the source changes.

## 4. Consistency and transactions

| Operation | Mechanism |
|---|---|
| Book appointment (slot + appointment + optional queue entry) | Transaction; idempotency key |
| Generate queue token | Transaction on `queue_counters` document |
| Invoice number allocation | Transaction on `invoice_counters` |
| Record payment (verify signature → payment + invoice status + receipt no.) | Transaction; document ID derived from idempotency key |
| Finalize consultation | Transaction: status change + immutable snapshot; amendments create revisions |
| Patient link | Transaction: link + consent + audit |

## 5. Ownership summary

| Owner | Collections |
|---|---|
| Platform | `platform_users`, `tenants`, `subscription_plans`, `platform_subscriptions`, `platform_audit_logs`, `clinic_invites` |
| Global patient identity | `patient_accounts`, `patient_links`, `family_relationships` |
| Tenant | everything under `tenants/{tenantId}/` |

## Phase 3 relationships
`doctor` 1—N `doctor_branch_assignments` N—1 `branch`; `member` ↔ `doctor`/`staff` (by id, created at invitation acceptance); `invitation` → `staff`/`doctor`; `seat` slots count entities per kind against subscription limits.

## Phase 4 relationships
`patient_account` 1—N `patient_clinic_link` (pointer) N—1 tenant `patient`; tenant `patient` 1—N history entries / allergies / medications / alerts / consents / documents / revisions / audit; `patient` 1—1 emergency contacts; `family_relationship` links two `patient_accounts` and holds no clinical data; `patient_link_code` → `patient` (single use).
