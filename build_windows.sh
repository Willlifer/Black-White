#!/usr/bin/env bash
# D395/D466: build the Windows release of Black | White (Git Bash twin of build_windows.bat).
#   ./build_windows.sh          -> dist/BlackWhite-<date>.exe  (ONE file: the game data is embedded)
#   ./build_windows.sh tests    -> dist/selftest/ (debug export of "Windows Desktop (tests)"; then
#                                dist/selftest/BlackWhite.console.exe --headless -- --self-test)
# Needs Godot 4.7 stable export templates in %APPDATA%/Godot/export_templates/4.7.stable/.
set -euo pipefail
GODOT="${GODOT:-$USERPROFILE/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y-%m-%d)"
"$GODOT" --headless --path "$ROOT/game" --import
if [ "${1:-}" = "tests" ]; then
  OUT="$ROOT/dist/selftest"; rm -rf "$OUT"; mkdir -p "$OUT"
  "$GODOT" --headless --path "$ROOT/game" --export-debug "Windows Desktop (tests)" "$OUT/BlackWhite.exe"
  [ -f "$OUT/BlackWhite.pck" ] || { echo "Export produced no pck"; exit 1; }
  echo "Built $OUT"; exit 0
fi
TMP="$ROOT/dist/.build"; rm -rf "$TMP"; mkdir -p "$TMP"
"$GODOT" --headless --path "$ROOT/game" --export-release "Windows Desktop" "$TMP/BlackWhite.exe"
[ -f "$TMP/BlackWhite.exe" ] || { echo "Export produced no exe"; exit 1; }
EXE="$ROOT/dist/BlackWhite-$STAMP.exe"
mv -f "$TMP/BlackWhite.exe" "$EXE"
rm -rf "$TMP"
echo "Built $EXE"
