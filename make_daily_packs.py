"""
Builds the two daily TikTok posts under marketing/tiktok/daily/:

  product/  - 3-slide mini-pack of today's featured products + QR closer,
              in the HotsTuff flame identity. The pick rotates by date so
              each day of a 3-day catalog cycle features different items.
  agent/    - 3-slide "the store ran itself today" pack in the East Coast Social
              navy/gold identity, ending on a QR to /automation — the daily
              ad for the automation business.

Every claim on the agent slides is true of this repo's real automation:
3 X posts daily, full catalog re-curation every 3 days, hourly uptime
checks. Captions for both packs land in daily/captions.md.

Usage:
    python make_daily_packs.py
"""

import io
import json
from datetime import date
from pathlib import Path

from make_tiktok_pack import (
    ACCENT, AMBER, BG, INK, MUTED, SITE, W, H,
    _flame_gradient, _font, build_slide, slide_name,
)
from generate_posts import price
from tweet_media import draw_flame

HERE = Path(__file__).parent
DAILY_DIR = HERE / "marketing" / "tiktok" / "daily"
PRODUCT_DIR = DAILY_DIR / "product"
AGENT_DIR = DAILY_DIR / "agent"

DAILY_COUNT = 3

# East Coast Social identity (matches automation/index.html)
NAVY = "#0d1f33"
NAVY_2 = "#14304d"
GOLD = "#f0b429"
FOG = "#a8bccf"
LH_INK = "#f2f6fa"


def _pick_daily(products):
    """3 products for today, rotating by date so consecutive days differ.
    Deduped by ad name (CJ sometimes double-lists one product)."""
    ranked = sorted(products, key=lambda x: x.get("trendScore", 0), reverse=True)
    usable, seen = [], set()
    for p in ranked:
        if not (p.get("image") or "").startswith("http"):
            continue
        key = slide_name(p).lower()
        if key in seen:
            continue
        seen.add(key)
        p["_ad"] = slide_name(p)
        usable.append(p)
    if not usable:
        return []
    start = (date.today().toordinal() * DAILY_COUNT) % len(usable)
    return [usable[(start + i) % len(usable)] for i in range(min(DAILY_COUNT, len(usable)))]


SERIF_FONTS = {
    True: ["/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
           r"C:\\Windows\\Fonts\\georgiab.ttf"],
    False: ["/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf",
            r"C:\\Windows\\Fonts\\georgia.ttf"],
}


def _serif(size, bold=False):
    from PIL import ImageFont
    for path in SERIF_FONTS[bold]:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return _font(size, bold)  # sans fallback


def _fit(draw, text, size, max_width, loader=None, bold=True):
    """Largest font (from `size` down) at which text fits max_width."""
    loader = loader or _font
    while size > 24:
        f = loader(size, bold)
        if draw.textlength(text, font=f) <= max_width:
            return f
        size -= 2
    return loader(24, bold)


def _glow(canvas, cx, cy, radius):
    """Soft gold radial glow, like the beam haze on the automation page."""
    from PIL import Image, ImageDraw
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    steps = 36
    for i in range(steps, 0, -1):
        r = radius * i / steps
        alpha = int(26 * (1 - i / steps) ** 2) + 2
        od.ellipse((cx - r, cy - r * 0.62, cx + r, cy + r * 0.62),
                   fill=(240, 180, 41, alpha))
    canvas.paste(Image.alpha_composite(canvas.convert("RGBA"), overlay).convert("RGB"), (0, 0))


def _lh_header(draw, canvas):
    """Gold beacon dot + EAST COAST SOCIAL wordmark, centered."""
    from PIL import ImageDraw  # noqa: F401 - parity with sibling builders

    wm_font = _font(52, True)
    label = "EAST COAST SOCIAL"
    lw = draw.textlength(label, font=wm_font)
    x = (W - (lw + 40)) // 2
    draw.ellipse((x, 196, x + 22, 218), fill=GOLD)
    draw.text((x + 40, 182), label, font=wm_font, fill=GOLD)


