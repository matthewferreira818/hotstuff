"""
Pinterest pin pack: 1000x1500 (2:3) product pins from the live catalog, in
the HotsTuff flame identity. Picks top trending products (max 2 per category
for variety), renders a pin for each, and writes pins.md with ready-to-paste
titles, descriptions, and the destination link for each upload.

Output: marketing/pinterest/pin-N.png + pins.md

Usage: python make_pinterest_pins.py
"""

import json
from pathlib import Path

from make_tiktok_pack import ACCENT, AMBER, BG, _flame_gradient, _font, slide_name
from tweet_media import draw_flame

HERE = Path(__file__).parent
OUT = HERE / "marketing" / "pinterest"
W, H = 1000, 1500
PIN_COUNT = 10
SITE = "findhotstuff.com"
INK_L, MUTED = "#f7f2ee", "#a3958f"


def pick_products():
    ps = json.loads((HERE / "products.json").read_text())
    ps = [p for p in ps if p.get("image")]
    ps.sort(key=lambda p: -p.get("trendScore", 0))
    picked, per_cat, seen_names = [], {}, set()
    for p in ps:
        cat = p.get("category", "?")
        name = slide_name(p)
        if per_cat.get(cat, 0) >= 2 or name in seen_names:
            continue
        per_cat[cat] = per_cat.get(cat, 0) + 1
        seen_names.add(name)
        picked.append(p)
        if len(picked) == PIN_COUNT:
            break
    return picked


def build_pin(p, n):
    import io
    import requests
    from PIL import Image, ImageDraw

    resp = requests.get(p["image"], timeout=25)
    resp.raise_for_status()
    photo = Image.open(io.BytesIO(resp.content)).convert("RGB")

    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)

    # header: flame + wordmark
    wm_f = _font(54, True)
    fh = 64
    group = int(fh * 0.84 + 14 + d.textlength("HotsTuff", font=wm_f))
    hx = (W - group) // 2
    fw = draw_flame(d, hx, 42, fh, core=BG)
    d.text((hx + fw + 14, 52), "HotsTuff", font=wm_f, fill=ACCENT)

    # product photo on a white card
    card = (60, 150, W - 60, 1010)
    d.rounded_rectangle(card, radius=40, fill="#ffffff")
    photo.thumbnail((card[2] - card[0] - 60, card[3] - card[1] - 60))
    img.paste(photo, (card[0] + (card[2] - card[0] - photo.width) // 2,
                      card[1] + (card[3] - card[1] - photo.height) // 2))

    # name (up to 2 centered lines)
    name = slide_name(p)
    nf = _font(56, True)
    words, lines, cur = name.split(), [], ""
    for w_ in words:
        t = f"{cur} {w_}".strip()
        if d.textlength(t, font=nf) <= W - 140 or not cur:
            cur = t
        else:
            lines.append(cur)
            cur = w_
    lines.append(cur)
    y = 1060
    for line in lines[:2]:
        d.text(((W - d.textlength(line, font=nf)) // 2, y), line, font=nf, fill=INK_L)
        y += 70

    # price pill on the flame gradient
    price = f"${p['price']}"
    pf = _font(64, True)
    pw = d.textlength(price, font=pf)
    pill_w, pill_h = int(pw) + 90, 96
    pill, mask = _flame_gradient((pill_w, pill_h), radius=pill_h // 2)
    py = y + 26
    img.paste(pill, ((W - pill_w) // 2, py), mask)
    d.text(((W - pw) // 2, py + 10), price, font=pf, fill="#ffffff")

    # footer
    d.text(((W - d.textlength(SITE, font=_font(44, True))) // 2, H - 130),
           SITE, font=_font(44, True), fill=AMBER)
    tail = "new drops every 3 days · free shipping"
    d.text(((W - d.textlength(tail, font=_font(30, False))) // 2, H - 68),
           tail, font=_font(30, False), fill=MUTED)

    img.save(OUT / f"pin-{n}.png")
    return name


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    picked = pick_products()
    entries = []
    for i, p in enumerate(picked, 1):
        try:
            name = build_pin(p, i)
        except Exception as exc:  # noqa: BLE001 - skip broken photos, keep the pack
            print(f"pin {i} skipped ({p.get('name', '?')[:30]}): {exc}")
            continue
        entries.append(
            f"## pin-{i}.png\n"
            f"- **Title:** {name} — Trending Now\n"
            f"- **Description:** {p.get('description', '')} Only ${p['price']} at "
            f"HotsTuff — a fresh drop of trending finds every 3 days, free shipping. "
            f"#{p.get('category', 'trending').replace(' ', '').lower()} #trendingproducts #onlinefinds\n"
            f"- **Link:** https://findhotstuff.com/\n")
        print(f"pin-{i}.png — {name} (${p['price']})")
    (OUT / "pins.md").write_text(
        "# Pinterest upload pack\n\n_Upload each pin with its title, description, "
        "and link below. Board suggestion: \"Trending Finds\"._\n\n" + "\n".join(entries),
        encoding="utf-8")
    print(f"{len(entries)} pins -> {OUT}")


if __name__ == "__main__":
    main()
