#!/usr/bin/env bash
# Launch The Filament Falcon. On a fresh clone, Godot must import the project once
# (builds the script class cache in .godot/) before the game can run.
# Before launching it maps the console touchscreen to the KIDS' CONSOLE monitor
# (tools/setup_displays.sh; skipped quietly when there is no touchscreen or xinput).
# Usage: ./run.sh [--cockpit|--dev] [--quality=ultra] [--mission=docking] ...
#        ./run.sh --landscape-console     also rotate the console monitor to landscape
#        ./run.sh --no-display-setup      skip the touch mapping
#        ./run.sh --no-ics                no intercom helper (headsets off)
# It also starts the intercom helper (tools/falcon_ics.py: 3 USB headsets, PTT/VOX, radio
# effect). It needs python3-numpy + pulseaudio-utils; if anything is missing it logs why to
# ~/.local/share/filament-falcon/ics.log and the game runs without intercom.
set -e
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
SETUP_ARGS=()
GAME_ARGS=()
DO_SETUP=1
DO_ICS=1
for a in "$@"; do
  case "$a" in
    --landscape-console) SETUP_ARGS+=("--landscape") ;;
    --no-display-setup) DO_SETUP=0 ;;
    --no-ics) DO_ICS=0; GAME_ARGS+=("$a") ;;
    *) GAME_ARGS+=("$a") ;;
  esac
done
# Re-import on a fresh clone, or after a git pull changed any script/scene/shader (a stale
# class cache causes "Identifier ... not declared" parse errors and a broken game).
STAMP=.godot/.falcon_import_stamp
if [ ! -f .godot/global_script_class_cache.cfg ] || [ ! -f "$STAMP" ] || \
   [ -n "$(find . -path ./.godot -prune -o \( -name '*.gd' -o -name '*.tscn' -o -name '*.gdshader' -o -name 'project.godot' \) -newer "$STAMP" -print -quit)" ]; then
  echo "Importing project (first run or after an update, ~1 minute)..."
  "$GODOT" --headless --path . --import
  touch "$STAMP"
fi
if [ "$DO_SETUP" = 1 ] && [ -x tools/setup_displays.sh ]; then
  tools/setup_displays.sh "${SETUP_ARGS[@]}" || true
fi
if [ "$DO_ICS" = 1 ] && command -v python3 >/dev/null 2>&1; then
  LOGDIR="${XDG_DATA_HOME:-$HOME/.local/share}/filament-falcon"
  mkdir -p "$LOGDIR"
  # --parent-pid $$: exec below keeps this pid, so the helper exits when the game does.
  nohup python3 tools/falcon_ics.py --parent-pid $$ --log "$LOGDIR/ics.log" >/dev/null 2>&1 &
fi
exec "$GODOT" --path . -- "${GAME_ARGS[@]}"
