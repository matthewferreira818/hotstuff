"""
CAVOK Brewing sample week v3 — seven cards, each with its own visual device,
now loaded with REAL CAVOK facts pulled from cavokbrewing.ca:

  - Real beers: Runway 11 (lager), Squeezed (NEIPA), East Coast Pirates
    (WCIPA), Leger Corner (honey blonde), Baie Sur L'Amer (raspberry sour)
  - Real amenities: 20+ taps, growler fills, golf simulator, sports TVs,
    pizza/pretzels, Aboiteau Beach spot, taproom seats 100+
  - Real hours: Sun-Tue 12-10pm, Wed-Sat 12pm-midnight

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
    d.text((64, S - 72), "CAVOK Brewing Co. — posted automatically", font=_font(34, bold=True), fill=BG)
    d.text((S - 64 - d.textlength(label, font=_font(28, bold=True)), 64 + 8), label,
           font=_font(28, bold=True), fill=(90, 120, 124))


def message(d, text, y, size=76, fill=INK, center=False, max_w=S - 128):
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


# ── Day 1 · Monday — departures board with their REAL beers ───────────────
def day1():
    img, d = base()
    header(d)
    d.text((64, 200), "NOW BOARDING · ON TAP", font=mono(34), fill=TEAL)
    rows = [("RUNWAY 11 · LAGER", "ON TAP"), ("SQUEEZED · NEIPA", "ON TAP"),
            ("EAST COAST PIRATES", "ON TAP"), ("LEGER CORNER · BLONDE", "ON TAP"),
            ("BAIE SUR L'AMER · SOUR", "LANDING SOON")]
    y = 290
    for name, status in rows:
        d.rectangle((64, y, S - 64, y + 92), fill=(16, 26, 30))
        d.text((96, y + 24), name, font=mono(38), fill=INK)
        col = TEAL if status == "ON TAP" else (240, 180, 41)
        d.text((S - 96 - d.textlength(status, font=mono(32)), y + 30), status, font=mono(32), fill=col)
        y += 112
    d.text((64, y + 24), "20+ taps in the taproom · full board on Instagram", font=_font(32), fill=(120, 148, 152))
    footer(d, "MONDAY")
    img.save(OUT / "day-1.png")


# ── Day 2 · Tuesday — golf simulator (they really have one) ───────────────
def day2():
    img, d = base()
    d.ellipse((560, 760, 1040, 920), fill=(18, 34, 30))            # the green
    d.ellipse((830, 828, 866, 852), fill=(8, 13, 16))              # the hole
    d.line((848, 500, 848, 838), fill=INK, width=8)                # pole
    d.polygon([(848, 500), (848, 570), (740, 535)], fill=TEAL)     # flag
    header(d)
    message(d, "Rainy day? Tee off inside.", 300, size=88)
    d.text((64, 600), "golf simulator · cold pints · book your slot", font=_font(36), fill=(120, 148, 152))
    footer(d, "TUESDAY")
    img.save(OUT / "day-2.png")


# ── Day 3 · Wednesday — beach forecast (Aboiteau Beach spot) ──────────────
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
    message(d, "Beach forecast: CAVOK.", 560, size=84)
    d.text((64, 700), "find us at Aboiteau Beach all summer", font=_font(36), fill=(140, 170, 174))
    footer(d, "WEDNESDAY")
    img.save(OUT / "day-3.png")


# ── Day 4 · Thursday — radar sweep teaser (seasonals rotate) ──────────────
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
    message(d, "Next seasonal on final approach.", 760, size=78, center=True)
    footer(d, "THURSDAY")
    img.save(OUT / "day-4.png")


# ── Day 5 · Friday — the runway, starring Runway 11 ───────────────────────
def day5():
    img, d = base()
    d.polygon([(340, 1000), (740, 1000), (620, 560), (460, 560)], fill=(20, 32, 36))
    for t0, t1 in [(0.05, 0.2), (0.35, 0.5), (0.65, 0.8)]:                # centerline dashes
        d.polygon([(540 - 10 + 6 * t0, 560 + 440 * t0), (540 + 10 - 6 * t0, 560 + 440 * t0),
                   (540 + 14 - 6 * t1, 560 + 440 * t1), (540 - 14 + 6 * t1, 560 + 440 * t1)], fill=TEAL)
    d.line((340, 1000, 460, 560), fill=DIM, width=5)
    d.line((740, 1000, 620, 560), fill=DIM, width=5)
    header(d)
    message(d, "Wheels down. It's Friday.", 260, size=96, center=True)
    sub = "Runway 11 is pouring — cleared to land"
    d.text(((S - d.textlength(sub, font=_font(38))) // 2, 525), sub, font=_font(38), fill=(120, 148, 152))
    footer(d, "FRIDAY")
    img.save(OUT / "day-5.png")


# ── Day 6 · Saturday — pick your flight (20+ taps, big screens) ───────────
def day6():
    img, d = base()
    heights = [90, 180, 140, 260, 200, 320, 170, 240, 130, 280, 190, 110]
    bw = (S - 128) // len(heights)
    for i, h in enumerate(heights):
        x = 64 + i * bw
        col = TEAL if i % 3 else (74, 150, 146)
        d.rounded_rectangle((x + 8, 980 - h, x + bw - 8, 980), radius=10, fill=col)
    header(d)
    message(d, "Saturday: 20+ taps. Pick your flight.", 280, size=80)
    d.text((64, 600), "pizza · pretzels · the game on the big screens", font=_font(36), fill=(120, 148, 152))
    footer(d, "SATURDAY")
    img.save(OUT / "day-6.png")


# ── Day 7 · Sunday — growler + fuel gauge (they do fills) ─────────────────
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
    d.text((64, 800), "open till 10 tonight", font=_font(36), fill=(120, 148, 152))
    footer(d, "SUNDAY")
    img.save(OUT / "day-7.png")


CAPTIONS = [
    ("Monday", "Fresh week, fresh board. Runway 11, Squeezed, East Coast Pirates and Leger Corner all pouring — and something sour on final approach. 20+ taps waiting. 🍺✈️ Full board: 'On Tap Today' on our Instagram."),
    ("Tuesday", "Rain in the forecast? Perfect golf weather — inside. Book the simulator room, order a pint, settle your foursome's arguments on the big screen. ⛳"),
    ("Wednesday", "Ceiling and visibility OK at Aboiteau Beach — find us there all summer, or in the taproom till midnight starting tonight. ☀️🏖️"),
    ("Thursday", "Something seasonal is conditioning in the tanks... on final approach for the weekend. Guesses in the comments. 👀🛬"),
    ("Friday", "Clock out, taxi in. Runway 11 on the tarmac, 20+ taps up, open till midnight. Wheels down, my friends. 🍻"),
    ("Saturday", "Saturday in the taproom: 20+ craft taps, pizza and pretzels, the game on the TVs, seats for 100 of your closest friends. Doors at noon. 🎉"),
    ("Sunday", "Take the taproom home — growler fills all afternoon, open till 10. Fuel up for the week ahead. 🛫"),
]


def write_captions():
    caps = ["# CAVOK Brewing — free sample week (engine mockups, v3)",
            "",
            "_7 daily posts in CAVOK's branding — sky-teal on black, aviation voice,_",
            "_built from their real lineup: Runway 11, Squeezed, East Coast Pirates,_",
            "_Leger Corner, Baie Sur L'Amer · golf sim · Aboiteau Beach · real hours._",
            "_Tap lineup is illustrative — swap to the live board at setup._", ""]
    for i, (day, caption) in enumerate(CAPTIONS, 1):
        caps += [f"## Day {i} — {day} (day-{i}.png)", f"**Caption:** {caption}", ""]
    (OUT / "captions.md").write_text("\n".join(caps), encoding="utf-8")


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    for fn in (day1, day2, day3, day4, day5, day6, day7):
        fn()
        print("rendered", fn.__name__)
    write_captions()
    print("captions.md written")
