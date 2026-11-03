# Security Architecture

Status: **Documented.** Implemented in Phase 0: deny-all Firebase rules (not deployed), secrets hygiene
(`.gitignore`), log redaction, security headers, strict CORS, fail-fast config, generic 500 responses,
request-id correlation. Everything else is the design for Phases 1–11.

Healthcare data is sensitive personal data. Requirements: CLAUDE.md §13, §14, §19. Applicable law:
India's Digital Personal Data Protection Act, 2023 and its rules (legal review required before launch). No ABDM/ABHA
compliance or connectivity is claimed.

## 1. Trust model

| Zone | Trust |
|---|---|
| Flutter apps (web, Android) | **Untrusted.** Anything can be modified or replayed. UI hiding is cosmetic. |
| Backend (Shelf) | Trusted policy decision/enforcement point. |
| Firebase (Auth, Firestore, Storage, FCM) | Trusted storage/identity, accessed from backend only. |
| Razorpay | Trusted only after signature/webhook verification. |

## 2. Authentication (Phase 1: implemented)

Details: [docs/authentication/](../authentication/AUTHENTICATION_ARCHITECTURE.md).

- Firebase Authentication; clients send ID tokens. The backend verifies them itself (no official Dart Admin SDK, ADR 012): RS256 only, `kid` from Google's published certificates, signature, `exp`/`iat`/`auth_time`, issuer `https://securetoken.google.com/<projectId>`, audience = the **current environment's** project id, `sub`, non-anonymous provider.
- Revocation and the Firebase `disabled` flag are checked on every request outside dev (`AUTH_CHECK_REVOKED` cannot be turned off in staging/production); lookup failures fail closed (503).
- Trusted profile `platform_users/{uid}` + `accountStatus` gate every protected route; only `active` passes unless a route explicitly allows more.
- Session revocation: `POST /auth/revoke-sessions`, `POST /auth/logout {allDevices}`; short token lifetime (1 h).
- Security events (provisioning, login, denied login, activation, logout, revocation) → structured log and `platform_audit_logs`; no tokens/e-mails/names. Rate limiting on `/auth/*` (in-memory, TD-16).
- Sign-up never grants a role, tenant or membership (tested: body, header, query and token-claim spoofing).
- Firestore rules: deny-all for clients (no client access to `platform_users` or audit logs); verified by 13 emulator tests, and a mutation check showed the tests fail when the rules are loosened.
- Identity writes use strict field allow-lists (`not_allowed` 422), so registration and `PATCH /auth/me` cannot carry roles, tenants or status.
- **Phase 2 control plane:** every platform route = `protect()` (verified token, active account) + a platform permission derived from the server-side `platformRole`; support admin is read-only; the applicant can never change status (no field accepted, `approve` forbids actor = applicant); tenant context comes from server-side memberships (`X-Tenant-Id` is a selector only); provisioning is idempotent and atomic; audit entries are append-only and written in the same commit as the change; all new collections are backend-only (rules tested). See `docs/phase-2/`.
- **Deferred:** MFA enforcement for privileged roles, App Check, shared rate limiter, account-status administration endpoint.

## 3. Authorization (every protected request)

Sequence in MULTI_TENANT_ARCHITECTURE §3. Policies are centralised (`backend/lib/modules/*/…policy.dart` + one permission catalogue in `common_models`), not scattered in handlers. A route without a declared policy fails startup tests.

- **Tenant isolation:** repositories require a resolved `TenantContext`; no raw tenant IDs from clients.
- **Branch access:** filter by `membership.branchIds`.
- **RBAC:** permissions are strings (`patient.read`, `consultation.finalize`, `invoice.create`…) resolved from role + overrides (see RBAC matrix). Owners configure within platform-defined bounds.
- **Resource relationship:** e.g. a doctor may read a patient's clinical data only through an appointment/consultation relationship or explicit permission; reception sees demographics, not clinical notes.
- **Patient consent:** required for patient-initiated sharing, caregiver access and any cross-clinic scenario; checked at read time, revocation effective immediately.

## 4. Patient data protection

