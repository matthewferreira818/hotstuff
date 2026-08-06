"""
Format-variety gallery for the automation page — six sample posts, each a
DIFFERENT format (photo, promo, review, event, list, behind-the-scenes) for a
different fictional local business. Answers the "will my feed look like one
robot template?" objection with pictures.

    python marketing/east-coast-social/make_format_gallery.py
Writes 720x720 PNGs to automation/samples/fmt-*.png
"""

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE / "engine"))
from post_card import _font, _wrap  # noqa: E402

S = 1080
OUT = HERE.parent.parent / "automation" / "samples"


def base(bg):
    img = Image.new("RGB", (S, S), bg)
    return img, ImageDraw.Draw(img)


def header(d, name, accent, y=56):
    d.ellipse((60, y + 6, 86, y + 32), fill=accent)
    d.text((104, y), name.upper(), font=_font(38, bold=True), fill=accent)


def footer(d, name, accent, bg):
    d.rectangle((0, S - 84, S, S), fill=accent)
    d.text((60, S - 66), f"{name} — posted automatically", font=_font(30, bold=True), fill=bg)


def star(d, cx, cy, r, fill):
    pts = []
    for i in range(10):
        ang = -math.pi / 2 + i * math.pi / 5
        rad = r if i % 2 == 0 else r * 0.42
        pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    d.polygon(pts, fill=fill)


def save(img, name):
    OUT.mkdir(parents=True, exist_ok=True)
    img.resize((720, 720)).save(OUT / name, optimize=True)
    print("rendered", name)


# 1 · PHOTO POST — The Harbour Café (warm amber) ─ drawn latte "photo"
def fmt_photo():
    BG, ACC, INK = (26, 19, 13), "#f59e0b", (244, 238, 230)
    img, d = base(BG)
    header(d, "The Harbour Café", ACC)
    # photo panel
    d.rounded_rectangle((60, 140, S - 60, 700), radius=28, fill=(38, 28, 20))
    cx, cy = S // 2, 420
    d.ellipse((cx - 190, cy - 190, cx + 190, cy + 190), fill=(232, 225, 214))   # saucer
    d.ellipse((cx - 160, cy - 160, cx + 160, cy + 160), fill=(84, 52, 30))      # coffee
    d.ellipse((cx - 130, cy - 130, cx + 130, cy + 130), fill=(214, 182, 148))   # crema
    for k in range(4):                                                          # rosetta leaves
        w = 90 - k * 18
        d.ellipse((cx - w, cy - 120 + k * 62, cx + w, cy - 40 + k * 62), outline=(120, 78, 44), width=10)
    d.text((60, 740), "Fresh pour, fresh cinnamon rolls —", font=_font(46, serif=True), fill=INK)
    d.text((60, 800), "warm till they're gone.", font=_font(46, serif=True), fill="#f59e0b")
    d.text((60, 880), "open till 5 · Water St.", font=_font(30), fill=(150, 132, 112))
    footer(d, "The Harbour Café", ACC, "#1a130d")
    save(img, "fmt-photo.png")


# 2 · PROMO — Rossi's Pizzeria (red) ─ starburst deal card
def fmt_promo():
    BG, ACC, INK = (22, 13, 13), "#e05252", (246, 238, 232)
    img, d = base(BG)
    header(d, "Rossi's Pizzeria", ACC)
    cx, cy = S // 2, 470
    pts = []
    for i in range(24):                                                          # starburst
        ang = i * math.pi / 12
        rad = 330 if i % 2 == 0 else 280
        pts.append((cx + rad * math.cos(ang), cy + rad * math.sin(ang)))
    d.polygon(pts, fill=(46, 22, 22), outline=ACC)
    d.text((cx - d.textlength("FRIDAY ONLY", font=_font(40, bold=True)) / 2, cy - 190),
           "FRIDAY ONLY", font=_font(40, bold=True), fill=ACC)
    big = _font(120, serif=True)
    d.text((cx - d.textlength("2 for $24.99", font=big) / 2, cy - 120), "2 for $24.99", font=big, fill=INK)
    d.text((cx - d.textlength("any two large pizzas", font=_font(44)) / 2, cy + 40),
           "any two large pizzas", font=_font(44), fill=(214, 186, 176))
    d.text((cx - d.textlength("call ahead · (506) 555-0134", font=_font(32)) / 2, cy + 130),
           "call ahead · (506) 555-0134", font=_font(32), fill=(160, 130, 122))
    footer(d, "Rossi's Pizzeria", ACC, "#160d0d")
    save(img, "fmt-promo.png")


