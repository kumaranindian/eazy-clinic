# Repository Structure

```
eazy-clinic/
├── CLAUDE.md, README.md
├── analysis_options.yaml            # shared lints for pure-Dart projects
├── analysis_options_flutter.yaml    # same rules + flutter_lints
├── apps/
│   ├── clinic_web/        # Clinic Management (Flutter Web)
│   ├── doctor_mobile/     # Doctor Workspace (Flutter Web + Android)
│   └── patient_mobile/    # Patient app (Flutter Android)
├── backend/               # Dart + Shelf REST API
│   ├── bin/server.dart    # entry point (config → logger → serve)
│   └── lib/
│       ├── app.dart                 # pipeline assembly
│       ├── config/                  # env-var config + validation
│       ├── core/{errors,middleware,responses,logging,validation}/
│       ├── routes/                  # root router, /health, domain routers later
│       ├── infrastructure/          # Firebase/Razorpay adapters (Phase 1+)
│       └── modules/                 # business domains (Phase 1+)
├── packages/
│   ├── common_models/     # pure Dart: role enums (more shared models later)
│   ├── api_contracts/     # pure Dart: envelope, error codes, pagination, header names
│   ├── validation/        # pure Dart: field validators (backend + apps)
│   ├── utilities/         # pure Dart: AppEnvironment, ClientConfig, log redaction
│   └── design_system/     # Flutter: tokens, theme, widgets, brand assets, Inter font
├── assets/                # branding (original + app-ready), fonts, icons, illustrations
├── firebase/              # deny-all rules, indexes, firebase.json (nothing deployed)
├── environments/{dev,staging,production}/   # *.example templates only
├── docs/
└── scripts/               # check_all.sh, run_backend.sh, sync_brand_assets.sh
```

## Dependency rules (no cycles)

```
apps/*  ──► design_system ──► (flutter only)
   │  └──► utilities
   └─────► api_contracts, common_models, validation   (added as features need them)
backend ──► api_contracts, utilities, validation, (common_models later)
pure-Dart packages ──► nothing inside the repo
```

- Packages never depend on apps or the backend.
- `design_system` is the only package that depends on Flutter.
- Business logic lives in the backend. Shared packages contain contracts and pure
  helpers only, so the three apps cannot diverge on rules.

## Decisions

- **Path dependencies, no Melos/pub workspaces.** Fewer moving parts; each project
  resolves independently. `scripts/check_all.sh` runs everything. Revisit if the
  package count grows.
- **Per-app `lib/` is feature-first** (`core/`, `features/<name>/{data,domain,presentation}`).
  Phase 0 has only `features/foundation/presentation`.
- **Docs layout** follows the Phase 0 task (nested folders). It supersedes the flat
  list in CLAUDE.md §17; CLAUDE.md was updated to match.
- **Docker builds use the repo root as context** because the backend depends on
  `../packages/*`.
