# Patient Authentication

Uses the Phase 1 strategy unchanged (`app_core`): Firebase e-mail/password sign-in and registration with e-mail verification, backend token verification, session restore and refresh by the Firebase SDK, sign-out, and screens for suspended/disabled accounts and expired sessions (all in `app_core`). No OTP provider was added and no password or token is stored by the app itself.

## Patient account
Signing up creates a login. The first time the signed-in person opens the app, the shell calls `GET /patient/profile`; a 403 ("create your patient account first") shows the **Set up your profile** form (name, optional mobile and date of birth) which calls the existing `POST /patient-accounts`. The screen states that this does not give any clinic access to their records.

## Rules enforced by the backend
- Every `/patient/...` route needs a valid token and an active patient account; staff tokens without an account get nothing, and patients get 403 on every clinic-staff route (tested).
- A suspended or disabled login is refused by the existing auth middleware.
- Rate limit: 600 requests per minute per user on portal routes; linking and relationship routes keep their stricter Phase 4 limits.

## Account deletion
`POST /patient/account/deletion-request` records a pending request and deletes nothing. Clinic medical records are retained as the clinics' records; how the platform then handles the account is a retention decision (TD-66).
