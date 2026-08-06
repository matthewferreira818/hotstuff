"""
East Coast Social pin pack for Pinterest — pitches the automation service to
small-business owners (a second funnel besides the product pins).

Renders 1000x1500 pins in the ECS card style and writes pins-ecs.md with
keyword-rich titles/descriptions for upload.

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
ACCENT = "#f0b429"
INK = "#f2f6fa"
MUTED = "#a8bccf"
SITE = "findhotstuff.com/automation"
OUT = HERE.parent / "pinterest" / "ecs"

# (card message, sub-line, pin title, pin description)
PINS = [
    ("Posting every day isn't discipline. It's automation.",
     "Done-for-you social media for local businesses",
     "Social Media Automation for Small Business — Post Daily on Autopilot",
     "The businesses that post every day aren't trying harder — they automated it. "
     "East Coast Social writes and publishes daily posts for your business. "
     "Free setup, $79/month, no contracts."),
    ("Agencies charge $1,000+ a month. The robot charges $79.",
     "Free setup · no contracts · cancel anytime",
     "Social Media Manager Cost: Agency vs Automation for Small Business",
     "Hiring a social media agency costs $1,000+ per month. An automation engine "
     "does the same daily posting for $79/month. See how it works — free setup, "
     "no contracts."),
    ("A page that posts daily looks open. A quiet one looks closed.",
     "Your customers check your page before they choose you",
     "Why Daily Posting Matters for Local Businesses",
     "Customers check your social media before they walk in. A page that posts "
     "daily looks open for business — a quiet one looks closed. Automate daily "
     "posts for your local business from $79/month."),
    ("“I know I should post more.” — every business owner, ever",
     "We fixed that. Daily posts, zero effort from you.",
     "No Time for Social Media? Automate Your Business Posts",
     "Every small business owner says the same thing: no time to post. "
     "East Coast Social automates your daily social media — you approve the "
     "style once, the engine does the rest. Free setup."),
    ("One 20-minute chat. Then your page runs itself.",
     "Setup is free · $79/month · daily posts, done for you",
     "Done-For-You Social Media for Small Business — Free Setup",
     "The whole setup is one 20-minute conversation: we learn your business, "
     "you approve sample posts, and the engine posts daily from then on. "
     "$79/month, no contracts, built in New Brunswick."),
]


def gradient(w, h, top, bottom):
    img = Image.new("RGB", (w, h), top)
    px = img.load()
    for y in range(h):
        t = y / (h - 1)
        px_row = tuple(round(a + (b - a) * t) for a, b in zip(top, bottom))
        for x in range(w):
            px[x, y] = px_row
    return img


def render_pin(message, sub, out_path):
    img = gradient(W, H, BG, BG2)
    d = ImageDraw.Draw(img)

    # header band: accent dot + brand
    d.ellipse((64, 88, 94, 118), fill=ACCENT)
    d.text((116, 82), "EAST COAST SOCIAL", font=_font(44, bold=True), fill=ACCENT)

    # big serif message, auto-sized, alternating ink/accent lines
    size = 96
    while size > 44:
        f = _font(size, serif=True)
        lines = _wrap(d, message, f, W - 128)
        block_h = len(lines) * (size + 20)
        if block_h < 760:
            break
        size -= 6
    y = (H - block_h) // 2 - 120
    y = max(y, 260)
    for i, line in enumerate(lines):
        d.text((64, y), line, font=f, fill=INK if i % 2 == 0 else ACCENT)
        y += size + 20

    # sub-line
    d.text((64, y + 36), sub, font=_font(36), fill=MUTED)

    # footer strip
    d.rectangle((0, H - 110, W, H), fill=ACCENT)
    d.text((64, H - 86), SITE, font=_font(42, bold=True), fill="#0d1f33")

    out_path.parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)


def main():
    md = ["# ECS pin pack — pitches the automation service (not products)",
          "",
          "_Board: **Small Business Marketing** (create it if it doesn't exist)._",
          "_Link every pin to: https://findhotstuff.com/automation/?ref=pin-ecs-ecs_",
          "_Cadence: 1 per day, after the product pins._",
          ""]
    for i, (msg, sub, title, desc) in enumerate(PINS, 1):
        out = OUT / f"pin-ecs-{i}.png"
        render_pin(msg, sub, out)
        print(f"rendered {out.name}")
        md += [f"## Pin {i} — pin-ecs-{i}.png",
               f"**Title:** {title}",
               "",
               f"**Description:** {desc}",
               "",
               "**Link:** https://findhotstuff.com/automation/?ref=pin-ecs-ecs",
               ""]
    (OUT / "pins-ecs.md").write_text("\n".join(md), encoding="utf-8")
    print(f"wrote {OUT / 'pins-ecs.md'}")


if __name__ == "__main__":
    main()
