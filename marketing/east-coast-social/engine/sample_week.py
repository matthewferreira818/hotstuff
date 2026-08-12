"""
Per-prospect sample week: seven branded post mockups + captions for ANY local
business, so a pitch opens with "here's your feed, already built" instead of a
description of one. Free work is East Coast Social's best-converting ad — this
makes it a five-minute job per prospect instead of an afternoon.

Two steps:

    # 1. start a profile, then fill in real facts from their page (5 min)
    python sample_week.py --new "Boulangerie Leger" --town "Shediac, NB" \
        --category bakery

    # 2. render the pack
    python sample_week.py samples/boulangerie-leger/profile.json

Writes day-1..7.png, captions.md and contact-sheet.png (the one page to print
and hand across the counter) into samples/<slug>/.

The seven cards each use a DIFFERENT visual device — a lineup board, a
statement, an hours grid, a spotlight, a quote, a stat, a teaser — because the
objection this pack answers is "will my feed look like one robot template?".
Filling in `items`, `hours` and `facts` is what makes an owner say "they
actually looked at us"; a profile left on defaults renders, but it pitches
like a stranger. Nothing here invents a testimonial: the quote card only
appears when the profile carries a real one, otherwise that slot renders an
invitation instead.
"""

import argparse
import json
import math
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

from post_card import _font, _wrap

HERE = Path(__file__).parent
SAMPLES = HERE / "samples"
S = 1080          # post cards are square, like the platforms want
DAYS = ["Monday", "Tuesday", "Wednesday", "Thursday",
        "Friday", "Saturday", "Sunday"]

# Category palettes — a starting point that already looks like the business,
# so a profile renders well before anyone picks colors. Override per prospect
# with "bg"/"accent" once you've seen their signage.
PALETTES = {
    "cafe":       ("#2a1a12", "#e0a458"),
    "bakery":     ("#2b1c11", "#e8a33d"),
    "restaurant": ("#1a1614", "#d97757"),
    "brewery":    ("#0b1216", "#8fe6e1"),
    "barber":     ("#14161c", "#c9a227"),
    "salon":      ("#1d1420", "#e5a0c4"),
    "fitness":    ("#101418", "#7ee081"),
    "retail":     ("#161824", "#8fa2e6"),
    "trades":     ("#171a14", "#e6c34a"),
    "*":          ("#141821", "#f0b429"),
}

