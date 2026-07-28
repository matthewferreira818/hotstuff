"""
Renders the PWA / favicon icon set into assets/icons/ from the shared brand
flame (tweet_media.draw_flame — same path as the X logo).

    icon-192.png / icon-512.png            regular app icons (full-bleed)
    icon-maskable-192.png / -512.png       Android maskable (flame in safe zone)
    apple-touch-icon.png                   180x180 iOS home-screen icon
    favicon-32.png / favicon-16.png        browser tab favicons

Drawn at 4x and downscaled for smooth edges. Rerun any time to regenerate.
"""

from pathlib import Path

from PIL import Image, ImageDraw

from tweet_media import draw_flame

OUT = Path(__file__).parent / "assets" / "icons"

RED_TOP = (225, 29, 72)     # #e11d48
RED_BOTTOM = (159, 18, 57)  # #9f1239


def render(size, flame_frac):
    """Red-gradient square with the brand flame at flame_frac of the height."""
    s = 4
    px = size * s
    img = Image.new("RGB", (px, px))
    d = ImageDraw.Draw(img)
    for row in range(px):
        t = row / px
        d.line([(0, row), (px, row)],
               fill=tuple(int(a + (b - a) * t) for a, b in zip(RED_TOP, RED_BOTTOM)))
    fh = px * flame_frac
    fw = fh * 0.84  # draw_flame's aspect
    # optically centre: nudge up slightly since the flame's mass sits low
    draw_flame(d, (px - fw) / 2, (px - fh) / 2 - px * 0.015, fh,
               outer="#ffffff", inner="#f59e0b", core="#fff9f2")
    return img.resize((size, size), Image.LANCZOS)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    # full-bleed icons: flame fills most of the tile
    for size in (192, 512):
        render(size, 0.62).save(OUT / f"icon-{size}.png")
    # maskable: Android crops to a circle/squircle — keep flame in inner 80%
    for size in (192, 512):
        render(size, 0.46).save(OUT / f"icon-maskable-{size}.png")
    render(180, 0.62).save(OUT / "apple-touch-icon.png")
    for size in (32, 16):
        render(size, 0.72).save(OUT / f"favicon-{size}.png")
    print(f"wrote {len(list(OUT.glob('*.png')))} icons to {OUT}")


if __name__ == "__main__":
    main()
