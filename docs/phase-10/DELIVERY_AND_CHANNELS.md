# Delivery lifecycle and channels

## Statuses
`queued` -> `processing` -> `sent` | `retry_scheduled` (-> `processing` ...) | `permanently_failed` | `cancelled` | `configuration_required`. In-app deliveries are written `delivered` (the clinic stores the inbox itself).

* **sent** means the provider accepted the message. FCM returns no receipt, so push never becomes `delivered`.
* **cancelled** reasons: `recipient_preference`, `channel_disabled`, `no_active_device`, `appointment_no_longer_confirmed`, `appointment_rescheduled`, `appointment_passed`, `followup_no_longer_active`, `followup_date_changed`.
* **retry**: transient provider errors retry with 30 s doubling to 30 min, +/-20% jitter, at most 5 attempts, then `permanently_failed`. Permanent errors and invalid tokens never retry. An invalid token also deactivates that device.
* **manual retry** (`notifications.manage`): only `permanently_failed` or `configuration_required`; resets attempts; counts `manualRetries`; audited; a second click on a queued delivery is a replay. 30 per hour per user.
* **pause**: a paused channel keeps its deliveries `queued` (re-checked every 5 minutes); resuming sends them. The in-app channel cannot be paused.
* Each delivery stores event id, channel, recipient type, template ref/version, attempts, timestamps, provider message id and a sanitized error code. It stores no token, address or provider response body.

## Channels
| Channel | State |
|---|---|
| In-app | Done (patient inbox, staff inbox). |
| Push (FCM) | `HttpFcmSender` posts to FCM HTTP v1 with the service account; enabled with `NOTIFICATIONS_FCM_ENABLED=true`. Disabled by default, so push deliveries read `configuration_required`. **Not run against live FCM.** No app registers tokens yet (no `firebase_messaging`, TD-83); the API and storage for tokens are done. |
| Email, SMS, WhatsApp | `MessageProvider` interface and dispatch path are done and tested with mocks. **No provider is implemented or configured**; deliveries read `configuration_required`. A clinic enables a channel in settings, but credentials would be environment-level (TD-84). |

## Configuration (never commit values)
`NOTIFICATIONS_FCM_ENABLED` (default false), `NOTIFICATIONS_WORKER_ENABLED` (default true), the existing `FIREBASE_PROJECT_ID`. The service account needs the `firebase.messaging` scope (added to the ADC scopes in `bootstrap.dart`) and the project needs the FCM API enabled. Provider credentials for email/SMS/WhatsApp would come from environment secrets once a provider is approved.
