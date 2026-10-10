#!/usr/bin/env bash
# Launch The Filament Falcon. On a fresh clone, Godot must import the project once
# (builds the script class cache in .godot/) before the game can run.
# Before launching it maps the console touchscreen to the KIDS' CONSOLE monitor
# (tools/setup_displays.sh; skipped quietly when there is no touchscreen or xinput).
# Usage: ./run.sh [--cockpit|--dev] [--quality=ultra] [--mission=docking] ...
#        ./run.sh --landscape-console     also rotate the console monitor to landscape
#        ./run.sh --no-display-setup      skip the touch mapping
set -e
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
SETUP_ARGS=()
GAME_ARGS=()
DO_SETUP=1
for a in "$@"; do
  case "$a" in
    --landscape-console) SETUP_ARGS+=("--landscape") ;;
    --no-display-setup) DO_SETUP=0 ;;
    *) GAME_ARGS+=("$a") ;;
  esac
done
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  echo "First run: importing project (one time, ~1 minute)..."
  "$GODOT" --headless --path . --import
fi
if [ "$DO_SETUP" = 1 ] && [ -x tools/setup_displays.sh ]; then
  tools/setup_displays.sh "${SETUP_ARGS[@]}" || true
fi
exec "$GODOT" --path . -- "${GAME_ARGS[@]}"
