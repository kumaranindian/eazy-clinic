#!/usr/bin/env bash
# Secret and unsafe-pattern scan of everything tracked by Git (and, with
# --history, every past revision). Exits non-zero on a finding. No network.
# Usage: scripts/security_scan.sh [--history]
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0

PATTERNS='AIza[0-9A-Za-z_-]{35}|-----BEGIN ([A-Z]+ )?PRIVATE KEY-----|sk_live_[0-9A-Za-z]+|rzp_live_[0-9A-Za-z]+|ya29\.[0-9A-Za-z_-]{20,}|"private_key"[[:space:]]*:|AKIA[0-9A-Z]{16}|xox[baprs]-[0-9A-Za-z-]{10,}'

echo "== tracked files that must not be committed"
bad=$(git ls-files | grep -E '\.(jks|keystore|p12|pem)$|(^|/)key\.properties$|google-services\.json$|GoogleService-Info\.plist$|service-?account.*\.json$|firebase-adminsdk.*\.json$|(^|/)\.env(\..*)?$' | grep -vE '\.example(\.|$)' || true)
if [ -n "$bad" ]; then echo "$bad"; fail=1; else echo "none"; fi

echo "== secret patterns in tracked files"
hits=$(git ls-files -z | xargs -0 grep -lIE "$PATTERNS" 2>/dev/null | grep -v '^scripts/security_scan.sh$' || true)
if [ -n "$hits" ]; then echo "$hits"; fail=1; else echo "none"; fi

if [ "${1:-}" = "--history" ]; then
  echo "== secret patterns in history"
  h=$(git log --all -p --no-color 2>/dev/null | grep -E '^\+' | grep -E "$PATTERNS" | head -3 || true)
  if [ -n "$h" ]; then echo "(match found in history; details withheld)"; fail=1; else echo "none"; fi
fi

echo "== release blockers in source"
# placeholders and leftovers that must not ship
todo=$(git ls-files 'apps/*/lib/*' 'backend/lib/*' 'packages/*/lib/*' | xargs grep -nE 'TODO|FIXME|HACK' 2>/dev/null || true)
if [ -n "$todo" ]; then echo "$todo"; fail=1; else echo "none"; fi
dbg=$(git ls-files 'apps/*/lib/*.dart' 'apps/*/lib/**/*.dart' 'packages/*/lib/**/*.dart' | xargs grep -nE '\bprint\(|debugPrint\(' 2>/dev/null || true)
if [ -n "$dbg" ]; then echo "$dbg"; fail=1; else echo "no print/debugPrint in app code"; fi

echo "== Android release signing must not use the debug key"
if git ls-files 'apps/*/android/app/build.gradle.kts' | xargs grep -n 'getByName("debug")' 2>/dev/null | grep -v '^.*//' ; then fail=1; else echo "ok"; fi

if [ $fail -ne 0 ]; then echo "SECURITY SCAN FAILED"; exit 1; fi
echo "Security scan passed."
