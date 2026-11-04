# Financial RBAC

Source of truth: `ClinicPermission` and `ClinicRolePolicy` (`packages/common_models`). Enforced by the backend on every route; the UI only hides what the backend would refuse. Tenant and branch scope come from the trusted membership, never the request.

| Permission | Owner | Admin | Accountant | Receptionist | Doctor / Nurse / Lab / Pharmacist |
|---|---|---|---|---|---|
| billing.view / create / edit_draft / finalize | ✔ | ✔ | ✔ | ✔ | |
| billing.cancel | ✔ | ✔ | ✔ | | |
| billing.apply_discount (limit per role) | ✔ | ✔ | ✔ (10% default) | | |
| billing.adjust (credit/debit notes, credit adjustments) | ✔ | ✔ | ✔ | | |
| billing.settings.manage, service_catalogue.manage | ✔ | ✔ | | | |
| payment.view / collect / allocate / record_advance | ✔ | ✔ | ✔ | ✔ | |
| refund.request | ✔ | ✔ | ✔ | ✔ | |
| refund.approve | ✔ | ✔ | | | |
| refund.process | ✔ | ✔ | ✔ | | |
| expense.view / create / edit / pay | ✔ | ✔ | ✔ | | |
| expense.approve / reject | ✔ | ✔ | | | |
| finance.reports.view / export | ✔ | ✔ | ✔ | | |

Rules beyond the table: no self-approval of refunds or expenses unless `allowSelfApproval`; discount limits per role from settings; expense approval limits per role; clinic-wide expenses and all-branch reports need all-branch access; a cashier cannot see other branches. Accountants do **not** hold `patients.view` (Phase 4 decision); billing loads the patient server-side. Doctors have no billing access. Patients: no patient-facing billing endpoint exists (Phase 8); patient accounts are not clinic members, so they reach none of these routes.

Open: custom roles and per-user overrides (TD-29), a separate "branch admin" billing role, and refund limits by amount.
