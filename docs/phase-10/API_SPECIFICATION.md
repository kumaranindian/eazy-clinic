# Phase 10 API (`/api/v1`)

Standard envelope, errors and pagination. Every route needs authentication, tenant membership and branch scope; the permission is shown. Bodies reject unknown fields.

## Staff notification center (any clinic member, own data only)
| Method / path | Notes |
|---|---|
| `GET /notifications?unread=true&limit&cursor` | newest first, archived hidden |
| `GET /notifications/unread-count` | `{unread, capped}` (capped at 100) |
| `POST /notifications/{id}/read`, `/archive` | own entries only; another user's id is 404 |
| `POST /notifications/read-all` | up to 200 per call |
| `GET /notifications/preferences`, `PATCH /notifications/preferences` | `pushEnabled`, `channels{email,sms,whatsapp}`, `categories{...}`; unknown keys 422; audited |
| `POST /notifications/devices` | `deviceId`, `token`, `platform` (`android`/`web`), `appVersion?`; owner is always the caller; the token is never returned; 30/hour |
| `DELETE /notifications/devices/{id}` | only the caller's device; deactivates; audited |

## Patient app (account-scoped)
`GET /patient/notifications` (archived hidden), `POST /patient/notifications/{id}/read`, `/archive`, `POST /patient/notifications/read-all`, `GET/PUT /patient/notifications/preferences`, `POST/DELETE /patient/devices` (Phase 8).

## Administration (`notifications.manage`: owner, admin)
| Method / path | Notes |
|---|---|
| `GET /admin/notification-templates` | built-in (read-only) and clinic templates, with allowed variables |
| `POST /admin/notification-templates` | `name`, `eventType`, `channel`, `locale`, `subject?`, `body`; one per event/channel/language (409); unknown variables 422 |
| `PATCH /admin/notification-templates/{id}` | `name`, `subject`, `body`, `active`; bumps version, keeps the old one |
| `POST /admin/notification-templates/{id}/preview` | `variables?`; renders only; sends nothing |
| `GET /admin/notification-deliveries?status&channel&type` | no title, body, recipient or token in the rows; branch-scoped |
| `POST /admin/notification-deliveries/{id}/retry` | failed or configuration-required only; audited; 30/hour |
| `GET /admin/notification-channels` | configured / enabled / paused per channel |
| `POST /admin/notification-channels/{channel}/pause`, `/resume` | audited |
| `GET/PUT /admin/notification-settings` | `channels`, `reminderLeadMinutes` (up to 4, 15 min to 7 days), `followupLeadDays` (0-14), `locale` |
| `GET /admin/notification-health` | counts, retry backlog, failures, events waiting |

## Reports and exports (`reports.view`, `reports.export`)
| Method / path | Notes |
|---|---|
| `GET /reports/dashboard?from&to&branchId&doctorId` | headline tiles per permitted section |
| `GET /reports/{appointments,queues,patients,consultations,laboratory,billing}` | same filters; see `REPORTING_DEFINITIONS.md` |
| `POST /reports/exports` | `report`, `format` (`csv`/`pdf`), filters; 201; 20/hour; refused if the report would be truncated or too large |
| `GET /reports/exports` | the caller's own exports (download history) |
| `GET /reports/exports/{id}` | the requester only; `expired` flag |
| `GET /reports/exports/{id}/download` | the requester only, before expiry (6 h); `Cache-Control: private, no-store`; audited |
