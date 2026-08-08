"""
Print materials for East Coast Social: a letter-size flyer (with tear-off
tabs for community boards) and a two-sided business card, all at 300 DPI in
the navy/gold identity from automation/index.html.

Outputs to marketing/east-coast-social/print/:
    flyer.png / flyer.pdf                 (2550x3300 - US letter)
    card-front.png / card-back.png        (1050x600 - 3.5x2 in)
    business-card.pdf                     (front + back, two pages)

Usage:
    python make_print_materials.py
"""

import io
from pathlib import Path

from make_daily_packs import _font, _serif
from tweet_media import draw_flame  # noqa: F401 - kept for future co-branding

HERE = Path(__file__).parent
OUT = HERE / "marketing" / "east-coast-social" / "print"

NAVY = "#0d1f33"
NAVY_2 = "#14304d"
NAVY_3 = "#1d4266"
GOLD = "#f0b429"
INK = "#16283c"
PAPER = "#ffffff"
FOG = "#5b7089"
LIGHT = "#f2f6fa"
PANEL = "#eef4fa"

AUTOMATION_URL = "https://eastcoastsocial.ca/"   # redirects to the automation page
PHONE = "(506) 889-9737"
EMAIL = "hello@eastcoastsocial.ca"
SITE_LINE = "eastcoastsocial.ca"


def _rgb(hexcolor):
    h = hexcolor.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def fit(draw, text, size, max_width, loader=_font, bold=True):
    while size > 20:
        f = loader(size, bold)
        if draw.textlength(text, font=f) <= max_width:
            return f
        size -= 4
    return loader(20, bold)


