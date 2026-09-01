#!/usr/bin/env bash
#
# build-dmj-os.sh
# Builds a bootable DMJ OS ISO based on Debian 12 (Bookworm).
#
# The Saudade AI CLI integration has been removed from this project.
# The custom "DMJ Cinematic" Plymouth boot splash is included by default;
# an optional macOS-style desktop theme (WhiteSur GTK/icons + Plank dock)
# can be enabled via INCLUDE_MACOS_THEME=true (off by default, since it
# adds a network-dependent build step on top of an already fragile
# live-build pipeline — see docs/BUILD_TROUBLESHOOTING.md).

set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------------------
OS_NAME="DMJ OS"
OS_ID="dmjos"
VERSION_CODENAME="Ashen"
VERSION_NUMBER="1.0"
BASE_SUITE="bookworm"
ARCH="amd64"

# Opt-in extras. All default OFF so the base build stays exactly as
# reliable as the current working configuration; enable via env vars, e.g.:
#   INCLUDE_PLYMOUTH_THEME=true sudo -E ./build/build-dmj-os.sh
INCLUDE_PLYMOUTH_THEME="${INCLUDE_PLYMOUTH_THEME:-true}"
INCLUDE_MACOS_THEME="${INCLUDE_MACOS_THEME:-false}"
INCLUDE_WALLPAPER="${INCLUDE_WALLPAPER:-false}"
INCLUDE_WELCOME_SCREEN="${INCLUDE_WELCOME_SCREEN:-false}"
INCLUDE_DESKTOP_APPS="${INCLUDE_DESKTOP_APPS:-false}"

# Adds a "-macos" suffix to the output ISO filename when the deluxe extras
# are on, so base and deluxe builds never overwrite each other in out/.
BUILD_VARIANT_SUFFIX=""
if [[ "${INCLUDE_MACOS_THEME}" == "true" ]]; then
  BUILD_VARIANT_SUFFIX="-macos"
fi

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LB_DIR="${WORKDIR}/live-build-work"
OUT_DIR="${WORKDIR}/out"
# Keep mirror URLs without a trailing slash. live-build appends paths such as
# /dists/<suite>; a trailing slash here can produce //dists/... URLs.
DEBIAN_MIRROR="https://deb.debian.org/debian"
SECURITY_MIRROR="https://security.debian.org/debian-security"

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
if [[ ${EUID} -ne 0 ]]; then
  echo "ERROR: This script must be run as root (sudo)." >&2
  exit 1
fi

for cmd in lb debootstrap; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "ERROR: Missing required tool: ${cmd}" >&2
    exit 1
  fi
done

mkdir -p "${OUT_DIR}"
rm -rf "${LB_DIR}"
mkdir -p "${LB_DIR}"
cd "${LB_DIR}"

# ---------------------------------------------------------------------------
# 1. Configure live-build explicitly as Debian
# ---------------------------------------------------------------------------
echo "==> Configuring Debian ${BASE_SUITE} live-build"

lb config \
  --ignore-system-defaults \
  --mode debian \
  --distribution "${BASE_SUITE}" \
  --architecture "${ARCH}" \
  --mirror-bootstrap "${DEBIAN_MIRROR}" \
  --mirror-chroot "${DEBIAN_MIRROR}" \
  --mirror-binary "${DEBIAN_MIRROR}" \
  --security false \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer live \
  --bootappend-live "boot=live components quiet splash" \
  --iso-application "${OS_NAME}" \
  --iso-volume "${OS_ID}-${VERSION_NUMBER}"

# ---------------------------------------------------------------------------
# 1a. Configure the correct Debian Bookworm security repository
# ---------------------------------------------------------------------------
mkdir -p config/archives
cat > config/archives/dmj-security.list.chroot <<EOF
deb ${SECURITY_MIRROR} ${BASE_SUITE}-security main contrib non-free non-free-firmware
EOF

