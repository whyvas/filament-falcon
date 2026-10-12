#!/usr/bin/env bash
# Adds "Filament Falcon - Spacewalk (VR)" to the WiVRn launcher in the Quest 3.
# WiVRn lists .desktop files whose Categories contain X-WiVRn-VR (standard locations, e.g.
# ~/.local/share/applications), so after this the spacewalk can be started from the headset.
# Usage: game/tools/install_vr_launcher.sh            (uses `godot` from PATH, or $GODOT)
#        GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64 game/tools/install_vr_launcher.sh
#        game/tools/install_vr_launcher.sh --remove
# The cockpit game should already be running (the client joins it on UDP 47820); without it
# the client still works as a solo spacewalk around the ship.
set -e
GAME_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APPS="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
FILE="$APPS/filament-falcon-eva.desktop"
if [ "${1:-}" = "--remove" ]; then
  rm -f "$FILE"
  echo "Removed $FILE"
  exit 0
fi
GODOT_BIN="${GODOT:-$(command -v godot || true)}"
if [ -z "$GODOT_BIN" ] || [ ! -x "$GODOT_BIN" ]; then
  echo "Godot not found: set GODOT=/path/to/Godot_v4.7.2-stable_linux.x86_64" >&2
  exit 1
fi
GODOT_BIN="$(readlink -f "$GODOT_BIN")"
mkdir -p "$APPS"
cat > "$FILE" <<DESK
[Desktop Entry]
Type=Application
Name=Filament Falcon - Spacewalk (VR)
Comment=EVA client for The Filament Falcon (Meta Quest 3 through WiVRn)
Exec=env GODOT=$GODOT_BIN $GAME_DIR/run.sh --eva-vr
Path=$GAME_DIR
Icon=$GAME_DIR/icon.svg
Terminal=false
Categories=Game;X-WiVRn-VR;
DESK
chmod 644 "$FILE"
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$APPS" 2>/dev/null || true
echo "Installed $FILE"
echo "Put the headset on: with WiVRn connected and no VR app running, pick 'Filament Falcon - Spacewalk (VR)'."
