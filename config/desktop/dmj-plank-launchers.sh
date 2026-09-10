#!/bin/sh
# Installs a small, curated set of Plank launchers into the new-user
# skeleton. The actual .desktop files come from the Debian packages.
set -eu

SKEL="/etc/skel/.config/plank/dock1/launchers"
mkdir -p "$SKEL"

write_launcher() {
  file="$1"
  desktop="$2"
  cat > "$SKEL/$file" <<EOF
[PlankDockItemPreferences]
Launcher=$desktop
EOF
}

write_launcher "org.xfce.Thunar.dockitem" "/usr/share/applications/thunar.desktop"
write_launcher "xfce4-terminal.dockitem" "/usr/share/applications/xfce4-terminal.desktop"
write_launcher "firefox-esr.dockitem" "/usr/share/applications/firefox-esr.desktop"
write_launcher "org.videolan.VLC.dockitem" "/usr/share/applications/vlc.desktop"
