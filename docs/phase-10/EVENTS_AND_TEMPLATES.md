# Events, templates and preferences

## Event types (categories) and where they come from
| Spec event | Category | Recipient | Emitted by | State |
|---|---|---|---|---|
| AppointmentBooked | `appointment_booked` | patient | patient-app booking (Phase 8) | done; staff-made bookings are **not** notified (TD-89) |
| AppointmentConfirmed | `appointment_confirmed` | patient | staff confirm route | done |
| AppointmentRescheduled | `appointment_rescheduled` | patient | patient app and staff route | done |
| AppointmentCancelled | `appointment_cancelled` | patient | patient app and staff route | done |
| AppointmentReminderDue | `appointment_reminder` | patient | worker scan | done |
| PatientCheckedIn | `token_generated` | patient | patient app and staff check-in | done |
| QueueTokenCalled | `doctor_calling` | patient | call-next, call, recall | done |
| ConsultationCompleted | `summary_available` | patient | doctor releases the summary (Phase 8) | done |
| FollowUpScheduled | `followup_reminder` | patient | follow-up creation; plus day-before reminder from the worker | done |
| InvoiceCreated / PaymentReceived / RefundProcessed | `invoice_generated` / `payment_received` / `refund_status` | patient | billing routes (Phase 8) | done |
| PaymentFailed | | | no online gateway exists | **not done** |
| LabOrderCreated | | | no meaningful recipient defined | **not done** |
| LabSampleRejected | `lab_sample_rejected` | requesting doctor | sample rejection | done (reason text is not sent) |
| LabReportPublished | `report_available` | patient and requesting doctor | report publication | done |
| Account / security / consent events | `security_event` (category only) | | nothing emits it | **not done** |

## Templates
Fields: name, event type, channel, language (2 letters), subject, body, allowed variables (derived from the event type), active, version. Built-in templates (version 1) exist for appointment and follow-up reminders on in-app, push, email and SMS. Editing a clinic template bumps its version and stores the previous text in `notification_template_versions`; each delivery records `templateRef` and `templateVersion`.

Allowed variables: appointment reminder `clinicName`, `doctorName`, `date`, `time`; follow-up reminder `clinicName`, `date`; others `clinicName`. A template naming any other variable, or using anything but `{{name}}`, is rejected when saved. A missing value fails that one delivery as `permanently_failed` (`template_error`) instead of sending a broken message. Language: the clinic's default language, then English.

Push text for reminders is generic ("You have an upcoming appointment. Open the app for details."); the in-app and email text may carry date, time and doctor name, never clinical content.

## Preferences and consent
* Patient: `patient_notification_preferences` (push on/off, category switches). Staff: `notification_preferences/{uid}` with push, email/sms/whatsapp and category switches. API: `GET/PATCH /notifications/preferences` (staff), `GET/PUT /patient/notifications/preferences`.
* Essential (service) categories cannot be removed from the inbox; the user controls push and other channels for them.
* `clinic_announcement` is promotional: nothing is created unless the person turned it on. Nothing in the product sends promotions today.
* Dependants and guardians: a message goes only to the account linked to the patient record. A guardian is not copied (TD-89).
