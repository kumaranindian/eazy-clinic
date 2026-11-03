# Phase 3 API Reference (`/api/v1`)

All routes require a Firebase ID token, an active account, tenant membership (selected with `X-Tenant-Id`, validated server-side), an entitlement level that allows the call, and the listed permission. Responses use the standard envelope; errors use `ApiErrorCode`. Writes are rate limited (120/min) and audited.

| Method & path | Permission |
|---|---|
| GET/PATCH `/clinics/current` | clinic.view / clinic.update |
| GET/PATCH `/clinics/current/settings` | clinic.view / clinic.settings.manage |
| PUT/GET `/clinics/current/logo` | clinic.update / clinic.view |
| GET/POST `/branches`; GET/PATCH `/branches/{id}`; POST `/branches/{id}/activate`, `/deactivate` | branches.* |
| GET/POST `/doctors`; GET/PATCH `/doctors/{id}`; POST `/doctors/{id}/activate`, `/deactivate` | doctors.* |
| GET/POST `/doctors/{id}/branches`; DELETE `/doctors/{id}/branches/{branchId}` | doctors.view / doctors.assign_branch |
| GET/POST `/staff`; GET/PATCH `/staff/{id}`; POST `/staff/{id}/invite`, `/activate`, `/deactivate`, `/suspend` | staff.* |
| GET/POST `/invitations`; POST `/invitations/{id}/resend`, `/revoke` | staff.view / staff.invite |
| POST `/invitations/accept` | authenticated user (token + verified e-mail) |
| GET `/roles`, `/permissions` | roles.view / permissions.view |
| GET `/members/current/permissions` | any member |
| GET `/members`; PATCH `/members/{id}/role`, `/members/{id}/branches` | staff.view / staff.assign_role / staff.assign_branch |

Validation failures: 422 with field issues; unknown/sensitive body fields rejected; out-of-scope resources 404; permission denial 403; limit exceeded and duplicate keys 409.