# Per-category wording so the copy doesn't read like a form letter. Each entry:
# what they sell, the daily-lineup word, and a Friday-ish line.
VOICE = {
    "cafe":       ("on the menu today", "TODAY'S MENU", "Pull up a chair."),
    "bakery":     ("out of the oven", "FRESH TODAY", "Still warm."),
    "restaurant": ("on the menu tonight", "TONIGHT'S MENU", "Table's ready."),
    "brewery":    ("pouring today", "ON TAP", "Doors are open."),
    "barber":     ("in the chair", "THE SERVICES", "Walk-ins welcome."),
    "salon":      ("in the studio", "THE SERVICES", "Book your chair."),
    "fitness":    ("on the schedule", "THIS WEEK", "Doors are open."),
    "retail":     ("in the shop", "IN STORE NOW", "Come have a look."),
    "trades":     ("on the truck", "WHAT WE DO", "Booking this week."),
    "*":          ("today", "TODAY", "We're open."),
}


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def mix(a, b, t):
    """Blend two RGB colors — used for muted motifs drawn behind the copy."""
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def slugify(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def ref_tag(slug):
    """Per-prospect attribution tag. The site's ref regex caps tags at 24
    chars; 'sample-' takes 7, so the slug part gets 17."""
    return "sample-" + slug[:17].strip("-")


def tracked_link(slug):
    return f"findhotstuff.com/automation/?ref={ref_tag(slug)}"


def register_slug(slug):
    """Keep samples/registry.json current so traffic_report.py can report
    ref-sample-<slug> scans by name. A scan = the hottest signal we have."""
    reg = SAMPLES / "registry.json"
    try:
        slugs = set(json.loads(reg.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        slugs = set()
    slugs.add(slug[:17].strip("-"))
    SAMPLES.mkdir(parents=True, exist_ok=True)
    reg.write_text(json.dumps(sorted(slugs), indent=1), encoding="utf-8")


def voice(profile):
    return VOICE.get(profile.get("category", "*"), VOICE["*"])


def fit(d, text, max_w, size, bold=True, floor=20):
    """Shrink, then ellipsize, until text fits max_w. Returns (text, font).

    Prospect names and menu items are whatever the owner calls them —
    "Marc-André's Family Restaurant & Catering Company" has to sit next to a
    day label without running through it.
    """
    f = _font(size, bold=bold)
    while d.textlength(text, font=f) > max_w and f.size > floor:
        f = _font(f.size - 2, bold=bold)
    while d.textlength(text, font=f) > max_w and len(text) > 4:
        text = text[:-2].rstrip() + "…"
    return text, f


# ── per-category style kits ──────────────────────────────────────────────
# The palette says "your colors"; the kit says "your kind of place". Texture,
# header and footer change per category so two packs side by side read as two
# different designers, not one template repainted. (Same lesson as the CAVOK
# week: individuality is what makes an owner say "that's US".)

def _tex_flour(card):
    """Bakery: soft flour-dust speckle drifting from the top corners."""
    import random
    rnd = random.Random(card.p.get("slug", "seed"))
    for _ in range(140):
        x = rnd.randint(0, S)
        y = int(abs(rnd.gauss(0, S * 0.22)))
        if rnd.random() < 0.5:
            x = S - x
        r = rnd.choice((2, 2, 3, 4))
        card.d.ellipse((x - r, y - r, x + r, y + r), fill=card.dim)


def _tex_checker(card):
    """Restaurant: gingham strips along the top and bottom edges."""
    sq = 36
    for row, y0 in ((0, 118), (1, 154)):
        for i, x in enumerate(range(0, S, sq)):
            if (i + row) % 2 == 0:
                card.d.rectangle((x, y0, x + sq, y0 + 36), fill=card.dim)


def _tex_bubbles(card):
    """Brewery/café: sparse rising bubbles up the right side."""
    import random
    rnd = random.Random(card.p.get("slug", "seed"))
    for _ in range(16):
        x = rnd.randint(int(S * 0.72), S - 30)
        y = rnd.randint(200, S - 160)
        r = rnd.choice((6, 9, 12, 16))
        card.d.ellipse((x - r, y - r, x + r, y + r), outline=card.dim, width=3)


def _tex_pinstripe(card):
    """Barber: thin vertical pinstripes down the left margin."""
    for x in (28, 40, 52):
        card.d.line((x, 130, x, S - 130), fill=card.dim, width=3)


def _tex_petals(card):
    """Salon: soft overlapping discs in the top-right corner."""
    for cx, cy, r in ((S - 60, 90, 90), (S - 150, 40, 60), (S - 30, 190, 55)):
        card.d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=card.dim, width=4)


def _tex_diag(card):
    """Trades/fitness: bold diagonal strokes cutting the bottom-left corner."""
    for i in range(4):
        off = i * 46
        card.d.line((0, S - 220 + off, 220 - off, S), fill=card.dim, width=10)


def _tex_grid(card):
    """Retail: fine dot grid in the top-left quarter."""
    for yy in range(150, 440, 46):
        for xx in range(40, 460, 46):
            card.d.ellipse((xx - 3, yy - 3, xx + 3, yy + 3), fill=card.dim)


STYLES = {
    "bakery":     {"texture": _tex_flour,     "header": "warm",  "footer": "scallop", "family": "artisan"},
    "cafe":       {"texture": _tex_bubbles,   "header": "warm",  "footer": "band", "family": "artisan"},
    "restaurant": {"texture": _tex_checker,   "header": "menu",  "footer": "band", "family": "diner"},
    "brewery":    {"texture": _tex_bubbles,   "header": "dot",   "footer": "band", "family": "diner"},
    "barber":     {"texture": _tex_pinstripe, "header": "sharp", "footer": "lines"},
    "salon":      {"texture": _tex_petals,    "header": "warm",  "footer": "lines", "family": "artisan"},
    "fitness":    {"texture": _tex_diag,      "header": "sharp", "footer": "band"},
    "retail":     {"texture": _tex_grid,      "header": "dot",   "footer": "band"},
    "trades":     {"texture": _tex_diag,      "header": "sharp", "footer": "band"},
    "*":          {"texture": None,           "header": "dot",   "footer": "band"},
}


def style_of(profile):
    return STYLES.get(profile.get("category", "*"), STYLES["*"])


class Card:
    """One 1080x1080 post in the prospect's colors.

    Every device draws its own middle; the header band and footer strip stay
    constant so the seven read as one brand rather than seven experiments.
    """

    def __init__(self, profile):
        self.p = profile
        self.bg = rgb(profile["bg"])
        self.accent = rgb(profile["accent"])
        self.ink = rgb(profile.get("ink", "#f4f6fa"))
        self.dim = mix(self.bg, self.accent, 0.22)     # motif color
        self.muted = mix(self.bg, self.ink, 0.45)      # small print
        self.img = Image.new("RGB", (S, S), self.bg)
        self.d = ImageDraw.Draw(self.img)
        self.style = style_of(profile)
        if self.style["texture"]:
            self.style["texture"](self)

    def header(self, day_label):
        """Brand band, in the pack's style. Same height in every variant so
        the seven devices never have to care which one is active.

        The label is measured first so a long business name gets whatever
        width is genuinely left, instead of running underneath it.
        """
        d = self.d
        lf = _font(26, bold=True)
        label = day_label.upper()
        label_w = d.textlength(label, font=lf)
        variant = self.style["header"]

        if variant == "warm":
            # centered name between short accent rules; day tucked right
            name, f = fit(d, self.p["name"].upper(), S - 420, 40)
            nw = d.textlength(name, font=f)
            x = (S - nw) // 2
            d.text((x, 64), name, font=f, fill=self.accent)
            d.line((max(30, x - 90), 88, x - 26, 88), fill=self.accent, width=4)
            # right rule must stop short of the day label, never run into it
            rule_end = min(x + nw + 90, S - 84 - label_w)
            if rule_end > x + nw + 26:
                d.line((x + nw + 26, 88, rule_end, 88), fill=self.accent, width=4)
            d.text((S - 64 - label_w, 72), label, font=lf, fill=self.muted)
        elif variant == "menu":
            # menu-card look: name left, double rule underneath, boxed day
            name, f = fit(d, self.p["name"].upper(), S - 128 - label_w - 90, 40)
            d.text((64, 58), name, font=f, fill=self.accent)
            d.line((64, 112, S - 64, 112), fill=self.accent, width=3)
            d.line((64, 120, S - 64, 120), fill=self.dim, width=2)
            d.rectangle((S - 84 - label_w, 62, S - 48, 100), outline=self.accent, width=2)
            d.text((S - 66 - label_w, 72), label, font=lf, fill=self.muted)
        elif variant == "sharp":
            # heavy accent slab behind the day; name flush left, no dot
            d.rectangle((S - 96 - label_w, 58, S, 104), fill=self.accent)
            d.text((S - 64 - label_w, 72), label, font=lf, fill=self.bg)
            name, f = fit(d, self.p["name"].upper(), S - 128 - label_w - 110, 40)
            d.text((64, 64), name, font=f, fill=self.accent)
        else:
            # classic: accent dot + name left, day right
            d.text((S - 64 - label_w, 72), label, font=lf, fill=self.muted)
            d.ellipse((64, 70, 92, 98), fill=self.accent)
            name, f = fit(d, self.p["name"].upper(), S - 112 - label_w - 100, 40)
            d.text((112, 64), name, font=f, fill=self.accent)

    def footer(self):
        d = self.d
        variant = self.style["footer"]
        town = self.p.get("town", "")
        tf = _font(28, bold=True)
        tw = d.textlength(town, font=tf) if town else 0

        if variant == "lines":
            # elegant: no band, twin rules with copy in the pack colors
            d.line((64, S - 96, S - 64, S - 96), fill=self.accent, width=3)
            d.line((64, S - 88, S - 64, S - 88), fill=self.dim, width=2)
            if town:
                d.text((S - 64 - tw, S - 64), town, font=tf, fill=self.muted)
            left, f = fit(d, f"{self.p['name']} — posted automatically",
                          S - 128 - tw - 40, 32)
            d.text((64, S - 68), left, font=f, fill=self.accent)
            return

        if variant == "scallop":
            r = 22
            for cx in range(0, S + r, r * 2):
                d.ellipse((cx - r, S - 92 - r, cx + r, S - 92 + r), fill=self.accent)
        d.rectangle((0, S - 92, S, S), fill=self.accent)
        if town:
            d.text((S - 64 - tw, S - 64), town,
                   font=tf, fill=mix(self.accent, self.bg, 0.45))
        left, f = fit(d, f"{self.p['name']} — posted automatically",
                      S - 128 - tw - 40, 32)
        d.text((64, S - 68), left, font=f, fill=self.bg)

    def message(self, text, y, size=78, center=False, max_w=S - 128, fill=None,
                max_lines=4):
        d = self.d
        f = _font(size, serif=True)
        lines = _wrap(d, text, f, max_w)
        while len(lines) > max_lines and size > 40:    # never let copy overrun
            size -= 8
            f = _font(size, serif=True)
            lines = _wrap(d, text, f, max_w)
        for i, line in enumerate(lines):
            x = (S - d.textlength(line, font=f)) // 2 if center else 64
            colour = fill or (self.ink if i % 2 == 0 else self.accent)
            d.text((x, y), line, font=f, fill=colour)
            y += size + 14
        return y

    def small(self, text, y, x=64, size=34, fill=None, center=False):
        f = _font(size)
        if center:
            x = (S - self.d.textlength(text, font=f)) // 2
        self.d.text((x, y), text, font=f, fill=fill or self.muted)
        return y + size + 12

    def save(self, path):
        self.img.save(path)


# ── the seven devices ─────────────────────────────────────────────────────
# Each takes the profile and returns a Card. They deliberately differ in
# layout, not just wording — a feed of seven near-identical cards is the thing
# a prospect is afraid of.

def card_lineup(p):
    """What they sell — composed differently per family so two packs never
    share a skeleton: chalkboard (artisan), menu panel with dotted leaders
    (diner), or boxed rows (default)."""
    c = Card(p)
    fam = c.style.get("family", "default")
    c.header("Monday")
    _, board, _ = voice(p)
    items = (p.get("items") or ["Add their real items to profile.json"])[:5]

    if fam == "artisan":
        # chalkboard: everything centered, serif, ornaments between lines
        bf = _font(40, bold=True)
        c.d.text(((S - c.d.textlength(board, font=bf)) // 2, 200), board,
                 font=bf, fill=c.accent)
        y = 300 + max(0, (560 - len(items) * 108) // 2)
        for i, item in enumerate(items):
            label, f = fit(c.d, item, S - 260, 54 if i == 0 else 44)
            f = _font(f.size, serif=True)
            c.d.text(((S - c.d.textlength(label, font=f)) // 2, y), label,
                     font=f, fill=c.ink if i else c.accent)
            y += f.size + 20
            if i < len(items) - 1:
                c.d.ellipse((S // 2 - 5, y + 2, S // 2 + 5, y + 12), fill=c.dim)
                y += 34
        extra = (p.get("facts") or [""])[0]
        if extra:
            c.small(extra, min(y + 30, 880), center=True)
    elif fam == "diner":
        # menu card: inset panel, double border, dotted leader to the tag
        c.d.rounded_rectangle((56, 196, S - 56, 900), radius=18,
                              fill=mix(c.bg, c.ink, 0.05))
        c.d.rounded_rectangle((72, 212, S - 72, 884), radius=12,
                              outline=c.dim, width=3)
        bf = _font(34, bold=True)
        c.d.text(((S - c.d.textlength(board, font=bf)) // 2, 244), board,
                 font=bf, fill=c.accent)
        y = 330 + max(0, (480 - len(items) * 96) // 2)
        for i, item in enumerate(items):
            tag = "TODAY" if i < 3 else "FRESH"
            tf = _font(26, bold=True)
            tag_w = c.d.textlength(tag, font=tf)
            label, f = fit(c.d, item.upper(), S - 320 - tag_w, 36)
            lw = c.d.textlength(label, font=f)
            c.d.text((120, y), label, font=f, fill=c.ink)
            dot_y = y + f.size - 10
            x = 120 + lw + 18
            while x < S - 150 - tag_w:
                c.d.ellipse((x, dot_y, x + 4, dot_y + 4), fill=c.dim)
                x += 16
            c.d.text((S - 128 - tag_w, y + 4), tag, font=tf, fill=c.accent)
            y += 96
        extra = (p.get("facts") or [""])[0]
        if extra:
            c.small(extra, 916, center=True)
    else:
        c.d.text((64, 200), board, font=_font(34, bold=True), fill=c.accent)
        y = 280 + min(80, max(0, (620 - len(items) * 112) // 2))
        for i, item in enumerate(items):
            c.d.rectangle((64, y, S - 64, y + 92), fill=mix(c.bg, c.ink, 0.06))
            tag = "TODAY" if i < 3 else "FRESH"
            tf = _font(28, bold=True)
            tag_w = c.d.textlength(tag, font=tf)
            c.d.text((S - 96 - tag_w, y + 32), tag, font=tf, fill=c.accent)
            label, f = fit(c.d, item.upper(), S - 192 - tag_w - 32, 36)
            c.d.text((96, y + 26), label, font=f, fill=c.ink)
            y += 112
        extra = (p.get("facts") or [""])[0]
        if extra:
            c.small(extra, y + 20)
    c.footer()
    return c


def card_statement(p):
    """One big line, staged per family: sunrise arcs (artisan), ticket frame
    (diner), or the off-center disc (default)."""
    c = Card(p)
    fam = c.style.get("family", "default")
    sells, _, _ = voice(p)
    line = p.get("statement") or f"Fresh {sells} at {p['name']}."

    if fam == "artisan":
        # rising sun: concentric arcs from the bottom edge, copy up top
        cx = S // 2
        for r in (520, 400, 280, 160):
            c.d.arc((cx - r, 980 - r, cx + r, 980 + r), 180, 360,
                    fill=c.dim, width=6)
        c.d.ellipse((cx - 70, 910, cx + 70, 1050), fill=c.accent)
        c.header("Tuesday")
        y = c.message(line, 250, size=88, center=True, max_lines=3)
        c.small(p.get("town", ""), y + 30, center=True)
    elif fam == "diner":
        # ticket: double frame with corner squares, copy centered inside
        c.d.rectangle((72, 200, S - 72, 880), outline=c.accent, width=5)
        c.d.rectangle((92, 220, S - 92, 860), outline=c.dim, width=2)
        for cx, cy in ((72, 200), (S - 72, 200), (72, 880), (S - 72, 880)):
            c.d.rectangle((cx - 14, cy - 14, cx + 14, cy + 14), fill=c.accent)
        c.header("Tuesday")
        y = c.message(line, 300, size=82, center=True, max_w=S - 260,
                      max_lines=3)
        c.small(p.get("town", ""), min(y + 26, 800), center=True)
    else:
        c.d.ellipse((640, 660, 1300, 1320), fill=c.dim)
        c.header("Tuesday")
        y = c.message(line, 280, size=92, max_lines=3)
        c.d.rectangle((64, y + 26, 344, y + 38), fill=c.accent)
        c.small(p.get("town", ""), y + 78)
    c.footer()
    return c


def card_hours(p):
    """The week's hours — every business has them, nobody posts them."""
    c = Card(p)
    c.header("Wednesday")
    c.d.text((64, 200), "WHEN WE'RE OPEN", font=_font(34, bold=True), fill=c.accent)
    hours = p.get("hours") or {}
    if not hours:
        # seven dashes look like a real post that's broken; say plainly that
        # this one still needs a human, so it can't be shown by accident
        c.d.rounded_rectangle((64, 300, S - 64, 700), radius=28, fill=c.dim)
        c.message("Add their opening hours to profile.json.", 400,
                  size=58, center=True, max_w=S - 220, fill=c.ink)
        c.small("this card is a placeholder — not for showing", 600,
                center=True)
        c.footer()
        return c
    y = 288
    for day in DAYS:
        val = hours.get(day[:3], hours.get(day, "—"))
        c.d.line((64, y + 62, S - 64, y + 62), fill=mix(c.bg, c.ink, 0.12), width=2)
        c.d.text((64, y + 14), day, font=_font(36, bold=True), fill=c.ink)
        closed = str(val).strip().lower() in ("closed", "-", "—", "")
        vf = _font(36, bold=True)
        c.d.text((S - 64 - c.d.textlength(str(val), font=vf), y + 14), str(val),
                 font=vf, fill=c.muted if closed else c.accent)
        y += 78
    c.footer()
    return c


def card_spotlight(p):
    """One hero item: scalloped plate (artisan), perforated ticket stub
    (diner), or the plain ring (default)."""
    c = Card(p)
    fam = c.style.get("family", "default")
    items = p.get("items") or []
    hero = p.get("spotlight") or (items[0] if items else p["name"])
    price = p.get("spotlight_price")

    if fam == "artisan":
        # doily plate: ring of small discs around the hero circle
        import math as _m
        cx, cy, R = S // 2, 590, 330
        for i in range(22):
            a = 2 * _m.pi * i / 22
            bx, by = cx + R * _m.cos(a), cy + R * _m.sin(a)
            c.d.ellipse((bx - 22, by - 22, bx + 22, by + 22), fill=c.dim)
        c.d.ellipse((cx - R + 26, cy - R + 26, cx + R - 26, cy + R - 26),
                    fill=mix(c.bg, c.ink, 0.05))
        c.d.ellipse((cx - R + 56, cy - R + 56, cx + R - 56, cy + R - 56),
                    outline=c.accent, width=4)
        c.header("Thursday")
        f = _font(30, bold=True)
        label = voice(p)[0].upper()
        c.d.text(((S - c.d.textlength(label, font=f)) // 2, 430), label,
                 font=f, fill=c.accent)
        c.message(hero, 500, size=70, center=True, max_w=470)
        if price:
            pf = _font(54, bold=True)
            c.d.text(((S - c.d.textlength(price, font=pf)) // 2, 740), price,
                     font=pf, fill=c.accent)
    elif fam == "diner":
        # ticket stub: perforation line splits the stub from the body
        c.d.rounded_rectangle((110, 280, S - 110, 860), radius=26,
                              fill=mix(c.bg, c.ink, 0.06))
        c.d.rounded_rectangle((110, 280, S - 110, 860), radius=26,
                              outline=c.accent, width=4)
        for y in range(300, 850, 26):
            c.d.line((320, y, 320, y + 12), fill=c.dim, width=3)
        c.header("Thursday")
        lf = _font(28, bold=True)
        label = voice(p)[0].upper()
        for i, ch in enumerate(label[:10]):
            c.d.text((196, 330 + i * 46), ch, font=lf, fill=c.accent)
        c.message(hero, 430, size=74, center=True, max_w=470)
        if price:
            pf = _font(56, bold=True)
            pw = c.d.textlength(price, font=pf)
            c.d.text(((320 + (S - 110) - pw) // 2, 730), price,
                     font=pf, fill=c.accent)
    else:
        c.d.ellipse((190, 250, 890, 950), outline=c.accent, width=6)
        c.d.ellipse((240, 300, 840, 900), fill=c.dim)
        c.header("Thursday")
        f = _font(30, bold=True)
        label = voice(p)[0].upper()
        c.d.text(((S - c.d.textlength(label, font=f)) // 2, 400), label,
                 font=f, fill=c.accent)
        c.message(hero, 470, size=72, center=True, max_w=560)
        if price:
            pf = _font(56, bold=True)
            c.d.text(((S - c.d.textlength(price, font=pf)) // 2, 760), price,
                     font=pf, fill=c.accent)
    c.footer()
    return c


def card_quote(p):
    """A real review if the profile carries one — otherwise an invitation.

    Never invents a testimonial: a made-up review is the fastest way to lose a
    prospect's trust, and it would be theirs to answer for, not ours.
    """
    c = Card(p)
    review = p.get("review") or {}
    text, author = review.get("text"), review.get("author")
    c.header("Friday")
    if text:
        c.d.text((64, 230), "“", font=_font(220, serif=True), fill=c.dim)
        c.message(text, 400, size=64, max_w=S - 160)
        c.small(f"— {author}" if author else "— a regular", 800, fill=c.accent, size=36)
    else:
        c.d.rounded_rectangle((64, 300, S - 64, 720), radius=32, fill=c.dim)
        c.message(voice(p)[2], 380, size=86, center=True, max_w=S - 220)
        c.small(p.get("town", ""), 620, center=True)
    c.footer()
    return c


def card_stat(p):
    """A single number: starburst badge (artisan), dinner plate (diner), or
    bare and huge (default)."""
    c = Card(p)
    fam = c.style.get("family", "default")
    stat = p.get("stat") or {}
    value = str(stat.get("value") or len(p.get("items") or []) or "7")
    label = stat.get("label") or f"things {voice(p)[0]}"
    c.header("Saturday")

    if fam == "artisan":
        import math as _m
        cx, cy = S // 2, 470
        pts = []
        for i in range(28):
            a = 2 * _m.pi * i / 28
            r = 320 if i % 2 == 0 else 268
            pts.append((cx + r * _m.cos(a), cy + r * _m.sin(a)))
        c.d.polygon(pts, fill=c.dim)
        c.d.ellipse((cx - 240, cy - 240, cx + 240, cy + 240), fill=c.bg)
        c.d.ellipse((cx - 240, cy - 240, cx + 240, cy + 240),
                    outline=c.accent, width=5)
        f = _font(220, bold=True)
        w = c.d.textlength(value, font=f)
        while w > 400 and f.size > 80:
            f = _font(f.size - 20, bold=True)
            w = c.d.textlength(value, font=f)
        c.d.text(((S - w) // 2, cy - f.size // 2 - 30), value, font=f, fill=c.accent)
        c.message(label, 800, size=58, center=True, max_w=S - 200, fill=c.ink,
                  max_lines=2)
    elif fam == "diner":
        cx, cy = S // 2, 480
        c.d.ellipse((cx - 300, cy - 300, cx + 300, cy + 300),
                    fill=mix(c.bg, c.ink, 0.05))
        c.d.ellipse((cx - 300, cy - 300, cx + 300, cy + 300),
                    outline=c.dim, width=4)
        c.d.ellipse((cx - 225, cy - 225, cx + 225, cy + 225),
                    outline=c.accent, width=4)
        for x in (150, 168, 186):                       # fork tines, abstract
            c.d.line((x, cy - 90, x, cy + 90), fill=c.dim, width=6)
        c.d.line((S - 165, cy - 90, S - 165, cy + 90), fill=c.dim, width=10)
        f = _font(230, bold=True)
        w = c.d.textlength(value, font=f)
        while w > 380 and f.size > 80:
            f = _font(f.size - 20, bold=True)
            w = c.d.textlength(value, font=f)
        c.d.text(((S - w) // 2, cy - f.size // 2 - 25), value, font=f, fill=c.accent)
        c.message(label, 820, size=58, center=True, max_w=S - 200, fill=c.ink,
                  max_lines=2)
    else:
        f = _font(300, bold=True)
        w = c.d.textlength(value, font=f)
        while w > S - 200 and f.size > 90:
            f = _font(f.size - 20, bold=True)
            w = c.d.textlength(value, font=f)
        c.d.text(((S - w) // 2, 300), value, font=f, fill=c.accent)
        c.message(label, 660, size=64, center=True, max_w=S - 200, fill=c.ink)
    c.footer()
    return c


def card_teaser(p):
    """The 'something's coming' post: sunrise glow (artisan), marquee bulbs
    (diner), or the radial burst (default)."""
    c = Card(p)
    fam = c.style.get("family", "default")

    if fam == "artisan":
        cx = S // 2
        for r, wdt in ((430, 8), (330, 6), (230, 5), (130, 4)):
            c.d.arc((cx - r, 560 - r, cx + r, 560 + r), 0, 180,
                    fill=c.dim, width=wdt)
        c.d.ellipse((cx - 64, 500, cx + 64, 628), fill=c.accent)
        c.header("Sunday")
        c.message(p.get("teaser") or "Something new this week.", 240,
                  size=72, center=True, max_lines=2)
    elif fam == "diner":
        step = 62
        for x in range(60, S - 40, step):
            c.d.ellipse((x, 160, x + 22, 182), fill=c.accent)
            c.d.ellipse((x, S - 150, x + 22, S - 128), fill=c.accent)
        for y in range(220, S - 190, step):
            c.d.ellipse((52, y, 74, y + 22), fill=c.accent)
            c.d.ellipse((S - 74, y, S - 52, y + 22), fill=c.accent)
        c.header("Sunday")
        c.message(p.get("teaser") or "Something new this week.", 430,
                  size=76, center=True, max_w=S - 260, max_lines=3)
    else:
        cx, cy = S // 2, 430
        for r in (300, 210, 120):
            c.d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=c.dim, width=4)
        for i in range(12):
            a = math.radians(i * 30)
            c.d.line((cx + 90 * math.cos(a), cy + 90 * math.sin(a),
                      cx + 300 * math.cos(a), cy + 300 * math.sin(a)),
                     fill=c.dim, width=3)
        c.d.ellipse((cx - 54, cy - 54, cx + 54, cy + 54), fill=c.accent)
        c.header("Sunday")
        c.message(p.get("teaser") or "Something new this week.", 760,
                  size=72, center=True, max_lines=2)
    c.footer()
    return c


DEVICES = [card_lineup, card_statement, card_hours, card_spotlight,
           card_quote, card_stat, card_teaser]


# ── captions ──────────────────────────────────────────────────────────────

def captions_for(p):
    sells, _, invite = voice(p)
    town = p.get("town", "")
    items = p.get("items") or []
    facts = p.get("facts") or []
    fact = facts[0] if facts else ""
    hero = p.get("spotlight") or (items[0] if items else "today's pick")
    statement = p.get("statement") or f"Fresh {sells} at {p['name']}."
    lineup = ", ".join(items[:3]) or "Come see"
    review_text = (p.get("review") or {}).get("text")
    in_town = f" in {town}" if town else ""

    # the closer is deliberately different most days: seven captions ending on
    # the same phrase is the "one robot template" objection in words
    return [
        ("Monday", f"Here's what's {sells}: {lineup}"
                   f"{' — ' + fact if fact else ''}. {invite}"),
        ("Tuesday", f"{statement}"),
        ("Wednesday", f"Planning your week? Here's when we're open{in_town}. "
                      f"Save the post so you've got it when you need it."),
        ("Thursday", f"{hero}. If you only try one thing this week, "
                     f"make it this one."),
        ("Friday", f"\"{review_text}\" — thank you, that made our week. "
                   f"See you this weekend."
                   if review_text else
                   f"Weekend's in sight. {invite}"),
        ("Saturday", f"A little about us, by the numbers"
                     f"{' — ' + facts[1] if len(facts) > 1 else ''}."),
        ("Sunday", f"{p.get('teaser') or 'Something new this week.'} "
                   f"Keep an eye on this page — you'll see it here first."),
    ]


def write_captions(p, out):
    lines = [
        f"# {p['name']} — free sample week (East Coast Social mockups)",
        "",
        f"_Seven days of posts in {p['name']}'s colors, built from their own "
        f"details. Mockups: swap any item, price or hour for the live one at "
        f"setup._",
        "",
    ]
    todo = missing_fields(p)
    if todo:
        lines += [f"> ⚠️ Still on defaults: {', '.join(todo)}. Fill these in "
                  f"`profile.json` and re-run before showing this to anyone — "
                  f"the pack only lands when the details are theirs.", ""]
    for i, (day, caption) in enumerate(captions_for(p), 1):
        lines += [f"## Day {i} — {day} (day-{i}.png)",
                  f"**Caption:** {caption}", ""]
    lines += ["---", "",
              f"Built by East Coast Social — {tracked_link(p['slug'])}",
              "", "Your page posts every day. You approve the style once."]
    (out / "captions.md").write_text("\n".join(lines), encoding="utf-8")


def missing_fields(p):
    """What still needs a human — the difference between 'they looked at us'
    and a form letter."""
    todo = []
    if not p.get("items"):
        todo.append("items")
    if not p.get("hours"):
        todo.append("hours")
    if not p.get("facts"):
        todo.append("facts")
    return todo


# ── the one page you print and hand over ──────────────────────────────────

def contact_sheet(p, out, paths):
    """All seven cards on one portrait page, plus the pitch line.

    This is the walk-in asset: an owner who won't open a link will still look
    at a sheet of their own posts held in front of them.
    """
    cols, rows, thumb, gap, top = 2, 4, 460, 40, 210
    W = cols * thumb + (cols + 1) * gap
    H = top + rows * thumb + (rows + 1) * gap
    sheet = Image.new("RGB", (W, H), rgb(p["bg"]))
    d = ImageDraw.Draw(sheet)
    accent = rgb(p["accent"])

    d.ellipse((gap, 54, gap + 34, 88), fill=accent)
    d.text((gap + 52, 48), p["name"].upper(), font=_font(46, bold=True), fill=accent)
    d.text((gap, 118), "One week of posts — already built for you.",
           font=_font(31, serif=True), fill=rgb(p.get("ink", "#f4f6fa")))
    d.text((gap, 164), "East Coast Social · findhotstuff.com/automation",
           font=_font(28), fill=mix(rgb(p["bg"]), accent, 0.7))

    # per-prospect QR: when THIS sheet gets scanned, the traffic ping says
    # this prospect's name — the highest-intent signal on the board
    try:
        import io as _io
        import segno
        qs = 150
        buf = _io.BytesIO()
        segno.make(f"https://{tracked_link(p['slug'])}", error="m").save(
            buf, kind="png", scale=10, border=1, dark="#111111", light="#ffffff")
        qr = Image.open(buf).convert("RGB").resize((qs, qs), Image.NEAREST)
        pad = 12
        qx = W - gap - qs - pad * 2
        d.rounded_rectangle((qx, 28, qx + qs + pad * 2, 28 + qs + pad * 2),
                            radius=14, fill="#ffffff")
        sheet.paste(qr, (qx + pad, 28 + pad))
    except Exception as exc:  # noqa: BLE001 - a missing QR lib never blocks a pack
        print(f"  (QR skipped: {exc})")

    for i, path in enumerate(paths):
        card = Image.open(path).resize((thumb, thumb), Image.LANCZOS)
        x = gap + (i % cols) * (thumb + gap)
        y = top + gap + (i // cols) * (thumb + gap)
        sheet.paste(card, (x, y))

    # final cell: the offer, where the eighth card would go
    x = gap + (7 % cols) * (thumb + gap)
    y = top + gap + (7 // cols) * (thumb + gap)
    d.rounded_rectangle((x, y, x + thumb, y + thumb), radius=28, fill=accent)
    for j, line in enumerate(["Your page,", "posting daily.", "",
                              "You approve the", "style once.", "",
                              "$79/month", "no contracts"]):
        d.text((x + 34, y + 40 + j * 52), line,
               font=_font(40 if j < 2 or j == 6 else 32, bold=j < 2 or j == 6),
               fill=rgb(p["bg"]))
    sheet.save(out / "contact-sheet.png")


# ── profiles ──────────────────────────────────────────────────────────────

STARTER_NOTE = ("Fill in items/hours/facts from their own page before "
                "rendering — that is what makes an owner say 'they actually "
                "looked at us'.")


def starter_profile(name, town, category):
    bg, accent = PALETTES.get(category, PALETTES["*"])
    return {
        "_note": STARTER_NOTE,
        "name": name,
        "slug": slugify(name),
        "town": town,
        "category": category,
        "bg": bg,
        "accent": accent,
        "items": [],
        "hours": {d[:3]: "" for d in DAYS},
        "facts": [],
        "statement": "",
        "spotlight": "",
        "spotlight_price": "",
        "teaser": "",
        "stat": {"value": "", "label": ""},
        "review": {"text": "", "author": ""},
    }


def load_profile(path):
    p = json.loads(Path(path).read_text(encoding="utf-8"))
    for required in ("name",):
        if not p.get(required):
            raise SystemExit(f"profile is missing '{required}'")
    p.setdefault("category", "*")
    p.setdefault("slug", slugify(p["name"]))
    bg, accent = PALETTES.get(p["category"], PALETTES["*"])
    p.setdefault("bg", bg)
    p.setdefault("accent", accent)
    # drop empty scaffolding so the renderers' "is it set?" checks work
    for k in ("statement", "spotlight", "spotlight_price", "teaser"):
        if not str(p.get(k, "")).strip():
            p.pop(k, None)
    for k in ("stat", "review"):
        if isinstance(p.get(k), dict) and not any(str(v).strip() for v in p[k].values()):
            p.pop(k, None)
    p["hours"] = {k: v for k, v in (p.get("hours") or {}).items() if str(v).strip()}
    p["items"] = [i for i in (p.get("items") or []) if str(i).strip()]
    p["facts"] = [f for f in (p.get("facts") or []) if str(f).strip()]
    return p


def render(profile_path):
    p = load_profile(profile_path)
    out = SAMPLES / p["slug"]
    out.mkdir(parents=True, exist_ok=True)

    paths = []
    for i, device in enumerate(DEVICES, 1):
        path = out / f"day-{i}.png"
        device(p).save(path)
        paths.append(path)
        print(f"  day-{i}.png  {device.__name__.replace('card_', '')}")
    write_captions(p, out)
    contact_sheet(p, out, paths)
    register_slug(p["slug"])
    print(f"captions.md + contact-sheet.png -> {out}  (ref tag: {ref_tag(p['slug'])})")

    todo = missing_fields(p)
    if todo:
        print(f"\n⚠️  still on defaults: {', '.join(todo)} — fill these in "
              f"{Path(profile_path).name} and re-run before pitching.")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("profile", nargs="?", help="path to a prospect profile.json")
    ap.add_argument("--new", metavar="NAME", help="scaffold a profile instead")
    ap.add_argument("--town", default="", help="with --new: e.g. 'Shediac, NB'")
    ap.add_argument("--category", default="*",
                    help=f"with --new: {', '.join(k for k in PALETTES if k != '*')}")
    args = ap.parse_args()

    if args.new:
        p = starter_profile(args.new, args.town, args.category)
        out = SAMPLES / p["slug"]
        out.mkdir(parents=True, exist_ok=True)
        dest = out / "profile.json"
        if dest.exists():
            raise SystemExit(f"{dest} already exists — edit it, or delete to restart.")
        dest.write_text(json.dumps(p, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {dest}\n\nNext: fill in items / hours / facts from their "
              f"page, then:\n  python sample_week.py {dest.relative_to(HERE)}")
        return 0

    if not args.profile:
        ap.print_help()
        return 1
    render(args.profile)
    return 0


if __name__ == "__main__":
    sys.exit(main())
