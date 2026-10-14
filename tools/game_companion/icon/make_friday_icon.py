#!/usr/bin/env python3
"""Draws Friday's app icon (1024x1024 PNG): a noir rounded square with her crimson glass orb, a tilted orbit ring and a few sparks.
Everything is drawn here with Pillow and numpy; nothing is copied from anywhere. Run: python3 make_friday_icon.py [out.png]
The Mac turns the PNG into the .icns during the update (rebuild.sh uses sips and iconutil)."""
import math
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2                      # supersampling
N = 1024 * S
BODY = 824 * S             # Apple's icon grid: an 824 px body inside the 1024 px canvas
OFF = (N - BODY) // 2
RADIUS = int(190 * S)


def grid(h, w):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    return x, y


def to_img(arr):
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def lerp(a, b, t):
    return a + (b - a) * t


def squircle_mask(size, radius, offset, canvas):
    m = Image.new("L", (canvas, canvas), 0)
    ImageDraw.Draw(m).rounded_rectangle([offset, offset, offset + size, offset + size], radius=radius, fill=255)
    return m


def background():
    x, y = grid(N, N)
    t = np.clip((y - OFF) / BODY, 0, 1)
    top = np.array([40, 14, 26], np.float32)     # deep wine
    bot = np.array([9, 4, 8], np.float32)        # near black
    rgb = top[None, None, :] * (1 - t[..., None]) + bot[None, None, :] * t[..., None]
    # a soft glow behind the orb and a vignette at the edges
    cx, cy = N * 0.5, N * 0.52
    d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2) / (BODY * 0.62)
    glow = np.clip(1 - d, 0, 1) ** 2.2
    rgb += glow[..., None] * np.array([120, 18, 44], np.float32) * 0.55
    v = np.sqrt((x - N / 2) ** 2 + (y - N / 2) ** 2) / (BODY * 0.72)
    rgb *= (1 - np.clip(v - 0.55, 0, 1) ** 1.6 * 0.55)[..., None]
    a = np.full((N, N, 1), 255, np.float32)
    return to_img(np.concatenate([rgb, a], axis=2))


