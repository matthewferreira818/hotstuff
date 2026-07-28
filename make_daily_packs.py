"""
Builds the two daily TikTok posts under marketing/tiktok/daily/:

  product/  - 3-slide mini-pack of today's featured products + QR closer,
              in the HotsTuff flame identity. The pick rotates by date so
              each day of a 3-day catalog cycle features different items.
  agent/    - 3-slide "the store ran itself today" pack in the Lighthouse
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

# Lighthouse Social identity (matches automation/index.html)
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


def _lh_header(draw, canvas):
    """Gold beacon dot + LIGHTHOUSE SOCIAL wordmark, centered."""
    from PIL import ImageDraw  # noqa: F401 - parity with sibling builders

    wm_font = _font(52, True)
    label = "LIGHTHOUSE SOCIAL"
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

    lines = ["This store ran", "itself today."]
    y = 620
    big = _font(110, True)
    for line in lines:
        draw.text(((W - draw.textlength(line, font=big)) // 2, y), line, font=big, fill=LH_INK)
        y += 132

    sub = "no employee posted. no one scheduled anything."
    sub_font = _font(44)
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

    title = "today's receipts"
    t_font = _font(72, True)
    draw.text(((W - draw.textlength(title, font=t_font)) // 2, 330), title, font=t_font, fill=LH_INK)

    rows = [
        "posted on X 3x, on schedule",
        f"kept {product_count} products live on the site",
        f"catalog refreshed {refreshed}",
        "checked the site every hour",
        "human hours required: zero",
    ]
    y = 560
    row_font = _font(42, True)
    for text in rows:
        card_h = 150
        draw.rounded_rectangle((90, y, W - 90, y + card_h), radius=24, fill=NAVY_2)
        draw.ellipse((140, y + 64, 162, y + 86), fill=GOLD)
        draw.text((200, y + 52), text, font=row_font, fill=LH_INK)
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

    hook_font = _font(64, True)
    for i, line in enumerate(["your business page", "could run like this"]):
        draw.text(((W - draw.textlength(line, font=hook_font)) // 2, 350 + i * 84),
                  line, font=hook_font, fill=LH_INK)

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

    sub_font = _font(34)
    for i, sub in enumerate(["setup in a week · you approve the voice", "no contracts · cancel anytime"]):
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
    print("wrote agent-1..3.png — Lighthouse receipts pack")

    _write_captions(made if made else picks)
    print(f"Done → {DAILY_DIR}")


if __name__ == "__main__":
    build_daily()
