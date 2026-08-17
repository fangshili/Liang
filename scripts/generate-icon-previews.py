#!/usr/bin/env python3
"""Generate three 1024x1024 Dock icon preview PNGs for Liang."""

import os
from PIL import Image, ImageDraw, ImageFilter
import numpy as np

SIZE = 1024
RADIUS = int(SIZE * 0.225)  # Big Sur-ish corner radius
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "icon-previews")

BG_TOP = (42, 42, 46, 255)
BG_BOT = (24, 24, 27, 255)
IDLE = (229, 131, 37, 255)      # #E58325
WARM_WHITE = (255, 245, 230, 255)


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
    y = np.linspace(0, 1, size[1])[:, None]
    x = np.linspace(0, 1, size[0])[None, :]
    # diagonal-ish: mix vertical and horizontal
    t = (y * 0.7 + x * 0.3).clip(0, 1)
    arr = (1 - t)[..., None] * np.array(top, dtype=np.float32) + t[..., None] * np.array(bottom, dtype=np.float32)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def radial_gradient(size, center, radius, inner, outer):
    h, w = size[1], size[0]
    yy, xx = np.ogrid[:h, :w]
    dist = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2)
    t = np.clip(dist / radius, 0, 1)[..., None]
    arr = (1 - t) * np.array(inner, dtype=np.float32) + t * np.array(outer, dtype=np.float32)
    return Image.fromarray(arr.astype(np.uint8), "RGBA")


def ring_gradient(size, center, inner_r, outer_r, color):
    h, w = size[1], size[0]
    yy, xx = np.ogrid[:h, :w]
    dist = np.sqrt((xx - center[0]) ** 2 + (yy - center[1]) ** 2)
    # smooth alpha from 1 at inner_r down to 0 at outer_r, 0 inside inner_r
    alpha = np.where(dist < inner_r, 0.0, 1.0 - np.clip((dist - inner_r) / (outer_r - inner_r), 0, 1))
    alpha = (alpha * color[3]).astype(np.uint8)
    rgb = np.full((h, w, 3), color[:3], dtype=np.uint8)
    arr = np.dstack([rgb, alpha])
    return Image.fromarray(arr, "RGBA")


def new_canvas():
    bg_grad = linear_gradient((SIZE, SIZE), BG_TOP, BG_BOT)
    mask = rounded_mask((SIZE, SIZE), RADIUS)
    bg_grad.putalpha(mask)
    bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    bg.paste(bg_grad, (0, 0), bg_grad)
    return bg


def save_option(img, name):
    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, name)
    img.save(path)
    print(f"Saved {path}")


def draw_orb():
    base = new_canvas()
    cx, cy = SIZE // 2, SIZE // 2

    # outer glow
    glow = radial_gradient((SIZE, SIZE), (cx, cy), 300, IDLE[:3] + (45,), IDLE[:3] + (0,))
    glow = glow.filter(ImageFilter.GaussianBlur(20))
    base = Image.alpha_composite(base, glow)

    # sphere
    sphere = radial_gradient((SIZE, SIZE), (cx, cy), 220, WARM_WHITE, IDLE)
    sphere.putalpha(circle_mask((SIZE, SIZE), (cx, cy), 220))
    base = Image.alpha_composite(base, sphere)

    # specular highlight
    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(highlight)
    hdraw.ellipse([cx - 75, cy - 85, cx + 35, cy - 25], fill=(255, 255, 255, 90))
    highlight = highlight.filter(ImageFilter.GaussianBlur(18))
    base = Image.alpha_composite(base, highlight)

    save_option(base, "option-01-orb.png")


def draw_notch_halo():
    base = new_canvas()

    # screen panel
    panel = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    pdraw = ImageDraw.Draw(panel)
    inset = 90
    pdraw.rounded_rectangle(
        [inset, inset, SIZE - inset, SIZE - inset],
        radius=140,
        fill=(34, 34, 38, 255),
    )
    base = Image.alpha_composite(base, panel)

    # menu bar line
    line = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ldraw = ImageDraw.Draw(line)
    ldraw.rounded_rectangle(
        [inset + 40, inset + 28, SIZE - inset - 40, inset + 36],
        radius=4,
        fill=(80, 80, 86, 255),
    )
    base = Image.alpha_composite(base, line)

    # top halo arc
    halo = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    hdraw = ImageDraw.Draw(halo)
    # a soft thick arc shape using a large ellipse with vertical compression
    arc_layer = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    adraw = ImageDraw.Draw(arc_layer)
    adraw.ellipse(
        [SIZE // 2 - 300, 110, SIZE // 2 + 300, 330],
        fill=IDLE[:3] + (120,),
    )
    arc_layer = arc_layer.filter(ImageFilter.GaussianBlur(35))
    base = Image.alpha_composite(base, arc_layer)

    # bright core of the halo
    core = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    cdraw = ImageDraw.Draw(core)
    cdraw.ellipse(
        [SIZE // 2 - 140, 150, SIZE // 2 + 140, 250],
        fill=WARM_WHITE[:3] + (160,),
    )
    core = core.filter(ImageFilter.GaussianBlur(20))
    base = Image.alpha_composite(base, core)

    save_option(base, "option-02-notch-halo.png")


def draw_status_dot():
    base = new_canvas()
    cx, cy = SIZE // 2, SIZE // 2

    # outer ring
    ring2 = ring_gradient((SIZE, SIZE), (cx, cy), 180, 260, IDLE[:3] + (40,))
    ring2 = ring2.filter(ImageFilter.GaussianBlur(12))
    base = Image.alpha_composite(base, ring2)

    # inner ring
    ring1 = ring_gradient((SIZE, SIZE), (cx, cy), 90, 150, WARM_WHITE[:3] + (90,))
    ring1 = ring1.filter(ImageFilter.GaussianBlur(8))
    base = Image.alpha_composite(base, ring1)

    # central dot
    dot = radial_gradient((SIZE, SIZE), (cx, cy), 55, WARM_WHITE, IDLE)
    dot.putalpha(circle_mask((SIZE, SIZE), (cx, cy), 55))
    base = Image.alpha_composite(base, dot)

    save_option(base, "option-03-status-dot.png")


if __name__ == "__main__":
    draw_orb()
    draw_notch_halo()
    draw_status_dot()
    print(f"\nAll previews written to: {OUT_DIR}")
