# RBAC Permission Matrix

Status: **Documented default policy.** Not implemented. Defaults below are the platform's starting
point; **Clinic Owners can adjust permissions within platform-defined bounds** (CLAUDE.md §5). Enforcement is
backend-only; the apps merely read the resolved permission list to adapt the UI.

Legend: ✔ allowed · ◐ limited (see note) · ✖ denied · ⚙ off by default, owner can enable. "Own" = only records the user is
directly involved in. All ◐ and ✔ on patient data additionally require tenant + branch scope, and are audited.

## 1. Permission model

- Permission = `<resource>.<action>` string from one catalogue (shared, `common_models`, added in Phase 3).
- Role = named set of permissions (`roles/{id}` in the tenant, seeded from platform defaults, `system: true` roles cannot be deleted).
- Member = role + per-member overrides (`permissionOverrides.allow/deny`) + branch scope.
- Bounds: certain permissions can never be granted to certain roles (e.g. `consultation.finalize` and `prescription.issue` only to roles linked to a verified doctor profile; `tenant.delete`/`billing.plan` only Owner).

## 2. Platform roles

**Phase 2 implementation:** platform permissions enforced by the backend on every `/platform/*` route:

| Permission | Super Admin | Support Admin |
|---|---|---|
| `platform.dashboard.read`, `applications.read`, `tenants.read`, `plans.read`, `subscriptions.read` | ✔ | ✔ |
| `platform.applications.review` (start review, request info, approve, reject, notes) | ✔ | ✖ |
| `platform.tenants.manage` (suspend, reactivate, close, retry provisioning) | ✔ | ✖ |
| `platform.plans.manage`, `platform.subscriptions.manage` | ✔ | ✖ |
| `platform.entitlements.override` | ✔ | ✖ |
| `platform.audit.read` | ✔ | ✖ |

Clinic owners get **no** platform permission; their only Phase 2 access is their own clinic's entitlement view. Granting/revoking `platformRole` through an API is deferred (TECHNICAL_DEBT TD-22); today it is set by hand with Admin credentials.

**Phase 1 implementation:** `platform_users/{uid}.platformRole` is written server-side only. `PermissionPolicy` (in `common_models`) defined
`platform.users.revoke_sessions` (super admin), `platform.users.read` (super admin, support admin) and `platform.users.change_status` (super admin, no endpoint yet).
Clinic and patient role mappings are intentionally empty and denied by default until Phases 3/4. The table below is the target matrix.

| Permission | Super Admin | Platform Support Admin |
|---|---|---|
| Platform dashboard | ✔ | ✔ |
| Approve / suspend tenants | ✔ | ✖ |
| Manage subscription plans | ✔ | ✖ |
| View tenant & subscription status | ✔ | ✔ |
| Manage platform users | ✔ | ✖ |
| View platform audit logs | ✔ | ◐ (own actions + support cases) |
| Read tenant clinical data | ✖ (break-glass only, audited, time-boxed, approved) | ✖ |

## 3. Clinic roles: default matrix

