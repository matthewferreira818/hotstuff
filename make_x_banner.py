"""
X (Twitter) profile banner for East Coast Social — 1500x500, navy/gold,
sunrise badge + hero line. Output: marketing/east-coast-social/x-banner.png

Usage: python make_x_banner.py
"""

from pathlib import Path

from make_daily_packs import _font, _serif
from make_print_materials import (GOLD, LIGHT, NAVY, NAVY_3, fit, logo_badge,
                                  radial_glow, v_gradient)

HERE = Path(__file__).parent
OUT = HERE / "marketing" / "east-coast-social" / "x-banner.png"


def main():
    from PIL import Image, ImageDraw

    W, H = 1500, 500
    img = Image.new("RGB", (W, H), NAVY)
    d = ImageDraw.Draw(img)
    v_gradient(d, (0, 0, W, H), NAVY, NAVY_3)
    radial_glow(img, (880, 250), 420, peak_alpha=50)

    badge = 290
    crop, mask = logo_badge(badge)
    img.paste(crop, (95, (H - badge) // 2), mask)
    d.ellipse((95, (H - badge) // 2, 95 + badge, (H + badge) // 2), outline=GOLD, width=6)

    tx = 470                      # text block starts right of the badge
    label_f = _font(40, True)
    d.ellipse((tx, 96, tx + 20, 116), fill=GOLD)
    d.text((tx + 34, 86), "EAST COAST SOCIAL", font=label_f, fill=GOLD)

    max_w = W - tx - 40
    hero1 = "Your business posts every day."
    hero2 = "You don't lift a finger."
    hf = fit(d, hero1, 64, max_w, loader=_serif)
    d.text((tx, 164), hero1, font=hf, fill=LIGHT)
    d.text((tx, 252), hero2, font=hf, fill=GOLD)

    sub = "Done-for-you social media · Sackville · Memramcook · Moncton"
    d.text((tx, 356), sub, font=_font(30, False), fill="#a8bccf")
    d.text((tx, 408), "findhotstuff.com/automation", font=_font(34, True), fill=GOLD)

    img.save(OUT)
    print(f"banner -> {OUT}")


if __name__ == "__main__":
    main()
