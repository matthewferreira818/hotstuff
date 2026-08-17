"""
Renders the ECS founder-hoodie BACK print file: transparent PNG for a navy
garment — gold wordmark, white QR tile (scannable on dark fabric), URL line.

The QR targets findhotstuff.com/automation/?ref=merch so hoodie scans show
up as their own channel in the traffic report (the old art pointed at
eastcoastsocial.ca, whose redirect strips the ?ref tag — that's the whole
reason this file exists).

    python make_merch_art.py
    -> marketing/east-coast-social/print/ecs-back.png  (3600x4800 @ 300dpi ~ 12x16")
"""

import io
from pathlib import Path

import segno
from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
OUT = HERE / "marketing" / "east-coast-social" / "print" / "ecs-back.png"

W, H = 3600, 4800          # 12x16" back placement at 300 dpi
GOLD = (240, 180, 41, 255)
WHITE = (242, 246, 250, 255)
QR_TARGET = "https://findhotstuff.com/automation/?ref=merch"

FONTS_BOLD = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
              r"C:\Windows\Fonts\arialbd.ttf"]


def font(size):
    for p in FONTS_BOLD:
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            continue
    raise SystemExit("no bold font found")


def main():
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)

    # wordmark: beacon dot + EAST COAST SOCIAL, gold, centered
    wm = "EAST COAST SOCIAL"
    wf = font(240)
    ww = d.textlength(wm, font=wf)
    dot = 110
    x = (W - (ww + dot + 90)) // 2
    d.ellipse((x, 560, x + dot, 560 + dot), fill=GOLD)
    d.text((x + dot + 90, 470), wm, font=wf, fill=GOLD)

    tag = "your page, posting daily — automatically"
    tf = font(120)
    d.text(((W - d.textlength(tag, font=tf)) // 2, 900), tag, font=tf, fill=WHITE)

    # QR on a white rounded tile so it scans against navy fabric
    qr = segno.make(QR_TARGET, error="q")
    buf = io.BytesIO()
    qr.save(buf, kind="png", scale=44, border=0, dark="#0d1f33", light="#ffffff")
    qr_img = Image.open(buf).convert("RGBA")
    tile = 1960
    pad = (tile - qr_img.width) // 2
    tx, ty = (W - tile) // 2, 1450
    d.rounded_rectangle((tx, ty, tx + tile, ty + tile), radius=90, fill=(255, 255, 255, 255))
    img.paste(qr_img, (tx + pad, ty + pad), qr_img)

    # under the tile: honest hook + human-readable URL
    hook = "scan it — this store runs itself"
    hf = font(130)
    d.text(((W - d.textlength(hook, font=hf)) // 2, ty + tile + 170), hook, font=hf, fill=WHITE)
    url = "findhotstuff.com/automation"
    uf = font(150)
    d.text(((W - d.textlength(url, font=uf)) // 2, ty + tile + 400), url, font=uf, fill=GOLD)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT, dpi=(300, 300))
    print(f"wrote {OUT} ({img.width}x{img.height})")


if __name__ == "__main__":
    main()
