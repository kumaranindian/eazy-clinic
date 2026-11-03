# Branch Management (Module C)

Endpoints: `GET/POST /branches`, `GET/PATCH /branches/{id}`, `POST /branches/{id}/activate|deactivate`.

- **Identity:** server-generated `branchId`; a branch `code` unique per clinic (uniqueness key document created in the same atomic commit) and immutable after creation.
- **Limit:** `max_branches` from the subscription, enforced race-free by seat slots (`tenants/{t}/seats/branch_{n}` created with a does-not-exist precondition in the same commit as the branch). Exceeding the limit → 409/limit error; no count-then-create window.
- **No deletion.** Branches are only deactivated. Deactivating the **last active branch** is refused. Deactivation keeps history and releases no assignments silently.
- **Hours:** optional per-branch weekly hours override (see `CLINIC_CONFIGURATION.md`).
- **Scope:** a member limited to specific branches sees and changes only those; an out-of-scope id answers 404. Creating a branch requires an all-branches member.
- **Audit:** create/update/activate/deactivate written atomically with the change.
- **UI:** `/clinic/branches` list (search, status filter, empty/error/loading), detail, create/edit form with optional hours editor; actions hidden without the permission (the backend still decides).
