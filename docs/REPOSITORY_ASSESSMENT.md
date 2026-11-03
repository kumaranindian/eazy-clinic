# Repository Assessment

Assessment date: 2026-11-03 · Branch: `feature/phase-0-foundation` (from `develop` @ `7645b16`)

## 1. Current state before Phase 0

| Area | Finding |
|---|---|
| Git | Fresh repository. History: `9fe2b7f` (empty root on `master`) and `7645b16` (README + CLAUDE.md on `develop`). Remote `origin` = `github.com/kumaranindian/eazy-clinic`; `master` and `develop` pushed. |
| Source code | **None.** No Flutter apps, no Dart backend, no packages. |
| Firebase | No configuration, rules, indexes or environment files. |
| Dependencies | None. |
| Tests / CI | None. |
| Documentation | `CLAUDE.md` (permanent specification) and `README.md` only. |
| Assets | Two untracked reference images in the repo root: the approved logo and the app-flow mockup. |

Existing functionality to preserve: **none** (nothing to rewrite or delete).
The two official images were moved (not modified) into
`assets/branding/original/` and `docs/design/reference/`; the logo is
byte-identical to the copy in `~/Downloads`.

## 2. Surrounding workspace (out of scope, untouched)

`eazy-clinic/` lives inside `~/development/workspace`, which is itself a Git
repository for **unrelated** projects (origin `kumaranindian/eazy_gold`;
siblings include `easy_school`, `eazy-school-lesson-plans`). It was neither
modified nor reused. EazyClinic has its own repository (created inside
`eazy-clinic/`). Consequences:

- The parent repo sees `eazy-clinic/` as an untracked directory. If that is
  noisy, add `eazy-clinic/` to the parent's `.git/info/exclude`.
- No code was imported from sibling projects; any reuse (e.g. auth patterns)
  must be a deliberate, documented decision in a later phase.

## 3. Toolchain

| Tool | Version | Notes |
|---|---|---|
| Flutter | 3.32.8 (stable, July 2025) | Works, but is old; see TECHNICAL_DEBT TD-02. |
| Dart | 3.8.1 | |
| Android SDK | 36 | Debug APKs build. |
| Chrome | present | Flutter Web builds. |
| Xcode | simulator runtimes unavailable | iOS is not a target; no impact. |
| Docker | not verified | Backend `Dockerfile` written but **not built** in Phase 0. |
| Firebase CLI | not verified/used | No Firebase commands were run. |

## 4. Findings and risks

| # | Finding | Severity | Decision |
|---|---|---|---|
| F-1 | No official, maintained Firebase **Admin SDK for Dart** exists from Google. Community packages (e.g. `dart_firebase_admin`) or Google REST APIs via `googleapis`/`googleapis_auth` are the options. CLAUDE.md mandates "Dart backend + Firebase Admin SDK". | **High** (Phase 1 blocker) | Phase 1 must start with a short spike comparing options (token verification, Firestore transactions, FCM, Storage signed URLs). Result goes into an ADR. Phase 0 intentionally adds **no** Firebase dependency. |
| F-2 | Logo is raster with an opaque white background; no vector/transparent master. | Medium | Used as-is on white surfaces. Request a vector/transparent master (TD-03). |
| F-3 | Mockup contains choices that conflict with CLAUDE.md or are undecided (self-selected signup role, Google sign-in, red header, patient password login). | Medium | Catalogued in `design/UI_UX_REFERENCE_ANALYSIS.md` §11 for decision before the relevant phase. |
| F-4 | Parent workspace is an unrelated Git repo. | Low | See §2. |
| F-5 | Android debug build failed once (4m35s) and succeeded on immediate retry without changes; the first error was not captured. Suspected first-run Gradle/dependency download issue. | Low | Re-verify on a clean machine/CI (TD-07). |

## 5. Security review of the starting point

No secrets, credentials, `.env` files or service-account keys exist in the
repository. `.gitignore` now blocks real env files, `google-services.json`,
`GoogleService-Info.plist`, keystores, service-account JSON and private keys.
Firebase rules are deny-all baselines.

## 6. Recommendations (carried into the roadmap)

1. Start Phase 1 with the Firebase-Admin-on-Dart spike (F-1).
2. Decide the mockup conflicts (F-3) before building auth screens.
3. Obtain a transparent/vector logo master (F-2).
4. Add CI (format, analyze, test, build) once the repo is on GitHub Actions; `scripts/check_all.sh` is the local equivalent.
5. Upgrade Flutter/Dart before Phase 1 feature work, or record the pin as an ADR.
