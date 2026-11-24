#!/usr/bin/env bash
# Format check + static analysis + tests for every project in the monorepo.
# Usage: scripts/check_all.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DART_PROJECTS=(backend packages/common_models packages/api_contracts packages/validation packages/utilities packages/country_config)
FLUTTER_PROJECTS=(packages/design_system packages/app_core apps/clinic_web apps/doctor_mobile apps/patient_mobile)

for p in "${DART_PROJECTS[@]}"; do
  echo "=== $p (dart)"
  (cd "$ROOT/$p" && dart pub get >/dev/null && dart format --output=none --set-exit-if-changed . && dart analyze --fatal-infos && dart test)
done
for p in "${FLUTTER_PROJECTS[@]}"; do
  echo "=== $p (flutter)"
  (cd "$ROOT/$p" && flutter pub get >/dev/null && dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test)
done
echo "=== translation completeness (app_core)"
(cd "$ROOT/packages/app_core" && dart run tool/l10n_report.dart --check)
echo "All checks passed."
