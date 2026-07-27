"""
Builds a ready-to-post TikTok photo pack from the current products.json:
eight 1080x1920 vertical slides (the top-trending products) plus paste-ready
captions, saved under marketing/tiktok/.

Slide layout keeps every critical element clear of TikTok's UI overlays —
the top ~150px, bottom ~250px, and outer ~10% of each side are treated as
unsafe, so text lives in the middle ~80% horizontally.

Everything degrades gracefully: a product whose photo won't download is
skipped and the next-ranked product backfills, so the pack still fills up and
the script always exits 0. Old slide-*.png are cleared on every run so a
refreshed catalog never leaves stale products behind.

Usage:
    python make_tiktok_pack.py   ->  writes marketing/tiktok/slide-*.png + captions.md
"""

import io
import json
from datetime import date
from pathlib import Path

from generate_posts import ad_name, price
from tweet_media import draw_flame

HERE = Path(__file__).parent
PRODUCTS_FILE = HERE / "products.json"
OUT_DIR = HERE / "marketing" / "tiktok"
SITE = "findhotstuff.com"

BG = "#191016"        # site background (dark plum-black)
ACCENT = "#e11d48"    # brand red (flame gradient start)
AMBER = "#f59e0b"     # flame gradient end / price color
INK = "#f7f2ee"       # near-white text on the dark bg
MUTED = "#a3958f"     # muted text on the dark bg

W, H = 1080, 1920     # TikTok vertical canvas
MARGIN = 108          # keep critical text inside the middle ~80% horizontally
SLIDES = 8

# bold/regular font locations on the GitHub runner (Ubuntu) and Windows
_FONTS = {
    True: ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
           r"C:\Windows\Fonts\arialbd.ttf"],
    False: ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            r"C:\Windows\Fonts\arial.ttf"],
}


def _font(size, bold=False):
    from PIL import ImageFont
    for path in _FONTS[bold]:
        try:
            return ImageFont.truetype(path, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _hex_rgb(color):
    color = color.lstrip("#")
    return tuple(int(color[i:i + 2], 16) for i in (0, 2, 4))


def _flame_gradient(size, radius=0):
    """Rose->amber horizontal gradient block; returns (image, paste mask)."""
    from PIL import Image, ImageDraw

    w, h = size
    c0, c1 = _hex_rgb(ACCENT), _hex_rgb(AMBER)
    block = Image.new("RGB", size)
    dr = ImageDraw.Draw(block)
    for x in range(w):
        t = x / max(1, w - 1)
        dr.line([(x, 0), (x, h)],
                fill=tuple(round(a + (b - a) * t) for a, b in zip(c0, c1)))
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1),
                                           radius=radius, fill=255)
    return block, mask


# ad_name()'s first-4-words fallback can end mid-phrase ("Dog Chew Toys For");
# trim dangling connector words so slide titles read clean.
_TRAILING_FILLER = {"for", "with", "and", "the", "in", "on", "of", "to"}


def slide_name(product):
    name = ad_name(product.get("name", ""), product.get("category", ""))
    words = name.split()
    while len(words) > 1 and words[-1].lower() in _TRAILING_FILLER:
        words.pop()
    return " ".join(words)


def _wrap_name(draw, text, max_width, size=58):
    """Wrap the name into at most 2 centered lines, shrinking until it fits."""
    while True:
        font = _font(size, True)
        lines, cur = [], ""
        for word in text.split():
            trial = f"{cur} {word}".strip()
            if draw.textlength(trial, font=font) <= max_width or not cur:
                cur = trial
            else:
                lines.append(cur)
                cur = word
        if cur:
            lines.append(cur)
        if len(lines) <= 2 or size <= 36:
            break
        size -= 4
    if len(lines) > 2:  # still too long at minimum size: keep 2, ellipsize
        lines = lines[:2]
        while draw.textlength(lines[1] + "…", font=font) > max_width and len(lines[1]) > 4:
            lines[1] = lines[1][:-2].rstrip()
        lines[1] += "…"
    return lines, font


