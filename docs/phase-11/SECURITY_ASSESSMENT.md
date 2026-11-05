# Security assessment

Method: code review plus **executable gates** added in this phase. Everything ran against the in-memory store or the local Firestore emulator. No penetration test, no external scan, no review by a qualified security or legal professional was done.

## Executable evidence
| Gate | What it proves | File |
|---|---|---|
| Every route needs a token | About 340 registered routes (read from the source, so new ones are included) answer 401 without a token and with a garbage token. Only `/health` and `/ready` are open. | `test/security/route_auth_test.dart` |
| Least privilege | A signed-in clinic member with only the basic read permissions, and a signed-in stranger with no membership, are refused by every route except a short allow-list of own-account or static-data routes. No server error on any of them. | same |
| Mass assignment | Every changing route given a body made only of `tenantId`, `role`, `status`, `uid`, `isAdmin`, `permissions` never succeeds, except two body-less actions on the caller's own data. | same |
| Cross-tenant | The owner of clinic B (all permissions in B) cannot read 21 resource types of clinic A by id and cannot change 17 (patient, appointment, consultation, prescription, invoice, lab order and results, notification, template, delivery, queue entry, device); lists show nothing; clinic A is unchanged. | `test/security/cross_tenant_test.dart` |
| Firestore and Storage rules | Deny-all for clients; positive and negative tests over every collection incl. collection-group queries and audit deletion (30 tests on the emulator). | `firebase/rules-tests` |
| Configuration | Production refuses to start without project id and bucket, with wildcard, http or local origins, or with revocation checks off. | `test/config/app_config_test.dart` |
| Secrets | No key, token or private key in tracked files or in any commit (pattern scan incl. history). | `scripts/security_scan.sh --history` |
| Earlier phases | Per-module negative tests (tenant, branch, role, patient, dependent, device token, export owner, report scope) remain green. | Phases 4-10 test suites |

## Review by area
| Area | Assessment |
|---|---|
| Authentication | ID token signature, issuer, audience and expiry verified; revocation checked by default and cannot be disabled outside dev; account status enforced; roles come from server-side memberships. MFA for privileged users is **not implemented** (F-10). |
| Authorization | Tenant, branch scope and permission derived from server records on every route; resources are looked up inside the caller's tenant, so a foreign id is 404. |
| Input and output | Bodies are validated field by field and reject unknown fields; JSON body size limit (1 MB default, 5 MB for document uploads); uploads are type-checked by content (PDF/PNG/JPEG/WebP), not by name; stored files get generated ids, so no path traversal; downloads are `attachment`, `nosniff`, `no-store`. No raw provider body or stack trace reaches a client. |
| Transport and headers | HSTS, `nosniff`, `DENY` framing, `no-referrer`, API CSP `default-src 'none'`, exact-origin CORS with no wildcard. TLS itself is terminated by the host (not verifiable here). Web hosting headers are a draft (`firebase/hosting.headers.example.json`) and unverified (F-08). |
| Abuse controls | Rate limits on authentication, writes, family and identity linking, search paths, retries, device registration and export creation. Limits are per instance (in-memory), so several instances multiply them (F-11). |
| Clinical data | Finalized consultations and prescriptions change only by recorded amendment; verified lab results and published reports are versioned, never overwritten; sensitive reads are audited; patient access is allow-listed. Notifications, logs and exports carry no clinical content (tested). |
| Payments | Server-side only; idempotency keys with body fingerprints; immutable invoice/payment/refund history. **No payment gateway is configured**, so webhook signature verification and reconciliation against a provider are untested (F-12, Informational until a gateway is approved). |
| Privacy | Consent and revocation exist (Phase 4/8); account deletion is a recorded request without a processing workflow (TD-66); retention periods are not defined. No claim of DPDP compliance is made; a qualified review is required (F-13). |
| Logging | One structured line per request without query, headers or body; severity by status; no PII or tokens in log calls (grep review). |

## Findings
| ID | Severity | Finding | Status |
|---|---|---|---|
| S-01 | Low | `GET /billing/gateway` was readable by any clinic member (payment configuration) | **Fixed** (needs billing or payment permission) |
| S-02 | Low | Production CORS validation accepted `https://localhost` | **Fixed** and tested |
| S-03 | High | Android release builds were signed with the debug key | **Fixed in Gradle (fails closed); not built here; keystore not provisioned** |
| S-04 | Medium | No MFA for privileged roles | Open (F-10) |
| S-05 | Medium | Rate limits are per instance | Open (F-11) |
| S-06 | Medium | Dependency scanning is limited to `npm audit` and `pub outdated`; Dart has no advisory scanner in this toolchain | Open |
| S-07 | Medium | Web security headers/CSP unverified; hosting target undefined | Open (F-08) |
| S-08 | Informational | Dev tooling advisories (34, one critical transitive `tar` in `firebase-tools`) not shipped to users | Triaged: update the tooling |
| S-09 | Informational | 10 self-service or static routes are intentionally open to any signed-in person | Allow-listed with reasons in the test |

**No Critical finding** was produced by these gates. That is a statement about what was tested, not a guarantee.
