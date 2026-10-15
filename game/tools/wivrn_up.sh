#!/usr/bin/env bash
# Make sure a WiVRn server (OpenXR runtime for the Quest) is running before the VR client starts.
#   tools/wivrn_up.sh start   -> starts it if needed; prints "XR_RUNTIME_JSON=<path>" (may be empty)
#   tools/wivrn_up.sh stop    -> stops it ONLY if this script started it (pid file)
# Never touches a server that was already running. Log: ~/.local/share/filament-falcon/wivrn.log
LOGDIR="${XDG_DATA_HOME:-$HOME/.local/share}/filament-falcon"; mkdir -p "$LOGDIR"
LOG="$LOGDIR/wivrn.log"; PIDF="$LOGDIR/wivrn_started.pid"
TIMEOUT="${WIVRN_TIMEOUT:-20}"
FP=io.github.wivrn.wivrn
log() { echo "$(date '+%F %T') $*" >> "$LOG"; echo "[WiVRn] $*" >&2; }

running() { pgrep -f 'wivrn-server' >/dev/null 2>&1; }
ready() {   # server alive + its IPC socket exists (native or Flatpak runtime dir)
  running && find "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" -maxdepth 4 \( -name 'wivrn*' -o -name 'comp_ipc' \) -print -quit 2>/dev/null | grep -q .
}
runtime_json() {
  for f in "$HOME/.local/share/flatpak/app/$FP/current/active/files/share/openxr/1/openxr_wivrn.json" \
           "/var/lib/flatpak/app/$FP/current/active/files/share/openxr/1/openxr_wivrn.json" \
           /usr/share/openxr/1/openxr_wivrn.json /usr/local/share/openxr/1/openxr_wivrn.json; do
    [ -f "$f" ] && { echo "$f"; return; }
  done
}
adb_reverse() {
  command -v adb >/dev/null 2>&1 || return 0
  if adb get-state >/dev/null 2>&1; then
    adb reverse tcp:9757 tcp:9757 >/dev/null 2>&1 && log "adb reverse tcp:9757 ok (USB link)" || log "adb reverse failed"
  else
    log "adb: no headset on USB (fine over Wi-Fi)"
  fi
}

case "${1:-start}" in
start)
  adb_reverse
  if running; then
    log "server already running: leaving it alone"
  else
    rm -f "$PIDF"
    if command -v wivrn-server >/dev/null 2>&1; then
      log "starting native wivrn-server"; nohup wivrn-server >>"$LOG" 2>&1 & echo $! > "$PIDF"
    elif command -v flatpak >/dev/null 2>&1 && flatpak info "$FP" >/dev/null 2>&1; then
      log "starting Flatpak $FP (wivrn-server)"
      nohup flatpak run --command=wivrn-server "$FP" >>"$LOG" 2>&1 & echo $! > "$PIDF"
    else
      log "WiVRn not installed (no wivrn-server, no Flatpak $FP). See docs/game/VR_SETUP.md"; echo "XR_RUNTIME_JSON="; exit 2
    fi
  fi
  i=0
  until ready; do
    i=$((i + 1))
    if [ "$i" -gt "$TIMEOUT" ]; then log "server not ready after ${TIMEOUT}s (check $LOG; is the Quest app open?)"; break; fi
    sleep 1
  done
  ready && log "runtime ready"
  echo "XR_RUNTIME_JSON=$(runtime_json)"
  ;;
stop)
  if [ -f "$PIDF" ]; then
    p=$(cat "$PIDF"); rm -f "$PIDF"
    log "stopping the WiVRn server we started (pid $p)"
    kill "$p" 2>/dev/null; pkill -P "$p" 2>/dev/null; pkill -f "flatpak run --command=wivrn-server" 2>/dev/null
    # Flatpak: kill the sandboxed server that our launcher spawned
    [ -n "$p" ] && flatpak kill "$FP" 2>/dev/null
  fi
  ;;
esac
exit 0
