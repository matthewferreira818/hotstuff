"""
Shared branded-post-card renderer for East Coast Social.

Used two ways:
  - generate_ecs_post.py renders ECS's own daily card (client #0)
  - sample_posts.py renders mockup cards for a PROSPECT's business, in their
    colors, to close the "you approve samples" step of the pitch

A card is a 1080x1080 square: brand band up top (business name + accent dot),
big message text in the middle, optional photo panel, footer strip. Colors and
name are parameters, so any business drops in.
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

HERE = Path(__file__).parent
CARD = 1080

_FONTS = {
    True: ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
           r"C:\Windows\Fonts\arialbd.ttf"],
    False: ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            r"C:\Windows\Fonts\arial.ttf"],
}
_SERIF = ["/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf",
          r"C:\Windows\Fonts\georgiab.ttf"]


def _font(size, bold=False, serif=False):
    paths = _SERIF if serif else _FONTS[bold]
    for p in paths:
        try:
            return ImageFont.truetype(p, size)
        except OSError:
            continue
    return ImageFont.load_default()


def _wrap(draw, text, font, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if draw.textlength(trial, font=font) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def render_card(business, message, out_path, *,
                bg="#0d1f33", accent="#f0b429", ink="#f2f6fa",
                footer=None, photo=None, tagline=None):
    """Render one branded post card PNG.

    business: display name in the header band
    message:  the post's key line, wrapped large in the middle
    footer:   small strip at the bottom (defaults to the business name)
    photo:    optional path to a photo shown as a rounded panel
    """
    img = Image.new("RGB", (CARD, CARD), bg)
    d = ImageDraw.Draw(img)

    # header band: accent dot + business name
    d.ellipse((64, 74, 92, 102), fill=accent)
    d.text((112, 68), business.upper(), font=_font(44, bold=True), fill=accent)

    # optional photo panel (top-right half) shrinks the text column
    text_w = CARD - 128
    top = 220
    if photo and Path(photo).exists():
        ph = Image.open(photo).convert("RGB")
        side = 440
        ph.thumbnail((side * 2, side * 2))
        ph = ph.crop((0, 0, min(ph.width, side * 2), min(ph.height, side * 2)))
        ph = ph.resize((side, side))
        mask = Image.new("L", (side, side), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, side, side), radius=36, fill=255)
        img.paste(ph, (CARD - side - 64, 180), mask)
        text_w = CARD - side - 192
        top = 260

    # message, auto-sized serif
    size = 88
    while size > 40:
        f = _font(size, serif=True)
        lines = _wrap(d, message, f, text_w)
        if len(lines) * (size + 18) < 560:
            break
        size -= 6
    y = top
    for i, line in enumerate(lines):
        d.text((64, y), line, font=f, fill=ink if i % 2 == 0 else accent)
        y += size + 18

    if tagline:
        d.text((64, y + 28), tagline, font=_font(34), fill="#a8bccf")

    # footer strip
    d.rectangle((0, CARD - 96, CARD, CARD), fill=accent)
    ft = footer or business
    d.text((64, CARD - 76), ft, font=_font(38, bold=True), fill=bg)

    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path)
    return out_path