def orb(cx, cy, r):
    size = int(r * 2.6)
    x, y = grid(size, size)
    ox, oy = size / 2, size / 2
    dx, dy = (x - ox) / r, (y - oy) / r
    dist = np.sqrt(dx ** 2 + dy ** 2)
    inside = (dist <= 1).astype(np.float32)
    edge = np.clip((1 - dist) * r / (1.5 * S), 0, 1)           # antialiased rim
    # shading: a light from the upper left
    nz = np.sqrt(np.clip(1 - dist ** 2, 0, 1))
    lx, ly, lz = -0.45, -0.55, 0.70
    lamb = np.clip(dx * lx + dy * ly + nz * lz, 0, 1)
    spec = np.clip(dx * lx + dy * ly + nz * lz, 0, 1) ** 46
    deep = np.array([58, 6, 20], np.float32)
    mid = np.array([214, 28, 62], np.float32)
    hot = np.array([255, 120, 138], np.float32)
    t = lamb[..., None]
    rgb = np.where(t < 0.55, deep + (mid - deep) * (t / 0.55), mid + (hot - mid) * ((t - 0.55) / 0.45))
    # rim light from below right (a warm bounce) and a darker edge
    rim = np.clip(((dx * 0.5 + dy * 0.6) * 0.9 + (1 - nz)) - 0.55, 0, 1) ** 1.5
    rgb = rgb + rim[..., None] * np.array([255, 70, 90], np.float32) * 0.35
    rgb = rgb * (0.78 + 0.22 * nz[..., None])
    rgb = rgb + spec[..., None] * 95
    a = (inside * (edge * 0 + 1) * 255)[..., None]
    a = a * np.clip(edge * 4, 0, 1)[..., None]
    img = to_img(np.concatenate([rgb, a], axis=2))
    # glassy highlight arc (top left) and a small hot spot
    hl = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(hl)
    d.ellipse([ox - r * 0.78, oy - r * 0.86, ox + r * 0.12, oy - r * 0.18], fill=(255, 255, 255, 62))
    hl = hl.filter(ImageFilter.GaussianBlur(r * 0.07))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse([ox - r, oy - r, ox + r, oy + r], fill=255)
    hl.putalpha(ImageChops.multiply(hl.getchannel("A"), mask))
    img = Image.alpha_composite(img, hl)
    dot = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(dot).ellipse([ox - r * 0.62, oy - r * 0.70, ox - r * 0.30, oy - r * 0.56], fill=(255, 255, 255, 150))
    dot = dot.rotate(32, resample=Image.BICUBIC, center=(ox - r * 0.46, oy - r * 0.63)).filter(ImageFilter.GaussianBlur(r * 0.03))
    img = Image.alpha_composite(img, dot)
    return img, (cx - size // 2, cy - size // 2)


def ring(cx, cy, rx, ry, angle, front):
    """The orbit ring: drawn twice, the back half dimmer (behind the orb) and the front half bright (in front of it)."""
    size = int(rx * 2.4)
    c = size / 2
    width = 13 * S
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    steps = 900
    for i in range(steps + 1):
        k = i / steps
        th = (0 if front else math.pi) + math.pi * k       # front half: the lower half of the ellipse on screen (y grows downward)
        px, py = c + rx * math.cos(th), c + ry * math.sin(th)
        fade = math.sin(math.pi * k) ** 0.6
        value = int(255 * (0.18 + 0.82 * fade))
        rad = width / 2 * (0.55 + 0.45 * fade)
        d.ellipse([px - rad, py - rad, px + rad, py + rad], fill=value)
    mask = mask.filter(ImageFilter.GaussianBlur(0.8 * S))
    base = 235 if front else 125
    layer = Image.new("RGBA", (size, size), (255, 118, 138, 0))
    layer.putalpha(mask.point(lambda v: int(v * base / 255)))
    core = Image.new("RGBA", (size, size), (255, 214, 222, 0))
    core.putalpha(mask.point(lambda v: int(max(0, v - 120) * (base / 255) * 0.9)))
    glow = layer.filter(ImageFilter.GaussianBlur(11 * S))
    layer = Image.alpha_composite(Image.alpha_composite(glow, layer), core)
    layer = layer.rotate(angle, resample=Image.BICUBIC, center=(c, c))
    return layer, (cx - size // 2, cy - size // 2)


def spark(draw_img, cx, cy, r, alpha=255, color=(255, 230, 236)):
    layer = Image.new("RGBA", draw_img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w = r * 0.16
    d.polygon([(cx, cy - r), (cx + w, cy - w), (cx + r, cy), (cx + w, cy + w), (cx, cy + r), (cx - w, cy + w), (cx - r, cy), (cx - w, cy - w)], fill=color + (alpha,))
    glow = layer.filter(ImageFilter.GaussianBlur(r * 0.35))
    out = Image.alpha_composite(draw_img, glow)
    return Image.alpha_composite(out, layer)


def main(path):
    canvas = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    mask = squircle_mask(BODY, RADIUS, OFF, N)
    # soft drop shadow under the body
    shadow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    sh = Image.new("L", (N, N), 0)
    ImageDraw.Draw(sh).rounded_rectangle([OFF, OFF + 14 * S, OFF + BODY, OFF + BODY + 14 * S], radius=RADIUS, fill=150)
    shadow.putalpha(sh.filter(ImageFilter.GaussianBlur(22 * S)))
    canvas = Image.alpha_composite(canvas, shadow)
    body = background()
    body.putalpha(mask)
    canvas = Image.alpha_composite(canvas, body)

    cx, cy, r = N // 2, int(N * 0.515), int(255 * S)
    back, pos = ring(cx, cy, int(385 * S), int(112 * S), -20, front=False)
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0)); layer.paste(back, pos, back)
    canvas = Image.alpha_composite(canvas, layer)
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse([cx - r * 1.25, cy - r * 1.25, cx + r * 1.25, cy + r * 1.25], fill=(230, 30, 70, 150))
    canvas = Image.alpha_composite(canvas, glow.filter(ImageFilter.GaussianBlur(70 * S)))
    o, pos = orb(cx, cy, r)
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0)); layer.paste(o, pos, o)
    canvas = Image.alpha_composite(canvas, layer)
    front, pos = ring(cx, cy, int(385 * S), int(112 * S), -20, front=True)
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0)); layer.paste(front, pos, front)
    canvas = Image.alpha_composite(canvas, layer)

    # sparks
    canvas = spark(canvas, int(N * 0.745), int(N * 0.285), int(54 * S))
    canvas = spark(canvas, int(N * 0.235), int(N * 0.70), int(30 * S), alpha=230)
    canvas = spark(canvas, int(N * 0.80), int(N * 0.705), int(20 * S), alpha=200, color=(255, 190, 205))
    canvas = spark(canvas, int(N * 0.30), int(N * 0.255), int(16 * S), alpha=190, color=(255, 190, 205))

    # keep everything inside the body shape
    canvas.putalpha(ImageChops.multiply(canvas.getchannel("A"), ImageChops.lighter(mask, shadow.getchannel("A"))))
    out = canvas.resize((1024, 1024), Image.LANCZOS)
    out.save(path)
    print("wrote", path)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "Friday-1024.png")
