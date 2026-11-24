# Known Gaps and Next Phase

| ID | Gap | Impact / plan |
|---|---|---|
| TD-109 | **Registers are unvalidated drafts**; sources are authority home pages (not fetched), no clause citations | Counsel review is a release gate (`LEGAL_REVIEW_CHECKLIST.md`) |
| TD-110 | New screens and messages are English only (not yet in the Phase 13 resources) | Localize with the compliance wording reviewed by counsel |
| TD-111 | No platform-reviewer MFA, four-eyes or review SLA; one reviewer can confirm applicability and approve evidence | Governance decision with Phase 20 |
| TD-112 | Evidence is type-checked, not malware-scanned; authenticity is not verified against any authority register; no OCR/extraction | Scanning hook; authority lookups only through approved integrations (Phase 17) |
| TD-113 | No retention/deletion policy for evidence and credentials; none are deleted | Needs a retention decision per country (Phase 21/22) |
| TD-114 | Existing doctor registration numbers are not migrated into credentials; credentials are not linked to the doctor profile UI | Add import/link in a follow-up |
| TD-115 | Facility-type applicability filter (`facilityTypes`) is stored but the dashboard does not filter by the clinic's type; practitioner-subject requirements are evidenced at facility level (the register of credentials holds the detail) | Per-practitioner items if counsel requires |
| – | Platform UI shows registers read-only (editing is API-only: no register editor, no impact-report screen) | Admin editor in a later phase |
| – | Expiry alerts are in-app/push only (no email/SMS provider) | Phase 18 |
| – | Evidence and credential data are visible to platform reviewers; a privacy notice to clinics about this is not drafted | Terms/DPA work |
| – | Collection-group indexes and emulator/rules tests unrun | TD-95 |

## Release risks
Do not describe the product as "supporting DHA/DoH/MOHAP/ABDM compliance". Do not enable the registers for clinics until counsel has validated them. Treat the reviewer role as highly privileged.

## Next phase
**Phase 15 – Tax, Invoicing & E-Invoicing Foundations.** It can reuse: tenant legal country (12), regional display (13), compliance registers/evidence for tax registrations (14). Prerequisites: tax advisor input per country; decision on which tax identifiers the compliance module should hold versus billing settings.
