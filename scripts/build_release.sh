#!/usr/bin/env bash
# Builds release artifacts from the current, clean commit and records what was
# built. Never deploys or publishes anything.
#
#   scripts/build_release.sh <staging|production> [out-dir]
#
# Needs environments/<env>/app.json (real values, git-ignored). The Android
# bundle additionally needs the Android SDK and apps/*/android/key.properties;
# without them it is skipped and the manifest says so.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENVN="${1:-}"
case "$ENVN" in staging|production) ;; *) echo "usage: $0 <staging|production> [out-dir]" >&2; exit 64;; esac
OUT="${2:-$ROOT/build/release-$ENVN}"
cd "$ROOT"

if [ -n "$(git status --porcelain)" ]; then echo "Refusing to build: working tree is not clean." >&2; exit 1; fi
COMMIT="$(git rev-parse HEAD)"
APPJSON="$ROOT/environments/$ENVN/app.json"
[ -f "$APPJSON" ] || { echo "Missing $APPJSON (copy app.example.json and fill it in)." >&2; exit 1; }
# the file must describe the environment being built: no staging build with
# production settings or the reverse
WANT="$ENVN"
GOT="$(python3 -c "import json,sys;print(json.load(open(sys.argv[1])).get('APP_ENV',''))" "$APPJSON")"
[ "$GOT" = "$WANT" ] || { echo "APP_ENV in $APPJSON is '$GOT', expected '$WANT'." >&2; exit 1; }
if grep -qiE 'localhost|127\.0\.0\.1|10\.0\.2\.2|\.invalid' "$APPJSON"; then echo "$APPJSON points to a local or placeholder address." >&2; exit 1; fi
if [ "$ENVN" = "staging" ] && grep -qi 'prod' "$APPJSON"; then echo "Staging config mentions 'prod'; check it." >&2; exit 1; fi

scripts/security_scan.sh
mkdir -p "$OUT"
echo "commit=$COMMIT" > "$OUT/MANIFEST.txt"
echo "env=$ENVN" >> "$OUT/MANIFEST.txt"
{ flutter --version | head -1; dart --version; } >> "$OUT/MANIFEST.txt" 2>&1

(cd backend && dart pub get >/dev/null && dart compile exe bin/server.dart -o "$OUT/server")
for app in clinic_web doctor_mobile; do
  (cd "apps/$app" && flutter pub get >/dev/null && flutter build web --release --dart-define-from-file="$APPJSON")
  rm -rf "$OUT/$app-web" && cp -r "apps/$app/build/web" "$OUT/$app-web"
done
if [ -n "${ANDROID_HOME:-}${ANDROID_SDK_ROOT:-}" ] && [ -f apps/patient_mobile/android/key.properties ]; then
  (cd apps/patient_mobile && flutter build appbundle --release --dart-define-from-file="$APPJSON")
  cp apps/patient_mobile/build/app/outputs/bundle/release/app-release.aab "$OUT/patient.aab"
else
  echo "android=SKIPPED (no Android SDK or no android/key.properties)" >> "$OUT/MANIFEST.txt"
fi
( cd "$OUT" && find . -type f ! -name MANIFEST.txt -exec sha256sum {} + | sort -k2 > SHA256SUMS )
echo "Built from $COMMIT into $OUT"
