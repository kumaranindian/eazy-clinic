# Patient Notification Workflow

One notification system: `PortalNotifier` writes `patient_notifications` for a patient account. Phase 10 will call the same interface to add push delivery and reminders; nothing here competes with it.

## Inbox
Created now, once each (deterministic id per event): appointment booked / rescheduled / cancelled, token generated (check-in), visit summary available, prescription available, invoice generated, payment received, refund status. Categories not yet produced: confirmed, reminder, doctor calling, queue changed, report available, follow-up reminder, announcement (Phase 10).
- Text is generic ("Your doctor issued a prescription. Open the app to view it.") and never carries diagnoses, medicines or amounts (tested). Detail is fetched from the authorized APIs after the tap; the app routes by `resourceType`.
- `GET /patient/notifications` (own only), `POST /patient/notifications/{id}/read` (owner only, 404 otherwise). Events for a clinic record with no linked account notify nobody.

## Devices
`POST /patient/devices {deviceId, token, platform: android}` stores the token for the signed-in user; the token is never returned. A token belongs to one user: registering it as another user moves it. `DELETE /patient/devices/{deviceId}` (on sign-out) deactivates only the caller's own tokens (tested).

## Preferences
`GET/PUT /patient/notifications/preferences`: push on/off and per-category switches; unknown categories are refused. They govern push delivery (Phase 10).

## FCM status
The app contains a `PushTokenSource` interface; the default returns no token, so nothing is registered and no push arrives. Enabling it needs `firebase_messaging` and an environment `google-services.json` (TD-67). Notification-permission prompts will be requested only then.
