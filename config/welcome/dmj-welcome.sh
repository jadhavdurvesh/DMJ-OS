#!/usr/bin/env bash
# dmj-welcome.sh
# Shows a one-time welcome dialog on first login to DMJ OS.
# Runs on every session start via autostart, but exits immediately after
# the first successful display (tracked via a marker file).
set -euo pipefail

MARKER_DIR="${HOME}/.config/dmj-os"
MARKER_FILE="${MARKER_DIR}/welcome-shown"

if [[ -f "$MARKER_FILE" ]]; then
  exit 0
fi

mkdir -p "$MARKER_DIR"

if command -v zenity >/dev/null 2>&1; then
  zenity --info \
    --title="Welcome to DMJ OS" \
    --width=420 \
    --text="Welcome to DMJ OS.\n\nA few things to know:\n\n• The dock along the bottom holds your pinned and running apps.\n• Right-click the desktop for display and wallpaper settings.\n• A browser, media player, and archive tool are preinstalled.\n\nEnjoy." \
    2>/dev/null || true
fi

touch "$MARKER_FILE"