def centered(draw, text, y, font, fill, width):
    draw.text(((width - draw.textlength(text, font=font)) // 2, y), text, font=font, fill=fill)


def v_gradient(draw, box, c_top, c_bottom):
    """Vertical gradient fill inside box (x0, y0, x1, y1)."""
    x0, y0, x1, y1 = box
    top, bot = _rgb(c_top), _rgb(c_bottom)
    span = max(1, y1 - y0)
    for y in range(y0, y1):
        t = (y - y0) / span
        col = tuple(int(top[i] + (bot[i] - top[i]) * t) for i in range(3))
        draw.line((x0, y, x1, y), fill=col)


def radial_glow(img, center, radius, color=GOLD, peak_alpha=70, steps=48):
    """Soft radial glow pasted onto img (RGB) at center."""
    from PIL import Image, ImageDraw
    overlay = Image.new("RGBA", (radius * 2, radius * 2), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    r, g, b = _rgb(color)
    for i in range(steps):
        t = i / steps                       # 0 outer -> 1 inner
        rr = int(radius * (1 - t))
        a = int(peak_alpha * t * t)
        od.ellipse((radius - rr, radius - rr, radius + rr, radius + rr), fill=(r, g, b, a))
    img.paste(overlay, (center[0] - radius, center[1] - radius), overlay)


def dot_grid(img, box, color=GOLD, alpha=42, step=56, dot_r=4):
    """Faint dot pattern inside box, pasted with alpha."""
    from PIL import Image, ImageDraw
    x0, y0, x1, y1 = box
    overlay = Image.new("RGBA", (x1 - x0, y1 - y0), (0, 0, 0, 0))
    od = ImageDraw.Draw(overlay)
    r, g, b = _rgb(color)
    for yy in range(step // 2, y1 - y0, step):
        for xx in range(step // 2, x1 - x0, step):
            od.ellipse((xx - dot_r, yy - dot_r, xx + dot_r, yy + dot_r), fill=(r, g, b, alpha))
    img.paste(overlay, (x0, y0), overlay)


def logo_badge(size):
    """Circular crop of the ECS logo (fb-logo.png, sunrise motif) + its paste mask."""
    from PIL import Image, ImageDraw
    logo = Image.open(HERE / "marketing" / "east-coast-social" / "fb-logo.png").convert("RGB")
    crop = logo.crop((92, 100, 932, 940)).resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    return crop, mask


def qr_image(size, url=AUTOMATION_URL + "?ref=print"):
    import segno
    from PIL import Image
    buf = io.BytesIO()
    segno.make(url, error="m").save(buf, kind="png", scale=20, border=2,
                                    dark="#111111", light="#ffffff")
    qr = Image.open(buf).convert("RGB")
    return qr.resize((size, size), Image.NEAREST)


def corner_brackets(d, box, length=70, width=12, color=GOLD):
    """Gold L-shaped marks on the four corners of box."""
    x0, y0, x1, y1 = box
    for cx, cy, dx, dy in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
        d.line((cx, cy, cx + dx * length, cy), fill=color, width=width)
        d.line((cx, cy, cx, cy + dy * length), fill=color, width=width)


def make_flyer():
    """Letter flyer: gradient header with diagonal cut, glow hero, panel rows,
    pricing ribbon, bracketed QR card, tear-off tabs."""
    from PIL import Image, ImageDraw

    W, H = 2550, 3300
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)

    # --- header band: gradient + texture + glow, diagonal bottom edge ---
    band_h = 1150
    v_gradient(d, (0, 0, W, band_h + 60), NAVY, NAVY_2)
    dot_grid(img, (0, 0, 760, 420))
    dot_grid(img, (W - 760, band_h - 420, W, band_h))
    radial_glow(img, (W // 2, 440), 720, peak_alpha=60)

    label_f = _font(72, True)
    label = "EAST COAST SOCIAL"
    lw = d.textlength(label, font=label_f)
    badge, gap = 200, 44
    bx = int((W - (badge + gap + lw)) // 2)
    by = 60
    crop, mask = logo_badge(badge)
    img.paste(crop, (bx, by), mask)
    d.ellipse((bx, by, bx + badge, by + badge), outline=GOLD, width=8)
    d.text((bx + badge + gap, by + 58), label, font=label_f, fill=GOLD)

    hero1 = fit(d, "Your business posts every day.", 150, W - 300, loader=_serif)
    centered(d, "Your business posts every day.", 300, hero1, LIGHT, W)
    hero2 = fit(d, "You don't lift a finger.", 150, W - 300, loader=_serif)
    centered(d, "You don't lift a finger.", 500, hero2, GOLD, W)

    sub = "Done-for-you social media for local businesses"
    sub2 = "Sackville · Memramcook · the greater Moncton area"
    centered(d, sub, 760, fit(d, sub, 64, W - 400, bold=False), LIGHT, W)
    centered(d, sub2, 870, fit(d, sub2, 54, W - 400, bold=False), "#a8bccf", W)

    # diagonal cut: carve the paper back in, then a gold edge line
    d.polygon(((0, band_h - 100), (W, band_h), (W, band_h + 80), (0, band_h + 80)), fill=PAPER)
    d.line((0, band_h - 100, W, band_h), fill=GOLD, width=12)

    # --- body: what you get (accent-bar panels) ---
    head = "WHAT YOU GET"
    hf = _font(46, True)
    hw = d.textlength(head, font=hf)
    hx = (W - (hw + 48)) // 2
    d.ellipse((hx, band_h + 62, hx + 26, band_h + 88), fill=GOLD)
    d.text((hx + 48, band_h + 48), head, font=hf, fill=NAVY)

    rows = [
        "Your page posts every single day — in your voice, with your photos",
        "Branded picture posts with QR codes to your menu or booking page",
        "Content refreshes itself, so your feed never goes quiet again",
        "A local human keeps watch — you get one simple monthly summary",
    ]
    # one shared size so all rows match: fit the longest row, use it everywhere
    row_f = min((fit(d, t, 58, W - 520) for t in rows), key=lambda f: f.size)
    y = band_h + 170
    for text in rows:
        d.rounded_rectangle((150, y - 22, W - 150, y + 92), radius=26, fill=PANEL)
        d.rounded_rectangle((150, y - 22, 174, y + 92), radius=10, fill=GOLD)
        d.text((250, y), text, font=row_f, fill=INK)
        y += 132

    # --- pricing ribbon (full-bleed navy band) ---
    y += 10
    rib_h = 130
    v_gradient(d, (0, y, W, y + rib_h), NAVY_2, NAVY)
    price = "Free setup  ·  $79/month  ·  no contracts, cancel anytime"
    pf = fit(d, price, 72, W - 560, loader=_serif)
    pw = d.textlength(price, font=pf)
    centered(d, price, y + 24, pf, GOLD, W)
    for sx in ((W - pw) // 2 - 90, (W + pw) // 2 + 90):
        cy = y + rib_h // 2
        d.polygon(((sx, cy - 22), (sx + 22, cy), (sx, cy + 22), (sx - 22, cy)), fill=GOLD)
    y += rib_h + 24
    proof = "See it running live — my own store has posted 3x a day for months, untouched:"
    centered(d, proof, y, fit(d, proof, 48, W - 360, bold=False), FOG, W)

    # --- QR card with gold corner brackets ---
    qy = y + 92
    box = 520
    bx0, bx1 = (W - box) // 2, (W + box) // 2
    d.rounded_rectangle((bx0 + 10, qy + 14, bx1 + 10, qy + box + 14), radius=40, fill="#dbe4ee")
    d.rounded_rectangle((bx0, qy, bx1, qy + box), radius=40, fill=PAPER, outline=NAVY, width=6)
    corner_brackets(d, (bx0 - 26, qy - 26, bx1 + 26, qy + box + 26))
    qr = qr_image(440)
    img.paste(qr, ((W - 440) // 2, qy + 40))
    qy += box + 42
    centered(d, SITE_LINE, qy, _font(64, True), NAVY, W)
    qy += 84
    contact = f"Matthew Ferreira  ·  {PHONE}  ·  {EMAIL}"
    centered(d, contact, qy, fit(d, contact, 52, W - 300, bold=False), INK, W)

    # --- tear-off tabs on a light strip ---
    from PIL import Image as Im
    tab_top = H - 460
    d.rectangle((0, tab_top, W, H), fill=LIGHT)
    d.line((0, tab_top, W, tab_top), fill=GOLD, width=8)
    n = 8
    tab_w = W // n
    tab_text_img = Im.new("RGB", (420, tab_w - 40), LIGHT)
    td = ImageDraw.Draw(tab_text_img)
    td.text((16, 8), "East Coast Social", font=fit(td, "East Coast Social", 40, 388), fill=NAVY)
    td.text((16, 68), PHONE, font=fit(td, PHONE, 40, 388, bold=False), fill=INK)
    td.text((16, 128), SITE_LINE, font=fit(td, SITE_LINE, 30, 388, bold=False), fill=FOG)
    tab_rot = tab_text_img.rotate(90, expand=True)
    for i in range(n):
        x = i * tab_w
        if i:  # dashed cut lines between tabs
            for yy in range(tab_top + 10, H - 10, 36):
                d.line((x, yy, x, yy + 18), fill=FOG, width=3)
        img.paste(tab_rot, (x + 20, tab_top + 20))

    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / "flyer.png")
    img.save(OUT / "flyer.pdf", resolution=300)
    print("flyer done")


def make_cards():
    from PIL import Image, ImageDraw

    W, H = 1050, 600

    # --- front: gradient navy with gold corner accents ---
    front = Image.new("RGB", (W, H), NAVY)
    d = ImageDraw.Draw(front)
    v_gradient(d, (0, 0, W, H), NAVY, NAVY_3)
    dot_grid(front, (0, 0, 400, 240), alpha=36, step=44, dot_r=3)
    radial_glow(front, (W // 2, 215), 300, peak_alpha=55)

    # top-right gold corner + echo line
    d.polygon(((W, 0), (W - 210, 0), (W, 210)), fill=GOLD)
    d.line((W - 270, 0, W, 270), fill=GOLD, width=6)
    # bottom-left soft corner + echo line
    d.polygon(((0, H), (0, H - 170), (170, H)), fill=NAVY_2)
    d.line((0, H - 110, 110, H), fill=GOLD, width=6)

    label_f = _font(40, True)
    label = "EAST COAST SOCIAL"
    lw = d.textlength(label, font=label_f)
    badge, gap = 96, 24
    bx = int((W - (badge + gap + lw)) // 2)
    by = 34
    crop, mask = logo_badge(badge)
    front.paste(crop, (bx, by), mask)
    d.ellipse((bx, by, bx + badge, by + badge), outline=GOLD, width=5)
    d.text((bx + badge + gap, by + 24), label, font=label_f, fill=GOLD)

    tag1 = fit(d, "Social media that", 64, W - 160, loader=_serif)
    centered(d, "Social media that", 170, tag1, LIGHT, W)
    centered(d, "runs itself.", 255, fit(d, "runs itself.", 64, W - 160, loader=_serif), GOLD, W)

    centered(d, "Matthew Ferreira", 390, _font(40, True), LIGHT, W)
    centered(d, PHONE + "  ·  " + EMAIL, 455, fit(d, PHONE + "  ·  " + EMAIL, 30, W - 140, bold=False), "#a8bccf", W)
    centered(d, SITE_LINE, 510, _font(32, True), GOLD, W)
    front.save(OUT / "card-front.png")

    # --- back: white, navy frame, gold corner ticks, QR ---
    back = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(back)
    d.rounded_rectangle((26, 26, W - 26, H - 26), radius=24, outline=NAVY, width=6)
    corner_brackets(d, (26, 26, W - 26, H - 26), length=46, width=10)
    qr = qr_image(350)
    back.paste(qr, ((W - 350) // 2, 70))
    d.rectangle(((W - 240) // 2, 462, (W + 240) // 2, 470), fill=GOLD)
    centered(d, "see it running → " + SITE_LINE, 498, fit(d, "see it running → " + SITE_LINE, 34, W - 160), NAVY, W)
    back.save(OUT / "card-back.png")

    front.save(OUT / "business-card.pdf", resolution=300, save_all=True, append_images=[back])
    print("cards done")


def gradient_pill(img, box, text, font):
    """Gold horizontal-gradient pill with navy text — the store's badge style."""
    from PIL import Image, ImageDraw
    x0, y0, x1, y1 = box
    w, h = x1 - x0, y1 - y0
    pill = Image.new("RGB", (w, h), GOLD)
    pd = ImageDraw.Draw(pill)
    left, right = _rgb("#ffd166"), _rgb("#f0a020")
    for x in range(w):
        t = x / max(1, w)
        col = tuple(int(left[i] + (right[i] - left[i]) * t) for i in range(3))
        pd.line((x, 0, x, h), fill=col)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h - 1), radius=h // 2, fill=255)
    img.paste(pill, (x0, y0), mask)
    if text:
        d = ImageDraw.Draw(img)
        tw = d.textlength(text, font=font)
        d.text((x0 + (w - tw) // 2, y0 + (h - int(font.size * 1.35)) // 2), text, font=font, fill=NAVY)


def tear_tabs(img, d, W, H, l1="East Coast Social", l2=PHONE, l3=SITE_LINE,
              l1_fill=NAVY, l2_fill=INK, l3_fill=FOG, strip=LIGHT, accent=GOLD):
    """Tear-off tab strip with dashed cut lines (shared by all flyers)."""
    from PIL import Image as Im, ImageDraw
    tab_top = H - 460
    d.rectangle((0, tab_top, W, H), fill=strip)
    d.line((0, tab_top, W, tab_top), fill=accent, width=8)
    n = 8
    tab_w = W // n
    tab_text_img = Im.new("RGB", (420, tab_w - 40), strip)
    td = ImageDraw.Draw(tab_text_img)
    td.text((16, 8), l1, font=fit(td, l1, 40, 388), fill=l1_fill)
    td.text((16, 68), l2, font=fit(td, l2, 40, 388, bold=False), fill=l2_fill)
    td.text((16, 128), l3, font=fit(td, l3, 30, 388, bold=False), fill=l3_fill)
    tab_rot = tab_text_img.rotate(90, expand=True)
    for i in range(n):
        x = i * tab_w
        if i:
            for yy in range(tab_top + 10, H - 10, 36):
                d.line((x, yy, x, yy + 18), fill=FOG, width=3)
        img.paste(tab_rot, (x + 20, tab_top + 20))


def make_flyer_dark():
    """Letter flyer in the HotsTuff store-slide style — full dark navy page,
    gradient badge pill, white content card, big price — ECS colours + logo."""
    from PIL import Image, ImageDraw

    W, H = 2550, 3300
    img = Image.new("RGB", (W, H), NAVY)
    d = ImageDraw.Draw(img)
    v_gradient(d, (0, 0, W, H), NAVY, NAVY_3)
    radial_glow(img, (W // 2, 640), 900, peak_alpha=55)

    # logo lockup (like the flame + wordmark on store slides)
    label_f = _font(84, True)
    label = "EAST COAST SOCIAL"
    lw = d.textlength(label, font=label_f)
    badge, gap = 220, 48
    bx = int((W - (badge + gap + lw)) // 2)
    crop, mask = logo_badge(badge)
    img.paste(crop, (bx, 70), mask)
    d.ellipse((bx, 70, bx + badge, 70 + badge), outline=GOLD, width=8)
    d.text((bx + badge + gap, 132), label, font=label_f, fill=GOLD)

    # gradient pill badge
    pill_f = _font(54, True)
    pt = "DONE-FOR-YOU SOCIAL MEDIA"
    pw = d.textlength(pt, font=pill_f)
    pill_w = int(pw + 140)
    gradient_pill(img, ((W - pill_w) // 2, 370, (W + pill_w) // 2, 480), pt, pill_f)

    # hero
    hero1 = fit(d, "Your business posts every day.", 150, W - 300, loader=_serif)
    centered(d, "Your business posts every day.", 560, hero1, LIGHT, W)
    hero2 = fit(d, "You don't lift a finger.", 150, W - 300, loader=_serif)
    centered(d, "You don't lift a finger.", 760, hero2, GOLD, W)
    sub2 = "Sackville · Memramcook · the greater Moncton area"
    centered(d, sub2, 950, fit(d, sub2, 54, W - 400, bold=False), "#a8bccf", W)

    # white content card (the store slides' rounded-card centerpiece)
    rows = [
        "Your page posts every single day — in your voice, with your photos",
        "Branded picture posts with QR codes to your menu or booking page",
        "Content refreshes itself, so your feed never goes quiet again",
        "A local human keeps watch — you get one simple monthly summary",
    ]
    cx0, cy0, cx1 = 170, 1070, W - 170
    row_f = min((fit(d, t, 58, cx1 - cx0 - 300) for t in rows), key=lambda f: f.size)
    card_h = 90 + len(rows) * 132 + 40
    d.rounded_rectangle((cx0 + 14, cy0 + 18, cx1 + 14, cy0 + card_h + 18), radius=60, fill="#08131f")
    d.rounded_rectangle((cx0, cy0, cx1, cy0 + card_h), radius=60, fill=PAPER)
    y = cy0 + 70
    for text in rows:
        d.ellipse((cx0 + 80, y + 12, cx0 + 124, y + 56), fill=GOLD)
        d.text((cx0 + 170, y), text, font=row_f, fill=INK)
        y += 132

    # gradient divider (the slides' underline bar)
    gradient_pill(img, ((W - 340) // 2, 1786, (W + 340) // 2, 1802), "", pill_f)

    # big price treatment (like the store slides' price)
    centered(d, "$79/month", 1850, _font(190, True), GOLD, W)
    sub_price = "free setup  ·  no contracts  ·  cancel anytime"
    centered(d, sub_price, 2100, fit(d, sub_price, 56, W - 500, bold=False), LIGHT, W)

    # QR card
    qbox = 430
    qx0, qy0 = (W - qbox) // 2, 2220
    d.rounded_rectangle((qx0 + 10, qy0 + 12, qx0 + qbox + 10, qy0 + qbox + 12), radius=50, fill="#08131f")
    d.rounded_rectangle((qx0, qy0, qx0 + qbox, qy0 + qbox), radius=50, fill=PAPER)
    img.paste(qr_image(360), ((W - 360) // 2, qy0 + 35))
    centered(d, SITE_LINE, 2672, _font(60, True), GOLD, W)
    contact = f"Matthew Ferreira  ·  {PHONE}  ·  {EMAIL}"
    centered(d, contact, 2752, fit(d, contact, 44, W - 300, bold=False), LIGHT, W)

    tear_tabs(img, d, W, H)

    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / "flyer-dark.png")
    img.save(OUT / "flyer-dark.pdf", resolution=300)
    print("dark flyer done")


def make_flyer_hotstuff():
    """Letter flyer for the HotsTuff store itself, in the TikTok-slide identity:
    dark plum page, flame + wordmark, flame-gradient pill, white card, amber claim."""
    from PIL import Image, ImageDraw
    from make_tiktok_pack import _flame_gradient

    SBG, SACCENT, SAMBER = "#191016", "#e11d48", "#f59e0b"
    SINK_L, SMUTED, SINK_D = "#f7f2ee", "#a3958f", "#231418"

    W, H = 2550, 3300
    img = Image.new("RGB", (W, H), SBG)
    d = ImageDraw.Draw(img)
    v_gradient(d, (0, 0, W, H), SBG, "#2a1a22")
    radial_glow(img, (W // 2, 640), 900, color=SAMBER, peak_alpha=45)

    # flame + wordmark lockup (same construction as the slides)
    wm_f = _font(170, True)
    fh = 200
    group = int(fh * 0.84 + 40 + d.textlength("HotsTuff", font=wm_f))
    hx = (W - group) // 2
    fw = draw_flame(d, hx, 90, fh, core=SBG)
    d.text((hx + fw + 40, 110), "HotsTuff", font=wm_f, fill=SACCENT)

    # flame-gradient pill badge
    pill_f = _font(54, True)
    pt = "NEW DROPS EVERY 3 DAYS"
    pw = d.textlength(pt, font=pill_f)
    pill_w = int(pw + 140)
    pill, pmask = _flame_gradient((pill_w, 110), radius=55)
    img.paste(pill, ((W - pill_w) // 2, 380), pmask)
    d.text(((W - pw) // 2, 380 + (110 - int(54 * 1.35)) // 2), pt, font=pill_f, fill="#ffffff")

    # hero
    hero1 = fit(d, "The internet's trending stuff.", 150, W - 300, loader=_serif)
    centered(d, "The internet's trending stuff.", 570, hero1, SINK_L, W)
    hero2 = fit(d, "Caught while it's still hot.", 150, W - 300, loader=_serif)
    centered(d, "Caught while it's still hot.", 770, hero2, SAMBER, W)
    sub2 = "findhotstuff.com · 120 fresh finds at a time"
    centered(d, sub2, 960, fit(d, sub2, 54, W - 400, bold=False), SMUTED, W)

    # white content card
    rows = [
        "120 hand-picked trending products, fresh from what's blowing up online",
        "The catalog refreshes itself every 3 days — always something new",
        "Custom tees: upload your own design, we print it and ship it",
        "Secure card checkout powered by Stripe",
    ]
    cx0, cy0, cx1 = 170, 1080, W - 170
    row_f = min((fit(d, t, 58, cx1 - cx0 - 300) for t in rows), key=lambda f: f.size)
    card_h = 90 + len(rows) * 132 + 40
    d.rounded_rectangle((cx0 + 14, cy0 + 18, cx1 + 14, cy0 + card_h + 18), radius=60, fill="#0d0a0c")
    d.rounded_rectangle((cx0, cy0, cx1, cy0 + card_h), radius=60, fill="#ffffff")
    y = cy0 + 70
    for text in rows:
        dot, dmask = _flame_gradient((44, 44), radius=22)
        img.paste(dot, (cx0 + 80, y + 10), dmask)
        d.text((cx0 + 170, y), text, font=row_f, fill=SINK_D)
        y += 132

    # divider + big claim (the slides' price treatment)
    bar, bmask = _flame_gradient((340, 16), radius=8)
    img.paste(bar, ((W - 340) // 2, 1800), bmask)
    big = "Snooze it, lose it."
    centered(d, big, 1880, fit(d, big, 190, W - 300), SAMBER, W)
    subp = "the whole shelf clears itself every 3 days — when it's gone, it's gone"
    centered(d, subp, 2110, fit(d, subp, 56, W - 500, bold=False), SINK_L, W)

    # QR card -> the store
    qbox = 430
    qx0, qy0 = (W - qbox) // 2, 2230
    d.rounded_rectangle((qx0 + 10, qy0 + 12, qx0 + qbox + 10, qy0 + qbox + 12), radius=50, fill="#0d0a0c")
    d.rounded_rectangle((qx0, qy0, qx0 + qbox, qy0 + qbox), radius=50, fill="#ffffff")
    img.paste(qr_image(360, "https://findhotstuff.com/?ref=print"), ((W - 360) // 2, qy0 + 35))
    centered(d, "findhotstuff.com", 2685, _font(64, True), SAMBER, W)

    tear_tabs(img, d, W, H, l1="HotsTuff", l2="findhotstuff.com", l3="new drops every 3 days",
              l1_fill=SACCENT, l2_fill=SINK_D, l3_fill="#8a7a74", strip="#fff9f2", accent=SACCENT)

    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / "flyer-hotstuff.png")
    img.save(OUT / "flyer-hotstuff.pdf", resolution=300)
    print("hotstuff flyer done")


if __name__ == "__main__":
    make_flyer()
    make_flyer_dark()
    make_flyer_hotstuff()
    make_cards()
    print(f"all print materials -> {OUT}")
