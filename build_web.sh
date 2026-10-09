#!/bin/sh
# D492: the browser build for Vercel -> web/ (index.html + wasm + pck). Commit web/ and push.
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
GODOT="${GODOT:-$HOME/Downloads/Godot_v4.7-stable_win64.exe/Godot_v4.7-stable_win64_console.exe}"
"$GODOT" --headless --path "$ROOT/game" --import
"$GODOT" --headless --path "$ROOT/game" --export-release "Web" "$ROOT/web/index.html"
[ -f "$ROOT/web/index.pck" ] || { echo "Export produced no pck."; exit 1; }
echo "Built $ROOT/web"
