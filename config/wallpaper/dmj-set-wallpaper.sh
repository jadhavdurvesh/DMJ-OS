#!/usr/bin/env bash
# dmj-set-wallpaper.sh
#
# A static xfce4-desktop.xml with hardcoded monitor property names (e.g.
# "monitor0", "monitorVirtual1") does NOT reliably work — XFCE names these
# based on the actual detected display hardware at runtime (varies by GPU
# driver, VM vs real hardware, even between two QEMU boots), so a build-time
# guess frequently just doesn't match anything and silently does nothing.
#
# This runs at login instead: asks xfconf directly what monitor/workspace
# properties actually exist right now, and sets the wallpaper on all of
# them. Safe to run on every login (idempotent, cheap).
set -uo pipefail

WALLPAPER="/usr/share/backgrounds/dmj-os/wallpaper.png"
[[ -f "$WALLPAPER" ]] || exit 0

command -v xfconf-query >/dev/null 2>&1 || exit 0

# Give xfdesktop a moment to register its channel on first login.
for _ in $(seq 1 10); do
  xfconf-query -c xfce4-desktop -l >/dev/null 2>&1 && break
  sleep 1
done

PROPS="$(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep -E '/last-image$' || true)"

if [[ -z "$PROPS" ]]; then
  # First-ever login: xfdesktop may not have created any properties yet.
  # Seed the most common default path directly; xfdesktop picks it up
  # once it starts, and this script will correct any others on next login.
  PROPS="/backdrop/screen0/monitor0/workspace0/last-image"
fi

while IFS= read -r prop; do
  [[ -z "$prop" ]] && continue
  xfconf-query -c xfce4-desktop -p "$prop" -s "$WALLPAPER" -t string --create 2>/dev/null
  style_prop="${prop%last-image}image-style"
  xfconf-query -c xfce4-desktop -p "$style_prop" -s 5 -t int --create 2>/dev/null
done <<< "$PROPS"
