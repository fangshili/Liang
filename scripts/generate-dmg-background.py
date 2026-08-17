#!/usr/bin/env python3
"""生成 Liang DMG 背景图。"""

import os
from PIL import Image, ImageDraw, ImageFont

SIZE = (660, 400)
BG_TOP = (245, 245, 247, 255)      # #F5F5F7
BG_BOTTOM = (232, 232, 237, 255)   # #E8E8ED
ARROW_COLOR = (249, 115, 22, 255)  # #F97316
TEXT_COLOR = (60, 60, 67, 255)     # #3C3C43

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUT_PATH = os.path.join(os.path.dirname(SCRIPT_DIR), "build", "dmg-background.png")


def linear_gradient(size, top, bottom):
    img = Image.new("RGBA", size)
    for y in range(size[1]):
        t = y / size[1]
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        a = int(top[3] + (bottom[3] - top[3]) * t)
        for x in range(size[0]):
            img.putpixel((x, y), (r, g, b, a))
    return img


def draw_arrow(draw, cx, cy, width, height, color):
    # 箭头主体：从左到右的粗线 + 三角形箭头
    shaft_left = cx - width // 2 + 30
    shaft_right = cx + width // 2 - 30
    shaft_y = cy
    shaft_half = height // 6

    # 箭杆
    draw.polygon([
        (shaft_left, shaft_y - shaft_half),
        (shaft_right, shaft_y - shaft_half),
        (shaft_right, shaft_y + shaft_half),
        (shaft_left, shaft_y + shaft_half),
    ], fill=color)

    # 箭头三角形
    draw.polygon([
        (shaft_right, shaft_y - height // 2),
        (shaft_right + 30, shaft_y),
        (shaft_right, shaft_y + height // 2),
    ], fill=color)


def main():
    img = linear_gradient(SIZE, BG_TOP, BG_BOTTOM)
    draw = ImageDraw.Draw(img)

    # 图标放在上方，文字放在下方，避免与 Finder 自动显示的文件名标签重叠
    icon_center_y = 140
    # 缩短箭头并使用文字同色，避免被 Applications 文件夹图标遮挡
    draw_arrow(draw, SIZE[0] // 2, icon_center_y, 160, 50, TEXT_COLOR)

    # 英文说明文字
    en_font = ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", 22)
    en_text = "Drag Liang.app to Applications"
    bbox = draw.textbbox((0, 0), en_text, font=en_font)
    en_w = bbox[2] - bbox[0]
    draw.text(((SIZE[0] - en_w) // 2, 270), en_text, font=en_font, fill=TEXT_COLOR)

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    img.save(OUT_PATH)
    print(f"Saved {OUT_PATH}")


if __name__ == "__main__":
    main()
