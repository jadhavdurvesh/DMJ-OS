#!/usr/bin/env bash
#
# build-dmj-os.sh
# Builds a bootable DMJ OS ISO (Debian-based).
#
# Saudade AI and the custom Plymouth theme are optional. The ISO build
# continues when those files are not present.
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

SAUDADE_CHECKPOINT_PATH="${SAUDADE_CHECKPOINT_PATH:-${WORKDIR}/dmj-ai-assets/saudade_v4.pt}"
SAUDADE_TOKENIZER_PATH="${SAUDADE_TOKENIZER_PATH:-${WORKDIR}/dmj-ai-assets/tokenizer_32k.json}"

# ---------------------------------------------------------------------------
# 0. Sanity checks
# ---------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root (sudo). Exiting." >&2
  exit 1
fi

for cmd in debootstrap lb; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required tool: $cmd"
    echo "Install with: sudo apt install debootstrap live-build"
    exit 1
  fi
done

mkdir -p "$LB_DIR" "$OUT_DIR"
cd "$LB_DIR"

# ---------------------------------------------------------------------------
# 1. Initialize live-build config
# ---------------------------------------------------------------------------
echo "==> Configuring live-build"
lb config \
  --distribution "$BASE_SUITE" \
  --architecture "$ARCH" \
  --archive-areas "main contrib non-free non-free-firmware" \
  --debian-installer live \
  --bootappend-live "boot=live components quiet splash" \
  --iso-application "$OS_NAME" \
  --iso-volume "${OS_ID}-${VERSION_NUMBER}"

# ---------------------------------------------------------------------------
# 2. Package list — base system + optional AI support
# ---------------------------------------------------------------------------
mkdir -p config/package-lists
cat > config/package-lists/dmj-os.list.chroot <<'EOF'
task-xfce-desktop
network-manager
firmware-linux
python3
python3-pip
python3-venv
plymouth
plymouth-themes
git
curl
vim
EOF

# ---------------------------------------------------------------------------
# 3. Branding — /etc/os-release, MOTD, hostname
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
HOME_URL="https://github.com/jadhavdurvesh"
EOF

cat > config/includes.chroot/etc/hostname <<EOF
${OS_ID}
EOF

cat > config/includes.chroot/etc/motd <<EOF

  ${OS_NAME} ${VERSION_NUMBER} "${VERSION_CODENAME}"
  ------------------------------------------
EOF

# ---------------------------------------------------------------------------
# 4. dmj-ai CLI — install only when its source files are present
# ---------------------------------------------------------------------------
DMJ_AI_SOURCE_DIR="${WORKDIR}/config/dmj-ai"
DMJ_AI_DEST_DIR="config/includes.chroot/opt/dmj-ai"
DMJ_AI_BIN_DIR="config/includes.chroot/usr/local/bin"

if [[ -f "${DMJ_AI_SOURCE_DIR}/dmj_ai_infer.py" && -f "${DMJ_AI_SOURCE_DIR}/dmj-ai" ]]; then
  echo "==> dmj-ai source found; adding CLI"

  mkdir -p "${DMJ_AI_DEST_DIR}/model" "$DMJ_AI_BIN_DIR"

  cp "${DMJ_AI_SOURCE_DIR}/dmj_ai_infer.py" \
     "${DMJ_AI_DEST_DIR}/dmj_ai_infer.py"
  cp "${DMJ_AI_SOURCE_DIR}/dmj-ai" \
     "${DMJ_AI_BIN_DIR}/dmj-ai"
  chmod +x "${DMJ_AI_BIN_DIR}/dmj-ai"

  # Copy model files only when they actually exist.
  if [[ -f "$SAUDADE_CHECKPOINT_PATH" ]]; then
    cp "$SAUDADE_CHECKPOINT_PATH" \
       "${DMJ_AI_DEST_DIR}/model/saudade_v4.pt"
    echo "==> Saudade checkpoint included"
  else
    echo "WARNING: Saudade checkpoint not found; skipping model"
  fi

  if [[ -f "$SAUDADE_TOKENIZER_PATH" ]]; then
    cp "$SAUDADE_TOKENIZER_PATH" \
       "${DMJ_AI_DEST_DIR}/model/tokenizer_32k.json"
    echo "==> Saudade tokenizer included"
  else
    echo "WARNING: Saudade tokenizer not found; skipping tokenizer"
  fi

  cat > "${DMJ_AI_DEST_DIR}/requirements.txt" <<'EOF'
