#!/usr/bin/env bash
# Launch The Filament Falcon. On a fresh clone, Godot must import the project once
# (builds the script class cache in .godot/) before the game can run.
# Usage: ./run.sh [--cockpit|--dev] [--quality=ultra] [--mission=docking] ...
set -e
cd "$(dirname "$0")"
GODOT="${GODOT:-godot}"
if [ ! -f .godot/global_script_class_cache.cfg ]; then
  echo "First run: importing project (one time, ~1 minute)..."
  "$GODOT" --headless --path . --import
fi
exec "$GODOT" --path . -- "$@"
