#!/usr/bin/env bash
# dmj-set-wallpaper.sh
#
# A static xfce4-desktop.xml with hardcoded monitor property names (e.g.
# "monitor0", "monitorVirtual1") does NOT reliably work — XFCE names these
# based on the actual detected display hardware at runtime (varies by GPU
# driver, VM vs real hardware, even between two QEMU boots), so a build-time
# guess frequently just doesn't match anything and silently does nothing.
#
# This runs at login instead: waits for xfdesktop to actually be running
# (not just for its xfconf channel to exist — a channel can technically be
# queryable before xfdesktop has finished registering its real properties,
# especially when several autostart apps are all racing to start at once
# under slow/non-KVM emulation), asks xfconf what monitor/workspace
# properties actually exist, sets the wallpaper on all of them, then forces
# xfdesktop to reload immediately rather than waiting on its own poll cycle.
#
# Logs every step to ~/.cache/dmj-os/wallpaper.log so a future run's boot
# video/log can show exactly what happened instead of a silent guess.
set -uo pipefail

WALLPAPER="/usr/share/backgrounds/dmj-os/wallpaper.png"
LOG_DIR="${HOME}/.cache/dmj-os"
LOG_FILE="${LOG_DIR}/wallpaper.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

log() {
  echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log "=== dmj-set-wallpaper.sh starting ==="

if [[ ! -f "$WALLPAPER" ]]; then
  log "ABORT: wallpaper file not found at $WALLPAPER"
  exit 0
fi

if ! command -v xfconf-query >/dev/null 2>&1; then
  log "ABORT: xfconf-query not found on PATH"
  exit 0
fi

# Wait for the xfdesktop PROCESS to actually be running — a more direct
# readiness signal than the xfconf channel merely being queryable, since
# under load (several autostart apps starting at once) the channel can
# exist before xfdesktop has finished registering real properties on it.
# Patient: up to 60s, since slow/non-KVM emulation can be genuinely slow.
xfdesktop_ready=0
for i in $(seq 1 60); do
  if pgrep -x xfdesktop >/dev/null 2>&1; then
    xfdesktop_ready=1
    log "xfdesktop process found after ${i}s"
    break
  fi
  sleep 1
done

if [[ "$xfdesktop_ready" -eq 0 ]]; then
  log "WARNING: xfdesktop process never appeared after 60s — proceeding anyway with a guessed property path"
fi

# Give it a further moment to finish registering its channel properties
# even after the process itself has started.
for i in $(seq 1 10); do
  xfconf-query -c xfce4-desktop -l >/dev/null 2>&1 && break
  sleep 1
done

PROPS="$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/last-image$' || true)"
log "Discovered properties: $(echo "$PROPS" | tr '\n' ' ')"

if [[ -z "$PROPS" ]]; then
  log "No existing last-image properties found — falling back to guessed default path"
  PROPS="/backdrop/screen0/monitor0/workspace0/last-image"
fi

set_count=0
while IFS= read -r prop; do
  [[ -z "$prop" ]] && continue
  if xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" -t string --create 2>>"$LOG_FILE"; then
    set_count=$((set_count + 1))
    log "Set ${prop} -> ${WALLPAPER}"
  else
    log "FAILED to set ${prop}"
  fi
  style_prop="${prop%last-image}image-style"
  xfconf-query -c xfce4-desktop -p "$style_prop" -s 5 -t int --create 2>>"$LOG_FILE"
done <<< "$PROPS"

log "Set wallpaper on ${set_count} propert(y/ies)"

# Force xfdesktop to pick up the change immediately, rather than waiting
# on its own internal poll/refresh cycle.
if command -v xfdesktop >/dev/null 2>&1 && [[ "$xfdesktop_ready" -eq 1 ]]; then
  xfdesktop --reload >/dev/null 2>&1
  log "Called xfdesktop --reload"
fi

log "=== dmj-set-wallpaper.sh finished ==="
