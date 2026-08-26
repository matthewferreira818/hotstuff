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


# ── Agent-pack story rotation ────────────────────────────────────────────
# The agent (East Coast Social) slides used to be byte-identical every day,
# which meant the same TikTok went out each evening — the fastest way to get
# an account throttled. Each day now draws a different story: its own hook,
# sub-line, receipts framing, closing pitch, and caption.
AGENT_STORIES = [
    {
        "hook": ("This store", "runs itself."),
        "sub": "no employees. nothing scheduled by hand.",
        "hint": "receipts →",
        "receipts": "what's on autopilot",
        "cta": ("your business page", "could run like this"),
        "caption": ("day in the life of a store with zero employees \U0001F916 everything you "
                    "just saw happened automatically. building this for local businesses now "
                    "#automation #smallbusiness #sidehustle #ai"),
    },
    {
        "hook": ("I haven't touched", "this store in days."),
        "sub": "it restocked and posted anyway.",
        "hint": "here's what it did →",
        "receipts": "while I was at work",
        "cta": ("imagine your page", "doing this daily"),
        "caption": ("I haven't opened this store in days and it still posted every day \U0001F916 "
                    "the whole thing runs on an engine I built — now setting it up for local "
                    "businesses #automation #smallbusiness #ai #sidehustle"),
    },
    {
        "hook": ("Zero employees.", "A post every single day."),
        "sub": "that's the whole business model.",
        "hint": "the math →",
        "receipts": "the numbers",
        "cta": ("your shop could", "post this often"),
        "caption": ("zero employees and this store still posts every single day \U0001F916 "
                    "the engine writes, designs and publishes on its own — building this for "
                    "local businesses now #smallbusiness #automation #ai #marketing"),
    },
    {
        "hook": ("What if your shop", "posted before you woke?"),
        "sub": "mine did. this morning. automatically.",
        "hint": "proof →",
        "receipts": "what ran this morning",
        "cta": ("this is the service", "not just my store"),
        "caption": ("what if your business page posted before you even woke up? \U0001F634 mine "
                    "did this morning — automatically. now building the same thing for local "
                    "shops #smallbusiness #automation #ai #localbusiness"),
    },
    {
        "hook": ("Most local pages", "went quiet in spring."),
        "sub": "this one hasn't missed a day.",
        "hint": "how →",
        "receipts": "the difference",
        "cta": ("keep your page alive", "without touching it"),
        "caption": ("most local business pages went quiet months ago \U0001F4A4 this one hasn't "
                    "missed a single day — because nobody has to remember. building it for "
                    "local businesses now #smallbusiness #socialmedia #automation #ai"),
    },
    {
        "hook": ("Nobody made", "this post."),
        "sub": "the engine did. like every other day.",
        "hint": "seriously →",
        "receipts": "made without me",
        "cta": ("your page, same deal", "you approve it once"),
        "caption": ("nobody made this post \U0001F916 the engine picked it, designed it and "
                    "published it — same as every other day this month. setting it up for "
                    "local businesses #automation #ai #smallbusiness #contentcreation"),
    },
]


def todays_agent_story():
    return AGENT_STORIES[date.today().toordinal() % len(AGENT_STORIES)]