| Permission | Owner | Admin | Doctor | Reception | Nurse | Accountant | Lab Tech | Pharmacist |
|---|---|---|---|---|---|---|---|---|
| **Clinic setup** (profile, hours, policies) | ✔ | ✔ | ✖ | ✖ | ✖ | ✖ | ✖ | ✖ |
| Branch manage | ✔ | ✔ | ✖ | ✖ | ✖ | ✖ | ✖ | ✖ |
| Subscription / plan view & change | ✔ | ◐ view | ✖ | ✖ | ✖ | ✖ | ✖ | ✖ |
| Role & permission configuration | ✔ | ◐ (cannot grant above own level) | ✖ | ✖ | ✖ | ✖ | ✖ | ✖ |
| Staff invite / activate / deactivate | ✔ | ✔ | ✖ | ✖ | ✖ | ✖ | ✖ | ✖ |
| Doctor profile manage | ✔ | ✔ | ◐ own non-critical fields | ✖ | ✖ | ✖ | ✖ | ✖ |
| **Patient registration** | ✔ | ✔ | ✔ | ✔ | ✔ | ◐ (billing identity only) | ✖ | ✖ |
| Patient search / demographics read | ✔ | ✔ | ✔ | ✔ | ✔ | ◐ (name, UHID, contact) | ◐ (patients with lab orders) | ◐ (patients with prescriptions) |
| Patient demographics edit | ✔ | ✔ | ✔ | ✔ | ◐ | ✖ | ✖ | ✖ |
| **Medical history read** | ◐ ⚙ | ◐ ⚙ | ✔ authorised (treating relationship) | ◐ restricted (allergies/alerts only) | ✔ (branch, active visit) | ✖ | ◐ (relevant to orders) | ◐ (allergies) |
| Medical history edit | ✖ | ✖ | ✔ | ✖ | ◐ (allergies, vitals) | ✖ | ✖ | ✖ |
| Vitals record | ✖ | ✖ | ✔ | ✖ | ✔ | ✖ | ✖ | ✖ |
| **Appointments** create/reschedule/cancel | ✔ | ✔ | ✔ own | ✔ | ◐ view | ✖ | ✖ | ✖ |
| Availability & slot configuration | ✔ | ✔ | ✔ own | ✖ | ✖ | ✖ | ✖ | ✖ |
| Queue manage (token, call, skip) | ✔ | ✔ | ✔ own queue | ✔ | ✔ | ✖ | ✖ | ✖ |
| **Consultation** create/edit draft | ✖ | ✖ | ✔ | ✖ | ◐ (vitals section) | ✖ | ✖ | ✖ |
| Consultation finalize / amend | ✖ | ✖ | ✔ (author; amend with reason) | ✖ | ✖ | ✖ | ✖ | ✖ |
| Consultation read (finalized) | ◐ ⚙ | ◐ ⚙ | ✔ authorised | ✖ | ◐ branch/active | ✖ | ✖ | ✖ |
| Diagnosis | ✖ | ✖ | ✔ | ✖ | ✖ | ✖ | ✖ | ✖ |
| **Prescription** create/issue | ✖ | ✖ | ✔ (issuing doctor authorises) | ✖ | ✖ | ✖ | ✖ | ✖ |
| Prescription view / print issued | ◐ | ◐ | ✔ | ✔ (print) | ◐ | ✖ | ✖ | ✔ |
| Medicine catalogue manage | ✔ | ✔ | ◐ propose | ✖ | ✖ | ✖ | ✖ | ✔ |
| Clinical templates manage | ✔ | ✔ | ◐ own variants ⚙ | ✖ | ✖ | ✖ | ✖ | ✖ |
| **Lab** order | ✖ | ✖ | ✔ | ✖ | ◐ ⚙ | ✖ | ✖ | ✖ |
| Lab result entry / report upload | ✖ | ✖ | ✖ | ✖ | ◐ ⚙ | ✖ | ✔ | ✖ |
| Lab result review | ✖ | ✖ | ✔ | ✖ | ✖ | ✖ | ✖ | ✖ |
| **Invoice** create / finalize | ✔ | ✔ | ⚙ | ✔ | ✖ | ✔ | ✖ | ⚙ |
| Invoice void / credit note | ✔ | ✔ (approval) | ✖ | ✖ | ✖ | ✔ (approval) | ✖ | ✖ |
| **Payment collect** (cash/UPI/card/online) | ✔ | ✔ | ⚙ | ✔ | ✖ | ✔ | ✖ | ⚙ |
| Refund initiate / approve | ✔ approve | ✔ approve | ✖ | ◐ initiate | ✖ | ◐ initiate (approval required) | ✖ | ✖ |
| Expense manage | ✔ | ✔ | ✖ | ✖ | ✖ | ✔ | ✖ | ✖ |
| **Financial reports** | ✔ | ✔ | ◐ own earnings ⚙ | ✖ | ✖ | ✔ | ✖ | ✖ |
| Clinical / operational reports | ✔ | ✔ | ◐ own | ◐ operational | ✖ | ✖ | ✖ | ✖ |
| Documents upload | ✔ | ✔ | ✔ | ✔ | ✔ | ✖ | ✔ (reports) | ✖ |
| Documents view (clinical) | ◐ ⚙ | ◐ ⚙ | ✔ authorised | ✖ | ◐ | ✖ | ◐ (reports) | ✖ |
| Follow-ups manage | ✔ | ✔ | ✔ | ✔ | ◐ | ✖ | ✖ | ✖ |
| Notification templates/settings | ✔ | ✔ | ✖ | ✖ | ✖ | ✖ | ✖ | ✖ |
| Audit log view | ✔ | ◐ (non-clinical) | ◐ own actions | ✖ | ✖ | ◐ (financial) | ✖ | ✖ |
| Data export (patients, finance) | ✔ (approval trail) | ◐ | ✖ | ✖ | ✖ | ◐ (finance) | ✖ | ✖ |

Notes:
- "Authorised" for doctors = the doctor is the treating doctor on an appointment/consultation for that patient, or holds an explicit, audited grant (e.g. referral within the same tenant).
- Owner/Admin clinical read is ⚙ (off by default) because administration does not need clinical content; when enabled it is audited like any clinical access.
- Reception sees only safety-relevant alerts (e.g. allergy flag) to schedule safely, not notes or diagnoses.

## 4. Patient-side roles