torch --index-url https://download.pytorch.org/whl/cpu
tokenizers
EOF

  mkdir -p config/hooks/normal
  cat > config/hooks/normal/0100-dmj-ai-setup.hook.chroot <<'EOF'
#!/bin/sh
set -e
if [ -f /opt/dmj-ai/requirements.txt ]; then
  echo "==> Installing dmj-ai Python dependencies"
  python3 -m venv /opt/dmj-ai/venv
  /opt/dmj-ai/venv/bin/pip install --no-cache-dir -r /opt/dmj-ai/requirements.txt
fi
EOF
  chmod +x config/hooks/normal/0100-dmj-ai-setup.hook.chroot

else
  echo "==> dmj-ai source not found; building OS without dmj-ai"
fi

# ---------------------------------------------------------------------------
# 5. Optional custom Plymouth theme
# ---------------------------------------------------------------------------
PLYMOUTH_SOURCE_DIR="${WORKDIR}/config/plymouth/dmj-cinematic"
PLYMOUTH_DEST_DIR="config/includes.chroot/usr/share/plymouth/themes/dmj-cinematic"

if [[ -f "${PLYMOUTH_SOURCE_DIR}/dmj-cinematic.plymouth" && \
      -f "${PLYMOUTH_SOURCE_DIR}/dmj-cinematic.script" && \
      -f "${PLYMOUTH_SOURCE_DIR}/images/logo.png" && \
      -f "${PLYMOUTH_SOURCE_DIR}/images/logo_glow.png" && \
      -f "${PLYMOUTH_SOURCE_DIR}/images/particle.png" && \
      -f "${PLYMOUTH_SOURCE_DIR}/images/progress_dot.png" ]]; then

  echo "==> Installing DMJ Cinematic Plymouth theme"
  mkdir -p "$PLYMOUTH_DEST_DIR"

  cp "${PLYMOUTH_SOURCE_DIR}/dmj-cinematic.plymouth" \
     "${PLYMOUTH_DEST_DIR}/"
  cp "${PLYMOUTH_SOURCE_DIR}/dmj-cinematic.script" \
     "${PLYMOUTH_DEST_DIR}/"
  cp "${PLYMOUTH_SOURCE_DIR}/images/logo.png" \
     "${PLYMOUTH_SOURCE_DIR}/images/logo_glow.png" \
     "${PLYMOUTH_SOURCE_DIR}/images/particle.png" \
     "${PLYMOUTH_SOURCE_DIR}/images/progress_dot.png" \
     "${PLYMOUTH_DEST_DIR}/"

  mkdir -p config/hooks/normal
  cat > config/hooks/normal/0200-plymouth-theme.hook.chroot <<'EOF'
#!/bin/sh
set -e
if command -v plymouth-set-default-theme >/dev/null 2>&1; then
  plymouth-set-default-theme -R dmj-cinematic
fi
EOF
  chmod +x config/hooks/normal/0200-plymouth-theme.hook.chroot
else
  echo "==> DMJ Cinematic Plymouth theme not found; using default Plymouth theme"
fi

# ---------------------------------------------------------------------------
# 6. Build
# ---------------------------------------------------------------------------
echo "==> Running lb build (this takes a while — grab coffee)"
lb build

ISO_FILE=$(find . -maxdepth 1 -type f -name "*.iso" | head -n1)
if [[ -n "$ISO_FILE" ]]; then
  FINAL_NAME="${OS_ID}-${VERSION_NUMBER}-${VERSION_CODENAME,,}.iso"
  cp "$ISO_FILE" "${OUT_DIR}/${FINAL_NAME}"
  echo
  echo "==> Build complete: ${OUT_DIR}/${FINAL_NAME}"
else
  echo "Build finished but no ISO was found — check the log above for errors." >&2
  exit 1
fi
