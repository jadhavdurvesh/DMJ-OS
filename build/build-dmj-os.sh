#!/usr/bin/env bash
#
# build-dmj-os.sh
# Builds a bootable DMJ OS ISO based on Debian 12 (Bookworm).
# Large Saudade AI files and custom Plymouth generation are intentionally
# omitted for this base build.

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

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LB_DIR="${WORKDIR}/live-build-work"
OUT_DIR="${WORKDIR}/out"
DEBIAN_MIRROR="https://deb.debian.org/debian/"
SECURITY_MIRROR="https://security.debian.org/debian-security/"

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
# The GitHub runner's live-build package can inherit host-specific defaults.
# --ignore-system-defaults prevents those defaults from leaking into the build.
# Security is configured manually below because the Ubuntu-packaged live-build
# used by the GitHub runner can generate the obsolete bookworm/updates path.
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
# Debian 12 security updates use the suite "bookworm-security".
# Do not use "bookworm/updates"; that path returns 404 and caused the last build
# to fail with APT exit code 100.
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

FINAL_NAME="${OS_ID}-${VERSION_NUMBER}-${VERSION_CODENAME,,}.iso"
cp "${ISO_FILE}" "${OUT_DIR}/${FINAL_NAME}"

echo "==> Build complete: ${OUT_DIR}/${FINAL_NAME}"
ls -lh "${OUT_DIR}/${FINAL_NAME}"
