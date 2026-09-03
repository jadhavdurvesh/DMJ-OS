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
# (BIOS + UEFI boot images) unchanged. Verified end-to-end against a real
# bootable test ISO (grub-mkrescue), including actually booting the
# patched result in QEMU to confirm both the new text AND working boot.
#
# Usage:
#   rebrand_grub.sh <input.iso> <output.iso> <brand-name> [codename]
#
# On any failure, falls back to copying the input ISO through unchanged
# (rebranding is cosmetic — it must never be the reason a build fails).
# Every xorriso call's full output is captured to a log and printed in
# full on failure, so a CI run always shows the real reason rather than
# a silent, undiagnosable fallback.
set -uo pipefail

ISO_IN="${1:?Usage: rebrand_grub.sh <input.iso> <output.iso> <brand-name> [codename]}"
ISO_OUT="${2:?Usage: rebrand_grub.sh <input.iso> <output.iso> <brand-name> [codename]}"
BRAND_NAME="${3:-DMJ OS}"
CODENAME="${4:-}"

WORKDIR="$(mktemp -d)"
LOG_FILE="${WORKDIR}/xorriso.log"
trap 'rm -rf "$WORKDIR"' EXIT

fail_soft() {
  echo "WARNING: $1 — leaving ISO unbranded (copying through unchanged)." >&2
  if [[ -f "$LOG_FILE" ]]; then
    echo "----- last xorriso output (for diagnosis) -----" >&2
    cat "$LOG_FILE" >&2
    echo "------------------------------------------------" >&2
  fi
  cp -f "$ISO_IN" "$ISO_OUT"
  exit 0
}

command -v xorriso >/dev/null 2>&1 || fail_soft "xorriso not found"
[[ -f "$ISO_IN" ]] || fail_soft "input ISO not found at $ISO_IN"

echo "==> Locating grub.cfg file(s) inside $(basename "$ISO_IN")"
xorriso -indev "$ISO_IN" -find / -name grub.cfg > "$LOG_FILE" 2>&1
find_status=$?
echo "----- xorriso -find output -----"
cat "$LOG_FILE"
echo "---------------------------------"

if [[ $find_status -ne 0 ]]; then
  fail_soft "xorriso -find exited with status $find_status"
fi

# xorriso prints matched paths as their own line, typically single-quoted
# (e.g. "'/boot/grub/grub.cfg'") but this is tolerant of unquoted output
# too, in case that format differs by xorriso version.
mapfile -t GRUB_PATHS < <(
  grep -oE "'?(/[A-Za-z0-9._/-]*grub\.cfg)'?" "$LOG_FILE" \
    | tr -d "'" | sort -u
)

if [[ ${#GRUB_PATHS[@]} -eq 0 ]]; then
  fail_soft "no grub.cfg path could be parsed from xorriso -find output above"
fi

echo "==> Found ${#GRUB_PATHS[@]} grub.cfg path(s): ${GRUB_PATHS[*]}"
cp -f "$ISO_IN" "$ISO_OUT"

i=0
any_patched=0
for iso_path in "${GRUB_PATHS[@]}"; do
  i=$((i + 1))
  local_file="${WORKDIR}/grub_${i}.cfg"

  echo "==> [$i/${#GRUB_PATHS[@]}] Extracting ${iso_path}"
  if ! xorriso -indev "$ISO_OUT" -osirrox on -extract "$iso_path" "$local_file" > "$LOG_FILE" 2>&1; then
    echo "WARNING: failed to extract ${iso_path}, skipping this file" >&2
    cat "$LOG_FILE" >&2
    continue
  fi

  if [[ ! -s "$local_file" ]]; then
    echo "WARNING: extracted ${iso_path} is empty, skipping this file" >&2
    continue
  fi

  echo "==> Patching branding text in ${iso_path} (${BRAND_NAME}${CODENAME:+, codename ${CODENAME}})"
  sed -i -e "s/Debian GNU\/Linux/${BRAND_NAME}/g" "$local_file"
  if [[ -n "$CODENAME" ]]; then
    sed -i -e "s/(bookworm)/(${CODENAME})/g" "$local_file"
  fi

  # Diagnostic only (not yet acted on): log any image/theme files this
  # grub.cfg references, so a future run's log tells us the real filename
  # of the background graphic (the yellow icon shown in the boot menu)
  # instead of guessing — needed before that can be replaced too.
  refs="$(grep -oE '(background_image|set theme=)[^ ]*[[:space:]]*\S*\.(png|tga|jpg|jpeg|txt)' "$local_file" || true)"
  if [[ -n "$refs" ]]; then
    echo "==> Image/theme references found in ${iso_path} (for future logo replacement):"
    echo "$refs" | sed 's/^/    /'
  else
    echo "==> No background_image/theme references found in ${iso_path}"
  fi

  echo "==> Writing patched ${iso_path} back into the ISO"
  tmp_out="${ISO_OUT}.tmp"
  if xorriso -indev "$ISO_OUT" -outdev "$tmp_out" \
       -boot_image any replay \
       -update "$local_file" "$iso_path" > "$LOG_FILE" 2>&1; then
    mv -f "$tmp_out" "$ISO_OUT"
    any_patched=1
  else
    echo "WARNING: failed to update ${iso_path} in the ISO, leaving prior state" >&2
    cat "$LOG_FILE" >&2
    rm -f "$tmp_out"
  fi
done

if [[ "$any_patched" -eq 0 ]]; then
  fail_soft "found grub.cfg path(s) but failed to patch any of them (see warnings above)"
fi

echo "==> Rebranding complete: ${ISO_OUT}"
