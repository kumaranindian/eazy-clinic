# Coding Standards

Authoritative rules: CLAUDE.md §12, §19. This file makes them concrete. Lints enforce what they can
(`analysis_options.yaml`, `analysis_options_flutter.yaml`: strict casts/inference/raw types, single quotes, trailing commas, sorted imports and dependencies, no `print`).

## 1. Flutter architecture (feature-first)

```
lib/
  core/{config,routing,network,errors,security,theme,utils}/   # app-wide plumbing
  shared/{widgets,models,services}/                             # cross-feature, app-local (prefer packages/)
  features/<feature>/
    data/          # API clients (DTOs ⇄ JSON), repositories (implementations)
    domain/        # entities, repository interfaces, use-cases, permission checks (pure Dart)
    presentation/  # pages, widgets, Riverpod controllers/notifiers
```
- Presentation → domain → data direction only. Domain has no Flutter imports.
- **No business rules in widgets.** Widgets render state and dispatch intents.
- Widgets > ~150 lines or with > 2 responsibilities are split. Prefer small `const` widgets.
- Reuse `design_system` components; no hex colours, text sizes or magic numbers in features.
- Never call Firestore/Storage directly for protected data; use the API client.
- No hardcoded IDs, tenant values, URLs (use `ClientConfig`).
- Shared logic goes to `packages/` (pure Dart) rather than being copied between apps.

## 2. Riverpod

- Providers are top-level `final`s, named `<thing>Provider`. Keep state immutable.
- `Notifier`/`AsyncNotifier` for state + actions; `Provider` for DI (API client, repositories); `FutureProvider`/`StreamProvider` for read-only async.
- Inject dependencies via `ref.watch(apiClientProvider)`; tests override providers (see `clientConfigProvider` tests).
- No `ref.read` in `build` for reactive data; no global mutable singletons.
- Errors surface as `AsyncError` mapped to user-safe messages; never show raw exceptions.

## 3. GoRouter

- Routes defined once per app in `core/routing`, paths as constants in `AppRoutes`.
- Guards via `redirect` using auth/permission state; **guards are UX only**, the backend enforces access.
- Use `StatefulShellRoute` for tabbed navigation; deep links must survive refresh on web.
- Dev-only routes are registered only when `!environment.isProduction`.

## 4. API client conventions (Phase 1)

Dio, one `ApiClient` per app configured with `ClientConfig.apiBaseUrl` + `/api/v1`; interceptors: auth token (refresh on 401 once), request id logging, retry for idempotent GETs, `Idempotency-Key` for payment/booking; responses parsed into `ApiEnvelope`; failures mapped to typed `AppFailure` (network, unauthenticated, forbidden, validation, server). Models come from JSON serialization with generated code (`json_serializable`) when models are introduced, living in shared packages when used by more than one app.

## 4b. Error handling and logging

- Backend: throw `ApiException`; never return raw errors; unexpected errors → 500 generic.
- Flutter: central error mapper → `EcErrorState`/snackbar; log with `debugPrint`-level logger that never includes personal or clinical data.
- No `print` in committed code (lint). No PHI in logs, analytics or crash reports.

## 5. Dart/backend

- Layers: route → service (rules, authorization) → repository interface → infrastructure adapter. Handlers stay thin.
- Validate every request with `RequestValidator`/`Validators`; reject unknown fields where safe.
- Repositories require a resolved `TenantContext`; never raw tenant IDs from requests.
- Money in integer minor units; times in UTC.
- Async: `await` or explicitly `unawaited`; no fire-and-forget without logging errors.

## 6. Naming and style

- Files `snake_case.dart`; types `UpperCamelCase`; members `lowerCamelCase`; constants `lowerCamelCase`.
- Design-system symbols prefixed `Ec`; providers suffixed `Provider`; routes in `AppRoutes`.
- JSON `camelCase`; enum wire values `snake_case` strings (`wireName`), never `index`.
- Format with `dart format` (CI/`check_all.sh` fails on diffs). Imports sorted; relative imports inside a package's `lib/`, package imports across packages.

## 7. Dependencies

Add a dependency only when it removes real complexity; record the reason in the PR and, for new frameworks, in MASTER_ARCHITECTURE (ADR).
Pin with caret ranges; commit `pubspec.lock` for apps and backend; keep `dependencies` alphabetically sorted (lint).
Current runtime deps: apps → `flutter_riverpod`, `go_router`, `design_system`, `utilities`; backend → `shelf`, `shelf_router`, shared packages.

## 8. Git

Branches `feature/<scope>`; Conventional Commit messages (`feat(scope):`, `fix:`, `chore:`, `docs:`, `test:`); small logical commits; never commit secrets,
generated build output or real env files; no force-push to `develop`/`master`.

## 9. Definition of done (per module)

Implemented and reviewed · analyzer clean · formatted · tests (unit, API incl. authz & tenant isolation, widget) passing · docs updated (API, DB, workflows, limitations) ·
no new debt without a TECHNICAL_DEBT entry · demonstrable end-to-end workflow.