def _lh_slide_hook():
    """Slide 1: the claim."""
    from PIL import Image, ImageDraw

    canvas = Image.new("RGB", (W, H), NAVY)
    draw = ImageDraw.Draw(canvas)
    _lh_header(draw, canvas)

    _glow(canvas, W // 2, 210, 520)

    y = 600
    for line, colour in (("This store", LH_INK), ("runs itself.", GOLD)):
        big = _fit(draw, line, 128, W - 2 * 90, loader=_serif)
        draw.text(((W - draw.textlength(line, font=big)) // 2, y), line, font=big, fill=colour)
        y += 152

    sub = "no employees. nothing scheduled by hand."
    sub_font = _fit(draw, sub, 44, W - 2 * 90, bold=False)
    draw.text(((W - draw.textlength(sub, font=sub_font)) // 2, y + 40), sub, font=sub_font, fill=FOG)

    hint = "receipts →"
    hint_font = _font(48, True)
    draw.text(((W - draw.textlength(hint, font=hint_font)) // 2, 1560), hint, font=hint_font, fill=GOLD)

    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    return buf.getvalue()


def _lh_slide_receipts(product_count, refreshed):
    """Slide 2: what the automation actually did — all true of this repo."""
    from PIL import Image, ImageDraw

    canvas = Image.new("RGB", (W, H), NAVY)
    draw = ImageDraw.Draw(canvas)
    _lh_header(draw, canvas)

    title = "what's on autopilot"
    t_font = _fit(draw, title, 76, W - 2 * 90, loader=_serif)
    draw.text(((W - draw.textlength(title, font=t_font)) // 2, 330), title, font=t_font, fill=LH_INK)

    rows = [
        "posts on X three times a day",
        f"keeps {product_count} products live on the site",
        f"refreshes the catalog every 3 days",
        "checks the site's pulse every hour",
        "human hours required: zero",
    ]
    y = 560
    text_left, text_right_pad = 200, 40
    max_text_w = (W - 90) - text_left - text_right_pad
    for text in rows:
        card_h = 150
        row_font = _fit(draw, text, 42, max_text_w)
        draw.rounded_rectangle((90, y, W - 90, y + card_h), radius=24, fill=NAVY_2)
        draw.ellipse((140, y + 64, 162, y + 86), fill=GOLD)
        row_h = row_font.size
        draw.text((text_left, y + (card_h - row_h) // 2 - 6), text, font=row_font, fill=LH_INK)
        y += card_h + 26

    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    return buf.getvalue()


def _lh_slide_cta():
    """Slide 3: the pitch + QR straight to the automation page."""
    import segno
    from PIL import Image, ImageDraw

    canvas = Image.new("RGB", (W, H), NAVY)
    draw = ImageDraw.Draw(canvas)
    _lh_header(draw, canvas)

    for i, (line, colour) in enumerate((("your business page", LH_INK), ("could run like this", GOLD))):
        hook_font = _fit(draw, line, 68, W - 2 * 90, loader=_serif)
        draw.text(((W - draw.textlength(line, font=hook_font)) // 2, 340 + i * 92),
                  line, font=hook_font, fill=colour)

    qr_buf = io.BytesIO()
    segno.make(f"https://{SITE}/automation/", error="m").save(
        qr_buf, kind="png", scale=22, border=2, dark="#111111", light="#ffffff")
    qr = Image.open(qr_buf).convert("RGB")
    if qr.width > 560:
        qr = qr.resize((560, 560), Image.NEAREST)
    card_w = qr.width + 88
    card_x = (W - card_w) // 2
    draw.rounded_rectangle((card_x, 600, card_x + card_w, 600 + card_w), radius=44, fill="#ffffff")
    canvas.paste(qr, ((W - qr.width) // 2, 600 + 44))

    for i, sub in enumerate(["setup in a week · you approve the voice", "no contracts · cancel anytime"]):
        sub_font = _fit(draw, sub, 34, W - 2 * 100, bold=False)
        draw.text(((W - draw.textlength(sub, font=sub_font)) // 2, 1310 + i * 52),
                  sub, font=sub_font, fill=FOG)

    site_font = _font(52, True)
    line = f"{SITE}/automation"
    draw.text(((W - draw.textlength(line, font=site_font)) // 2, 1420), line, font=site_font, fill=GOLD)

    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    return buf.getvalue()


def _refreshed_text(products_file):
    """Human phrase for when products.json last changed, from its mtime."""
    from datetime import datetime, timezone
    age_days = (datetime.now(timezone.utc) -
                datetime.fromtimestamp(products_file.stat().st_mtime, tz=timezone.utc)).days
    if age_days <= 0:
        return "this morning"
    if age_days == 1:
        return "yesterday"
    return f"{age_days} days ago"


def _write_captions(picks):
    tag_items = " + ".join(p["_ad"].split()[0].lower() for p in picks[:2])
    L = [
        "# Daily TikTok posts (auto-generated)\n",
        f"_Generated {date.today().isoformat()} · post PRODUCT in the daytime, AGENT in the evening._\n",
        "\n## \U0001F525 Product post (product/) — caption\n",
        "```",
        f"today's heat check \U0001F525 {tag_items} and more — all under one link "
        "#tiktokmademebuyit #trending #dailyfinds",
        "```\n",
        "\n## \U0001F5FC Agent post (agent/) — caption\n",
        "```",
        "day in the life of a store with zero employees \U0001F916 everything you "
        "just saw happened automatically. building this for local businesses now "
        "#automation #smallbusiness #sidehustle #ai",
        "```\n",
        "> \U0001F3B5 Add a trending sound to each in-app. Product post: upbeat. "
        "Agent post: something calm/lofi reads as 'systems humming'.\n",
    ]
    (DAILY_DIR / "captions.md").write_text("\n".join(L), encoding="utf-8")


def build_daily():
    products = json.loads((HERE / "products.json").read_text(encoding="utf-8"))

    for d in (PRODUCT_DIR, AGENT_DIR):
        d.mkdir(parents=True, exist_ok=True)
        for stale in d.glob("*.png"):
            stale.unlink()

    picks = _pick_daily(products)
    made = []
    for i, p in enumerate(picks, 1):
        try:
            (PRODUCT_DIR / f"product-{i}.png").write_bytes(build_slide(p, i))
            made.append(p)
            print(f"wrote product-{i}.png — {p['_ad']} ({price(p)})")
        except Exception as exc:  # noqa: BLE001 - a bad photo must not sink the pack
            print(f"skipped {p['_ad']}: {exc}")

    from make_tiktok_pack import build_qr_slide
    try:
        (PRODUCT_DIR / "product-4-qr.png").write_bytes(build_qr_slide(len(made)))
        print("wrote product-4-qr.png — QR closer")
    except Exception as exc:  # noqa: BLE001
        print(f"skipped product QR slide: {exc}")

    refreshed = _refreshed_text(HERE / "products.json")
    (AGENT_DIR / "agent-1.png").write_bytes(_lh_slide_hook())
    (AGENT_DIR / "agent-2.png").write_bytes(_lh_slide_receipts(len(products), refreshed))
    (AGENT_DIR / "agent-3.png").write_bytes(_lh_slide_cta())
    print("wrote agent-1..3.png — East Coast Social receipts pack")

    _write_captions(made if made else picks)
    print(f"Done → {DAILY_DIR}")


if __name__ == "__main__":
    build_daily()
