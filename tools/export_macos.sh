#!/usr/bin/env bash
# Export Keystone.app for macOS.
# Requires: Godot 4.6 at /opt/homebrew/bin/godot, plus the macOS export templates
# (downloaded via `godot --headless --install-export-templates` or via the
# editor at Project → Manage Export Templates).

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

GODOT="${GODOT:-/opt/homebrew/bin/godot}"
OUT_DIR="$ROOT/build"
APP="$OUT_DIR/Keystone.app"

mkdir -p "$OUT_DIR"
rm -rf "$APP"

echo "→ Importing assets..."
"$GODOT" --headless --import >/dev/null 2>&1 || true

echo "→ Exporting macOS app..."
"$GODOT" --headless --export-release "macOS" "$APP" 2>&1 | tail -20 || \
"$GODOT" --headless --export-debug "macOS" "$APP" 2>&1 | tail -20

if [[ -d "$APP" ]]; then
  echo "✓ Built: $APP"
  du -sh "$APP"
else
  echo "✗ Build failed — see output above"
  exit 1
fi