- Clinic-scoped medical records; global account holds minimal identity (MULTI_TENANT §6).
- Phone number is **never** an authorizer. Linking = verified account + clinic-side authorization + recorded consent.
- Field-level restraint: list endpoints return minimal fields; detail endpoints enforce permission per section (history, vitals, notes).
- Purpose limitation, minimisation and retention: schedule in PATIENT_DATA_PRIVACY (Phase 4). Rights handling (access, correction, erasure, nomination, grievance) designed in Phase 4.
- No clinical data in push notification payloads, URLs, logs or analytics.

## 5. Audit logging

Append-only `audit_logs` (tenant) and `platform_audit_logs`. Events: login/logout/MFA, role & permission change, patient record read/search/export, consultation create/finalize/amend, prescription issue, document access, consent grant/revoke, invoice finalize/void, payment/refund, settings changes, tenant approval/suspension. Fields: actor, role, action, resource, outcome, request id, time, field names changed (not clinical values). Not editable by any API.

## 6. Secure document access

Files in Storage under `tenants/{tenantId}/…`; metadata in `documents`. Download/upload via **short-lived signed URLs** (≤ 5 min) issued by the backend after authorization; MIME allow-list, size limits, content-type sniffing, optional malware scan hook; every issuance audited. Storage rules deny all direct client access.

## 7. Firestore and Storage rules

Phase 0: `firebase/firestore.rules` and `firebase/storage.rules` = `allow read, write: if false`. Admin SDK bypasses rules; therefore the backend must enforce everything. Any future direct-client access needs a design review and rules tests (emulator).

## 8. Payment security (Phase 7)

Server-side order creation; **verify Razorpay signature** on capture; **verify webhook signature**; reconcile by order/payment ID; idempotency keys; never trust client "success"; no card data stored (PCI scope stays with Razorpay); Razorpay secret only in backend secret store; payment/refund logs with actor; invoices immutable after finalization.

## 9. Transport, headers, CORS, abuse

HTTPS only (HSTS, `https` required in staging/production by config validation). Security headers on all responses (nosniff, frame deny, CSP `default-src 'none'`, no-store, referrer none). CORS exact allow-list. Rate limiting per IP/uid on auth, OTP, search and payment endpoints (Phase 1). Body size cap 256 KiB (uploads use signed URLs). Input validation on every request.

## 10. Secrets and configuration

No secrets in the repo (`.gitignore` blocks env files, keystores, service-account JSON, `google-services.json`). Backend gets credentials from the platform (Application Default Credentials / secret manager). Apps only receive public identifiers via `--dart-define-from-file`. Environment isolation: separate Firebase projects, separate Razorpay keys, distinct service accounts. Rotation runbook in Phase 11.

## 11. Logging restrictions

Structured JSON; redaction filter on fields; request logs omit query strings, bodies, headers; errors log exception *type* + request id only. Clinical or personal data must never be logged (CLAUDE.md §19.16). Tests assert this.

## 12. Backup, recovery, incident response (Phase 11)

Firestore scheduled exports to a locked bucket (per environment), restore drill, RPO/RTO targets, breach-notification procedure aligned with DPDP obligations, access review cadence.

## 13. Threat model (initial)

| Threat | Mitigation |
|---|---|
| Cross-tenant data access (IDOR) | Tenant context on every query; cross-tenant tests; 404/403 uniformity |
| Privilege escalation via signup/profile edit | Roles server-side only; invite/approval workflow; role-change audit + token revoke |
| Phone-number account takeover to read records | Phone never authorizes; link requires verification + consent |
| Token theft/replay | Short lifetimes, revocation, HTTPS, no tokens in logs/URLs |
| Payment tampering | Backend verification, idempotency, immutable invoices |
| Sensitive data leakage in logs/notifications | Redaction, no PHI in payloads, tests |
| Malicious uploads | MIME/size allow-list, signed URLs, scanning hook |
| Misconfiguration (wrong environment/CORS wildcard) | Fail-fast config validation (implemented, tested) |
| Insider misuse | Role least-privilege, audit logs, access reviews |

## 14. Testing

Security test suite is mandatory per phase (CLAUDE.md §15): unauthorized access, cross-tenant access, role escalation, patient record access, document access, payment manipulation, invalid tokens. Phase 0 tests cover config validation, redaction, error hiding, CORS allow-list and security headers.
