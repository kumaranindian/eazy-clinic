# Phase 12 – Global Architecture & Country Configuration: Implementation Plan

Branch: `feature/phase-12-country-configuration` (from `develop` @ `b1205f0`). Date: 2026-11-05.
Specification: `EazyClinic_Phase_12_Implementation_Prompt.docx` + `CLAUDE.md`.

> **Branch note.** The prompt says to stay on `feature/phase-0-foundation`. At the user's later instruction
> (one branch per phase, delivered by pull request into `develop`) this phase uses its own branch. The
> prompt's other rules (no push to production, no deploy, no force operations) were followed.

## 1. Pre-flight findings (what the code actually was)

| Area | Finding |
|---|---|
| Tenancy | Tenants (`tenants/{id}`) are provisioned from `clinic_applications` by `TenantService.approve` (two atomic phases). No country on tenant or application. |
| Country today | Free-text `address.country` (default "India") on applications, clinic profile and branches; PIN-code regex applied by comparing that text with "india"; phone validation was Indian-mobile only (`Validators.indianMobile`). |
| Settings | `tenants/{t}/clinic_settings/operations` already held `timezone`, `currency` (only `INR` allowed), `language` (Indian languages only). |
| Branches | `timezone` (regex only) and `phone` (Indian rule) optional; address free text. |
| Flutter | No `flutter_localizations`/`intl`; no locale handling; no formatting helpers. Material date picker used the device locale implicitly. |
| Platform admin | Clinic Web has a role-gated platform area (applications, tenants, plans, subscriptions, audit). Permission catalogue in `common_models`. |
| Tests | 863 backend + app tests passing before the phase; fixtures create clinics through the real application → approval flow. |

## 2. Impact assessment

| Impact | Mitigation |
|---|---|
| New required field `address.countryCode` on clinic applications breaks every fixture and any open application | Fixtures updated; legacy (in-flight) applications are approved by supplying `countryCode` at approval (validated, audited) |
| Phone numbers are now stored in E.164 for clinics with a country | Legacy clinics (no country) keep the old rules and storage; no data is rewritten |
| Existing tenants have no country | Not guessed. Dry-run report + per-tenant audited assignment; resolver reports `countryConfigured: false`; all existing workflows keep working |
| Country master becomes a dependency of onboarding | Read fresh inside the approval transaction; failure aborts before any write |
| New libraries (`intl`, `timezone`, `phone_numbers_parser`) | ADR 083; pure Dart; used instead of a hand-maintained catalogue |
| Security: client-supplied country | Only an applicant's explicit choice, validated against the master; never trusted after provisioning; tenant users cannot change it |

## 3. Scope delivered

1. Country master (`countries/{ISO}`), versioned snapshots, India and UAE baseline, platform admin API + UI.
2. Typed configuration resolution (country → tenant → branch → user locale → deployment) with safe DTO and cache invalidation.
3. Onboarding country selector, backend validation, tenant `countryCode` immutability, dry-run backfill report, audited assignment/correction.
4. Branch timezone (IANA-validated), structured + localized address, country-aware phone (E.164) and postal rules.
5. Locale-aware date/time/number/currency formatting (shared package), locale resolution and user preference, representative translations (en, hi, ar), RTL smoke test.
6. Platform-admin screens: country list (availability, version, warnings, active clinics) and backfill report.
7. Documentation, ADRs 083–088, technical debt TD-95…TD-101, tests.

## 4. Explicit exclusions (per the prompt)

GST/VAT engine, payment gateways, ABDM/ABHA, DHA/DoH/MOHAP integration, full translations, FX conversion, multi-region production deployment, production migration/deployment.

## 5. Test plan

Unit (country_config, backend config), API (country admin, onboarding, provisioning, immutability, branches, resolution, migration, permissions, cross-tenant), widget (apply page, country admin, backfill report, regional formatter, strings, RTL), regression (all existing suites), builds (web, Android debug, backend exe). Results: `TEST_REPORT.md`.
