"""
Print-ready merch art for East Coast Social — founder wear, not (yet) a
public product. Transparent-background PNGs sized for Printify's DTG print
area (4500x5100 ≈ 15"x17" at 300 DPI), designed for a NAVY or BLACK garment:

    merch/ecs-front.png    logo badge + wordmark + tagline (full chest)
    merch/ecs-back.png     "scan → eastcoastsocial.ca" QR panel (upper back)
    merch/preview-*.png    what each looks like on a navy sweater (not for print)

Usage:
    python marketing/east-coast-social/make_merch_art.py
"""

import io
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parents[1]))          # repo root for make_daily_packs

from make_daily_packs import _font, _serif  # noqa: E402
from ecs_site import ecs_url  # noqa: E402

OUT = HERE / "merch"
GOLD = "#f0b429"
LIGHT = "#f2f6fa"
MIST = "#a8bccf"
NAVY = "#0d1f33"
W, H = 4500, 5100                      # Printify DTG max print area @300dpi
# direct domain, not eastcoastsocial.ca: the forward strips query strings,
# which would silently untag every sweater scan
QR_URL = ecs_url("merch")


def logo_disc(size):
    """Sunrise logo circle-cropped with a gold ring, on transparency."""
    from PIL import Image, ImageDraw
    logo = Image.open(HERE / "fb-logo.png").convert("RGB")
    crop = logo.crop((92, 100, 932, 940)).resize((size, size), Image.LANCZOS)
    disc = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, size - 1, size - 1), fill=255)
    disc.paste(crop, (0, 0), mask)
    ring = ImageDraw.Draw(disc)
    rw = max(10, size // 55)
    ring.ellipse((rw // 2, rw // 2, size - rw // 2 - 1, size - rw // 2 - 1),
                 outline=GOLD, width=rw)
    return disc


def centered(d, text, y, font, fill, width):
    d.text(((width - d.textlength(text, font=font)) // 2, y), text, font=font, fill=fill)


def make_front():
    from PIL import Image, ImageDraw
    art = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)

    disc = logo_disc(1500)
    art.paste(disc, ((W - 1500) // 2, 260), disc)

    word_f = _font(430, True)
    label = "EAST COAST"
    centered(d, label, 2050, word_f, GOLD, W)
    centered(d, "SOCIAL", 2560, word_f, GOLD, W)

    # gold rule between wordmark and tagline
    d.rectangle(((W - 900) // 2, 3210, (W + 900) // 2, 3238), fill=GOLD)

    # no URL on the front — the back's QR carries the link; the front stays clean
    tag_f = _serif(230, False)
    centered(d, "social media that runs itself.", 3340, tag_f, LIGHT, W)

    art.save(OUT / "ecs-front.png")
    print("front art done")
    return art


def make_front_hoodie():
    """Wide layout for hoodie chests: the zone between collar and kangaroo
    pocket is short (Print Geek: 14in x 9.33in), so the stack goes wide.
    Canvas matches that print area exactly at 300 DPI — upload and fill."""
    from PIL import Image, ImageDraw
    HW, HH = 4200, 2799
    art = Image.new("RGBA", (HW, HH), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)

    disc = logo_disc(960)
    art.paste(disc, ((HW - 960) // 2, 60), disc)

    word_f = _font(330, True)
    centered(d, "EAST COAST SOCIAL", 1180, word_f, GOLD, HW)

    d.rectangle(((HW - 760) // 2, 1700, (HW + 760) // 2, 1724), fill=GOLD)

    tag_f = _serif(195, False)
    centered(d, "social media that runs itself.", 1810, tag_f, LIGHT, HW)

    art.save(OUT / "ecs-front-hoodie.png")
    print("hoodie front art done")
    return art


def make_back():
    """Upper-back conversation starter: white QR panel + one line."""
    import segno
    from PIL import Image, ImageDraw
    art = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)

    head_f = _serif(260, True)
    centered(d, "Ask me about the robot.", 200, head_f, LIGHT, W)

    qr_size, pad = 1500, 110
    buf = io.BytesIO()
    segno.make(QR_URL, error="q").save(buf, kind="png", scale=30, border=0,
                                       dark="#111111", light="#ffffff")
    qr = Image.open(buf).convert("RGB").resize((qr_size, qr_size), Image.NEAREST)
    px = (W - qr_size) // 2
    py = 780
    d.rounded_rectangle((px - pad, py - pad, px + qr_size + pad, py + qr_size + pad),
                        radius=120, fill="#ffffff")
    art.paste(qr, (px, py))

    d.rectangle(((W - 900) // 2, 2640, (W + 900) // 2, 2668), fill=GOLD)
    scan_f = _font(190, True)
    centered(d, "scan → eastcoastsocial.ca", 2760, scan_f, GOLD, W)

    art.save(OUT / "ecs-back.png")
    print("back art done")
    return art


def preview(art, name, scale_to=1400, chest_offset=430):
    """Rough on-garment look: the art floated on a navy panel. NOT for print."""
    from PIL import Image
    panel = Image.new("RGB", (1800, 2000), NAVY)
    scaled = art.resize((scale_to, int(scale_to * H / W)), Image.LANCZOS)
    panel.paste(scaled, ((1800 - scale_to) // 2, chest_offset), scaled)
    panel.save(OUT / f"preview-{name}.png")
    print(f"preview-{name} done")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    front = make_front()
    hoodie = make_front_hoodie()
    back = make_back()
    preview(front, "front", chest_offset=260)
    preview(back, "back", chest_offset=180)
    # hoodie canvas is wide (4200x2799): scale by width, sit mid-chest
    from PIL import Image
    panel = Image.new("RGB", (1800, 2000), NAVY)
    scaled = hoodie.resize((1400, int(1400 * 2799 / 4200)), Image.LANCZOS)
    panel.paste(scaled, (200, 480), scaled)
    panel.save(OUT / "preview-front-hoodie.png")
    print("preview-front-hoodie done")
    print(f"merch art -> {OUT}")


if __name__ == "__main__":
    main()
