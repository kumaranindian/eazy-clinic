# Family and Dependent Management (Module D)

`family_relationships/{id}` (global, between two **accounts**): requester, subject, `relationshipType` (parent, child, spouse, guardian, caregiver, other), `isGuardian`, `permissionScope` (`view_clinic_links`, `link_clinic_records`, `manage_appointments`, `view_records`, `give_consent` — later phases check these), `verificationStatus`, `status` (pending, active, revoked, rejected; expired is derived from `validUntil`), `scopeTenantId`, `verifiedBy`, `consentRef`, validity dates.

* **Adult relationship:** requester creates it (pending); only the **subject** can approve or reject it (`POST /family-relationships/{id}/verify`). Guardianship over an adult cannot be claimed.
* **Dependent:** a parent/guardian creates a dependent profile (kind `dependent`, no sign-in). It is verified **by the clinic**: when the minor's record (with a staff-verified guardian) is linked by the guardian's account, the relationship becomes verified and active for **that clinic only** (`scopeTenantId`). Nobody can approve their own request.
* **Revoke:** either party at any time; takes effect immediately. **Update:** the requester may only narrow the scope or set `validUntil`.
* **Authorization helper** `authorize(actor, subject, scope, tenant?)`/`allowedTenants`: relationship must be active, verified, unexpired and include the scope. Implemented use in Phase 4: `GET …/clinic-links?accountId=` (pointers only).

A relationship **never** grants access to a clinic record: clinic endpoints do not consult relationships. Clinics cannot read relationships. Clinic Web shows no family screens (they belong to the patient; Phase 8 patient app). Minor age = clinic setting `minorAgeYears` (default 18).
