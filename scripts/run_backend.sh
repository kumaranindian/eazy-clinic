#!/usr/bin/env bash
# Runs the backend locally. Usage: scripts/run_backend.sh [dev|staging|production]
# Loads environments/<env>/backend.env if it exists (git-ignored).
set -euo pipefail
ENV_NAME="${1:-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/environments/$ENV_NAME/backend.env"
if [ -f "$FILE" ]; then set -a; . "$FILE"; set +a; else export APP_ENV="$ENV_NAME"; fi
cd "$ROOT/backend" && dart pub get >/dev/null && exec dart run bin/server.dart
