#!/usr/bin/env bash
# Runs the emulator-backed tests (Firestore rules + backend Firestore store)
# against the LOCAL Firebase emulator. Needs Node 18+, Java 11+ and
# `npm install` in firebase/rules-tests. Never touches a real Firebase project.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/firebase/rules-tests"
[ -d node_modules ] || npm install --no-audit --no-fund
./node_modules/.bin/firebase emulators:exec --only firestore \
  --project demo-eazyclinic --config "$ROOT/firebase/firebase.json" \
  "npm test --silent && cd $ROOT/backend && dart test test/integration"