def _lh_hint(draw, story):
    hint_font = _font(48, True)
    draw.text(((W - draw.textlength(story["hint"], font=hint_font)) // 2, 1560),
              story["hint"], font=hint_font, fill=GOLD)


def _lh_sub(draw, text, y, centered=True, size=44):
    f = _fit(draw, text, size, W - 2 * 90, bold=False)
    x = (W - draw.textlength(text, font=f)) // 2 if centered else 90
    draw.text((x, y), text, font=f, fill=FOG)


def _hook_centered(canvas, draw, story):
    """Treatment A — big centered claim over a gold haze."""
    _glow(canvas, W // 2, 210, 520)
    y = 600
    for line, colour in zip(story["hook"], (LH_INK, GOLD)):
        big = _fit(draw, line, 128, W - 2 * 90, loader=_serif)
        draw.text(((W - draw.textlength(line, font=big)) // 2, y), line, font=big, fill=colour)
        y += 152
    _lh_sub(draw, story["sub"], y + 40)


def _hook_left_rule(canvas, draw, story):
    """Treatment B — left-aligned with a gold rule, editorial feel."""
    draw.rectangle((90, 520, 90 + 180, 532), fill=GOLD)
    y = 600
    for line, colour in zip(story["hook"], (LH_INK, GOLD)):
        big = _fit(draw, line, 120, W - 2 * 90, loader=_serif)
        draw.text((90, y), line, font=big, fill=colour)
        y += 146
    _lh_sub(draw, story["sub"], y + 44, centered=False)


def _hook_panel(canvas, draw, story):
    """Treatment C — claim inside a raised navy panel."""
    _glow(canvas, W // 2, 900, 620)
    draw.rounded_rectangle((70, 520, W - 70, 1180), radius=44, fill=NAVY_2)
    y = 600
    for line, colour in zip(story["hook"], (LH_INK, GOLD)):
        big = _fit(draw, line, 112, W - 2 * 130, loader=_serif)
        draw.text(((W - draw.textlength(line, font=big)) // 2, y), line, font=big, fill=colour)
        y += 138
    _lh_sub(draw, story["sub"], y + 36, size=40)


HOOK_TREATMENTS = [_hook_centered, _hook_left_rule, _hook_panel]


def _lh_slide_hook():
    """Slide 1: the claim. Visual treatment rotates with the story so the
    pack changes shape, not just wording."""
    from PIL import Image, ImageDraw

    canvas = Image.new("RGB", (W, H), NAVY)
    draw = ImageDraw.Draw(canvas)
    _lh_header(draw, canvas)

    story = todays_agent_story()
    treatment = HOOK_TREATMENTS[date.today().toordinal() % len(HOOK_TREATMENTS)]
    treatment(canvas, draw, story)
    _lh_hint(draw, story)

    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    return buf.getvalue()


def _lh_slide_receipts(product_count, refreshed):
    """Slide 2: what the automation actually did — all true of this repo."""
    from PIL import Image, ImageDraw

    canvas = Image.new("RGB", (W, H), NAVY)
    draw = ImageDraw.Draw(canvas)
    _lh_header(draw, canvas)

    title = todays_agent_story()["receipts"]
    t_font = _fit(draw, title, 76, W - 2 * 90, loader=_serif)
    draw.text(((W - draw.textlength(title, font=t_font)) // 2, 330), title, font=t_font, fill=LH_INK)

    # a larger pool of TRUE claims, rotated so a different mix — and a
    # different first line — leads the slide each day. Every line here must
    # describe something the stack actually does today: no "3× a day on X"
    # while X posting waits on credits, no "every hour" when the reports run
    # every three. The website's proof copy already holds this bar (see the
    # 2026-08-13 council); the slides hold it too.
    claims = [
        "publishes a branded card every day",
        f"keeps {product_count} products live on the site",
        "refreshes the catalog every 3 days",
        "sends traffic reports every 3 hours",
        "writes its own captions and cards",
        "rebuilds the storefront on its own",
        "files an alert if anything breaks",
        "swaps out products when trends cool",
        "runs the site in two languages",
    ]
    shift = date.today().toordinal() % len(claims)
    rows = [claims[(shift + i) % len(claims)] for i in range(5)]
    rows.append("human hours required: zero")
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

    for i, (line, colour) in enumerate(zip(todays_agent_story()["cta"], (LH_INK, GOLD))):
        hook_font = _fit(draw, line, 68, W - 2 * 90, loader=_serif)
        draw.text(((W - draw.textlength(line, font=hook_font)) // 2, 340 + i * 92),
                  line, font=hook_font, fill=colour)

    qr_buf = io.BytesIO()
    # ?ref=tt-ecs: TikTok agent-pack scans, kept distinct from store scans
    segno.make(f"https://{SITE}/automation/?ref=tt-ecs", error="m").save(
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
    # categories make clean caption words; product-name first words are
    # often brand gibberish ("elecpow"). Dedupe in case both share one.
    cats = []
    for p in picks[:2]:
        c = (p.get("category") or p["_ad"].split()[0]).lower()
        if c not in cats:
            cats.append(c)
    # " finds" reads as a noun for a bare category ("jewelry finds"), but
    # the catch-all category is literally "Trending Finds" — appending it
    # there produced "trending finds finds" in a public caption.
    solo = len(cats) == 1 and not cats[0].endswith("finds")
    tag_items = " + ".join(cats) + (" finds" if solo else "")
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
        todays_agent_story()["caption"],
        "```\n",
        "> \U0001F3B5 Add a trending sound to each in-app. Product post: upbeat. "
        "Agent post: something calm/lofi reads as 'systems humming'.\n",
    ]
    (DAILY_DIR / "captions.md").write_text("\n".join(L), encoding="utf-8")


def build_daily():
    products = json.loads((HERE / "products.json").read_text(encoding="utf-8"))

    for d in (PRODUCT_DIR, AGENT_DIR):
        d.mkdir(parents=True, exist_ok=True)
        for stale in list(d.glob("*.png")) + list(d.glob("*.jpg")):
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
    _write_jpeg_twins()
    print(f"Done → {DAILY_DIR}")


def _write_jpeg_twins():
    """JPEG copy of every slide: TikTok's photo API rejects PNG
    (file_format_check_failed), so the draft pusher pulls the .jpg twins.
    The .png versions stay for humans and manual posting."""
    from PIL import Image
    for d in (PRODUCT_DIR, AGENT_DIR):
        for stale in d.glob("*.jpg"):
            stale.unlink()
        for png in sorted(d.glob("*.png")):
            Image.open(png).convert("RGB").save(
                png.with_suffix(".jpg"), quality=92, optimize=True)
    print("wrote JPEG twins for the TikTok draft pusher")


if __name__ == "__main__":
    build_daily()
