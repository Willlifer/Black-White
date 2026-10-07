#!/usr/bin/env bash
# D395: build the Windows release of Black | White (Git Bash twin of build_windows.bat).
#   ./build_windows.sh          -> dist/BlackWhite-<date>/ and dist/BlackWhite-<date>.zip
#   ./build_windows.sh tests    -> dist/selftest/ (debug export of "Windows Desktop (tests)"; then
#                                dist/selftest/BlackWhite.console.exe --headless -- --self-test)
# Needs Godot 4.7 stable export templates in %APPDATA%/Godot/export_templates/4.7.stable/.
set -euo pipefail
GODOT="${GODOT:-$USERPROFILE/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%Y-%m-%d)"
if [ "${1:-}" = "tests" ]; then
  PRESET="Windows Desktop (tests)"; OUT="$ROOT/dist/selftest"; MODE=--export-debug
else
  PRESET="Windows Desktop"; OUT="$ROOT/dist/BlackWhite-$STAMP"; MODE=--export-release
fi
rm -rf "$OUT"; mkdir -p "$OUT"
"$GODOT" --headless --path "$ROOT/game" --import
"$GODOT" --headless --path "$ROOT/game" "$MODE" "$PRESET" "$OUT/BlackWhite.exe"
for f in BlackWhite.exe BlackWhite.pck; do
  [ -f "$OUT/$f" ] || { echo "Export produced no $f"; exit 1; }
done
if [ "${1:-}" = "tests" ]; then echo "Built $OUT"; exit 0; fi
cp "$ROOT/packaging/README.txt" "$OUT/README.txt"
ZIP="$ROOT/dist/BlackWhite-$STAMP.zip"
rm -f "$ZIP"
WOUT="$(cygpath -w "$OUT")"; WZIP="$(cygpath -w "$ZIP")"
powershell -NoProfile -Command "Compress-Archive -Path '$WOUT' -DestinationPath '$WZIP'"
echo "Built $OUT"
echo "Zipped $ZIP"
