# API Standards

Implemented in Phase 0: base path, health check, response envelope, error codes, request-id,
security headers, CORS, request validation helpers, structured logging. Everything else here is the
**standard that later phases must follow**.

## 1. Base and versioning

- Business endpoints: `/api/v1/<domain>/...` (domains listed in CLAUDE.md §10).
- Infrastructure: `GET /health` (unversioned, unauthenticated, no sensitive data).
- Breaking changes require `/api/v2`; additive changes stay in v1.
- Constants: `packages/api_contracts/lib/src/api_paths.dart`.

## 2. Resources and methods

| Method | Use | Success |
|---|---|---|
| GET | Read; list with filters/pagination | 200 |
| POST | Create or command (`/appointments/{id}/cancel`) | 201 (created) / 200 |
| PUT | Full replace (rare) | 200 |
| PATCH | Partial update (with `If-Match`/version for clinical & financial docs, from Phase 6) | 200 |
| DELETE | Soft-delete/deactivate where permitted; never for clinical/financial records | 204 |

Plural nouns, kebab-case paths (`/clinical-templates`), camelCase JSON fields, ISO-8601 UTC timestamps, money as integer minor units + `currency`.
Tenant selection: `X-Tenant-Id` header **as a selector only** (authorized against membership; see MULTI_TENANT §2).

## 3. Response envelope (implemented, `api_contracts`)

Success:
```json
{ "success": true, "data": { }, "meta": { "requestId": "…", "page": { "limit": 20, "hasMore": true, "nextCursor": "…" } } }
```
Failure:
```json
{ "success": false,
  "error": { "code": "validation_failed", "message": "The request is invalid.",
             "issues": [ { "field": "phone", "code": "invalid_phone", "message": "Enter a valid 10-digit mobile number." } ] },
  "meta": { "requestId": "…" } }
```
- `data` is an object (single resource) or `{ "items": [...] }` (lists).
- `message` is safe for display; clients branch on `error.code`.
- Never included: stack traces, exception text, SQL/Firestore paths, other tenants' identifiers.
- Every response has header `x-request-id` (always server-generated) and `cache-control: no-store`.

## 4. Status codes and error codes

| HTTP | `error.code` | When |
|---|---|---|
| 400 | `bad_request` | Malformed JSON, wrong content type |
| 401 | `unauthenticated` | Missing/invalid/expired/revoked token |
| 403 | `forbidden` | Authenticated but not permitted (also used when a tenant/resource must not be revealed) |
| 404 | `not_found` | Unknown route or resource (also for cross-tenant IDs) |
| 405 | `method_not_allowed` | (reserved; see TD-08) |
| 409 | `conflict`, `idempotency_conflict` | State conflict; same idempotency key with different payload |
| 413 | `payload_too_large` | JSON body > 256 KiB |
| 422 | `validation_failed` | Field-level validation errors (`issues[]`) |
| 429 | `rate_limited` | Throttled (Phase 1) |
| 500 | `internal_error` | Unexpected; generic message, details only in server logs |
| 503 | `unavailable` | Dependency down |

## 5. Validation

- Validate **every** request on the backend (`RequestValidator`, shared `Validators`). Collect all field issues, return one 422.
- Reject unknown/oversized/wrong-typed input; trim and normalise strings; enforce max lengths on every string.
- Client-side validation is for UX only.

## 6. Pagination, filtering, sorting

- Cursor pagination: `?limit=20&cursor=<opaque>`; default 20, max 100. Response `meta.page`.
- Filters as query parameters with documented allow-lists (e.g. `?status=booked&branchId=…&from=…&to=…`). Unknown filters → 422.
- Sorting: `?sort=createdAt:desc` from an allow-list matching available indexes.
- **Do not put PHI/PII in query strings where avoidable** (logs/proxies). Search by phone/name uses POST `/…/search` with a body.

## 7. Idempotency

`Idempotency-Key` header (client UUID) is **required** for payment creation/verification, refunds, and appointment booking. The backend stores key → request hash → response; replays return the original response; same key + different body → 409 `idempotency_conflict`.

## 8. Authentication and authorization (Phase 1+)

`Authorization: Bearer <Firebase ID token>` → verify → resolve tenant context → authorize per route (policy name in route registration) → audit. See SECURITY_ARCHITECTURE.

## 9. Middleware order

`request id → CORS → security headers → request logging → error handler → [auth → tenant context →] router`.

## 10. Logging

JSON lines to stdout: `time`, `severity`, `message`, plus fields passed through a redaction filter (names, phones, emails, tokens, clinical terms…). Request logs contain method, path (no query), status, duration, request id only. Never log bodies or tokens.

## 11. CORS

Exact-origin allow-list from `CORS_ALLOWED_ORIGINS`; no wildcard; preflight 204 for allowed origins, 403 otherwise. Android apps are not subject to CORS.

## 12. Documentation

Each phase appends its endpoints here (or a per-domain file under `docs/api/`) with: method + path, roles/permissions, request schema, response schema, error cases, audit event, example. OpenAPI generation is a candidate for Phase 1 (decide then).

## 13. Implemented endpoints (Phase 0)

| Method | Path | Auth | Response `data` |
|---|---|---|---|
| GET | `/health` | none | `{ "status": "ok", "service": "eazyclinic-backend", "version": "0.1.0" }` |

Any other path returns the 404 error envelope.