def build_slide(product, rank):
    """Compose one vertical slide for a product. Returns PNG bytes (or raises)."""
    import requests
    from PIL import Image, ImageDraw

    # fetch the photo first — if this fails, the caller skips the whole slide
    resp = requests.get(product["image"], timeout=25)
    resp.raise_for_status()
    photo = Image.open(io.BytesIO(resp.content)).convert("RGB")

    canvas = Image.new("RGB", (W, H), BG)
    draw = ImageDraw.Draw(canvas)

    # header: flame + wordmark centered, just below TikTok's top overlay zone
    wm_font = _font(72, True)
    fh = 88
    group = fh * 0.84 + 16 + draw.textlength("HotsTuff", font=wm_font)
    hx = (W - group) // 2
    fw = draw_flame(draw, hx, 168, fh, core=BG)
    draw.text((hx + fw + 16, 182), "HotsTuff", font=wm_font, fill=ACCENT)

    # rank badge on the flame gradient
    badge = f"#{rank} TRENDING"
    badge_font = _font(40, True)
    bw = draw.textlength(badge, font=badge_font)
    pill_w, pill_h = int(bw) + 76, 76
    pill, pill_mask = _flame_gradient((pill_w, pill_h), radius=pill_h // 2)
    canvas.paste(pill, ((W - pill_w) // 2, 296), pill_mask)
    draw.text(((W - bw) // 2, 308), badge, font=badge_font, fill="#ffffff")

    # product photo large and centered on a white card (supplier photos are
    # shot on white — a deliberate card beats a floating white rectangle)
    card = (140, 420, 940, 1220)
    draw.rounded_rectangle(card, radius=48, fill="#ffffff")
    photo.thumbnail((card[2] - card[0] - 64, card[3] - card[1] - 64))
    canvas.paste(photo, (card[0] + (card[2] - card[0] - photo.width) // 2,
                         card[1] + (card[3] - card[1] - photo.height) // 2))

    # short ad name, max 2 centered lines
    lines, name_font = _wrap_name(draw, slide_name(product), W - 2 * MARGIN)
    y = 1280
    for line in lines:
        draw.text(((W - draw.textlength(line, font=name_font)) // 2, y),
                  line, font=name_font, fill=INK)
        y += 74

    # flame-gradient accent bar between name and price
    bar, bar_mask = _flame_gradient((320, 12), radius=6)
    canvas.paste(bar, ((W - 320) // 2, 1452), bar_mask)

    # price, big and amber
    tag = price(product)
    price_font = _font(112, True)
    draw.text(((W - draw.textlength(tag, font=price_font)) // 2, 1492),
              tag, font=price_font, fill=AMBER)

    # site line, kept clear of TikTok's bottom overlay zone (~250px)
    site_font = _font(38)
    draw.text(((W - draw.textlength(SITE, font=site_font)) // 2, 1616),
              SITE, font=site_font, fill=MUTED)

    buf = io.BytesIO()
    canvas.save(buf, format="PNG")
    return buf.getvalue()


# --- Captions --------------------------------------------------------------
# category -> TikTok-native hashtag, appended to the evergreen base tags
CAT_TAGS = {
    "Fashion": "#fashiontok",
    "Footwear": "#shoetok",
    "Beauty": "#beautytok",
    "Jewelry": "#jewelrytok",
    "Pet": "#petsoftiktok",
    "Electronics": "#techtok",
    "Kitchen": "#kitchengadgets",
    "Home": "#cozy",
    "Fitness": "#fittok",
    "Sports": "#fittok",
    "Auto": "#cartok",
    "Bags": "#bagtok",
    "Outdoor": "#outdoortok",
    "*": "#trendingfinds",
}
BASE_TAGS = "#tiktokmademebuyit #trending"


def _pack_tags(products):
    """Base tags + up to 3 category tags drawn from the featured products."""
    seen = []
    for p in products:
        tag = CAT_TAGS.get(p.get("category"), CAT_TAGS["*"])
        if tag not in seen:
            seen.append(tag)
    return " ".join([BASE_TAGS] + seen[:3])


def write_captions(products):
    """marketing/tiktok/captions.md — 3 paste-ready variants + posting notes."""
    tags = _pack_tags(products)
    top = products[0]["_ad"].lower()
    under = max(float(p["price"]) for p in products)
    variants = [
        ("Variant 1 — curiosity hook",
         f"ok this week's finds are actually unreal 👀 everything under ${under:.0f} {tags}"),
        ("Variant 2 — POV hook",
         f"POV: your fyp finally delivered 🔥 slide 1 is the {top} btw {tags}"),
        ("Variant 3 — ranked-list hook",
         f"ranked this week's trending finds so you don't have to 😮‍💨 which one are you grabbing {tags}"),
    ]

    L = []
    L.append("# HotsTuff — TikTok Photo Pack (auto-generated)\n")
    L.append(f"_Generated {date.today().isoformat()} · {len(products)} slides · "
             "post all slides as one TikTok photo (swipe) post._\n")
    L.append("\n## 🖼️ Slides\n")
    for i, p in enumerate(products, 1):
        L.append(f"{i}. `slide-{i:02d}.png` — {p['_ad']} — {price(p)} "
                 f"({p.get('category', 'Trending Finds')})")
    L.append("\n\n## 📝 Captions — pick one, paste as-is\n")
    for label, text in variants:
        L.append(f"**{label}**\n")
        L.append("```\n" + text + "\n```\n")
    L.append("> 🎵 Add a trending sound in-app before posting — photo posts "
             "ride the sound's reach.\n")
    L.append("\n_Post this pack within ~3 days: the catalog refreshes on that "
             "cycle and these slides regenerate with new products._\n")
    (OUT_DIR / "captions.md").write_text("\n".join(L), encoding="utf-8")


def build():
    products = json.loads(PRODUCTS_FILE.read_text(encoding="utf-8"))
    ranked = sorted(products, key=lambda x: x.get("trendScore", 0), reverse=True)
    candidates = [p for p in ranked if (p.get("image") or "").startswith("http")]
    for p in candidates:
        p["_ad"] = slide_name(p)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for stale in OUT_DIR.glob("slide-*.png"):  # never leave rotated-out products behind
        stale.unlink()

    made, skipped = [], []
    for p in candidates:
        if len(made) == SLIDES:
            break
        try:
            png = build_slide(p, len(made) + 1)
        except Exception as exc:  # noqa: BLE001 - one bad photo must never sink the pack
            print(f"skipped {p['_ad']} ({p.get('id', '?')}): {exc}")
            skipped.append(p)
            continue
        out = OUT_DIR / f"slide-{len(made) + 1:02d}.png"
        out.write_bytes(png)
        made.append(p)
        print(f"wrote {out.name} — {p['_ad']} "
              f"({p.get('category', '?')}, score {p.get('trendScore', 0)})")

    if made:
        write_captions(made)
    else:
        print("no slides generated — captions.md left untouched")
    print(f"Done: {len(made)} slides, {len(skipped)} skipped -> {OUT_DIR}")


if __name__ == "__main__":
    build()