# Fail early if the known-invalid security path appears in generated config.
echo "==> Verifying generated live-build configuration"
if grep -RqsE 'security\.debian\.org.*/bookworm/updates|bookworm/updates.*security\.debian\.org' config 2>/dev/null; then
  echo "ERROR: Invalid Debian security repository path was generated." >&2
  grep -RInE 'security\.debian\.org.*/bookworm/updates|bookworm/updates.*security\.debian\.org' config >&2 || true
  exit 1
fi

if grep -RqsE 'ubuntu/|security\.ubuntu\.com|ubuntu/24\.04' config 2>/dev/null; then
  echo "ERROR: Ubuntu repository settings leaked into the Debian live-build configuration." >&2
  grep -RInE 'ubuntu/|security\.ubuntu\.com|ubuntu/24\.04' config >&2 || true
  exit 1
fi

# ---------------------------------------------------------------------------
# 2. Package list
# ---------------------------------------------------------------------------
mkdir -p config/package-lists
cat > config/package-lists/dmj-os.list.chroot <<'EOF'
task-xfce-desktop
network-manager
firmware-linux
firmware-misc-nonfree
plymouth
plymouth-themes
git
curl
vim
sudo
EOF

if [[ "${INCLUDE_MACOS_THEME}" == "true" ]]; then
  cat >> config/package-lists/dmj-os.list.chroot <<'EOF'
plank
sassc
optipng
EOF
fi

if [[ "${INCLUDE_DESKTOP_APPS}" == "true" ]]; then
  cat >> config/package-lists/dmj-os.list.chroot <<'EOF'
firefox-esr
vlc
xarchiver
EOF
fi

if [[ "${INCLUDE_WELCOME_SCREEN}" == "true" ]]; then
  cat >> config/package-lists/dmj-os.list.chroot <<'EOF'
zenity
EOF
fi

# ---------------------------------------------------------------------------
# 3. DMJ OS branding
# ---------------------------------------------------------------------------
mkdir -p config/includes.chroot/etc

cat > config/includes.chroot/etc/os-release <<EOF
NAME="${OS_NAME}"
PRETTY_NAME="${OS_NAME} ${VERSION_NUMBER} (${VERSION_CODENAME})"
ID=${OS_ID}
ID_LIKE=debian
VERSION="${VERSION_NUMBER} (${VERSION_CODENAME})"
VERSION_ID="${VERSION_NUMBER}"
VERSION_CODENAME=${VERSION_CODENAME,,}
HOME_URL="https://github.com/jadhavdurvesh/DMJ-OS"
EOF

cat > config/includes.chroot/etc/hostname <<EOF
${OS_ID}
EOF

cat > config/includes.chroot/etc/motd <<EOF

  ${OS_NAME} ${VERSION_NUMBER} "${VERSION_CODENAME}"
  ------------------------------------------
  Welcome to DMJ OS.

EOF

# ---------------------------------------------------------------------------
# 3a. Plymouth: install the custom "DMJ Cinematic" boot theme
# ---------------------------------------------------------------------------
mkdir -p config/hooks/normal

if [[ "${INCLUDE_PLYMOUTH_THEME}" == "true" ]]; then
  echo "==> Including DMJ Cinematic Plymouth boot theme"

  PLYMOUTH_SRC="${WORKDIR}/config/plymouth/dmj-cinematic"
  PLYMOUTH_DEST="config/includes.chroot/usr/share/plymouth/themes/dmj-cinematic"
  mkdir -p "${PLYMOUTH_DEST}"

  cp "${PLYMOUTH_SRC}/dmj-cinematic.plymouth" "${PLYMOUTH_SRC}/dmj-cinematic.script" "${PLYMOUTH_DEST}/"
  cp "${PLYMOUTH_SRC}/images/logo.png" \
     "${PLYMOUTH_SRC}/images/logo_glow.png" \
     "${PLYMOUTH_SRC}/images/particle.png" \
     "${PLYMOUTH_SRC}/images/progress_dot.png" \
     "${PLYMOUTH_DEST}/"

  cat > config/hooks/normal/0100-plymouth-theme.hook.chroot <<'EOF'
