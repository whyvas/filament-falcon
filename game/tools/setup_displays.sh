#!/usr/bin/env bash
# Map the kids' console touchscreen (ViewSonic TD2220 / NextWindow optical touch) to the
# monitor the game uses as the KIDS' CONSOLE, so touches land on the right screen.
# Optionally turn that monitor to landscape first.
#
#   tools/setup_displays.sh                 map touch -> console output (from the game's config)
#   tools/setup_displays.sh --landscape     also: xrandr --output <console> --rotate normal
#   tools/setup_displays.sh --output DisplayPort-0 --device "NextWindow"   override detection
#   tools/setup_displays.sh --list          show outputs and touch devices, change nothing
#
# Console output name, first match wins: --output, $FALCON_CONSOLE_OUTPUT, console_output in
# ~/.local/share/filament-falcon/falcon_settings.cfg, CONSOLE_OUTPUT in displays.env there
# (written by the game at start-up), else DisplayPort-0.
# Touch device: --device, $FALCON_TOUCH_DEVICE, else every pointer whose name contains
# NextWindow, ViewSonic or touch (not "touchpad").
# Exits 0 and does nothing when there is no X display, no xinput, or no touch device.
# run.sh calls this before every launch; see docs/game/README.md to run it at login too.
set -u
LANDSCAPE=0
LIST=0
QUIET=0
OUT="${FALCON_CONSOLE_OUTPUT:-}"
DEV="${FALCON_TOUCH_DEVICE:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --landscape) LANDSCAPE=1 ;;
    --list) LIST=1 ;;
    --quiet|-q) QUIET=1 ;;
    --output) OUT="${2:-}"; shift ;;
    --output=*) OUT="${1#*=}" ;;
    --device) DEV="${2:-}"; shift ;;
    --device=*) DEV="${1#*=}" ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
  esac
  shift
done
log() { [ "$QUIET" = 1 ] || echo "setup_displays: $*"; }

if [ -z "${DISPLAY:-}" ]; then log "no X display; skipping"; exit 0; fi
if [ "${XDG_SESSION_TYPE:-x11}" = "wayland" ]; then log "Wayland session: xinput mapping does not apply; skipping"; exit 0; fi

CFG_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/filament-falcon"
if [ -z "$OUT" ] && [ -f "$CFG_DIR/falcon_settings.cfg" ]; then
  OUT=$(awk -F= '/^\[/{sec=$0} sec=="[display]" && $1 ~ /^console_output[ \t]*$/ {v=$2; gsub(/["\r \t]/,"",v); print v}' "$CFG_DIR/falcon_settings.cfg" | tail -1)
fi
if [ -z "$OUT" ] && [ -f "$CFG_DIR/displays.env" ]; then
  OUT=$(sed -n 's/^CONSOLE_OUTPUT=//p' "$CFG_DIR/displays.env" | tail -1)
fi
OUT="${OUT:-DisplayPort-0}"

find_touch_ids() {
  command -v xinput >/dev/null 2>&1 || return 0
  if [ -n "$DEV" ]; then
    xinput list | grep -E 'slave +pointer' | grep -iF -- "$DEV"
  else
    xinput list | grep -E 'slave +pointer' | grep -iE 'nextwindow|viewsonic|touch' | grep -viE 'touchpad|xtest'
  fi | sed -n 's/.*id=\([0-9][0-9]*\).*/\1/p'
}

if [ "$LIST" = 1 ]; then
  echo "Console output (from config): $OUT"
  command -v xrandr >/dev/null 2>&1 && xrandr --listmonitors
  if command -v xinput >/dev/null 2>&1; then
    echo "Touch devices:"; for id in $(find_touch_ids); do echo "  id=$id  $(xinput list --name-only "$id" 2>/dev/null)"; done
  else
    echo "xinput not installed (sudo apt install xinput)"
  fi
  exit 0
fi

if command -v xrandr >/dev/null 2>&1; then
  if ! xrandr --listmonitors 2>/dev/null | awk '{print $NF}' | grep -qxF -- "$OUT"; then
    log "output '$OUT' is not active (see: xrandr --listmonitors); skipping"
    exit 0
  fi
  if [ "$LANDSCAPE" = 1 ]; then
    if xrandr --output "$OUT" --rotate normal; then log "$OUT set to landscape"; sleep 1; fi
  fi
fi

if ! command -v xinput >/dev/null 2>&1; then log "xinput not installed; skipping touch mapping"; exit 0; fi
IDS=$(find_touch_ids)
if [ -z "$IDS" ]; then log "no touchscreen found; skipping"; exit 0; fi
for id in $IDS; do
  name=$(xinput list --name-only "$id" 2>/dev/null)
  if xinput map-to-output "$id" "$OUT" 2>/dev/null; then
    log "touch '$name' (id $id) -> $OUT"
  else
    log "could not map '$name' (id $id) to $OUT"
  fi
done
exit 0
