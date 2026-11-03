#!/usr/bin/env bash
# Copies app-ready brand assets and fonts from the repo-level assets/ folder
# into the design_system package (Flutter packages can only bundle their own
# files). Run after changing anything under assets/branding or assets/fonts.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="$ROOT/packages/design_system/assets"
mkdir -p "$PKG/branding" "$PKG/fonts"
cp "$ROOT/assets/branding/eazyclinic_logo.png" "$ROOT/assets/branding/eazyclinic_icon.png" "$PKG/branding/"
cp "$ROOT"/assets/fonts/inter/*.ttf "$ROOT/assets/fonts/inter/LICENSE.txt" "$PKG/fonts/"
echo "Synced brand assets and fonts into packages/design_system/assets."
