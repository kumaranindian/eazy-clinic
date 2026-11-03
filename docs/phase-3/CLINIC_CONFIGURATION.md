# Clinic Configuration (Modules A and B)

## Profile (`GET/PATCH /api/v1/clinics/current`)
Name, type, specialities, registration number, e-mail, phone, alternate phone, website, address. Permissions: `clinic.view` / `clinic.update`. The tenant is always the caller's own (derived from the membership); the body is strict — unknown or sensitive fields (`tenantId`, `status`, `ownerUid`, plan fields …) are rejected with 422. Address updates merge into the stored address.

## Logo (`PUT/GET /api/v1/clinics/current/logo`)
PNG, JPEG or WebP only, detected from the **magic bytes** (the declared content type is not trusted), max 512 KB. Stored in the private bucket (`STORAGE_BUCKET`) under `tenants/{tenantId}/branding/logo`; never public. The Flutter app fetches it through the authenticated endpoint. Replacing the logo overwrites the object and is audited. Storage rules deny all direct client access.

## Operating configuration (`GET/PATCH /api/v1/clinics/current/settings`, `clinic.settings.manage`)
| Setting | Rule |
|---|---|
| `timeZone` | Explicit IANA zone (default `Asia/Kolkata`); never inferred from the browser |
| `weeklyHours` | Keys `"1"`–`"7"` (Mon–Sun); each `{open, from, to, breaks[]}`; missing days are closed |
| Overnight | `to < from` runs past midnight (`overnight: true`); `from == to` rejected |
| Breaks | ≤ 5 per day, inside the opening period, non-overlapping |
| `holidays` | ≤ 100, unique valid dates `YYYY-MM-DD` |
| `specialDays` | ≤ 100 open days with their own hours; a date cannot be both holiday and special day |
| Default appointment / consultation durations | Bounded integers (minutes) |

Branches may override the weekly hours (`weeklyHours` on the branch; `null` = inherit). Validation lives in `backend/lib/features/clinic/settings/operating_hours.dart` and is covered by `clinic_config_test.dart`.

## Subscription gating
All routes pass the Phase 2 entitlement gate: blocked tenants answer 403, read-only tenants refuse writes (`writesAllowed`).
