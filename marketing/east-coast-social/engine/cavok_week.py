"""
CAVOK Brewing sample week v2 — seven cards, each with its own visual device,
all in the sky-teal-on-black family. Aviation motifs drawn in PIL.

    python cavok_week.py    (from engine/)
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw

from post_card import _font, _wrap

HERE = Path(__file__).parent
OUT = HERE / "samples" / "cavok-brewing-co"
S = 1080
BG = (11, 18, 22)
TEAL = (143, 230, 225)
DIM = (26, 52, 56)      # muted teal for background motifs
INK = (242, 246, 250)
MONO = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf"


def base(bg=BG):
    img = Image.new("RGB", (S, S), bg)
    return img, ImageDraw.Draw(img)


def header(d, y=64):
    d.ellipse((64, y + 6, 92, y + 34), fill=TEAL)
    d.text((112, y), "CAVOK BREWING CO.", font=_font(40, bold=True), fill=TEAL)


def footer(d, label):
    d.rectangle((0, S - 92, S, S), fill=TEAL)
    d.text((64, S - 72), f"CAVOK Brewing Co. — posted automatically", font=_font(34, bold=True), fill=BG)
    d.text((S - 64 - d.textlength(label, font=_font(28, bold=True)), 64 + 8), label,
           font=_font(28, bold=True), fill=(90, 120, 124))


def message(d, text, y, size=76, fill=INK, accent_words=None, center=False, max_w=S - 128):
    f = _font(size, serif=True)
    lines = _wrap(d, text, f, max_w)
    for i, line in enumerate(lines):
        x = (S - d.textlength(line, font=f)) // 2 if center else 64
        d.text((x, y), line, font=f, fill=fill if i % 2 == 0 else TEAL)
        y += size + 16
    return y


def mono(sz):
    from PIL import ImageFont
    try:
        return ImageFont.truetype(MONO, sz)
    except OSError:
        return _font(sz, bold=True)


# ── Day 1 · Monday — departures board tap list ────────────────────────────
def day1():
    img, d = base()
    header(d)
    d.text((64, 200), "NOW BOARDING · THIS WEEK'S TAPS", font=mono(34), fill=TEAL)
    rows = [("HAZY IPA", "ON TAP"), ("CREAM ALE", "ON TAP"), ("AMBER LAGER", "ON TAP"),
            ("DRY STOUT", "ON TAP"), ("SOUR · RADLER", "LANDING SOON")]
    y = 290
    for name, status in rows:
        d.rectangle((64, y, S - 64, y + 92), fill=(16, 26, 30))
        d.text((96, y + 24), name, font=mono(40), fill=INK)
        col = TEAL if status == "ON TAP" else (240, 180, 41)
        d.text((S - 96 - d.textlength(status, font=mono(34)), y + 28), status, font=mono(34), fill=col)
        y += 112
    d.text((64, y + 24), "gate open 12pm · full list at the bar", font=_font(32), fill=(120, 148, 152))
    footer(d, "MONDAY")
    img.save(OUT / "day-1.png")


# ── Day 2 · Tuesday — giant ? watermark, centered ─────────────────────────
def day2():
    img, d = base()
    d.text((S - 560, 60), "?", font=_font(760, serif=True), fill=DIM)
    header(d)
    message(d, "Trivia night: bring a co-pilot.", 420, size=84, center=True)
    d.text(((S - d.textlength("Tuesdays · 7 PM · taproom", font=_font(36))) // 2, 700),
           "Tuesdays · 7 PM · taproom", font=_font(36), fill=(120, 148, 152))
    footer(d, "TUESDAY")
    img.save(OUT / "day-2.png")


# ── Day 3 · Wednesday — sky gradient, sun + cloud, patio ──────────────────
def day3():
    img = Image.new("RGB", (S, S), BG)
    px = img.load()
    sky_top, sky_bot = (24, 60, 66), BG
    for y in range(S):
        t = min(1.0, y / 640)
        row = tuple(round(a + (b - a) * t) for a, b in zip(sky_top, sky_bot))
        for x in range(S):
            px[x, y] = row
    d = ImageDraw.Draw(img)
    d.ellipse((790, 130, 950, 290), fill=TEAL)                       # sun
    for cx, cy, w in [(220, 220, 260), (420, 150, 200), (640, 260, 230)]:  # clouds
        d.rounded_rectangle((cx, cy, cx + w, cy + 64), radius=32, fill=(34, 66, 72))
    header(d, y=70)
    message(d, "Mid-week forecast: patio cleared for landing.", 560, size=76)
    d.text((64, 850), "sun's out · pints out", font=_font(36), fill=(140, 170, 174))
    footer(d, "WEDNESDAY")
    img.save(OUT / "day-3.png")


# ── Day 4 · Thursday — radar sweep teaser ─────────────────────────────────
def day4():
    img, d = base((8, 13, 16))
    cx, cy = S // 2, 430
    for r in (120, 210, 300):
        d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=DIM, width=3)
    d.pieslice((cx - 300, cy - 300, cx + 300, cy + 300), start=-90, end=-30, fill=(18, 34, 38))
    d.line((cx, cy, cx + 300 * math.cos(math.radians(-30)), cy + 300 * math.sin(math.radians(-30))),
           fill=TEAL, width=4)
    d.ellipse((cx + 88, cy - 152, cx + 112, cy - 128), fill=TEAL)    # the blip
    header(d)
    message(d, "New release on final approach.", 760, size=80, center=True)
    footer(d, "THURSDAY")
    img.save(OUT / "day-4.png")


# ── Day 5 · Friday — runway perspective ───────────────────────────────────
def day5():
    img, d = base()
    d.polygon([(340, 1000), (740, 1000), (620, 560), (460, 560)], fill=(20, 32, 36))
    for t0, t1 in [(0.05, 0.2), (0.35, 0.5), (0.65, 0.8)]:                # centerline dashes
        x0 = 540 - 8 * (1 - t0), 560 + 440 * t0
        d.polygon([(540 - 10 + 6 * t0, 560 + 440 * t0), (540 + 10 - 6 * t0, 560 + 440 * t0),
                   (540 + 14 - 6 * t1, 560 + 440 * t1), (540 - 14 + 6 * t1, 560 + 440 * t1)], fill=TEAL)
    d.line((340, 1000, 460, 560), fill=DIM, width=5)
    d.line((740, 1000, 620, 560), fill=DIM, width=5)
    header(d)
    message(d, "Wheels down. It's Friday.", 260, size=96, center=True)
    d.text(((S - d.textlength("first round's calling", font=_font(38))) // 2, 525),
           "first round's calling", font=_font(38), fill=(120, 148, 152))
    footer(d, "FRIDAY")
    img.save(OUT / "day-5.png")


# ── Day 6 · Saturday — equalizer bars ─────────────────────────────────────
def day6():
    img, d = base()
    heights = [90, 180, 140, 260, 200, 320, 170, 240, 130, 280, 190, 110]
    bw = (S - 128) // len(heights)
    for i, h in enumerate(heights):
        x = 64 + i * bw
        col = TEAL if i % 3 else (74, 150, 146)
        d.rounded_rectangle((x + 8, 980 - h, x + bw - 8, 980), radius=10, fill=col)
    header(d)
    message(d, "Tonight: live music + fresh pours.", 280, size=84)
    d.text((64, 560), "doors 7 PM · no cover", font=_font(36), fill=(120, 148, 152))
    footer(d, "SATURDAY")
    img.save(OUT / "day-6.png")


# ── Day 7 · Sunday — growler + fuel gauge ─────────────────────────────────
def day7():
    img, d = base()
    gx, gy = 790, 560                                                  # growler silhouette
    d.rounded_rectangle((gx - 110, gy - 40, gx + 110, gy + 300), radius=40, fill=(20, 32, 36), outline=TEAL, width=5)
    d.rectangle((gx - 38, gy - 130, gx + 38, gy - 30), fill=(20, 32, 36), outline=TEAL, width=5)
    d.rounded_rectangle((gx - 52, gy - 170, gx + 52, gy - 120), radius=14, fill=TEAL)
    d.arc((gx - 80, gy + 40, gx + 80, gy + 200), start=150, end=390, fill=DIM, width=10)   # gauge
    d.arc((gx - 80, gy + 40, gx + 80, gy + 200), start=150, end=330, fill=TEAL, width=10)
    d.text((gx - 34, gy + 100), "FUEL", font=mono(30), fill=TEAL)
    header(d)
    message(d, "Sunday growler fills, before the week takes off.", 280, size=78, max_w=560)
    footer(d, "SUNDAY")
    img.save(OUT / "day-7.png")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for fn in (day1, day2, day3, day4, day5, day6, day7):
        fn()
        print("rendered", fn.__name__)