| Permission | Patient (adult, own account) | Authorized caregiver / guardian |
|---|---|---|
| View own profile; edit contact details | ✔ | ◐ for dependent, per `scope` |
| Link to a clinic record (with clinic authorization + consent) | ✔ | ◐ for dependent |
| Discover clinics/doctors | ✔ | ✔ |
| Book / cancel / reschedule appointments | ✔ | ◐ per scope |
| Queue status | ✔ | ◐ per scope |
| View prescriptions, lab reports, history **of clinics they are linked to** | ✔ | ◐ per scope + consent |
| Manage consents (grant/revoke) | ✔ | ◐ for dependent (guardian of minor) |
| Manage family relationships | ✔ | ✖ (cannot grant further access) |
| See other clinics' data | ✖ | ✖ |

Dependent-minor rules (age thresholds, transition to own account at majority) are decided in Phase 4 with legal input.

## 5. Implementation requirements (Phase 3)

1. One permission catalogue; backend policy helper `can(ctx, permission, {resource})`.
2. Table-driven unit tests generated from this matrix: for each role × permission assert allow/deny.
3. UI reads `GET /members/me` → permission list; hides actions but never relies on it.
4. Changing a member's role/permissions writes an audit entry and revokes that user's refresh tokens.
5. This matrix and the code must not diverge: updating one requires updating the other in the same change.

## Phase 3 clinic permissions
The implemented clinic matrix is in `docs/phase-3/RBAC_PERMISSION_MATRIX.md`.

## Phase 4 patient permissions
| Permission group | Owner | Admin | Doctor | Nurse | Receptionist | Others |
|---|---|---|---|---|---|---|
| patients.view/create/update/duplicates | ✔ | ✔ | ✔ | ✔ | ✔ | |
| patients.status (activate/deactivate/archive) | ✔ | ✔ | | | | |
| patients.link_account | ✔ | ✔ | | | ✔ | |
| history.view | ✔ | | ✔ | ✔ | | |
| history.manage | ✔ | | ✔ | | | |
| allergies / medications view+manage | ✔ | | ✔ | ✔ | | |
| alerts.view | ✔ | ✔ | ✔ | ✔ | ✔ | |
| alerts.manage (clinical categories also need clinical rights) | ✔ | ✔ | ✔ | ✔ | ✔ | |
| consents.view/manage | ✔ | ✔ | ✔ | ✔ | ✔ | |
| patient_documents view/manage | ✔ | | ✔ | ✔ | | |
| patient_audit.view | ✔ | ✔ | | | | |

Administrators run the clinic but do not read clinical information by default. Verifying clinical information needs the **doctor** role (not just a permission).

## Phase 5 scheduling permissions
| Permission | Owner | Admin | Doctor | Nurse | Receptionist |
|---|---|---|---|---|---|
| appointment_types.view | ✔ | ✔ | ✔ | ✔ | ✔ |
| appointment_types.manage | ✔ | ✔ | | | |
| availability.view | ✔ | ✔ | ✔ | ✔ | ✔ |
| availability.manage | ✔ | ✔ | | | |
| availability.manage_own | | | ✔ (own profile) | | |
| appointments.view | ✔ | ✔ | ✔ | ✔ | ✔ |
| appointments.book | ✔ | ✔ | ✔ | | ✔ |
| appointments.manage (confirm, cancel, reschedule, no-show, notes) | ✔ | ✔ | | | ✔ |
| appointments.check_in | ✔ | ✔ | | ✔ | ✔ |
| appointments.cancel_checked_in | ✔ | ✔ | | | ✔ |
| appointments.consult (start, complete) | ✔ | | ✔ (own patients) | | |
| queue.view | ✔ | ✔ | ✔ | ✔ | ✔ |
| queue.operate | ✔ | ✔ | ✔ | ✔ | ✔ |
| queue.consult | ✔ | | ✔ (own queue) | | |
| queue.priority | ✔ | ✔ | | | |

Accountants, lab technicians and pharmacists have no scheduling access.

## Phase 6 clinical permissions
| Permission | Owner | Admin | Doctor | Nurse | Receptionist |
|---|---|---|---|---|---|
| consultations.view | ✔ | | ✔ (own) | | |
| consultations.view_all | ✔ | | | | |
| consultations.manage / finalize | ✔ held, cannot author* | | ✔ (own) | | |
| vitals.view / vitals.record | ✔ held* | | ✔ | ✔ | |
| prescriptions.view / manage / finalize | ✔ held, cannot author* | | ✔ (own) | | |
| followups.view | ✔ | ✔ | ✔ | ✔ | ✔ |
| followups.manage | ✔ held, cannot author* | | ✔ | | |
| investigations.request | ✔ held, cannot author* | | ✔ | | |
| clinical_templates.view / manage | ✔ | ✔ | ✔ | | |
| clinical_templates.manage_clinic, clinical_catalogue.manage | ✔ | ✔ | | | |
| clinical_audit.view | ✔ | | | | |

*The owner holds every permission, but clinical authoring additionally requires the `doctor` role with a linked `doctorId` (ADR 048), so an owner reads but never authors. Admin deliberately has no clinical read/write permission. Source of truth: `ClinicRolePolicy`.
