#!/usr/bin/env python3
"""
generate_assets.py

Generates the image assets used by the DMJ OS cinematic Plymouth theme:
  - logo.png       : "DMJ OS" wordmark, white on transparent, for the main reveal
  - logo_glow.png  : soft blurred glow version of the same wordmark, drawn
                     behind the logo for a glow effect
  - particle.png   : a small soft-edged dot, reused many times by the
                     script to build an ambient particle field
  - progress_dot.png : small solid dot used to render the loading bar

Run this once locally (Pillow required: pip install pillow) before
building the ISO. Output goes into the theme's images/ directory.
"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "images")
os.makedirs(OUT_DIR, exist_ok=True)


def find_font(size):
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    ]
    for c in candidates:
        if os.path.exists(c):
            return ImageFont.truetype(c, size)
    return ImageFont.load_default()


def make_logo():
    W, H = 900, 260
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    font_main = find_font(120)
    font_sub = find_font(34)

    text_main = "DMJ OS"
    bbox = draw.textbbox((0, 0), text_main, font=font_main)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    main_x = (W - tw) / 2
    main_y = 40
    draw.text((main_x, main_y), text_main, font=font_main, fill=(255, 255, 255, 255))

    text_sub = "P O W E R E D   B Y   S A U D A D E"
    bbox2 = draw.textbbox((0, 0), text_sub, font=font_sub)
    sw = bbox2[2] - bbox2[0]
    draw.text(((W - sw) / 2, main_y + th + 30), text_sub, font=font_sub,
               fill=(160, 190, 255, 200))

    img.save(os.path.join(OUT_DIR, "logo.png"))

    # Glow version: blur a solid white silhouette of the same text
    glow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    gdraw = ImageDraw.Draw(glow)
    gdraw.text((main_x, main_y), text_main, font=font_main, fill=(120, 170, 255, 255))
    glow = glow.filter(ImageFilter.GaussianBlur(18))
    glow.save(os.path.join(OUT_DIR, "logo_glow.png"))


def make_particle():
    size = 24
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    cx = cy = size / 2
    for r in range(int(size / 2), 0, -1):
        alpha = int(255 * (1 - r / (size / 2)) ** 2)
        draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(170, 200, 255, alpha))
    img.save(os.path.join(OUT_DIR, "particle.png"))


def make_progress_dot():
    size = 10
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.ellipse([0, 0, size - 1, size - 1], fill=(120, 170, 255, 255))
    img.save(os.path.join(OUT_DIR, "progress_dot.png"))


def make_background():
    # Deep navy -> near-black vertical gradient, matches a "cinematic" feel
    W, H = 1920, 1080
    img = Image.new("RGB", (W, H))
    top = (8, 10, 20)
    bottom = (2, 3, 8)
    for y in range(H):
        t = y / H
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        for x in range(0, W, 4):  # coarse fill, fast, fine for a gradient
            img.putpixel((x, y), (r, g, b))
    img = img.resize((W, H))  # smooth out the coarse step via resize blur
    img.save(os.path.join(OUT_DIR, "background.png"))


if __name__ == "__main__":
    make_logo()
    make_particle()
    make_progress_dot()
    make_background()
    print(f"Assets written to {OUT_DIR}")
