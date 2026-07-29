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


def draw_sunrise(img, cx, horizon_y, radius, ray_count=9, reflection=True):
    """Half-risen gold sun on the horizon line at (cx, horizon_y), with a fan
    of rays above and a shimmering reflection in the water below."""
    d = ImageDraw.Draw(img, "RGBA")
    r = radius

    # rays: tapered spokes fanning over the top half, gaps left for air
    for i in range(ray_count):
        ang = math.pi * (i + 0.5) / ray_count  # 0..pi, sunrise fan
        r0, r1 = r * 1.35, r * (2.1 if i % 2 == 0 else 1.75)
        wa = math.pi / ray_count * 0.30       # angular half-width of a ray
        pts = []
        for a in (ang - wa, ang + wa):
            pts.append((cx + math.cos(a) * r0, horizon_y - math.sin(a) * r0))
        for a in (ang + wa * 0.5, ang - wa * 0.5):
            pts.append((cx + math.cos(a) * r1, horizon_y - math.sin(a) * r1))
        d.polygon(pts, fill=(240, 180, 41, 210))

    # the half-sun, two-tone for depth
    d.pieslice((cx - r, horizon_y - r, cx + r, horizon_y + r), 180, 360, fill=GOLD)
    d.pieslice((cx - r * 0.72, horizon_y - r * 0.72, cx + r * 0.72, horizon_y + r * 0.72),
               180, 360, fill=(255, 214, 110))

    # horizon line
    d.line([(cx - r * 2.4, horizon_y), (cx + r * 2.4, horizon_y)],
           fill=(120, 160, 200, 130), width=max(2, int(r * 0.03)))

    # water: wave arcs + a broken gold reflection path under the sun
    for k, (dx, wl) in enumerate(((-1.5, 1.0), (1.2, 0.8), (-0.3, 1.3))):
        y = horizon_y + r * (0.42 + 0.30 * k)
        x0 = cx + r * dx - r * wl / 2
        d.arc((x0, y - r * 0.10, x0 + r * wl, y + r * 0.10), 200, 340,
              fill=(120, 160, 200, 200), width=max(2, int(r * 0.035)))
    if reflection:
        for k in range(4):
            y = horizon_y + r * (0.16 + 0.24 * k)
            w = r * (0.85 - 0.17 * k)
            d.rounded_rectangle((cx - w / 2, y, cx + w / 2, y + r * 0.075),
                                radius=r * 0.04, fill=(240, 180, 41, 170 - 30 * k))


def make_logo():
    s = 3
    size = 1024 * s
    img = night_sky(size, size)
    # circle-safe: sun on a horizon just below centre, rays inside inner ~72%
    draw_sunrise(img, size / 2, size * 0.58, size * 0.175)
    img.resize((1024, 1024), Image.LANCZOS).save(HERE / "fb-logo.png")


def make_cover():
    s = 3
    W, H = 1640 * s, 624 * s
    img = night_sky(W, H)

    # sunrise at the right edge of the mobile-safe band; text is drawn
    # afterwards and must stay clear of the sun + rays (< 0.67 W)
    draw_sunrise(img, W * 0.85, H * 0.55, H * 0.19)

    d = ImageDraw.Draw(img)
    # wordmark + copy block, inside the mobile-safe band (center ~68% of width)
    x0 = W * 0.17
    dot_r = 10 * s
    wm_font = font(50 * s)
    d.ellipse((x0, H * 0.28 - dot_r, x0 + dot_r * 2, H * 0.28 + dot_r), fill=GOLD)
    d.text((x0 + dot_r * 3.2, H * 0.28 - 28 * s), "EAST COAST SOCIAL", font=wm_font, fill=GOLD)

    line1 = "Your business posts every day."
    line2 = "You don't lift a finger."
    serif_big = font(54 * s, bold=True, serif=True)
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
