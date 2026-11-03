# Staff Management (Module E)

Endpoints: `GET/POST /staff`, `GET/PATCH /staff/{id}`, `POST /staff/{id}/invite`, `POST /staff/{id}/activate|deactivate|suspend`.

- Profiles carry name, e-mail, phone, designation, intended role and branch assignment; **role and branches only take effect through the membership**, never through the profile.
- **Statuses:** `invited`, `active`, `inactive`, `suspended`, `invitation_expired`. Transitions are validated server-side; a suspended/inactive staff member's membership is disabled in the same commit.
- **Limit:** `max_staff` via seat slots.
- Staff roles that can be invited: `clinic_admin` (owner only), `doctor`, `receptionist`, `nurse`, `accountant`, `lab_technician`, `pharmacist`. `clinic_owner` can never be assigned.
- Removing access never deletes the person's Firebase account or other clinics' memberships.
- See `INVITATION_WORKFLOW.md` and `RBAC_PERMISSION_MATRIX.md`.
