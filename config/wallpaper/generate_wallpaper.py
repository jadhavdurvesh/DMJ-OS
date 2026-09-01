#!/usr/bin/env python3
"""
generate_wallpaper.py

Builds the default DMJ OS desktop wallpaper: the same dark gradient +
glow visual language as the "DMJ Cinematic" boot splash, but with the
logo small and tucked into a corner (a wallpaper needs to leave room for
desktop icons and a dock — not repeat the boot splash's centered hero
logo treatment).

Reads the real logo from ../plymouth/dmj-cinematic/images/logo.png so
there's a single source of truth for the logo asset. Run this locally
whenever that logo changes:

    python3 generate_wallpaper.py

Output: wallpaper.png (1920x1080) in this directory.
"""
import os
import math
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
LOGO_PATH = os.path.join(HERE, "..", "plymouth", "dmj-cinematic", "images", "logo.png")
OUT_PATH = os.path.join(HERE, "wallpaper.png")

W, H = 1920, 1080


def make_background():
    img = Image.new("RGB", (1, H))
    top = (7, 9, 18)
    bottom = (2, 2, 6)
    px = img.load()
    for y in range(H):
        t = y / H
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        px[0, y] = (r, g, b)
    img = img.resize((W, H))
    return img.convert("RGBA")


def add_ambient_glow(img):
    # A couple of large, very soft glow blobs off to one side, echoing the
    # boot splash's particle field without being distracting on a desktop.
    glow_layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow_layer)
    spots = [
        (int(W * 0.82), int(H * 0.28), 320, (90, 120, 220, 90)),
        (int(W * 0.15), int(H * 0.85), 260, (120, 90, 220, 60)),
    ]
    for cx, cy, r, color in spots:
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    glow_layer = glow_layer.filter(ImageFilter.GaussianBlur(120))
    img.alpha_composite(glow_layer)
    return img


def add_logo_watermark(img):
    if not os.path.exists(LOGO_PATH):
        print(f"WARNING: logo not found at {LOGO_PATH}, skipping watermark")
        return img
    logo = Image.open(LOGO_PATH).convert("RGBA")

    # Small, bottom-left, low-opacity — a watermark, not a hero element.
    target_w = int(W * 0.14)
    scale = target_w / logo.width
    logo = logo.resize((target_w, int(logo.height * scale)), Image.LANCZOS)

    # Reduce opacity
    alpha = logo.split()[3].point(lambda a: int(a * 0.5))
    logo.putalpha(alpha)

    margin = 56
    pos = (margin, H - logo.height - margin)
    img.alpha_composite(logo, pos)
    return img


if __name__ == "__main__":
    img = make_background()
    img = add_ambient_glow(img)
    img = add_logo_watermark(img)
    img.convert("RGB").save(OUT_PATH, quality=95)
    print(f"Wrote {OUT_PATH}")
