# Migration and Rollback

## Data
* `platform_users.preferredLanguage` is optional and additive. No existing document is changed; no migration runs. Existing users follow the device language until they choose one.
* Notification templates: new built-ins are code, not data. Tenant-defined templates are untouched; a tenant template for a language still wins over the built-in.

## Behaviour changes users will notice
| Change | Why |
|---|---|
| Money shows thousands separators and ISO codes for non-symbol currencies (`₹1,200.00`, `AED 1,200.00`) | Correct, locale-aware display (old: `₹1200.00`) |
| Date/time use the user's language style (`2 Jun 2026`, `12:00 am`) and the **clinic's** time zone | Old output used the device zone and 24 h text |
| Back/Show password/Search/Retry texts follow the language | Localized design-system widgets |
| Language menu appears in every app | New feature |

## Rollout
1. Deploy backend (adds the field and templates; old apps ignore unknown fields).
2. Release apps. No backend flag is required.
3. Optional: ask native speakers to review `tool/gen_arb.py` tables before announcing Arabic/Hindi/Tamil.

## Rollback
* Redeploy the previous apps/backend: the extra `preferredLanguage` field is ignored; nothing needs cleaning up.
* To hide a language, remove it from `supportedUiLanguages` (`common_models`) and the ARB; stored values for it are ignored by `PlatformUser.fromMap`.
