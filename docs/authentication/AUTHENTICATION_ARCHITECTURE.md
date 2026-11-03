# Authentication Architecture (Phase 1)

Status: **implemented and tested with test doubles**. Not yet exercised against a live Firebase project (see §8).

## 1. Principle

Firebase Authentication proves **who** the caller is. The backend decides **what** they may do, using only
server-side records. Nothing the client sends (uid, role, tenant, status) is ever used as authorization evidence.

```
Flutter app ──(Firebase SDK)──► Firebase Auth ──► ID token
     │                                              │
     └──────── Authorization: Bearer <ID token> ────┘
                                  │
                   Shelf backend  ▼
   rate limit (IP) → tokenAuthMiddleware → accountMiddleware → handler
                      verify token          load platform_users/{uid}
                      check revocation      gate on accountStatus
                      → VerifiedIdentity    → AuthContext (+ memberships)
```

## 2. Components

| Layer | Component | Location |
|---|---|---|
| Shared contracts | `AccountStatus`, `Permission`, `PermissionPolicy`, roles | `packages/common_models` |
| | `AuthSessionDto`, `AuthProfileDto`, `MembershipSummaryDto`, error codes | `packages/api_contracts` |
| Backend | `FirebaseTokenVerifier` (RS256, Google signing keys) | `backend/lib/features/auth/application/token_verifier.dart` |
| | `GoogleSigningKeyProvider` (x509 cert cache, `max-age`) | `.../data/signing_key_provider.dart` |
| | `IdentityToolkitAuthAdmin` (lookup, revoke) | `.../data/firebase_auth_admin.dart` |
| | `FirestorePlatformUserStore` (REST) | `.../data/firestore_platform_user_store.dart` |
| | `tokenAuthMiddleware`, `accountMiddleware` | `.../application/auth_middleware.dart` |
| | `AccountService`, `SecurityEventRecorder`, `AccessResolver` | `.../application/`, `.../domain/` |
| | `AuthModule.protect()` (reusable guard for future routers) | `.../presentation/auth_routes.dart` |
| Flutter | `app_core`: repository, API client, `AuthController`, redirect rules, screens | `packages/app_core` |
| Apps | audience, wording, routes, home | `apps/*/lib/main.dart`, `core/routing/` |

## 3. Decisions (ADRs)

| # | Decision | Reason |
|---|---|---|
| 012 | **Resolves TD-01.** No official Firebase Admin SDK exists for Dart. The backend verifies ID tokens itself (RS256 against Google's published certificates; checks `alg`, `kid`, signature, `exp`, `iat`, `auth_time`, `aud`, `iss`, `sub`) using `dart_jsonwebtoken`, and calls Identity Toolkit / Firestore REST with `googleapis_auth` Application Default Credentials. | Only Google-published / widely used packages; no unofficial Admin SDK clone; approved by the product owner. |
| 013 | New shared Flutter package `packages/app_core` (resolves part of TD-05). | Authentication logic must not be duplicated across three apps (Phase 1 requirement). |
| 014 | `platform_users/{uid}` now holds the identity of **every** account (not only Avail404 staff). Staff are distinguished by a server-written `platformRole`. | Single identity record per Firebase user; supersedes the Phase 0 schema text. |
| 015 | `POST /auth/profile/initialize` creates the identity record. Client SDK still performs sign-in/registration/reset/sign-out. | The backend must hold a trusted profile before any protected call; provisioning derives every field from the verified token. |
| 016 | Revocation is checked on **every** request in staging/production (`AUTH_CHECK_REVOKED=true`, mandatory outside dev). | Immediate effect of suspension/revocation; cost is one Identity Toolkit lookup per request (see TD-14). |
| 017 | **Firestore emulator** is used for rules and store tests (`scripts/test_emulator.sh`). The Auth emulator is not (its tokens are unsigned and are correctly rejected by the production verifier); token tests use a generated RSA key and an openssl-issued certificate check. | Real Firestore behaviour without a cloud project (TD-15). |

## 4. What public registration can and cannot do

Registration creates a Firebase identity and a `platform_users` record (`pending` until the e-mail is verified, then `active`).
It grants **no** platform role, clinic membership, patient-record access or tenant. There is no role/tenant field in any
auth request, and tests assert that extra body fields, headers, query parameters and custom token claims are ignored.

## 4a. Authentication state model

| Spec state | Implementation (`AuthState`) |
|---|---|
| initializing, profileLoading | `AuthResolving` (every route held on the loading screen) |
| unauthenticated | `Unauthenticated` (optional notice, e.g. session ended) |
| authenticated | `Authenticated(user, session)` (only after the backend confirmed an active, admitted account) |
| profileIncomplete | resolved automatically (`session` → `account_not_provisioned` → `profile/initialize`); if that fails → `AuthFailed` with retry |
| pending | `AccessDenied(emailUnverified)` |
| suspended / disabled | `AccessDenied(suspended / disabled)` |
| unauthorized | `AccessDenied(notAuthorized)` |
| error | `AuthFailed(isNetwork)` |

## 5. Access resolution contract

`AccessResolver.membershipsFor(user)` returns the clinic memberships derived from trusted records. Phase 1 ships
`NoMembershipsAccessResolver` (always empty) because the `members` model arrives in Phase 3; Phase 3 swaps the implementation.
Apps use the result only to choose a screen (`AppAudience.admits`); the backend re-authorizes each request.

| App | Admits an active account when |
|---|---|
| Clinic Web | server-side `platformRole` is set, or a membership has a clinic staff role |
| Doctor | a membership has role `doctor` |
| Patient | any active account (clinic data access is a separate consent decision, Phase 4) |

Consequence: **until Phase 2/3, nobody can enter Clinic Web or Doctor without a manually assigned `platformRole`**; they see "Access not available".

## 6. Deferred

`POST /auth/account-status` (no authorized admin use case yet), MFA enforcement, clinic roles/permissions, shared rate limiter,
social/phone sign-in, device/session list, Firebase App Check.

## 7. Failure behaviour

Fail closed: token invalid → 401; keys or revocation lookup unavailable → 503 (never "allow"); unknown stored status → treated as `disabled`;
missing profile → 403 `account_not_provisioned`.

## 8. Not verified

Because no Firebase project/credentials exist in this environment, the following were **not** run against real services: Firebase sign-in,
Google signing-key fetch, Identity Toolkit `accounts:lookup/update` request shapes, Android builds (Android SDK
download is blocked by the sandbox proxy). Firestore REST calls **were** verified against the local Firestore emulator. Request shapes follow Google's REST documentation and are covered by unit tests with a mock HTTP client.
Run the manual checklist in `AUTHENTICATION_WORKFLOWS.md` §7 against the dev Firebase project before relying on this.
