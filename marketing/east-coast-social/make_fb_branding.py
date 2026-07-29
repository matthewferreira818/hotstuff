"""
Renders the East Coast Social Facebook page branding:
    fb-logo.png   1024x1024 - profile picture (shown cropped to a circle)
    fb-cover.png  1640x624  - page cover photo (keep text in the middle band;
                              mobile crops the sides, desktop crops top/bottom)

Same palette as automation/index.html: navy #0d1f33/#14304d, gold #f0b429.
Drawn at 3x and downscaled for smooth edges. Rerun any time to regenerate.
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent

NAVY = (13, 31, 51)
NAVY_2 = (20, 48, 77)
GOLD = (240, 180, 41)
GOLD_SOFT = (240, 180, 41, 70)
INK_LIGHT = (242, 246, 250)
MUTED = (168, 188, 207)


def font(size, bold=True, serif=False):
    if serif:
        path = r"C:\Windows\Fonts\georgiab.ttf" if bold else r"C:\Windows\Fonts\georgia.ttf"
    else:
        path = r"C:\Windows\Fonts\arialbd.ttf" if bold else r"C:\Windows\Fonts\arial.ttf"
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def night_sky(size_w, size_h):
    """Vertical navy gradient, darker at the top, with a few faint stars."""
    img = Image.new("RGB", (size_w, size_h))
    d = ImageDraw.Draw(img)
    top, bottom = (7, 18, 32), NAVY_2
    for row in range(size_h):
        t = row / size_h
        d.line([(0, row), (size_w, row)],
               fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    # deterministic star field (no randomness so output is stable in git)
    for i in range(90):
        x = (i * 379) % size_w
        y = (i * 227) % int(size_h * 0.55)
        r = 1 + (i % 3)
        alpha = 60 + (i * 37) % 90
        star = Image.new("RGBA", (r * 6, r * 6), (0, 0, 0, 0))
        ImageDraw.Draw(star).ellipse((r * 2, r * 2, r * 4, r * 4),
                                     fill=(255, 255, 255, alpha))
        img.paste(Image.new("RGB", star.size, (255, 255, 255)), (x, y), star)
    return img


def draw_lighthouse(img, cx, base_y, height, beam_left=True, beam_right=True):
    """Gold-striped lighthouse with a glowing lantern and light beams,
    drawn onto `img` with the lantern at (cx, base_y - height)."""
    d = ImageDraw.Draw(img, "RGBA")
    h = height
    top_y = base_y - h
    w_base = h * 0.30
    w_top = h * 0.17

    # beams first so the tower overlaps them
    lantern_y = top_y + h * 0.10
    beam_len = h * 1.5
    spread = h * 0.16
    for direction, on in ((-1, beam_left), (1, beam_right)):
        if not on:
            continue
        x_far = cx + direction * beam_len
        d.polygon([(cx, lantern_y), (x_far, lantern_y - spread), (x_far, lantern_y + spread)],
                  fill=(240, 180, 41, 48))
        d.polygon([(cx, lantern_y),
                   (x_far, lantern_y - spread * 0.45), (x_far, lantern_y + spread * 0.45)],
                  fill=(255, 220, 120, 42))

    # tapered tower with gold/navy stripes
    stripes = 5
    for i in range(stripes):
        t0, t1 = i / stripes, (i + 1) / stripes
        yy0 = top_y + h * 0.18 + (h * 0.82) * t0
        yy1 = top_y + h * 0.18 + (h * 0.82) * t1
        ww0 = w_top + (w_base - w_top) * t0
        ww1 = w_top + (w_base - w_top) * t1
        color = GOLD if i % 2 == 0 else (226, 232, 240)
        d.polygon([(cx - ww0 / 2, yy0), (cx + ww0 / 2, yy0),
                   (cx + ww1 / 2, yy1), (cx - ww1 / 2, yy1)], fill=color)

    # gallery deck + railing
    deck_y = top_y + h * 0.18
    d.rectangle((cx - w_top * 0.85, deck_y - h * 0.015, cx + w_top * 0.85, deck_y + h * 0.015),
                fill=(226, 232, 240))
    # lantern room with glow
    lw = w_top * 0.62
    glow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse((cx - lw * 1.7, lantern_y - lw * 1.7,
                                  cx + lw * 1.7, lantern_y + lw * 1.7),
                                 fill=(255, 214, 100, 90))
    img.paste(glow, (0, 0), glow)
    d.rectangle((cx - lw / 2, lantern_y - h * 0.045, cx + lw / 2, deck_y), fill=(255, 224, 130))
    d.line([(cx, lantern_y - h * 0.04), (cx, deck_y)], fill=NAVY, width=max(2, int(h * 0.008)))
    # dome cap
    d.pieslice((cx - lw * 0.7, lantern_y - h * 0.10, cx + lw * 0.7, lantern_y + h * 0.02),
               180, 360, fill=GOLD)

    # rocks / waves at the base
    d.ellipse((cx - w_base * 1.15, base_y - h * 0.03, cx + w_base * 1.15, base_y + h * 0.05),
              fill=(9, 22, 38))
    for k, (dx, wl) in enumerate(((-1.9, 1.1), (1.4, 0.9), (-0.4, 1.5))):
        y = base_y + h * (0.055 + 0.02 * k)
        x0 = cx + w_base * dx - w_base * wl / 2
        d.arc((x0, y - h * 0.02, x0 + w_base * wl, y + h * 0.02), 200, 340,
              fill=(120, 160, 200, 200), width=max(2, int(h * 0.006)))


def make_logo():
    s = 3
    size = 1024 * s
    img = night_sky(size, size)
    # circle-safe: lighthouse centred, content inside inner ~72%
    draw_lighthouse(img, size / 2, size * 0.80, size * 0.52)
    img.resize((1024, 1024), Image.LANCZOS).save(HERE / "fb-logo.png")


def make_cover():
    s = 3
    W, H = 1640 * s, 624 * s
    img = night_sky(W, H)

    # lighthouse at the right edge of the mobile-safe band, beaming left;
    # text is drawn afterwards and must stay clear of the tower (< 0.70 W)
    lx = W * 0.80
    draw_lighthouse(img, lx, H * 0.86, H * 0.60, beam_left=True, beam_right=False)

    d = ImageDraw.Draw(img)
    # wordmark + copy block, inside the mobile-safe band (center ~68% of width)
    x0 = W * 0.17
    dot_r = 10 * s
    wm_font = font(50 * s)
    d.ellipse((x0, H * 0.28 - dot_r, x0 + dot_r * 2, H * 0.28 + dot_r), fill=GOLD)
    d.text((x0 + dot_r * 3.2, H * 0.28 - 28 * s), "EAST COAST SOCIAL", font=wm_font, fill=GOLD)

    line1 = "Your business posts every day."
    line2 = "You don't lift a finger."
    serif_big = font(60 * s, bold=True, serif=True)
    d.text((x0, H * 0.40), line1, font=serif_big, fill=INK_LIGHT)
    d.text((x0, H * 0.53), line2, font=serif_big, fill=GOLD)

    tag_font = font(32 * s, bold=False)
    d.text((x0, H * 0.72), "Done-for-you social media for local businesses",
           font=tag_font, fill=MUTED)
    d.text((x0, H * 0.80), "findhotstuff.com/automation  ·  Sackville & Memramcook, NB",
           font=tag_font, fill=MUTED)

    img.resize((1640, 624), Image.LANCZOS).save(HERE / "fb-cover.png")


if __name__ == "__main__":
    make_logo()
    make_cover()
    print("wrote fb-logo.png (1024x1024) + fb-cover.png (1640x624)")
