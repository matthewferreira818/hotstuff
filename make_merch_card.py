"""Regenerates marketing/merch-tweet-card.png — the ad card attached to the
one-off merch showcase tweet (post_merch_tweet.py).

Launch edition: the Printify pop-up store is live, so the card announces the
full logo lineup alongside the custom-tee upload flow.

Usage: python make_merch_card.py
"""
from pathlib import Path

from tweet_media import ACCENT, BG, INK, MUTED, SITE, _fit_text, _font, draw_flame

HERE = Path(__file__).parent
OUT = HERE / "marketing" / "merch-tweet-card.png"
CARD = 1080
DARK = "#16151a"
PANEL = "#f2ede7"


def main():
    from PIL import Image, ImageDraw

    img = Image.new("RGB", (CARD, CARD), BG)
    d = ImageDraw.Draw(img)

    def centered(text, font, cx, y, fill):
        d.text((cx - d.textlength(text, font=font) / 2, y), text, font=font, fill=fill)

    # header: flame + wordmark left, site right (house style)
    fw = draw_flame(d, 44, 26, 84)
    d.text((44 + fw + 16, 34), "HotsTuff", font=_font(68, True), fill=ACCENT)
    site_font = _font(32)
    d.text((CARD - 48 - d.textlength(SITE, font=site_font), 62),
           SITE, font=site_font, fill=MUTED)

    headline, hf = _fit_text(d, "The flame lineup is LIVE", 76, True, CARD - 120)
    centered(headline, hf, CARD // 2, 156, INK)

    # left panel: the logo tile (dark, like the tee)
    d.rounded_rectangle((70, 290, 500, 700), radius=24, fill=DARK)
    flame_h = 200
    draw_flame(d, 285 - (flame_h * 0.84) / 2, 330, flame_h, core=DARK)
    centered("HotsTuff", _font(52, True), 285, 560, "#ffffff")
    centered(SITE, _font(26), 285, 630, "#b7aca4")

    # right panel: the upload-your-art flow
    d.rounded_rectangle((580, 290, 1010, 700), radius=24, fill=PANEL)
    d.rounded_rectangle((640, 330, 950, 620), radius=24, outline=ACCENT, width=6)
    centered("↑", _font(96, True), 795, 350, ACCENT)
    art, af = _fit_text(d, "YOUR ART", 54, True, 250)
    centered(art, af, 795, 462, ACCENT)
    centered("HERE", af, 795, 462 + af.size + 14, ACCENT)

    # captions: both sides are live now
    cap, cf = _fit_text(d, "Logo merch — LIVE now", 40, True, 420)
    centered(cap, cf, 285, 730, ACCENT)
    cap, cf = _fit_text(d, "Custom tee — $32.99 shipped", 40, True, 420)
    centered(cap, cf, 795, 730, INK)

    # lineup pill
    lineup, lf = _fit_text(d, "Tee · Crewneck · Cap · Mug · Sticker", 44, True, CARD - 200)
    pw = d.textlength(lineup, font=lf)
    pill = ((CARD - pw) // 2 - 45, 820, (CARD + pw) // 2 + 45, 908)
    d.rounded_rectangle(pill, radius=44, fill=ACCENT)
    centered(lineup, lf, CARD // 2, 838, "#ffffff")

    foot, ff = _fit_text(d, "Printed to order · Shop at findhotstuff.com → Merch", 30, False, CARD - 120)
    centered(foot, ff, CARD // 2, 960, MUTED)

    img.save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
