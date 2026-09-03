#!/usr/bin/env bash
# dmj-set-menu-icon.sh
#
# XFCE's panel plugin IDs (e.g. "plugin-14") are assigned per-install, not
# fixed — the same lesson learned from the wallpaper monitor-name bug
# applies here too: don't guess the property path at build time, query
# xfconf for what's actually there at login time.
#
# Finds whichever panel plugin is a whiskermenu/applicationsmenu/
# xfce4-popup-whiskermenu-style launcher and points its icon at the DMJ
# OS mark. Safe to run every login (idempotent).
set -uo pipefail

ICON="/usr/share/icons/hicolor/48x48/apps/start-here.png"
[[ -f "$ICON" ]] || exit 0

command -v xfconf-query >/dev/null 2>&1 || exit 0

for _ in $(seq 1 10); do
  xfconf-query -c xfce4-panel -l >/dev/null 2>&1 && break
  sleep 1
done

# Find plugin IDs whose "plugin-N" value names a menu-style plugin.
PLUGIN_IDS="$(
  xfconf-query -c xfce4-panel -p /plugins -l -v 2>/dev/null \
    | awk '$2 ~ /whiskermenu|applicationsmenu|xfce4-appmenu/ { print $1 }' \
    | sed -E 's#/plugins/plugin-([0-9]+)$#\1#'
)"

for id in $PLUGIN_IDS; do
  # whiskermenu uses "button-icon"; applicationsmenu uses "button-icon" too
  # in recent versions — set both possible property names, harmless if one
  # doesn't apply to this plugin type.
  xfconf-query -c xfce4-panel -p "/plugins/plugin-${id}/button-icon" \
    -s "$ICON" -t string --create 2>/dev/null
done
