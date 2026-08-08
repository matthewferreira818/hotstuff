"""
East Coast Social Pinterest pack — the service funnel (business owners), as
opposed to the product pins (shoppers).

Ten 1000x1500 pins, each a DIFFERENT layout: statement, price comparison,
checklist, before/after, stat block, quote, steps, question, local list and
objection-killer. Pinterest is a search engine, so every pin ships with a
keyword-rich title and description in pins-ecs.md.

    python marketing/east-coast-social/make_ecs_pins.py
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE / "engine"))
from post_card import _font, _wrap  # noqa: E402

W, H = 1000, 1500
BG, BG2 = (13, 31, 51), (23, 48, 76)
GOLD = "#f0b429"
INK = "#f2f6fa"
MUTED = "#a8bccf"
CARD = (20, 42, 68)
RED = (58, 34, 34)
SITE = "findhotstuff.com/automation"
LINK = "https://findhotstuff.com/automation/?ref=pin-ecs"
OUT = HERE.parent / "pinterest" / "ecs"


# ── shared furniture ──────────────────────────────────────────────────────
def base():
    img = Image.new("RGB", (W, H), BG)
    px = img.load()
    for y in range(H):
        t = y / (H - 1)
        row = tuple(round(a + (b - a) * t) for a, b in zip(BG, BG2))
        for x in range(W):
            px[x, y] = row
    d = ImageDraw.Draw(img)
    d.ellipse((64, 88, 94, 118), fill=GOLD)
    d.text((116, 82), "EAST COAST SOCIAL", font=_font(44, bold=True), fill=GOLD)
    return img, d


def footer(d):
    d.rectangle((0, H - 110, W, H), fill=GOLD)
    d.text((64, H - 86), SITE, font=_font(42, bold=True), fill="#0d1f33")


def big_text(d, text, y, size=96, max_w=W - 128, center=False):
    while size > 40:
        f = _font(size, serif=True)
        lines = _wrap(d, text, f, max_w)
        if len(lines) * (size + 20) < 720:
            break
        size -= 6
    for i, line in enumerate(lines):
        x = (W - d.textlength(line, font=f)) // 2 if center else 64
        d.text((x, y), line, font=f, fill=INK if i % 2 == 0 else GOLD)
        y += size + 20
    return y


def sub_text(d, text, y, size=36, fill=MUTED):
    f = _font(size)
    for line in _wrap(d, text, f, W - 128):
        d.text((64, y), line, font=f, fill=fill)
        y += size + 12
    return y


# ── layouts ───────────────────────────────────────────────────────────────
def pin_statement(msg, sub):
    img, d = base()
    y = big_text(d, msg, 300)
    sub_text(d, sub, y + 36)
    footer(d)
    return img


def pin_price_compare(msg, sub):
    img, d = base()
    d.text((64, 250), "WHAT DAILY POSTING COSTS", font=_font(38, bold=True), fill=GOLD)
    y = 360
    for label, amount, per, fill, amt_fill in (
            ("A social media agency", "$1,000+", "/month", RED, (240, 160, 160)),
            ("East Coast Social", "$79", "/month", CARD, INK)):
        d.rounded_rectangle((64, y, W - 64, y + 300), radius=28, fill=fill)
        d.text((104, y + 40), label, font=_font(36), fill=MUTED)
        af = _font(130, serif=True)
        d.text((104, y + 100), amount, font=af, fill=amt_fill)
        d.text((104 + d.textlength(amount, font=af) + 16, y + 195), per, font=_font(38), fill=MUTED)
        y += 336
    sub_text(d, "Same daily posts. One of them is a robot.", y + 24)
    footer(d)
    return img


def pin_checklist(msg, sub):
    img, d = base()
    big_text(d, "What you actually get.", 250, size=82)
    y = 500
    for item in ("A post every day, in your colours",
                 "Written, designed and published for you",
                 "Your schedule — daily or 3x a week",
                 "A human keeping watch (that's me)",
                 "Free setup, cancel any month"):
        d.rounded_rectangle((64, y, W - 64, y + 132), radius=20, fill=CARD)
        d.ellipse((104, y + 46, 144, y + 86), outline=GOLD, width=5)
        d.line((113, y + 66, 124, y + 78), fill=GOLD, width=6)
        d.line((124, y + 78, 140, y + 54), fill=GOLD, width=6)
        d.text((178, y + 48), item, font=_font(33), fill=INK)
        y += 152
    footer(d)
    return img


def pin_before_after(msg, sub):
    img, d = base()
    d.text((64, 250), "YOUR PAGE, TWO WAYS", font=_font(38, bold=True), fill=GOLD)
    y = 350
    for title, lines, fill, tcol in (
            ("Right now", ["last post: March", "customers assume you're closed"], RED, (230, 150, 150)),
            ("On the engine", ["posted today", "and yesterday", "and every day before"], CARD, GOLD)):
        h = 118 + len(lines) * 62
        d.rounded_rectangle((64, y, W - 64, y + h), radius=26, fill=fill)
        d.text((104, y + 30), title, font=_font(46, bold=True), fill=tcol)
        yy = y + 104
        for ln in lines:
            d.text((104, yy), ln, font=_font(33), fill=INK if fill == CARD else MUTED)
            yy += 62
        y += h + 44
    sub_text(d, "Nothing to remember. Nothing to schedule.", y + 16)
    footer(d)
    return img


def pin_stats(msg, sub):
    img, d = base()
    big_text(d, "The math on autopilot.", 250, size=78)
    y = 520
    for num, label in (("180+", "posts a month"), ("0 min", "of your time"), ("$79", "a month, flat")):
        d.rounded_rectangle((64, y, W - 64, y + 190), radius=26, fill=CARD)
        nf = _font(92, serif=True)
        d.text((104, y + 38), num, font=nf, fill=GOLD)
        d.text((104 + d.textlength(num, font=nf) + 30, y + 80), label, font=_font(36), fill=MUTED)
        y += 214
    footer(d)
    return img


def pin_quote(msg, sub):
    img, d = base()
    d.text((56, 200), "“", font=_font(300, serif=True), fill=(30, 58, 88))
    y = big_text(d, msg, 430, size=82)
    sub_text(d, sub, y + 30)
    footer(d)
    return img


def pin_steps(msg, sub):
    img, d = base()
    big_text(d, "Three steps. One week.", 250, size=80)
    y = 520
    for num, text in (("1", "A 20-minute chat about your business"),
                      ("2", "I build it and show you samples"),
                      ("3", "It posts. You run your business.")):
        d.ellipse((72, y + 22, 148, y + 98), fill=GOLD)
        d.text((99, y + 32), num, font=_font(52, bold=True), fill="#0d1f33")
        f = _font(35)
        yy = y + 24
        for ln in _wrap(d, text, f, W - 300):
            d.text((186, yy), ln, font=f, fill=INK)
            yy += 46
        y += 186
    sub_text(d, "Setup is free. You approve the voice before anything goes live.", y + 10)
    footer(d)
    return img


def pin_question(msg, sub):
    img, d = base()
    d.text((W - 320, 170), "?", font=_font(540, serif=True), fill=(26, 52, 80))
    y = big_text(d, msg, 470, size=88)
    sub_text(d, sub, y + 30)
    footer(d)
    return img


def pin_local(msg, sub):
    img, d = base()
    big_text(d, "Made in New Brunswick, for New Brunswick.", 250, size=72)
    towns = ["Memramcook", "Sackville", "Moncton", "Dieppe", "Shediac", "Riverview"]
    col_w = (W - 144) // 2
    y = 640
    for i, town in enumerate(towns):
        col = i % 2
        x = 64 + col * (col_w + 16)
        d.rounded_rectangle((x, y, x + col_w, y + 96), radius=999, fill=CARD)
        d.ellipse((x + 28, y + 38, x + 48, y + 58), fill=GOLD)
        d.text((x + 66, y + 30), town, font=_font(31), fill=INK)
        if col:
            y += 116
    sub_text(d, "A neighbour runs it — not an agency three provinces away.", y + 150)
    footer(d)
    return img


def pin_objection(msg, sub):
    img, d = base()
    y = big_text(d, msg, 300, size=84)
    y = sub_text(d, sub, y + 34)
    d.rounded_rectangle((64, y + 60, W - 64, y + 190), radius=24, fill=CARD)
    d.text((104, y + 96), "You approve the voice once.", font=_font(38, bold=True), fill=GOLD)
    footer(d)
    return img


# (layout, card message, sub-line, pin title, pin description)
PINS = [
    (pin_statement, "Posting every day isn't discipline. It's automation.",
     "Done-for-you social media for local businesses",
     "Social Media Automation for Small Business — Post Daily on Autopilot",
     "The businesses that post every day aren't trying harder — they automated it. East Coast "
     "Social writes and publishes daily posts for your business. Free setup, $79/month, no "
     "contracts. Serving small businesses across New Brunswick."),
    (pin_price_compare, "", "",
     "Social Media Manager Cost: Agency vs Automation for Small Business",
     "Hiring a social media agency costs $1,000+ per month. An automation engine does the same "
     "daily posting for $79/month. See exactly how it works — free setup, no contracts, cancel "
     "anytime."),
    (pin_checklist, "", "",
     "Done-For-You Social Media: What's Actually Included",
     "A daily branded post, written and designed for you, on the schedule you choose — plus a "
     "real human keeping watch. Small business social media management from $79/month with free "
     "setup."),
    (pin_before_after, "", "",
     "Why a Quiet Facebook Page Costs You Customers",
     "Customers check your page before they choose you. A page that posts daily looks open for "
     "business; a quiet one looks closed. Here's the fix for local businesses — automated daily "
     "posts from $79/month."),
    (pin_stats, "", "",
     "180 Social Media Posts a Month Without Lifting a Finger",
     "180+ posts a month, zero minutes of your time, $79 flat. That's what small business social "
     "media looks like when an engine does the posting. Free setup, no contracts."),
    (pin_quote, "“I know I should post more.”",
     "— every business owner, ever. We fixed that.",
     "No Time for Social Media? Automate Your Small Business Posts",
     "Every small business owner says the same thing: I know I should post more, I just don't have "
     "time. East Coast Social automates it — you approve the style once, the engine does the rest. "
     "Free setup, $79/month."),
    (pin_steps, "", "",
     "How to Set Up Automated Social Media for Your Business in a Week",
     "One 20-minute conversation, sample posts in your branding, then it posts daily on its own. "
     "Small business social media automation with free setup and no contracts — built in New "
     "Brunswick."),
    (pin_question, "When did your business last post?",
     "If you had to think about it, that's the problem.",
     "Small Business Marketing Tip: Consistency Beats Everything",
     "If you have to think about when you last posted, your customers noticed too. Consistent "
     "daily posting is the easiest marketing win for a local business — and it can be fully "
     "automated for $79/month."),
    (pin_local, "", "",
     "Social Media Management for New Brunswick Small Businesses",
     "Local social media help for Memramcook, Sackville, Moncton, Dieppe, Shediac and Riverview. "
     "A neighbour runs it, not an agency — daily posts for your business, free setup, $79/month."),
    (pin_objection, "But I don't want a robot sounding like me.",
     "You approve the voice, the colours and the sample posts before anything goes live.",
     "Will Automated Posts Sound Like My Business? Here's How It Works",
     "The most common worry about automated social media: will it sound like me? You approve the "
     "voice, colours and sample posts before anything publishes, and you can change it any time. "
     "Small business social media from $79/month."),
]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    md = ["# ECS pin pack — pitches the automation service (not products)",
          "",
          "_Board: **Small Business Marketing**._",
          f"_Link every pin to: {LINK}_",
          "_Cadence: 1 per day, after the product pins. Ten layouts, no two alike._",
          ""]
    for i, (layout, msg, sub, title, desc) in enumerate(PINS, 1):
        layout(msg, sub).save(OUT / f"pin-ecs-{i}.png", optimize=True)
        print(f"rendered pin-ecs-{i}.png  ({layout.__name__.replace('pin_', '')})")
        md += [f"## Pin {i} — pin-ecs-{i}.png ({layout.__name__.replace('pin_', '')})",
               f"**Title:** {title}", "",
               f"**Description:** {desc}", "",
               f"**Link:** {LINK}", ""]
    (OUT / "pins-ecs.md").write_text("\n".join(md), encoding="utf-8")
    print(f"wrote {OUT / 'pins-ecs.md'}")


if __name__ == "__main__":
    main()
