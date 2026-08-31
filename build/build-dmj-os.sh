#!/usr/bin/env bash
#
# build-dmj-os.sh
# Builds a bootable DMJ OS ISO based on Debian 12 (Bookworm).
# This repository build intentionally skips the large Saudade AI files and
# custom Plymouth assets so it can build directly in GitHub Actions.

set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIG
# ---------------------------------------------------------------------------
OS_NAME="DMJ OS"
OS_ID="dmjos"
VERSION_CODENAME="Ashen"
VERSION_NUMBER="1.0"
BASE_SUITE="bookworm"
ARCH="amd64"

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LB_DIR="${WORKDIR}/live-build-work"
OUT_DIR="${WORKDIR}/out"

# Use the official Debian mirror explicitly. The installed live-build version
# on the GitHub runner does not support the newer *-security mirror flags.
DEBIAN_MIRROR="http://deb.debian.org/debian/"

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (sudo). Exiting." >&2
  exit 1
fi

for cmd in debootstrap lb; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required tool: $cmd" >&2
    exit 1
  fi
done

mkdir -p "$LB_DIR" "$OUT_DIR"
cd "$LB_DIR"

# ---------------------------------------------------------------------------
# 1. Start from a completely clean live-build workspace
# ---------------------------------------------------------------------------
echo "==> Cleaning previous live-build workspace"
rm -rf config auto local .build cache binary chroot tmp
rm -f ./*.iso

# ---------------------------------------------------------------------------
# 2. Configure live-build for Debian Bookworm
# ---------------------------------------------------------------------------
echo "==> Configuring live-build for Debian ${BASE_SUITE}"
lb config \
  --distribution "$BASE_SUITE" \
  --architecture "$ARCH" \
  --mirror-bootstrap "$DEBIAN_MIRROR" \
  --mirror-chroot "$DEBIAN_MIRROR" \
  --mirror-binary "$DEBIAN_MIRROR" \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer live \
  --bootappend-live "boot=live components quiet splash" \
  --iso-application "$OS_NAME" \
  --iso-volume "${OS_ID}-${VERSION_NUMBER}"

# ---------------------------------------------------------------------------
# 3. Packages included in DMJ OS
# ---------------------------------------------------------------------------
mkdir -p config/package-lists
cat > config/package-lists/dmj-os.list.chroot <<'EOF'
task-xfce-desktop
network-manager
firmware-linux
firmware-misc-nonfree
python3
python3-pip
python3-venv
plymouth
plymouth-themes
git
curl
vim
sudo
EOF

# ---------------------------------------------------------------------------
# 4. DMJ OS branding
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
# 5. Build ISO
# ---------------------------------------------------------------------------
echo "==> Running lb build"
lb build

# ---------------------------------------------------------------------------
# 6. Copy finished ISO to repository output directory
# ---------------------------------------------------------------------------
ISO_FILE="$(find . -maxdepth 1 -type f -name "*.iso" -print -quit)"

if [[ -z "$ISO_FILE" ]]; then
  echo "Build finished but no ISO was found." >&2
  exit 1
fi

FINAL_NAME="${OS_ID}-${VERSION_NUMBER}-${VERSION_CODENAME,,}.iso"
cp "$ISO_FILE" "${OUT_DIR}/${FINAL_NAME}"

echo
echo "==> Build complete: ${OUT_DIR}/${FINAL_NAME}"
ls -lh "${OUT_DIR}/${FINAL_NAME}"
