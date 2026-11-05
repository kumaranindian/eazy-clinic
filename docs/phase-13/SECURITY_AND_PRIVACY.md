# Security and Privacy (Phase 13)

| Topic | Control | Evidence |
|---|---|---|
| Language ≠ authority | The language never reaches authorization, tenancy, country, currency or policy code. `preferredLanguage` is a display field on the account | `localization_backend_test.dart` ("language does not alter roles, tenant or country") |
| Mass assignment | `PATCH /auth/me` still rejects every field not on the allow-list; a language cannot be sent together with a forbidden field | "cannot be smuggled together with forbidden fields" |
| Input validation | Exact allow-list `en/ar/hi/ta`; case and region variants rejected | "unsupported or malformed languages are rejected" |
| **Bidirectional-text injection** | Values interpolated into notification templates have bidi controls (U+200E/F, U+061C, U+202A–E, U+2066–9) removed, so names or free text cannot reorder or disguise a message; the renderer's own isolates are added afterwards. HTML is still escaped | "bidi control characters in a value are removed" |
| Template safety | Single-pass `{{variable}}` replacement unchanged (no expressions); allow-listed variables only; missing value → error in every language; translated templates must use exactly the English placeholders and **no clinical variables** | placeholder-parity and "no clinical detail" tests |
| Push/notification content | Translated push texts are generic ("open the app for details") like their English originals | unchanged policy |
| Logs | Language values and request bodies are not logged; audit stores the field name | "audit event records the field name, never the value" |
| Persistence | The language is saved best-effort over the authenticated API; a failure keeps the local choice and is never shown with details | `LocalePersistence` tests |
| Client trust | The server never trusts the client's language for any decision; the apps only display it | — |
| Rules / storage | No Firestore/Storage rule change; `platform_users` remains backend-only (deny-all for clients) | existing rules tests (unrun here, TD-95) |
| Clinical meaning | Machine-assisted translations are **not** used for legal, clinical or consent wording; documents and templates with legal/clinical content are not translated in this phase | Plan §4 |
| Accessibility | Tap targets and labels checked by Flutter's guidelines on the sign-in screen in all four languages; contrast of the brand red remains TD-13 | `localization_test.dart` |
| Privacy | A language preference is personal data of low sensitivity; it is stored only on the user's own account, readable only by them (and backend), exported/deleted with the account | — |
