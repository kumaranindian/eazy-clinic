# API Contracts (Phase 14)

Standard envelope and errors (`docs/api/API_STANDARDS.md`). Clinic routes resolve the tenant from the caller's membership (`x-tenant-id` is only a selector). Platform routes need the stated permission.

## Clinic (`/api/v1`)

| Method & path | Permission | Notes |
|---|---|---|
| `GET /compliance/dashboard` | `compliance.view` | `{ tenantId, countryCode, disclaimer, readiness, profiles[], credentials{…}, counts }`. Each profile: `key,title,authority,jurisdiction,domain,appliesWhenNote,status,version,legalReview,applicability{status,reason,setBy,setAt},summary,requirements[]` (requirements only when applicability is `applies`; each with effective `status`, `storedStatus`, `expiresAt`, `evidenceId`, `requirementChanged`, `evidence` rules, `source`, `confidence`) |
| `GET /compliance/history` | view | newest first |
| `GET /compliance/evidence` | view | evidence metadata (no storage path) |
| `POST /compliance/evidence` | `compliance.manage` | `201`. Body: `profileKey, requirementKey, kind, title, documentNumber?, issuerName?, validFrom?, validTo?, contentType?(ignored), dataBase64`. Errors: `409` applicability not confirmed or requirement not applicable; `404` unknown register/requirement; `422` kind, dates, file type (PDF/PNG/JPEG by **bytes**), size (≤ 3 MB), expiry required for expiry-tracked requirements and must be in the future |
| `GET /compliance/evidence/{id}/file` | view | `application/pdf|png|jpeg`, `content-disposition: attachment; filename="evidence-{id}.ext"`, `cache-control: private, no-store`, `nosniff`. Each read is logged in the history and audit |
| `GET /compliance/credentials` | view | with computed `validity`, `daysToExpiry`, `verifiedAndValid` |
| `POST /compliance/credentials` | manage | `201`. `subjectType (facility|practitioner), subjectName, doctorId?, kind, authorityCode, authorityName, jurisdiction?, number, issuedOn?, validFrom?, validTo?, notes?` |
| `PATCH /compliance/credentials/{id}` | manage | partial; voids verification when a material field changes; `409` if archived |
| `POST /compliance/credentials/{id}/archive` | manage | |
| `POST /compliance/credentials/{id}/document` | manage | `{ dataBase64 }`; makes the credential `unverified` until a reviewer verifies this file |

## Platform (`/api/v1/platform`)

| Method & path | Permission | Notes |
|---|---|---|
| `GET /compliance/overview` | read | counts + disclaimer |
| `GET /compliance/profiles?countryCode=` , `GET /compliance/profiles/{key}` , `GET …/{key}/versions` , `GET …/{key}/impact` | read | impact = live tenants where it applies + change of the last version |
| `POST /compliance/profiles/seed-baseline` | manage | create-if-absent; never overwrites |
| `PATCH /compliance/profiles/{key}` | manage | `expectedVersion`, `reason` required; fields `title, authority, facilityTypes, appliesWhenNote, requirements, legalReview, status`; `409` stale; `422` invalid (missing source/owner, unknown category, reviewed without reviewer/date, high confidence without review date, duplicates) |
| `GET /compliance/review-queue` | review | submitted evidence across clinics, oldest first |
| `GET /tenants/{id}/compliance` , `…/compliance/history` , `…/compliance/credentials` | read | same dashboard as the clinic sees |
| `PUT /tenants/{id}/compliance/applicability/{profileKey}` | review | `{ status: applies|not_applicable|unknown, reason }`; `409` if the register's country differs from the clinic's |
| `GET /tenants/{id}/compliance/evidence` , `GET …/evidence/{eid}/file` | review | file view is logged |
| `POST /tenants/{id}/compliance/evidence/{eid}/review` | review | `{ decision: accept|reject, note }` (note required to reject). Accept → requirement `approved`, expiry = document `validTo` (required and in the future when tracked). `409` unless the evidence is the one currently under review |
| `POST /tenants/{id}/compliance/items/{profileKey}/{reqKey}/status` | review | `{ status: not_applicable|pending_evidence, reason }`; transition table enforced |
| `POST /tenants/{id}/compliance/credentials/{cid}/verify` | review | `{ decision: verify|reject, note }`; needs a submitted document and (to verify) an end date |

All write routes are rate limited per user. Unknown body fields are rejected (`422`) on every route.
