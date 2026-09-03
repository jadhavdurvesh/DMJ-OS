#!/usr/bin/env python3
"""
generate_icons.py

Derives a full set of square system-branding icons from the real
DMJ OS logo (config/plymouth/dmj-cinematic/images/logo.png). The source
logo is a wide wordmark (circular mark + "DMJ OS" text side by side) —
not usable directly as a square app/menu icon — so this auto-detects the
gap between the mark and the text (by finding the column range of
near-zero alpha ink density) and crops just the mark.

Output (all under config/branding/generated/):
  - distributor-logo.png        (256x256, standard Linux "who made this
                                   distro" icon path convention)
  - hicolor/<size>x<size>/apps/start-here.png
        for size in 16 22 24 32 48 64 96 128 256
        ("start-here" is the icon name most desktop environments,
        including XFCE's application menu button, fall back to for
        distro branding — this is how Ubuntu/Mint/etc. brand their
        start menu icon without per-app configuration)

Run this locally whenever logo.png changes:
    python3 generate_icons.py
"""
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO_PATH = os.path.join(HERE, "..", "plymouth", "dmj-cinematic", "images", "logo.png")
OUT_DIR = os.path.join(HERE, "generated")

ICON_SIZES = [16, 22, 24, 32, 48, 64, 96, 128, 256]


def find_mark_crop_box(im):
    """
    Auto-detects the icon mark's bounding box by finding the first
    significant horizontal gap in alpha-channel ink density (the visual
    separation between the circular mark and the wordmark text), after
    the content has robustly started (skips past faint antialiased edge
    pixels near the very start, which otherwise look like a false gap).
    Falls back to a centered square crop if no clear gap is found.
    """
    alpha = np.array(im.split()[3])
    col_density = alpha.sum(axis=0)
    nonzero = np.nonzero(col_density)[0]
    if len(nonzero) == 0:
        return None

    first_col, last_col = nonzero[0], nonzero[-1]
    max_density = col_density.max()
    strong_threshold = max_density * 0.3
    gap_threshold = max_density * 0.01

    seen_strong_content = False
    in_gap = False
    gap_start = None
    for i in range(first_col, last_col + 1):
        v = col_density[i]
        if not seen_strong_content:
            if v >= strong_threshold:
                seen_strong_content = True
            continue

        if v <= gap_threshold:
            if not in_gap:
                gap_start = i
                in_gap = True
        else:
            if in_gap and (i - gap_start) > 15:
                crop_right = gap_start + 15
                return (max(0, first_col - 20), 0, min(im.width, crop_right), im.height)
            in_gap = False

    return None  # no clear gap found


def main():
    if not os.path.exists(LOGO_PATH):
        raise SystemExit(f"Logo not found at {LOGO_PATH}")

    im = Image.open(LOGO_PATH).convert("RGBA")
    box = find_mark_crop_box(im)

    if box is None:
        print("WARNING: couldn't auto-detect mark/wordmark gap — "
              "falling back to a centered square crop of the full logo.")
        side = min(im.width, im.height)
        cx = im.width // 2
        box = (cx - side // 2, 0, cx + side // 2, side)

    mark = im.crop(box)

    # Pad to square (the detected mark is usually close to square already,
    # but pad symmetrically either way to guarantee it).
    side = max(mark.width, mark.height)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(mark, ((side - mark.width) // 2, (side - mark.height) // 2), mark)

    os.makedirs(OUT_DIR, exist_ok=True)

    # distributor-logo.png — standard path many Linux tools check for
    # "which distro made this" branding (about dialogs, some info tools).
    distributor = square.resize((256, 256), Image.LANCZOS)
    distributor.save(os.path.join(OUT_DIR, "distributor-logo.png"))

    for size in ICON_SIZES:
        size_dir = os.path.join(OUT_DIR, "hicolor", f"{size}x{size}", "apps")
        os.makedirs(size_dir, exist_ok=True)
        resized = square.resize((size, size), Image.LANCZOS)
        resized.save(os.path.join(size_dir, "start-here.png"))

    print(f"Generated distributor-logo.png + {len(ICON_SIZES)} start-here.png sizes "
          f"in {OUT_DIR}")
    print(f"Auto-detected mark crop box: {box}")


if __name__ == "__main__":
    main()
