# Family and Dependents

Built on the Phase 4 relationships; the portal adds a list and uses the scopes.

- **List:** `GET /patient/family`: relationships with the other person's display name and kind only, `direction` (`i_manage` / `manages_me`), status, verification, scopes, `canActFor` (true only while the relationship is active and verified and the caller is the one who acts).
- **Add a child:** `POST /patient-accounts/me/family` with a `dependent` (name, date of birth, gender), `relationshipType: parent`, `isGuardian: true`. Linking the child's clinic record needs a clinic-verified guardian code.
- **Adults:** a caregiver or spouse requests access with chosen scopes; **the other person must approve** (`/family-relationships/{id}/verify`); nothing is granted while pending. Either side can end it at once (`/revoke`).
- **Scopes:** `manage_appointments` (list, book, cancel, move, check in, queue), `view_records` (records, billing), `give_consent`, `view_clinic_links`, `link_clinic_records`. Exact: a caregiver with only appointments gets 404 on records and billing (tested); after revocation every route answers 404 immediately (tested).
- **App:** a person selector (me / people you act for) sends `accountId`; the backend re-authorizes every request. Consent decisions in the app are for oneself; a child's consent is given by the guardian through the clinic.
- Never by phone number alone. Age-related guardian rules follow the clinic's configured minor age (Phase 4); nothing here claims legal validation.