#!/bin/sh
set -e
plymouth-set-default-theme -R dmj-cinematic
EOF
  chmod +x config/hooks/normal/0100-plymouth-theme.hook.chroot
else
  echo "==> Skipping Plymouth boot theme (INCLUDE_PLYMOUTH_THEME=false)"
fi

# ---------------------------------------------------------------------------
# 3b. Optional: macOS-style desktop (WhiteSur GTK theme + icons + Plank dock)
# ---------------------------------------------------------------------------
if [[ "${INCLUDE_MACOS_THEME}" == "true" ]]; then
  echo "==> Including macOS-style desktop theme (WhiteSur + Plank)"

  # Clones and installs the theme/icon packs at build time — needs network
  # access inside the chroot to reach GitHub.
  cat > config/hooks/normal/0200-macos-theme.hook.chroot <<'EOF'
#!/bin/sh
set -e
echo "==> Installing WhiteSur GTK theme"
git clone --depth=1 https://github.com/vinceliuice/WhiteSur-gtk-theme.git /tmp/WhiteSur-gtk-theme
cd /tmp/WhiteSur-gtk-theme
./install.sh -d /usr/share/themes || true
cd /
rm -rf /tmp/WhiteSur-gtk-theme

echo "==> Installing WhiteSur icon theme"
git clone --depth=1 https://github.com/vinceliuice/WhiteSur-icon-theme.git /tmp/WhiteSur-icon-theme
cd /tmp/WhiteSur-icon-theme
./install.sh -d /usr/share/icons
cd /
rm -rf /tmp/WhiteSur-icon-theme

echo "==> Installing WhiteSur cursors"
git clone --depth=1 https://github.com/vinceliuice/WhiteSur-cursors.git /tmp/WhiteSur-cursors
cd /tmp/WhiteSur-cursors
./install.sh -d /usr/share/icons || true
cd /
rm -rf /tmp/WhiteSur-cursors
EOF
  chmod +x config/hooks/normal/0200-macos-theme.hook.chroot

  # Defaults applied to every new user via /etc/skel, so a fresh live
  # session boots straight into the themed desktop with the dock running.
  SKEL="config/includes.chroot/etc/skel"
  mkdir -p "${SKEL}/.config/gtk-3.0"
  mkdir -p "${SKEL}/.config/xfce4/xfconf/xfce-perchannel-xml"
  mkdir -p "${SKEL}/.config/autostart"
  mkdir -p "${SKEL}/.config/plank/dock1/launchers"

  cat > "${SKEL}/.config/gtk-3.0/settings.ini" <<'EOF'
[Settings]
gtk-theme-name=WhiteSur-Dark
gtk-icon-theme-name=WhiteSur
gtk-cursor-theme-name=WhiteSur-cursors
gtk-application-prefer-dark-theme=1
EOF

  cat > "${SKEL}/.config/xfce4/xfconf/xfce-perchannel-xml/xsettings.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="WhiteSur-Dark"/>
    <property name="IconThemeName" type="string" value="WhiteSur"/>
  </property>
  <property name="Gtk" type="empty">
    <property name="CursorThemeName" type="string" value="WhiteSur-cursors"/>
  </property>
</channel>
EOF

  cat > "${SKEL}/.config/xfce4/xfconf/xfce-perchannel-xml/xfwm4.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="WhiteSur-Dark"/>
  </property>
</channel>
EOF

  cat > "${SKEL}/.config/autostart/plank.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=Plank
Comment=macOS-style dock
Exec=plank
X-GNOME-Autostart-enabled=true
EOF

  cat > "${SKEL}/.config/plank/dock1/settings.ini" <<'EOF'
[PlankDockPreferences]
Theme=Transparent
IconSize=48
Position=2
Alignment=1
HideMode=1
PinnedOnly=false
EOF
else
  echo "==> Skipping macOS-style theme (INCLUDE_MACOS_THEME=false)"
