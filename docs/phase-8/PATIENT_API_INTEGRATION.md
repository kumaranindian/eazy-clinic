# Patient API Integration

Base `/api/v1`, standard envelope, bearer token. Prompt paths were treated as suggestions: existing endpoints are reused and the rest live under `/patient/...`.

| Area | Endpoint | Notes |
|---|---|---|
| Account | `POST /patient-accounts` (existing), `GET/PATCH /patient/profile`, `POST /patient/account/deletion-request` | |
| Linking | `GET /patient-accounts/me/clinic-links`, `POST …/link-clinic-record`, `POST …/clinic-links/{id}/unlink` (existing) | |
| Discovery | `GET /patient/clinics`, `/clinics/{c}`, `/clinics/{c}/doctors`, `/doctors/{d}`, `/specialities`, `/availability` | |
| Appointments | `GET/POST /patient/appointments` (POST needs `Idempotency-Key`), `GET /patient/clinics/{c}/appointments/{a}`, `POST …/cancel`, `…/reschedule`, `…/check-in`, `GET …/queue` | `accountId` query/body selects a family member |
| Records | `GET /patient/medical-records`, `/consultations`, `/prescriptions`, `/documents`, `/reports` | |
| Billing | `GET /patient/invoices`, `/clinics/{c}/invoices/{i}`, `/payments`, `/clinics/{c}/receipts/{r}`, `/refunds`, `/billing-summary` | |
| Family | `GET /patient/family`; create/verify/revoke via existing `/patient-accounts/me/family`, `/family-relationships/{id}/…` | |
| Notifications | `GET /patient/notifications`, `POST …/{id}/read`, `GET/PUT …/preferences`, `POST /patient/devices`, `DELETE /patient/devices/{deviceId}` | |
| Consent | `GET /patient/consent-catalog`, `GET /patient/clinics/{c}/consents`, `POST /patient/consents`, `POST /patient/clinics/{c}/consents/{k}/revoke` | |
| Doctor side | `POST /consultations/{id}/release`, `/unrelease` | `consultations.finalize`, author doctor |

Not implemented, with reasons: `/patient/clinics/{id}/unlink` (use the existing unlink), `/patient/queue` (per-appointment queue instead), `/patient/receipts` list (receipts come from payments), `/patient/documents` content (see above).

Errors: 400 header or filter, 401, 403 (no patient account, clinic not available, staff routes), 404 (not yours, not linked, relationship ended), 409 (slot taken, policy, state), 422 validation, 429. Replays carry `idempotentReplay: true`.
