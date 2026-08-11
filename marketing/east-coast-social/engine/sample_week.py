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

    def header(self, day_label):
        """Brand band: accent dot + name on the left, day label on the right.

        The label is measured first so a long business name gets whatever
        width is genuinely left, instead of running underneath it.
        """
        d = self.d
        lf = _font(26, bold=True)
        label = day_label.upper()
        label_w = d.textlength(label, font=lf)
        d.text((S - 64 - label_w, 72), label, font=lf, fill=self.muted)

        d.ellipse((64, 70, 92, 98), fill=self.accent)
        name, f = fit(d, self.p["name"].upper(), S - 112 - label_w - 100, 40)
        d.text((112, 64), name, font=f, fill=self.accent)

    def footer(self):
        d = self.d
        d.rectangle((0, S - 92, S, S), fill=self.accent)
        town = self.p.get("town", "")
        tw = 0
        if town:
            tf = _font(28, bold=True)
            tw = d.textlength(town, font=tf)
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
    """Rows of what they sell — the 'today's board' post."""
    c = Card(p)
    c.header("Monday")
    _, board, _ = voice(p)
    c.d.text((64, 200), board, font=_font(34, bold=True), fill=c.accent)
    items = (p.get("items") or ["Add their real items to profile.json"])[:5]
    # nudge a short list down a little, but stay tucked under its heading —
    # fully centring it leaves an odd gap below the label
    y = 280 + min(80, max(0, (620 - len(items) * 112) // 2))
    for i, item in enumerate(items):
        c.d.rectangle((64, y, S - 64, y + 92), fill=mix(c.bg, c.ink, 0.06))
        tag = "TODAY" if i < 3 else "FRESH"
        tf = _font(28, bold=True)
        tag_w = c.d.textlength(tag, font=tf)
        c.d.text((S - 96 - tag_w, y + 32), tag, font=tf, fill=c.accent)
        # the row label gets what's left after the tag, never the tag's space
        label, f = fit(c.d, item.upper(), S - 192 - tag_w - 32, 36)
        c.d.text((96, y + 26), label, font=f, fill=c.ink)
        y += 112
    extra = (p.get("facts") or [""])[0]
    if extra:
        c.small(extra, y + 20)
    c.footer()
    return c


def card_statement(p):
    """One big line — the post that reads at arm's length in a feed."""
    c = Card(p)
    # soft disc low and right, kept clear of the copy: a shape behind the type
    # fights it, and the day label lives in the top-right corner
    c.d.ellipse((640, 660, 1300, 1320), fill=c.dim)
    c.header("Tuesday")
    sells, _, _ = voice(p)
    line = p.get("statement") or f"Fresh {sells} at {p['name']}."
    # a statement that wraps to four lines isn't a statement any more
    y = c.message(line, 280, size=92, max_lines=3)
    c.d.rectangle((64, y + 26, 344, y + 38), fill=c.accent)   # rule, not a void
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
    """One item, centered and large — the 'this is the thing' post."""
    c = Card(p)
    items = p.get("items") or []
    hero = p.get("spotlight") or (items[0] if items else p["name"])
    c.d.ellipse((190, 250, 890, 950), outline=c.accent, width=6)
    c.d.ellipse((240, 300, 840, 900), fill=c.dim)
    c.header("Thursday")
    f = _font(30, bold=True)
    label = voice(p)[0].upper()
    c.d.text(((S - c.d.textlength(label, font=f)) // 2, 400), label,
             font=f, fill=c.accent)
    c.message(hero, 470, size=72, center=True, max_w=560)
    price = p.get("spotlight_price")
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
    """A single number — the most-scrolled-past-proof shape there is."""
    c = Card(p)
    stat = p.get("stat") or {}
    value = str(stat.get("value") or len(p.get("items") or []) or "7")
    label = stat.get("label") or f"things {voice(p)[0]}"
    c.header("Saturday")
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
    """A radial burst — 'something's coming', the post that gets replies."""
    c = Card(p)
    cx, cy = S // 2, 430
    for r in (300, 210, 120):
        c.d.ellipse((cx - r, cy - r, cx + r, cy + r), outline=c.dim, width=4)
    for i in range(12):                      # spokes, fading outward
        a = math.radians(i * 30)
        c.d.line((cx + 90 * math.cos(a), cy + 90 * math.sin(a),
                  cx + 300 * math.cos(a), cy + 300 * math.sin(a)),
                 fill=c.dim, width=3)
    c.d.ellipse((cx - 54, cy - 54, cx + 54, cy + 54), fill=c.accent)
    c.header("Sunday")
    c.message(p.get("teaser") or "Something new this week.", 760,
              size=72, center=True)
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
              "Built by East Coast Social — findhotstuff.com/automation/?ref=sample",
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
    d.text((gap, 116), "One week of posts — already built for you.",
           font=_font(36, serif=True), fill=rgb(p.get("ink", "#f4f6fa")))
    d.text((gap, 164), "East Coast Social · findhotstuff.com/automation",
           font=_font(28), fill=mix(rgb(p["bg"]), accent, 0.7))

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
    print(f"captions.md + contact-sheet.png -> {out}")

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
