#!/usr/bin/env python3
"""Draws The Helm's app icon (1024x1024 PNG, 2026-10-25): a ship's wheel in dark gunmetal with crimson edges, and Friday's glowing
crimson orb at its hub, ringed by wavy crimson and blue light, on a midnight rounded square. Everything is drawn here with Pillow
and numpy; nothing is copied from anywhere. Run: python3 make_helm_icon.py [out.png] (default: Friday-1024.png next to this file,
the name rebuild.sh looks for). The Mac turns the PNG into the .icns during the update (rebuild.sh uses sips and iconutil)."""
import math
import os
import sys

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 2                      # supersampling
N = 1024 * S
BODY = 824 * S             # Apple's icon grid: an 824 px body inside the 1024 px canvas
OFF = (N - BODY) // 2
RADIUS = int(190 * S)
C = N / 2
W = 0.84                   # the wheel's size inside the icon body


def grid(h, w):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    return x, y


def rgba(rgb, alpha):
    arr = np.concatenate([rgb, alpha[..., None]], axis=2)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGBA")


def background():
    x, y = grid(N, N)
    t = np.clip((y - OFF) / BODY, 0, 1)[..., None]
    top = np.array([14, 18, 40], np.float32)       # midnight blue
    bot = np.array([6, 5, 10], np.float32)         # near black
    rgb = top * (1 - t) + bot * t
    d = np.sqrt((x - C) ** 2 + (y - C) ** 2) / (BODY * 0.55)
    rgb += (np.clip(1 - d, 0, 1) ** 2.0)[..., None] * np.array([150, 20, 52], np.float32) * 0.55   # crimson heart glow
    up = np.sqrt((x - C) ** 2 + (y - (OFF + BODY * 0.12)) ** 2) / (BODY * 0.6)
    rgb += (np.clip(1 - up, 0, 1) ** 2.4)[..., None] * np.array([40, 90, 200], np.float32) * 0.35  # cool blue from above
    v = np.sqrt((x - C) ** 2 + (y - C) ** 2) / (BODY * 0.72)
    rgb *= (1 - np.clip(v - 0.55, 0, 1) ** 1.6 * 0.6)[..., None]
    return rgba(rgb, np.full((N, N), 255, np.float32))


def wheel_mask():
    m = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(m)
    u = S * W
    ro, ri = 300 * u, 258 * u
    d.ellipse([C - ro, C - ro, C + ro, C + ro], fill=255)
    d.ellipse([C - ri, C - ri, C + ri, C + ri], fill=0)
    for k in range(8):
        a = math.pi / 8 + k * math.pi / 4
        ca, sa = math.cos(a), math.sin(a)
        # spoke from the hub out through the rim
        for r in np.linspace(112 * u, 336 * u, 120):
            w = 12 * u
            d.ellipse([C + ca * r - w, C + sa * r - w, C + ca * r + w, C + sa * r + w], fill=255)
        # the handle: a tapered grip ending in a round knob
        for i, r in enumerate(np.linspace(336 * u, 372 * u, 40)):
            w = (17 - 4 * i / 39) * u
            d.ellipse([C + ca * r - w, C + sa * r - w, C + ca * r + w, C + sa * r + w], fill=255)
        kr = 24 * u
        kx, ky = C + ca * 384 * u, C + sa * 384 * u
        d.ellipse([kx - kr, ky - kr, kx + kr, ky + kr], fill=255)
    # the hub ring that holds the orb
    hro, hri = 138 * u, 112 * u
    d.ellipse([C - hro, C - hro, C + hro, C + hro], fill=255)
    d.ellipse([C - hri, C - hri, C + hri, C + hri], fill=0)
    return m


def metal(mask):
    m = np.asarray(mask, np.float32) / 255
    soft = np.asarray(mask.filter(ImageFilter.GaussianBlur(7 * S)), np.float32) / 255
    # emboss: light from the upper left
    sh = 5 * S
    lit = np.roll(np.roll(soft, sh, 0), sh, 1) - np.roll(np.roll(soft, -sh, 0), -sh, 1)
    x, y = grid(N, N)
    t = np.clip((y - (C - 400 * S)) / (800 * S), 0, 1)[..., None]
    base = np.array([44, 47, 64], np.float32) * (1 - t) + np.array([14, 14, 22], np.float32) * t
    rgb = base + np.clip(lit, 0, 1)[..., None] * np.array([170, 180, 215], np.float32) * 1.25
    rgb -= np.clip(-lit, 0, 1)[..., None] * np.array([30, 30, 40], np.float32)
    # crimson edge light
    inner = np.asarray(mask.filter(ImageFilter.MinFilter(5)), np.float32) / 255
    edge = np.clip(m - inner, 0, 1)
    edge = np.asarray(Image.fromarray((edge * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2 * S)), np.float32) / 255
    rgb += edge[..., None] * np.array([235, 40, 70], np.float32) * 0.85
    # a faint brushed sheen along each ring
    ang = np.arctan2(y - C, x - C)
    rgb += ((np.sin(ang * 22) * 0.5 + 0.5) ** 6)[..., None] * 10
    return rgba(rgb, m * 255)


