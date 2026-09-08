# -*- coding: utf-8 -*-
"""Generate FolderMount AppIcon (1024x1024) using PIL."""
import math
from PIL import Image, ImageDraw, ImageFilter

SIZE = 1024


def lerp(a, b, t):
    return a + (b - a) * t


def lerp_color(c1, c2, t):
    return tuple(int(lerp(c1[i], c2[i], t)) for i in range(3))


def draw():
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    # ---- vertical gradient background (deep navy -> blue) ----
    top = (16, 34, 88)
    bottom = (37, 99, 235)
    for y in range(SIZE):
        t = y / (SIZE - 1)
        color = lerp_color(top, bottom, t)
        d = ImageDraw.Draw(img)
        d.line([(0, y), (SIZE, y)], fill=color + (255,))
    # soft radial glow top-left
    glow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gx, gy, gr = 260, 220, 520
    for i in range(gr, 0, -8):
        alpha = int(34 * (1 - i / gr))
        gd.ellipse([gx - i, gy - i, gx + i, gy + i], fill=(120, 180, 255, alpha))
    img = Image.alpha_composite(img, glow)

    d = ImageDraw.Draw(img)

    def rounded_rect(x0, y0, x1, y1, radius, fill, outline=None, width=0):
        d.rounded_rectangle([x0, y0, x1, y1], radius=radius, fill=fill,
                            outline=outline, width=width)

    # ---- folder tab shape ----
    cx = SIZE / 2
    fw, fh = 640, 480
    fx0, fy0 = cx - fw / 2, 300
    fx1, fy1 = cx + fw / 2, fy0 + fh
    tab_h = 130
    folder_color = (245, 247, 252)
    folder_shadow = (10, 24, 66)

    # shadow under folder
    sh = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sd = ImageDraw.Draw(sh)
    sd.rounded_rectangle([fx0 + 16, fy0 + 20, fx1 + 16, fy1 + 24],
                         radius=56, fill=(0, 0, 0, 90))
    sh = sh.filter(ImageFilter.GaussianBlur(28))
    img = Image.alpha_composite(img, sh)
    d = ImageDraw.Draw(img)

    # back panel of folder (rounded rect)
    rounded_rect(fx0, fy0, fx1, fy1, radius=64, fill=folder_color)
    # tab
    rounded_rect(fx0 + 36, fy0 - 74, fx0 + 300, fy0 + 40, radius=44, fill=folder_color)

    # folder inner shading (subtle)
    shade = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    sdd = ImageDraw.Draw(shade)
    sdd.rounded_rectangle([fx0, fy0, fx1, fy1], radius=64, fill=(16, 30, 80, 26))
    mask = Image.new("L", (SIZE, SIZE), 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle([fx0, fy0, fx1, fy1], radius=64, fill=255)
    img = Image.composite(Image.alpha_composite(img, shade), img, mask)

    # ---- link / mount glyph: two folders + arrow ----
    # small folder (mapped target) on right
    s_w, s_h = 300, 220
    sx0, sy0 = cx + 96, fy0 + 250
    sx1, sy1 = sx0 + s_w, sy0 + s_h
    d.rounded_rectangle([sx0, sy0, sx1, sy1], radius=44, fill=(90, 140, 255))
    d.rounded_rectangle([sx0 + 22, sy0 - 40, sx0 + 170, sy0 + 30], radius=30, fill=(90, 140, 255))

    # chain-link ring between the two folders
    ring_color = (255, 255, 255)
    r1 = 52
    ring_cx, ring_cy = cx - 8, fy0 + 396
    d.ellipse([ring_cx - r1, ring_cy - r1, ring_cx + r1, ring_cy + r1],
              outline=ring_color, width=40)
    d.ellipse([ring_cx - r1 - 46, ring_cy - 30, ring_cx + 34, ring_cy + 30],
              outline=ring_color, width=40)
    # second ring overlapping to the left folder
    r2 = 52
    ring2_cx, ring2_cy = cx - 150, fy0 + 396
    d.ellipse([ring2_cx - r2, ring2_cy - r2, ring2_cx + r2, ring2_cy + r2],
              outline=ring_color, width=40)
    # downward arrow inside left folder (mount indicator)
    ar_cx, ar_cy = cx - 150, fy0 + 372
    arrow_color = (23, 56, 150)
    shaft = 34
    d.rounded_rectangle([ar_cx - shaft // 2, ar_cy - 90, ar_cx + shaft // 2, ar_cy + 46],
                        radius=16, fill=arrow_color)
    d.polygon([(ar_cx - 74, ar_cy - 6), (ar_cx + 74, ar_cy - 6),
               (ar_cx, ar_cy + 84)], fill=arrow_color)

    img = img.convert("RGB")
    img.save(r"C:\Users\Administrator\AppData\Local\Doubao\User Data\Default\.doubao\agent_mode\workspace\FolderMount\FolderMount\Assets.xcassets\AppIcon.appiconset\AppIcon.png")
    print("icon saved")


if __name__ == "__main__":
    draw()