fi

# ---------------------------------------------------------------------------
# 3c. Optional: matching desktop wallpaper
# ---------------------------------------------------------------------------
if [[ "${INCLUDE_WALLPAPER}" == "true" ]]; then
  echo "==> Including default desktop wallpaper"

  WALLPAPER_SRC="${WORKDIR}/config/wallpaper/wallpaper.png"
  if [[ ! -f "${WALLPAPER_SRC}" ]]; then
    echo "ERROR: ${WALLPAPER_SRC} not found. Run:" >&2
    echo "  python3 config/wallpaper/generate_wallpaper.py" >&2
    echo "before building with INCLUDE_WALLPAPER=true." >&2
    exit 1
  fi

  mkdir -p config/includes.chroot/usr/share/backgrounds/dmj-os
  cp "${WALLPAPER_SRC}" config/includes.chroot/usr/share/backgrounds/dmj-os/wallpaper.png

  SKEL="config/includes.chroot/etc/skel"
  mkdir -p "${SKEL}/.config/xfce4/xfconf/xfce-perchannel-xml"

  # xfce4-desktop's monitor/workspace property names vary by hardware, so
  # this sets the common defaults; XFCE falls back sanely if a specific
  # monitor property doesn't match at runtime.
  cat > "${SKEL}/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-desktop" version="1.0">
  <property name="backdrop" type="empty">
    <property name="screen0" type="empty">
      <property name="monitor0" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/dmj-os/wallpaper.png"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
      <property name="monitorVirtual1" type="empty">
        <property name="workspace0" type="empty">
          <property name="last-image" type="string" value="/usr/share/backgrounds/dmj-os/wallpaper.png"/>
          <property name="image-style" type="int" value="5"/>
        </property>
      </property>
    </property>
  </property>
</channel>
EOF
else
  echo "==> Skipping default wallpaper (INCLUDE_WALLPAPER=false)"
fi

# ---------------------------------------------------------------------------
# 3d. Optional: first-boot welcome screen
# ---------------------------------------------------------------------------
if [[ "${INCLUDE_WELCOME_SCREEN}" == "true" ]]; then
  echo "==> Including first-boot welcome screen"

  mkdir -p config/includes.chroot/usr/local/bin
  cp "${WORKDIR}/config/welcome/dmj-welcome.sh" config/includes.chroot/usr/local/bin/dmj-welcome.sh
  chmod +x config/includes.chroot/usr/local/bin/dmj-welcome.sh

  SKEL="config/includes.chroot/etc/skel"
  mkdir -p "${SKEL}/.config/autostart"
  cat > "${SKEL}/.config/autostart/dmj-welcome.desktop" <<'EOF'
[Desktop Entry]
Type=Application
Name=DMJ OS Welcome
Comment=One-time welcome screen
Exec=/usr/local/bin/dmj-welcome.sh
X-GNOME-Autostart-enabled=true
EOF
else
  echo "==> Skipping first-boot welcome screen (INCLUDE_WELCOME_SCREEN=false)"
fi

# ---------------------------------------------------------------------------
# 4. Build
# ---------------------------------------------------------------------------
echo "==> Running live-build"
lb build

# ---------------------------------------------------------------------------
# 5. Locate and publish ISO
# ---------------------------------------------------------------------------
ISO_FILE="$(find "${LB_DIR}" -maxdepth 1 -type f -name '*.iso' -print -quit)"

if [[ -z "${ISO_FILE}" ]]; then
  echo "ERROR: Build finished but no ISO was found." >&2
  exit 1
fi

FINAL_NAME="${OS_ID}-${VERSION_NUMBER}-${VERSION_CODENAME,,}${BUILD_VARIANT_SUFFIX}.iso"
cp "${ISO_FILE}" "${OUT_DIR}/${FINAL_NAME}"

echo "==> Build complete: ${OUT_DIR}/${FINAL_NAME}"
ls -lh "${OUT_DIR}/${FINAL_NAME}"
