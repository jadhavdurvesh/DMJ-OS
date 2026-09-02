#!/usr/bin/env bash
#
# rebrand_grub.sh
#
# live-build's default GRUB menu shows "Debian GNU/Linux <version>
# (<codename>)" as the headline text — there's no reliable, version-agnostic
# way to override that from the live-build config side (the exact template
# location differs between live-build versions, and we build live-build
# from source in CI, so pinning to one version's internal paths is fragile).
#
# Instead, this patches the text directly inside the finished ISO: finds
# every grub.cfg on the image, replaces the "Debian GNU/Linux" branding
# text, and writes each file back in place using xorriso's -update, with
# -boot_image any replay to explicitly preserve the El Torito boot catalog
# (BIOS + UEFI boot images) unchanged. Verified end-to-end (including an
# actual QEMU boot of the patched result) before being wired into the build.
#
# Usage:
#   rebrand_grub.sh <input.iso> <output.iso> <brand-name> [codename]
#
# On any failure, falls back to copying the input ISO through unchanged
# (rebranding is cosmetic — it must never be the reason a build fails).
set -uo pipefail

ISO_IN="${1:?Usage: rebrand_grub.sh <input.iso> <output.iso> <brand-name> [codename]}"
ISO_OUT="${2:?Usage: rebrand_grub.sh <input.iso> <output.iso> <brand-name> [codename]}"
BRAND_NAME="${3:-DMJ OS}"
CODENAME="${4:-}"

fail_soft() {
  echo "WARNING: $1 — leaving ISO unbranded (copying through unchanged)." >&2
  cp -f "$ISO_IN" "$ISO_OUT"
  exit 0
}

command -v xorriso >/dev/null 2>&1 || fail_soft "xorriso not found"
[[ -f "$ISO_IN" ]] || fail_soft "input ISO not found at $ISO_IN"

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Locating grub.cfg file(s) inside $(basename "$ISO_IN")"
mapfile -t GRUB_PATHS < <(
  xorriso -indev "$ISO_IN" -find / -name grub.cfg 2>/dev/null \
    | grep -oE "'/[^']*grub\.cfg'" | tr -d "'"
)

if [[ ${#GRUB_PATHS[@]} -eq 0 ]]; then
  fail_soft "no grub.cfg found on ISO"
fi

echo "==> Found: ${GRUB_PATHS[*]}"
cp -f "$ISO_IN" "$ISO_OUT"

i=0
for iso_path in "${GRUB_PATHS[@]}"; do
  i=$((i + 1))
  local_file="${WORKDIR}/grub_${i}.cfg"

  echo "==> Extracting ${iso_path}"
  if ! xorriso -indev "$ISO_OUT" -osirrox on -extract "$iso_path" "$local_file" >/dev/null 2>&1; then
    echo "WARNING: failed to extract ${iso_path}, skipping" >&2
    continue
  fi

  echo "==> Patching branding text in ${iso_path}"
  sed -i -e "s/Debian GNU\/Linux/${BRAND_NAME}/g" "$local_file"
  if [[ -n "$CODENAME" ]]; then
    sed -i -e "s/(bookworm)/(${CODENAME})/g" "$local_file"
  fi

  echo "==> Writing patched ${iso_path} back into the ISO"
  tmp_out="${ISO_OUT}.tmp"
  if xorriso -indev "$ISO_OUT" -outdev "$tmp_out" \
       -boot_image any replay \
       -update "$local_file" "$iso_path" >/dev/null 2>&1; then
    mv -f "$tmp_out" "$ISO_OUT"
  else
    echo "WARNING: failed to update ${iso_path} in the ISO, leaving prior state" >&2
    rm -f "$tmp_out"
  fi
done

echo "==> Rebranding complete: ${ISO_OUT}"
