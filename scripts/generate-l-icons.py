#!/usr/bin/env python3
"""Generate 2-3 'L' icon previews for Liang using the Luminous Signal philosophy."""

import os
import math
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import numpy as np

SIZE = 1024
RADIUS = int(SIZE * 0.225)
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets")
CANVAS_FONTS = "/Users/fangshili/.codebuddy/plugins/marketplaces/codebuddy-plugins-official/external_plugins/canvas-design/canvas-fonts"
FONT_PATH = os.path.join(CANVAS_FONTS, "Outfit-Bold.ttf")

# Design system colors
BLUE = (59, 130, 246, 255)       # #3B82F6
LIGHT_BLUE = (96, 165, 250, 255) # #60A5FA
ORANGE = (249, 115, 22, 255)     # #F97316
WHITE = (255, 255, 255, 255)


def hex_to_rgba(hex_color, alpha=255):
    hex_color = hex_color.lstrip("#")
    return tuple(int(hex_color[i:i + 2], 16) for i in (0, 2, 4)) + (alpha,)


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle((0, 0, size[0], size[1]), radius=radius, fill=255)
    return mask


def circle_mask(size, center, radius):
    mask = Image.new("L", size, 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse(
        [center[0] - radius, center[1] - radius, center[0] + radius, center[1] + radius],
        fill=255,
    )
    return mask


def linear_gradient(size, top, bottom):
    h, w = size[1], size[0]
    y = np.linspace(0, 1, h)[:, None]
    x = np.linspace(0, 1, w)[None, :]
    t = (y * 0.6 + x * 0.4).clip(0, 1)
    arr = (1 - t)[..., None] * np.array(top, dtype=np.float32) + t[..., None] * np.array(bottom, dtype=np.float32)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def radial_gradient(size, center, radius, inner, outer):
    h, w = size[1], size[0]
    yy, xx = np.ogrid[:h, :w]
    dist = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2)
    t = np.clip(dist / radius, 0, 1)[..., None]
    arr = (1 - t) * np.array(inner, dtype=np.float32) + t * np.array(outer, dtype=np.float32)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def icon_background(size, radius, top, bottom):
    grad = linear_gradient(size, top, bottom)
    mask = rounded_mask(size, radius)
    grad.putalpha(mask)
    bg = Image.new("RGBA", size, (0, 0, 0, 0))
    bg.paste(grad, (0, 0), grad)
    return bg


def make_text_layer(text, font_path, font_size, size, color):
    font = ImageFont.truetype(font_path, font_size)
    bbox = font.getbbox(text)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    x = (size[0] - text_w) // 2 - bbox[0]
    y = (size[1] - text_h) // 2 - bbox[1]
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.text((x, y), text, font=font, fill=color)
    return img


def make_glow(text_img, glow_color, blur_radius):
    alpha = text_img.getchannel("A")
    glow = Image.new("RGBA", text_img.size, glow_color)
    glow.putalpha(alpha)
    glow = glow.filter(ImageFilter.GaussianBlur(blur_radius))
    return glow


def draw_l_glow():
    # Deep indigo -> violet, not black
    bg = icon_background(
        (SIZE, SIZE), RADIUS,
        hex_to_rgba("#312e81"), hex_to_rgba("#4f46e5")
    )

    text = make_text_layer("L", FONT_PATH, 560, (SIZE, SIZE), WHITE)
    glow = make_glow(text, ORANGE, 55)
    bg = Image.alpha_composite(bg, glow)
    bg = Image.alpha_composite(bg, text)

    # subtle halo ring
    ring = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    rdraw = ImageDraw.Draw(ring)
    rdraw.ellipse([SIZE // 2 - 340, SIZE // 2 - 340, SIZE // 2 + 340, SIZE // 2 + 340],
                  outline=LIGHT_BLUE[:3] + (40,), width=8)
    ring = ring.filter(ImageFilter.GaussianBlur(10))
    bg = Image.alpha_composite(bg, ring)

    return bg


def draw_l_rays():
    # Deep blue -> sky
    bg = icon_background(
        (SIZE, SIZE), RADIUS,
        hex_to_rgba("#1e3a8a"), hex_to_rgba("#0ea5e9")
    )

    # scattered rays
    rays = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    rdraw = ImageDraw.Draw(rays)
    cx, cy = SIZE // 2, SIZE // 2
    ray_count = 12
    for i in range(ray_count):
        angle = 2 * math.pi * i / ray_count + 0.15
        length = 420
        x2 = cx + math.cos(angle) * length
        y2 = cy + math.sin(angle) * length
        # alternate colors
        color = WHITE[:3] + (50,) if i % 2 == 0 else ORANGE[:3] + (45,)
        rdraw.line([(cx, cy), (x2, y2)], fill=color, width=22)
    rays = rays.filter(ImageFilter.GaussianBlur(18))
    bg = Image.alpha_composite(bg, rays)

    text = make_text_layer("L", FONT_PATH, 520, (SIZE, SIZE), WHITE)
    glow = make_glow(text, LIGHT_BLUE, 45)
    bg = Image.alpha_composite(bg, glow)
    bg = Image.alpha_composite(bg, text)

    return bg


def draw_l_orb():
    # Purple -> fuchsia
    bg = icon_background(
        (SIZE, SIZE), RADIUS,
        hex_to_rgba("#581c87"), hex_to_rgba("#c026d3")
    )

    # glowing orb behind L
    orb = radial_gradient(
        (SIZE, SIZE), (SIZE // 2, SIZE // 2), 360,
        LIGHT_BLUE[:3] + (90,), LIGHT_BLUE[:3] + (0,)
    )
    orb = orb.filter(ImageFilter.GaussianBlur(25))
    bg = Image.alpha_composite(bg, orb)

    # inner bright core
    core = radial_gradient(
        (SIZE, SIZE), (SIZE // 2, SIZE // 2), 180,
        WHITE[:3] + (80,), WHITE[:3] + (0,)
    )
    core = core.filter(ImageFilter.GaussianBlur(15))
    bg = Image.alpha_composite(bg, core)

    text = make_text_layer("L", FONT_PATH, 480, (SIZE, SIZE), WHITE)
    glow = make_glow(text, ORANGE, 35)
    bg = Image.alpha_composite(bg, glow)
    bg = Image.alpha_composite(bg, text)

    return bg


def save(img, name):
    path = os.path.join(OUT_DIR, name)
    img.save(path)
    print(f"Saved {path}")


if __name__ == "__main__":
    save(draw_l_glow(), "icon-l-glow.png")
    save(draw_l_rays(), "icon-l-rays.png")
    save(draw_l_orb(), "icon-l-orb.png")
    print("Done.")