# 3 · REVIEW — Main Street Barber Co. (gold on charcoal) ─ stars + quote
def fmt_review():
    BG, ACC, INK = (16, 20, 24), "#c9a227", (242, 246, 250)
    img, d = base(BG)
    header(d, "Main Street Barber Co.", ACC)
    for i in range(5):
        star(d, 120 + i * 96, 240, 40, ACC)
    y = 340
    for i, line in enumerate(['"Best fade in town.', 'Hands down. Worth', 'the drive from Moncton."']):
        d.text((60, y), line, font=_font(72, serif=True), fill=INK if i % 2 == 0 else ACC)
        y += 92
    d.text((60, y + 40), "— Julie R. · ★★★★★ Google review", font=_font(34), fill=(150, 158, 168))
    d.text((60, y + 110), "walk-ins welcome till 6", font=_font(30), fill=(110, 118, 128))
    footer(d, "Main Street Barber Co.", ACC, "#101418")
    save(img, "fmt-review.png")


# 4 · EVENT — Bayside Pub (green) ─ date block + event billing
def fmt_event():
    BG, ACC, INK = (15, 26, 20), "#7fb069", (240, 246, 240)
    img, d = base(BG)
    header(d, "Bayside Pub", ACC)
    d.rounded_rectangle((60, 180, 320, 440), radius=24, fill=(26, 44, 34), outline=ACC, width=4)
    d.text((115, 215), "THU", font=_font(56, bold=True), fill=ACC)
    d.text((122, 285), "12", font=_font(110, serif=True), fill=INK)
    y = 200
    for i, line in enumerate(["Trivia", "Night."]):
        d.text((380, y), line, font=_font(120, serif=True), fill=INK if i == 0 else ACC)
        y += 140
    d.text((380, y + 20), "7 PM · teams of 4 · prizes", font=_font(38), fill=(170, 190, 172))
    d.text((60, 560), "Free popcorn while the questions last — book your table before Wednesday.",
           font=_font(34), fill=(150, 170, 152))
    d.rounded_rectangle((60, 680, 480, 760), radius=999, fill=ACC)
    d.text((100, 700), "Reserve a table →", font=_font(36, bold=True), fill="#0f1a14")
    footer(d, "Bayside Pub", ACC, "#0f1a14")
    save(img, "fmt-event.png")


# 5 · LIST — Duval's Garage (slate blue) ─ checklist rows
def fmt_list():
    BG, ACC, INK = (16, 22, 35), "#6ea8d8", (240, 244, 250)
    img, d = base(BG)
    header(d, "Duval's Garage", ACC)
    d.text((60, 160), "WINTER-READY CHECKLIST", font=_font(44, bold=True), fill=ACC)
    rows = [("Tires swapped + stored", True), ("Brakes inspected", True),
            ("Battery load-tested", True), ("Wipers + washer fluid", True)]
    y = 260
    for label, _ in rows:
        d.rounded_rectangle((60, y, S - 60, y + 100), radius=16, fill=(24, 32, 48))
        d.ellipse((92, y + 28, 136, y + 72), outline=ACC, width=5)
        d.line((100, y + 50, 112, y + 64), fill=ACC, width=6)
        d.line((112, y + 64, 132, y + 36), fill=ACC, width=6)
        d.text((170, y + 26), label, font=_font(40), fill=INK)
        y += 124
    d.text((60, y + 20), "One visit, all four. Booking this week + next.", font=_font(34), fill=(150, 168, 190))
    footer(d, "Duval's Garage", ACC, "#101623")
    save(img, "fmt-list.png")


# 6 · BEHIND THE SCENES — Stitch & Timber (wood tones) ─ maker quote
def fmt_bts():
    BG, ACC, INK = (20, 17, 13), "#c9a97a", (243, 238, 230)
    img, d = base(BG)
    for k in range(5):                                                            # wood-grain arcs
        r = 220 + k * 90
        d.arc((S - 420 - r, 620 - r, S - 420 + r, 620 + r), start=300, end=420,
              fill=(46, 38, 28), width=14)
    header(d, "Stitch & Timber", ACC)
    y = 240
    lines = ["Every table we sell", "started as a tree", "we picked ourselves."]
    for i, line in enumerate(lines):
        d.text((60, y), line, font=_font(76, serif=True), fill=INK if i % 2 == 0 else ACC)
        y += 100
    d.text((60, y + 40), "— Danny, somewhere in the sawdust", font=_font(34), fill=(160, 146, 124))
    d.text((60, y + 110), "shop tours Saturdays · come say hi", font=_font(30), fill=(120, 108, 90))
    footer(d, "Stitch & Timber", ACC, "#14110d")
    save(img, "fmt-bts.png")


if __name__ == "__main__":
    for fn in (fmt_photo, fmt_promo, fmt_review, fmt_event, fmt_list, fmt_bts):
        fn()
