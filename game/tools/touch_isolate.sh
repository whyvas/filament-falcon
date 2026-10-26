#!/usr/bin/env bash
# Keep the kids' console touchscreen (ViewSonic TD2220 / NextWindow) from stealing the
# Commander's mouse pointer and keyboard focus, while touch keeps working in the game.
#
#   tools/touch_isolate.sh start        isolate the touchscreen (run.sh does this before launch)
#   tools/touch_isolate.sh stop         undo it (idempotent; also cleans up after a crash)
#   tools/touch_isolate.sh watch PID    wait for PID to exit, then stop (run.sh starts this)
#   tools/touch_isolate.sh status       show what is isolated
#
# FALCON_TOUCH_ISOLATE picks the method:
#   auto   (default) "float" for a true multi-touch device, else "master"
#   float  detach the device from the core pointer (xinput float). X stops moving the cursor
#          and sending clicks for it; the game still gets its XI2 touch events (Godot listens to
#          every device) and turns them into taps on the console window.
#   master put the device on its own master pointer (xinput create-master "Falcon Touch").
#          The mouse cursor stays where it is; a second cursor follows the finger. For devices
#          that are plain absolute pointers with no touch class. NOT for real touchscreens under
#          Cinnamon/GNOME: the window manager hides the cursor (XFixes, screen-wide) when the
#          last-used device is a touchscreen and only shows it again when the *core* pointer
#          switches devices, which never happens once touch lives on another master. The game
#          nudges the pointer after touches (tools/x11_show_cursor.py) to bring it back.
#   0      off (same as ./run.sh --no-touch-isolate)
# Does nothing (exit 1) with no X display, Wayland, no xinput or no touchscreen.
# Touch device detection is setup_displays.sh's (--device / $FALCON_TOUCH_DEVICE override it).
set -u
cd "$(dirname "$0")" || exit 1
MODE="${FALCON_TOUCH_ISOLATE:-auto}"
MASTER="Falcon Touch"
STATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/filament-falcon"
STATE="$STATE_DIR/touch_isolate.state"
log() { echo "touch_isolate: $*"; }

usable() {
  [ -n "${DISPLAY:-}" ] || { log "no X display; skipping"; return 1; }
  [ "${XDG_SESSION_TYPE:-x11}" != "wayland" ] || { log "Wayland session: not supported, skipping"; return 1; }
  command -v xinput >/dev/null 2>&1 || { log "xinput not installed; skipping"; return 1; }
}

# master id a slave is attached to ("" when floating)
master_of() { xinput list "$1" 2>/dev/null | sed -n 's/.*slave  *\(pointer\|keyboard\)  *(\([0-9][0-9]*\)).*/\2/p' | head -1; }
# xinput prints "Touch mode: direct" for a touchscreen ("dependent" for touchpads)
is_direct_touch() { xinput list --long "$1" 2>/dev/null | grep -qiE 'touch mode: *direct|direct touch'; }
dev_exists() { xinput list --name-only "$1" >/dev/null 2>&1; }
id_of() { xinput list --id-only "$1" 2>/dev/null; }

do_stop() {
  usable >/dev/null || return 0
  if [ -f "$STATE" ]; then
    while read -r kind id orig; do
      [ "$kind" = dev ] || continue
      dev_exists "$id" || continue
      [ -n "$orig" ] && dev_exists "$orig" || orig="Virtual core pointer"
      xinput reattach "$id" "$orig" 2>/dev/null && log "device $id back on master $orig"
    done < "$STATE"
  fi
  local mid
  mid=$(id_of "$MASTER pointer")
  if [ -n "$mid" ]; then
    xinput remove-master "$mid" AttachToMaster "Virtual core pointer" "Virtual core keyboard" 2>/dev/null \
      && log "removed master '$MASTER'"
  fi
  rm -f "$STATE"
}

do_start() {
  case "$MODE" in 0|off|no|false) log "disabled (FALCON_TOUCH_ISOLATE=$MODE)"; return 1 ;; esac
  usable || return 1
  do_stop >/dev/null   # leftovers from a crashed run
  local ids id orig how n=0 mid=""
  ids=$(./setup_displays.sh --ids 2>/dev/null)
  [ -n "$ids" ] || { log "no touchscreen found; skipping"; return 1; }
  mkdir -p "$STATE_DIR"
  : > "$STATE"
  for id in $ids; do
    orig=$(master_of "$id")
    [ -n "$orig" ] || continue          # already floating (not by us): leave it alone
    how="$MODE"
    if [ "$how" = auto ]; then
      if is_direct_touch "$id"; then how=float; else how=master; fi
    fi
    if [ "$how" = master ]; then
      if [ -z "$mid" ]; then
        xinput create-master "$MASTER" 2>/dev/null
        mid=$(id_of "$MASTER pointer")
        [ -n "$mid" ] || { log "could not create master '$MASTER'"; continue; }
        echo "master $mid" >> "$STATE"
      fi
      xinput reattach "$id" "$mid" || continue
    else
      xinput float "$id" || continue
    fi
    echo "dev $id $orig" >> "$STATE"
    log "touch '$(xinput list --name-only "$id")' (id $id): $how"
    n=$((n + 1))
  done
  if [ "$n" = 0 ]; then do_stop >/dev/null; return 1; fi
  if pgrep -x 'unclutter|unclutter-xfixes' >/dev/null 2>&1; then
    log "warning: unclutter is running and hides the mouse cursor; stop it for the Commander"
  fi
  return 0
}

case "${1:-}" in
  start) do_start ;;
  stop) do_stop ;;
  watch)
    pid="${2:?watch needs a PID}"
    trap 'do_stop; exit 0' TERM INT HUP
    while kill -0 "$pid" 2>/dev/null; do sleep 2; done
    do_stop ;;
  status)
    if [ -f "$STATE" ]; then cat "$STATE"; else echo "not isolated"; fi ;;
  *) sed -n '2,21p' "$0"; exit 2 ;;
esac
