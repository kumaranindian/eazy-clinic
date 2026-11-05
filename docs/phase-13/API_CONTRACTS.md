# API Contracts (Phase 13)

## `PATCH /api/v1/auth/me` (changed)
Body fields (any of): `displayName`, `phoneNumber`, **`preferredLanguage`**. Unknown fields → `422 not_allowed` (unchanged: `platformRole`, `uid`, `accountStatus`, tenant ids… cannot be set).
`preferredLanguage`: one of `en`, `ar`, `hi`, `ta` (exact, lower case) or `null` to clear. Otherwise `422` with `unsupported_language`.
Response: the profile (`AuthProfileDto`), which now includes `preferredLanguage` when set.
Audit: the security event `profile_updated` records the **field names** only.

## `GET /api/v1/auth/me`, `GET /api/v1/auth/session`, `POST /api/v1/auth/profile/initialize` (changed)
Profile/session DTOs include `preferredLanguage` (omitted when unset). The session value initialises the app language after sign-in.

## `GET /api/v1/clinics/current/country-config?branchId=&locale=` (Phase 12, behaviour extended)
`locale` is validated (`^[A-Za-z]{2,3}([-_][A-Za-z]{2})?$`); the resolved tag now comes from `en, ar, hi, ta`. Unsupported values are ignored (fall through the precedence order). No change to authorization.

## Notification templates
`POST/PATCH …/notification-templates` already accept a two-letter `locale`; no contract change. Rendering now: prefers the recipient's `locale`, else English; strips bidi controls from values; isolates values in RTL languages.

## No other endpoint changed. Server error messages remain English.