def glow_of(mask, color, blur, strength):
    g = np.asarray(mask.filter(ImageFilter.GaussianBlur(blur)), np.float32) / 255 * strength
    rgb = np.zeros((N, N, 3), np.float32) + np.array(color, np.float32)
    return rgba(rgb, np.clip(g, 0, 1) * 255)


def waves():
    """Wavy rings of light around the orb, crimson, blue and white (Matthew: "reddish ... not as cloudy, more so like wavy")."""
    layer = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    specs = [(112, 7.0, 6, 0.0, (255, 60, 90, 235), 4),
             (110, 6.0, 5, 1.3, (90, 150, 255, 215), 3),
             (114, 4.0, 7, 2.6, (255, 235, 240, 160), 2)]
    for base, amp, lobes, phase, color, width in specs:
        pts = []
        for i in range(721):
            a = 2 * math.pi * i / 720
            r = (base + amp * math.sin(lobes * a + phase)) * S * W
            pts.append((C + r * math.cos(a), C + r * math.sin(a)))
        d.line(pts, fill=color, width=width * S, joint="curve")
    blurred = layer.filter(ImageFilter.GaussianBlur(5 * S))
    return Image.alpha_composite(blurred, layer.filter(ImageFilter.GaussianBlur(0.8 * S)))


def orb(r):
    size = int(r * 2.6)
    x, y = grid(size, size)
    o = size / 2
    dx, dy = (x - o) / r, (y - o) / r
    dist = np.sqrt(dx ** 2 + dy ** 2)
    nz = np.sqrt(np.clip(1 - dist ** 2, 0, 1))
    lx, ly, lz = -0.45, -0.55, 0.70
    lamb = np.clip(dx * lx + dy * ly + nz * lz, 0, 1)
    spec = lamb ** 46
    deep = np.array([58, 6, 20], np.float32)
    mid = np.array([214, 28, 62], np.float32)
    hot = np.array([255, 120, 138], np.float32)
    t = lamb[..., None]
    rgb = np.where(t < 0.55, deep + (mid - deep) * (t / 0.55), mid + (hot - mid) * ((t - 0.55) / 0.45))
    # a swirl of cooler light inside the glass, so she reads as alive rather than a ball
    ang = np.arctan2(dy, dx)
    swirl = np.clip(np.sin(ang * 3 + dist * 7.5) * 0.5 + 0.5, 0, 1) ** 4 * np.clip(1 - dist, 0, 1)
    rgb = rgb + swirl[..., None] * np.array([70, 110, 255], np.float32) * 0.22
    rim = np.clip(((dx * 0.5 + dy * 0.6) * 0.9 + (1 - nz)) - 0.55, 0, 1) ** 1.5
    rgb = rgb + rim[..., None] * np.array([255, 70, 90], np.float32) * 0.35
    rgb = rgb * (0.78 + 0.22 * nz[..., None]) + spec[..., None] * 95
    edge = np.clip((1 - dist) * r / (1.5 * S), 0, 1)
    img = rgba(rgb, (dist <= 1) * np.clip(edge * 4, 0, 1) * 255)
    hl = Image.new("L", (size, size), 0)
    ImageDraw.Draw(hl).ellipse([o - r * 0.62, o - r * 0.80, o + r * 0.18, o - r * 0.22], fill=120)
    hl = hl.filter(ImageFilter.GaussianBlur(r * 0.10))
    white = Image.new("RGBA", (size, size), (255, 235, 240, 0))
    white.putalpha(ImageChops.multiply(hl, img.getchannel("A")))
    return Image.alpha_composite(img, white)


def main(out):
    icon = background()
    mask = wheel_mask()
    icon = Image.alpha_composite(icon, glow_of(mask, (230, 30, 70), 22 * S, 0.55))
    shadow = glow_of(mask, (0, 0, 0), 9 * S, 0.9)
    icon = Image.alpha_composite(icon, ImageChops.offset(shadow, 6 * S, 10 * S))
    icon = Image.alpha_composite(icon, metal(mask))
    icon = Image.alpha_composite(icon, waves())
    r = 100 * S * W
    halo = Image.new("L", (N, N), 0)
    ImageDraw.Draw(halo).ellipse([C - r * 1.15, C - r * 1.15, C + r * 1.15, C + r * 1.15], fill=255)
    icon = Image.alpha_composite(icon, glow_of(halo, (255, 40, 80), 30 * S, 0.8))
    ball = orb(r)
    icon.alpha_composite(ball, (int(C - ball.width / 2), int(C - ball.height / 2)))
    # clip to the rounded square
    sq = Image.new("L", (N, N), 0)
    ImageDraw.Draw(sq).rounded_rectangle([OFF, OFF, OFF + BODY, OFF + BODY], radius=RADIUS, fill=255)
    icon.putalpha(ImageChops.multiply(icon.getchannel("A"), sq))
    icon.resize((1024, 1024), Image.LANCZOS).save(out)
    print("wrote", out)


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "Friday-1024.png"))
