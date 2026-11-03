# RBAC Permission Matrix (Phase 3)

Source of truth: `packages/common_models/lib/src/clinic_permissions.dart` (`ClinicPermission`, `ClinicRolePolicy`). Platform permissions can never appear here. Effective permissions are computed server-side per request from the membership role; clients only display them (`GET /members/current/permissions`).

| Permission | Owner | Admin | Doctor | Receptionist | Nurse | Accountant | Lab tech | Pharmacist |
|---|---|---|---|---|---|---|---|---|
| clinic.view | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| clinic.update | ✔ | ✔ | | | | | | |
| clinic.settings.manage | ✔ | ✔ | | | | | | |
| branches.view | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ | ✔ |
| branches.create / update / activate / deactivate | ✔ | ✔ | | | | | | |
| doctors.view | ✔ | ✔ | ✔ | ✔ | ✔ | | | |
| doctors.create / update / activate / assign_branch | ✔ | ✔ | | | | | | |
| staff.view / create / update / invite / activate / deactivate | ✔ | ✔ | | | | | | |
| staff.assign_role / staff.assign_branch | ✔ | ✔ | | | | | | |
| roles.view / permissions.view | ✔ | ✔ | | | | | | |
| roles.manage | ✔ | | | | | | | |

## Authority rules
1. Nobody changes their own role or branches.
2. Only the owner assigns or removes `clinic_admin`; admins manage the other non-owner roles.
3. The `clinic_owner` role cannot be assigned, changed or removed through any API (ownership transfer is deferred), which guarantees the last-owner invariant (also checked defensively).
4. Custom/configurable roles are **deferred** (ADR 026); the catalog and policy are designed so overrides can be added without changing endpoints.
5. UI hiding is cosmetic; every endpoint calls `t.require(permission)` and branch checks.
