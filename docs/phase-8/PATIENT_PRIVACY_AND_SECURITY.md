# Patient Privacy and Security

## Authorization on every request
1. Firebase token verified; the user's patient account found by uid (never from the request).
2. Another person (`accountId`) only through an active, verified relationship whose scope covers the action; otherwise 404 (existence not revealed).
3. A clinic only through an existing clinic link; `clinicId` in a path is matched against the links, so changing it cannot reach another clinic.
4. Every document read is matched to the linked patient id; changing a document id reaches nothing of anyone else.
5. Clinic gating: active, not blocked, `patient_mobile_app` in the plan; read-only clinics refuse writes.
6. Unknown body fields are rejected; no endpoint accepts tenant, patient, role, status or timestamps.

## Data minimization
Allow-listed projections only (see PATIENT_MEDICAL_RECORDS.md and PATIENT_BILLING.md); generic notification text; queue status without other patients; doctors without registration numbers or contact data; clinic cards without staff or plan data. Audit entries (`portal.*`) record that a record was viewed or an action taken, never its content.

## Storage
Firestore and Storage rules remain **deny-all** for clients; the new collections (`patient_notifications`, `patient_devices`, `patient_notification_preferences`, `account_deletion_requests`) are backend-only (rules tests added: no client read, write, collection-group query or update). No public Storage URLs exist for patient data; documents are not exposed yet. FCM tokens are stored per user and device, never returned by any API. The app stores no clinical data on disk and no passwords or tokens (the Firebase SDK manages the session).

## Consent
Per purpose, with the wording version, collected through `ConsentService` (append-only, withdrawal keeps the evidence); an outdated wording is refused; a duplicate grant is refused. Nothing is bundled or assumed at registration. The privacy screen states it is not a legal-compliance claim. Dependents' consent is given by the guardian through the clinic.

## Android
Only the `INTERNET` permission; `allowBackup=false`; cleartext only in debug builds. No contacts, location, camera or storage access, so no runtime permission prompts exist yet (notification permission arrives with FCM).

## Residual risks
Discovery scans active tenants (cap 300) per search (TD-69); booking policy is fixed (TD-65); no MFA for patients (TD-38); push not wired (TD-67); the release build still uses the debug signing key until a release key is supplied (checklist); rate limits are per instance (TD-16).
