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
GOLD = "#f0b429"
INK = "#16283c"
PAPER = "#ffffff"
FOG = "#5b7089"
LIGHT = "#f2f6fa"

AUTOMATION_URL = "https://findhotstuff.com/automation/"
PHONE = "(506) 889-9737"
EMAIL = "matthew.ferreira818@gmail.com"
SITE_LINE = "findhotstuff.com/automation"


def fit(draw, text, size, max_width, loader=_font, bold=True):
    while size > 20:
        f = loader(size, bold)
        if draw.textlength(text, font=f) <= max_width:
            return f
        size -= 4
    return loader(20, bold)


def centered(draw, text, y, font, fill, width):
    draw.text(((width - draw.textlength(text, font=font)) // 2, y), text, font=font, fill=fill)


def qr_image(size):
    import segno
    from PIL import Image
    buf = io.BytesIO()
    segno.make(AUTOMATION_URL, error="m").save(buf, kind="png", scale=20, border=2,
                                               dark="#111111", light="#ffffff")
    qr = Image.open(buf).convert("RGB")
    return qr.resize((size, size), Image.NEAREST)


def make_flyer():
    """Letter flyer: navy header band, ink-friendly white body, tear-off tabs."""
    from PIL import Image, ImageDraw

    W, H = 2550, 3300
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img)

    # --- navy header band ---
    band_h = 1150
    d.rectangle((0, 0, W, band_h), fill=NAVY)
    label_f = _font(72, True)
    label = "EAST COAST SOCIAL"
    lw = d.textlength(label, font=label_f)
    lx = (W - (lw + 60)) // 2
    d.ellipse((lx, 128, lx + 36, 164), fill=GOLD)
    d.text((lx + 60, 110), label, font=label_f, fill=GOLD)

    hero1 = fit(d, "Your business posts every day.", 150, W - 300, loader=_serif)
    centered(d, "Your business posts every day.", 320, hero1, LIGHT, W)
    hero2 = fit(d, "You don't lift a finger.", 150, W - 300, loader=_serif)
    centered(d, "You don't lift a finger.", 520, hero2, GOLD, W)

    sub = "Done-for-you social media for local businesses"
    sub2 = "Sackville · Memramcook · the greater Moncton area"
    centered(d, sub, 780, fit(d, sub, 64, W - 400, bold=False), LIGHT, W)
    centered(d, sub2, 890, fit(d, sub2, 54, W - 400, bold=False), "#a8bccf", W)

    # --- body: what you get ---
    rows = [
        "Your page posts every single day — in your voice, with your photos",
        "Branded picture posts with QR codes to your menu or booking page",
        "Content refreshes itself, so your feed never goes quiet again",
        "A local human keeps watch — you get one simple monthly summary",
    ]
    y = band_h + 130
    row_f = _font(58, True)
    for text in rows:
        d.ellipse((170, y + 14, 218, y + 62), fill=GOLD)
        f = fit(d, text, 58, W - 480)
        d.text((280, y), text, font=f, fill=INK)
        y += 140

    # pricing
    y += 40
    price = "$299 setup  ·  $49/month  ·  no contracts, cancel anytime"
    pf = fit(d, price, 72, W - 400, loader=_serif)
    centered(d, price, y, pf, NAVY, W)
    y += 110
    proof = "See it running live — my own store has posted 3x a day for months, untouched:"
    centered(d, proof, y, fit(d, proof, 48, W - 360, bold=False), FOG, W)

    # --- QR + contact block ---
    qy = y + 100
    qr = qr_image(480)
    d.rounded_rectangle(((W - 560) // 2, qy, (W + 560) // 2, qy + 560, ), radius=40,
                        fill=PAPER, outline=NAVY, width=8)
    img.paste(qr, ((W - 480) // 2, qy + 40))
    qy += 590
    centered(d, SITE_LINE, qy, _font(64, True), NAVY, W)
    qy += 95
    contact = f"Matthew Ferreira  ·  {PHONE}  ·  {EMAIL}"
    centered(d, contact, qy, fit(d, contact, 52, W - 300, bold=False), INK, W)

    # --- tear-off tabs ---
    from PIL import Image as Im
    tab_top = H - 460
    d.line((0, tab_top, W, tab_top), fill=FOG, width=3)
    n = 8
    tab_w = W // n
    tab_text_img = Im.new("RGB", (420, tab_w - 40), PAPER)
    td = ImageDraw.Draw(tab_text_img)
    td.text((16, 8), "East Coast Social", font=_font(40, True), fill=NAVY)
    td.text((16, 68), PHONE, font=_font(40, False), fill=INK)
    td.text((16, 128), SITE_LINE, font=_font(30, False), fill=FOG)
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

    # --- front: navy ---
    front = Image.new("RGB", (W, H), NAVY)
    d = ImageDraw.Draw(front)
    label_f = _font(40, True)
    label = "EAST COAST SOCIAL"
    lw = d.textlength(label, font=label_f)
    lx = (W - (lw + 34)) // 2
    d.ellipse((lx, 66, lx + 20, 86), fill=GOLD)
    d.text((lx + 34, 56), label, font=label_f, fill=GOLD)

    tag1 = fit(d, "Social media that", 64, W - 160, loader=_serif)
    centered(d, "Social media that", 170, tag1, LIGHT, W)
    centered(d, "runs itself.", 255, fit(d, "runs itself.", 64, W - 160, loader=_serif), GOLD, W)

    centered(d, "Matthew Ferreira", 390, _font(40, True), LIGHT, W)
    centered(d, PHONE + "  ·  " + EMAIL, 455, fit(d, PHONE + "  ·  " + EMAIL, 30, W - 120, bold=False), "#a8bccf", W)
    centered(d, SITE_LINE, 510, _font(32, True), GOLD, W)
    front.save(OUT / "card-front.png")

    # --- back: white with QR ---
    back = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(back)
    qr = qr_image(380)
    back.paste(qr, ((W - 380) // 2, 60))
    d.rectangle(((W - 240) // 2, 470, (W + 240) // 2, 478), fill=GOLD)
    centered(d, "see it running → " + SITE_LINE, 505, fit(d, "see it running → " + SITE_LINE, 34, W - 120), NAVY, W)
    back.save(OUT / "card-back.png")

    front.save(OUT / "business-card.pdf", resolution=300, save_all=True, append_images=[back])
    print("cards done")


if __name__ == "__main__":
    make_flyer()
    make_cards()
    print(f"all print materials -> {OUT}")
