# Security and Privacy (Phase 14)

| Topic | Control | Evidence |
|---|---|---|
| Tenant scope | Clinic routes use the caller's membership; evidence and credentials live under `tenants/{t}/…`; an id from another clinic returns 404; the `x-tenant-id` selector is checked against membership | "downloads are tenant-scoped", "another clinic cannot see or edit these credentials" |
| Separation of duties | Only platform roles with `review` can approve evidence, verify credentials, confirm applicability or mark requirements not applicable; a clinic owner calling those routes gets 403; Support Admin is read-only and cannot open evidence files | permission tests |
| No false badge | No "compliant" value exists; approvals expire or are voided by requirement changes; unvalidated registers cap readiness; baseline is draft/low confidence | `compliance_core_test.dart`, readiness tests |
| File safety | Allow-list PDF/PNG/JPEG **by magic bytes** (declared type ignored), 3 MB cap, base64 validated, private bucket path built by the server, no path from the client; `nosniff`, `no-store`, generic file names (no titles or numbers in names) | upload tests |
| Evidence access audit | Every file read writes a history entry and an audit event with actor and request id | "audited" test |
| Mass assignment | Strict allow-lists on every body; a clinic cannot send `status`, `tenantId`, `verification`, reviewer fields | "unsupported kinds and fields", credential validation |
| Privilege escalation | Compliance permissions are not in any non-admin clinic role; platform permissions are never in clinic roles (existing test) | `common_models` + route-auth sweep |
| Sensitive data | Licence numbers and practitioner names are personal/professional data: visible only to owners/admins and platform reviewers; alert texts omit them; logs record ids and field names, not values | alert test |
| Notification content | Expiry alerts say only that "a compliance document expires/has expired" | alert test |
| Rate limits | All writes rate limited per user | `secured(write: true)` |
| Firestore/Storage | Deny-all for clients (unchanged); new collections added to the rules test list (not run here); two collection-group indexes added | TD-95 |
| Legal claims | Registers are drafts with disclaimers in the API and UI; no regulator integration; `legalReview` records who validated what and when | baseline tests, UI tests |
| Retention | Evidence and history are not deleted by the product (deletion of regulated records needs a retention decision, TD-113) | — |

## Residual risks
* A reviewer account is powerful (it can confirm applicability and approve evidence). MFA for platform roles is still open (TD-94).
* Evidence files are not malware-scanned (type check only).
* The compliance workflow trusts the reviewer's reading of the document; the product cannot validate authenticity against an authority register.
