# Doctor Management (Module D)

Endpoints: `GET/POST /doctors`, `GET/PATCH /doctors/{id}`, `POST /doctors/{id}/activate|deactivate`, `GET/POST /doctors/{id}/branches`, `DELETE /doctors/{id}/branches/{branchId}`.

- **One profile, many assignments.** `doctors/{doctorId}` holds identity (name, qualifications, specialities, registration number/council, fee, e-mail, phone). Branch relationships are separate `doctor_branch_assignments` documents (status, optional per-branch fee/hours) with a uniqueness-key document preventing duplicates.
- **Account association** only through the invitation workflow (`staff`/doctor invite → acceptance by a verified account whose e-mail matches the profile e-mail). An administrator cannot attach an arbitrary Firebase UID.
- **Limit:** `max_doctors` via seat slots (atomic). Deactivation releases nothing silently and keeps appointments/history references.
- **Member sync:** assigning/unassigning keeps the doctor's membership `branchIds` consistent; branch scope applies to listing and mutation.
- **Clinical neutrality:** no clinical data is generated or defaulted; the registration number is stored as entered and is **not verified** against any medical council (documented limitation).
- **Audit:** all changes written atomically.
