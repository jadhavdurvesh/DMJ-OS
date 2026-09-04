#!/usr/bin/env bash
# dmj-set-menu-icon.sh
#
# XFCE's panel plugin IDs (e.g. "plugin-14") are assigned per-install, not
# fixed — the same lesson learned from the wallpaper monitor-name bug
# applies here too: don't guess the property path at build time, query
# xfconf for what's actually there at login time.
#
# Waits for the xfce4-panel PROCESS itself (not just its xfconf channel
# being queryable — under load, with several autostart apps racing to
# start at once, the channel can exist before the panel has finished
# registering its actual plugin properties), then finds whichever panel
# plugin is a whiskermenu/applicationsmenu-style launcher and points its
# icon at the DMJ OS mark. Safe to run every login (idempotent).
#
# Logs every step to ~/.cache/dmj-os/menu-icon.log for diagnosis.
set -uo pipefail

ICON="/usr/share/icons/hicolor/48x48/apps/start-here.png"
LOG_DIR="${HOME}/.cache/dmj-os"
LOG_FILE="${LOG_DIR}/menu-icon.log"
mkdir -p "$LOG_DIR" 2>/dev/null || true

log() {
  echo "[$(date '+%H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
}

log "=== dmj-set-menu-icon.sh starting ==="

if [[ ! -f "$ICON" ]]; then
  log "ABORT: icon file not found at $ICON"
  exit 0
fi

if ! command -v xfconf-query >/dev/null 2>&1; then
  log "ABORT: xfconf-query not found on PATH"
  exit 0
fi

panel_ready=0
for i in $(seq 1 60); do
  if pgrep -x xfce4-panel >/dev/null 2>&1; then
    panel_ready=1
    log "xfce4-panel process found after ${i}s"
    break
  fi
  sleep 1
done

if [[ "$panel_ready" -eq 0 ]]; then
  log "WARNING: xfce4-panel process never appeared after 60s — proceeding anyway"
fi

for i in $(seq 1 10); do
  xfconf-query -c xfce4-panel -l >/dev/null 2>&1 && break
  sleep 1
done

# Find plugin IDs whose "plugin-N" value names a menu-style plugin.
RAW_LIST="$(xfconf-query -c xfce4-panel -p /plugins -l -v 2>/dev/null)"
log "Raw plugin list: $(echo "$RAW_LIST" | tr '\n' ' | ')"

PLUGIN_IDS="$(
  echo "$RAW_LIST" \
    | awk '$2 ~ /whiskermenu|applicationsmenu|xfce4-appmenu/ { print $1 }' \
    | sed -E 's#/plugins/plugin-([0-9]+)$#\1#'
)"
log "Matched menu plugin IDs: ${PLUGIN_IDS:-none}"

set_count=0
for id in $PLUGIN_IDS; do
  # whiskermenu uses "button-icon"; applicationsmenu uses "button-icon" too
  # in recent versions — set both possible property names, harmless if one
  # doesn't apply to this plugin type.
  if xfconf-query -c xfce4-panel -p "/plugins/plugin-${id}/button-icon" \
       -s "$ICON" -t string --create 2>>"$LOG_FILE"; then
    set_count=$((set_count + 1))
    log "Set plugin-${id} button-icon -> ${ICON}"
  else
    log "FAILED to set plugin-${id} button-icon"
  fi
done

log "Set icon on ${set_count} plugin(s)"

# Restart the panel to force it to pick up the new icon immediately,
# rather than waiting on its own refresh cycle. xfce4-panel supports a
# graceful restart via --restart that reloads config without logging out.
if command -v xfce4-panel >/dev/null 2>&1 && [[ "$set_count" -gt 0 ]]; then
  xfce4-panel --restart >/dev/null 2>&1
  log "Called xfce4-panel --restart"
fi

log "=== dmj-set-menu-icon.sh finished ==="
