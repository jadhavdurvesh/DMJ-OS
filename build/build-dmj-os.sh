#!/usr/bin/env bash
#
# build-dmj-os.sh
# Builds a bootable DMJ OS ISO (Debian-based) with the Saudade AI model
# baked in as a CLI assistant (`dmj-ai`).
#
# Run this on a real Linux machine (or a Debian/Ubuntu VM), NOT inside a
# restricted sandbox — it needs network access to Debian mirrors and root
# privileges for debootstrap/live-build.
#
# Usage:
#   sudo ./build-dmj-os.sh
#
# Output:
#   ./out/dmj-os-<VERSION>.iso
set -euo pipefail

# ---------------------------------------------------------------------------
# CONFIG — edit these
# ---------------------------------------------------------------------------
OS_NAME="DMJ OS"
OS_ID="dmjos"
VERSION_CODENAME="Ashen"        # <- your release name, separate from "DMJ OS"
VERSION_NUMBER="1.0"
BASE_SUITE="bookworm"           # Debian 12
ARCH="amd64"
WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LB_DIR="${WORKDIR}/live-build-work"
OUT_DIR="${WORKDIR}/out"

SAUDADE_CHECKPOINT_PATH="${SAUDADE_CHECKPOINT_PATH:-${WORKDIR}/dmj-ai-assets/saudade_v4.pt}"
SAUDADE_TOKENIZER_PATH="${SAUDADE_TOKENIZER_PATH:-${WORKDIR}/dmj-ai-assets/tokenizer_32k.json}"
SAUDADE_REPO_URL="https://github.com/jadhavdurvesh/microgpt_by_DMJ"

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

if [[ ! -f "$SAUDADE_CHECKPOINT_PATH" ]]; then
  echo "WARNING: Saudade checkpoint not found at $SAUDADE_CHECKPOINT_PATH"
  echo "The ISO will still build, but dmj-ai will not work until you place"
  echo "the checkpoint there (or set SAUDADE_CHECKPOINT_PATH) and rebuild."
  echo
  read -r -p "Continue anyway? [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

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
# 2. Package list — base system + tools + Python for the AI CLI
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
  Built-in AI assistant: run 'dmj-ai "your prompt"'

EOF

# ---------------------------------------------------------------------------
# 4. dmj-ai CLI + Saudade model files
# ---------------------------------------------------------------------------
mkdir -p config/includes.chroot/opt/dmj-ai/model
mkdir -p config/includes.chroot/usr/local/bin

cp "${WORKDIR}/config/dmj-ai/dmj_ai_infer.py" config/includes.chroot/opt/dmj-ai/dmj_ai_infer.py
cp "${WORKDIR}/config/dmj-ai/dmj-ai" config/includes.chroot/usr/local/bin/dmj-ai
chmod +x config/includes.chroot/usr/local/bin/dmj-ai

if [[ -f "$SAUDADE_CHECKPOINT_PATH" ]]; then
  cp "$SAUDADE_CHECKPOINT_PATH" config/includes.chroot/opt/dmj-ai/model/saudade_v4.pt
fi
if [[ -f "$SAUDADE_TOKENIZER_PATH" ]]; then
  cp "$SAUDADE_TOKENIZER_PATH" config/includes.chroot/opt/dmj-ai/model/tokenizer_32k.json
fi

# requirements for inference, installed inside the chroot via hook
mkdir -p config/includes.chroot/opt/dmj-ai
cat > config/includes.chroot/opt/dmj-ai/requirements.txt <<'EOF'
torch --index-url https://download.pytorch.org/whl/cpu
tokenizers
EOF

# ---------------------------------------------------------------------------
# 5. Hook: install Python deps for dmj-ai inside the chroot at build time
# ---------------------------------------------------------------------------
mkdir -p config/hooks/normal
cat > config/hooks/normal/0100-dmj-ai-setup.hook.chroot <<'EOF'
#!/bin/sh
set -e
echo "==> Installing dmj-ai Python dependencies"
python3 -m venv /opt/dmj-ai/venv
/opt/dmj-ai/venv/bin/pip install --no-cache-dir -r /opt/dmj-ai/requirements.txt
EOF
chmod +x config/hooks/normal/0100-dmj-ai-setup.hook.chroot

# Plymouth: install the custom DMJ Cinematic theme and set it as default
mkdir -p config/includes.chroot/usr/share/plymouth/themes/dmj-cinematic
cp "${WORKDIR}/config/plymouth/dmj-cinematic/dmj-cinematic.plymouth" \
   config/includes.chroot/usr/share/plymouth/themes/dmj-cinematic/
cp "${WORKDIR}/config/plymouth/dmj-cinematic/dmj-cinematic.script" \
   config/includes.chroot/usr/share/plymouth/themes/dmj-cinematic/
cp "${WORKDIR}/config/plymouth/dmj-cinematic/images/logo.png" \
   "${WORKDIR}/config/plymouth/dmj-cinematic/images/logo_glow.png" \
   "${WORKDIR}/config/plymouth/dmj-cinematic/images/particle.png" \
   "${WORKDIR}/config/plymouth/dmj-cinematic/images/progress_dot.png" \
   config/includes.chroot/usr/share/plymouth/themes/dmj-cinematic/

cat > config/hooks/normal/0200-plymouth-theme.hook.chroot <<'EOF'
#!/bin/sh
set -e
plymouth-set-default-theme -R dmj-cinematic
EOF
chmod +x config/hooks/normal/0200-plymouth-theme.hook.chroot

# ---------------------------------------------------------------------------
# 6. Build
# ---------------------------------------------------------------------------
echo "==> Running lb build (this takes a while — grab coffee)"
lb build

ISO_FILE=$(find . -maxdepth 1 -name "*.iso" | head -n1)
if [[ -n "$ISO_FILE" ]]; then
  FINAL_NAME="${OS_ID}-${VERSION_NUMBER}-${VERSION_CODENAME,,}.iso"
  cp "$ISO_FILE" "${OUT_DIR}/${FINAL_NAME}"
  echo
  echo "==> Build complete: ${OUT_DIR}/${FINAL_NAME}"
else
  echo "Build finished but no ISO was found — check the log above for errors." >&2
  exit 1
fi
