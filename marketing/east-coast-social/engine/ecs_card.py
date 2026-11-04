"""
East Coast Social's own daily card, redesigned 2026-11-04 (Matthew: the old
cards "seem bland": same navy square every day). Each kind of post gets its own
colours, label and icon, with East Coast waves along the bottom.

Kinds: tip, idea, story, offer. Rendered at 2x and scaled down for smooth edges.

    python ecs_card.py   # writes one sample of each kind to out/samples-new/
"""

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

SIZE = 1080
S = 2                      # supersampling factor
W = SIZE * S

FONT_BOLD = ["/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
             "/Library/Fonts/Arial Bold.ttf", r"C:\Windows\Fonts\arialbd.ttf"]
FONT_REG = ["/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
            "/Library/Fonts/Arial.ttf", r"C:\Windows\Fonts\arial.ttf"]

THEMES = {
    #        background  ink        accent     wave colours (back to front)      label
    "tip":   ("#0f3b3d", "#f3fbf8", "#5eead4", ("#1d6663", "#25807b", "#2f9e96"), "FREE TIP"),
    "idea":  ("#fff4e6", "#2a1d14", "#ea6a2a", ("#fde2c4", "#fbcf9f", "#f6b277"), "POST IDEA"),
    "story": ("#0d1f33", "#f2f6fa", "#f0b429", ("#1d3f66", "#28568a", "#336fb0"), "BEHIND THE SCENES"),
    "offer": ("#f0b429", "#14213a", "#14213a", ("#f6cc66", "#f9db8f", "#fceabc"), "THE OFFER"),
}
FOOTER = "findhotstuff.com/automation  ·  Memramcook, NB"


def _font(size, bold=True):
    for p in (FONT_BOLD if bold else FONT_REG):
        try:
            return ImageFont.truetype(p, size * S)
        except OSError:
            continue
    return ImageFont.load_default()


def _wrap(d, text, font, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if d.textlength(trial, font=font) <= max_w:
            cur = trial
        else:
            if cur:
                lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def _waves(d, colours):
    """Three layered waves running edge to edge (whole cycles, drawn past both
    edges so no wave stops short): the East Coast signature."""
    base = W + 10
    for i, col in enumerate(colours):
        top = int(W * (0.79 + 0.05 * i))
        amp = int(W * (0.028 - 0.005 * i))
        cycles = (2, 3, 2)[i]
        shift = (0.0, 1.9, 3.6)[i]
        pts = [(x, top + amp * math.sin(2 * math.pi * cycles * x / W + shift))
               for x in range(-40, W + 48, 6)]
        d.polygon(pts + [(W + 40, base), (-40, base)], fill=col)


def _icon(d, kind, cx, cy, r, col, bg):
    """Simple drawn icons (no emoji font needed on the runner)."""
    lw = max(6, r // 7)
    if kind == "tip":            # lightbulb
        d.ellipse((cx - r, cy - r, cx + r, cy + r * 0.9), outline=col, width=lw)
        d.rectangle((cx - r * 0.45, cy + r * 0.85, cx + r * 0.45, cy + r * 1.25), fill=col)
        d.rectangle((cx - r * 0.3, cy + r * 1.35, cx + r * 0.3, cy + r * 1.5), fill=col)
        for a in (-150, -110, -70, -30, 10):   # rays
            t = math.radians(a)
            d.line((cx + math.cos(t) * r * 1.3, cy + math.sin(t) * r * 1.3,
                    cx + math.cos(t) * r * 1.6, cy + math.sin(t) * r * 1.6), fill=col, width=lw)
    elif kind == "idea":         # four-point sparkle + small one
        def star(x, y, s):
            k = s * 0.22
            d.polygon([(x, y - s), (x + k, y - k), (x + s, y), (x + k, y + k),
                       (x, y + s), (x - k, y + k), (x - s, y), (x - k, y - k)], fill=col)
        star(cx, cy, r * 1.25)
        star(cx + r * 1.35, cy - r * 1.05, r * 0.5)
    elif kind == "story":        # map pin
        d.ellipse((cx - r, cy - r * 1.3, cx + r, cy + r * 0.7), fill=col)
        d.polygon([(cx - r * 0.86, cy - r * 0.0), (cx + r * 0.86, cy - r * 0.0), (cx, cy + r * 1.5)], fill=col)
        d.ellipse((cx - r * 0.38, cy - r * 0.68, cx + r * 0.38, cy + r * 0.08), fill=bg)
    else:                        # offer: check in a circle
        d.ellipse((cx - r * 1.2, cy - r * 1.2, cx + r * 1.2, cy + r * 1.2), outline=col, width=lw)
        d.line((cx - r * 0.55, cy + r * 0.02, cx - r * 0.12, cy + r * 0.48, cx + r * 0.62, cy - r * 0.5),
               fill=col, width=lw + 4, joint="curve")


def render(kind, message, out_path):
    bg, ink, accent, waves, label = THEMES.get(kind, THEMES["story"])
    img = Image.new("RGB", (W, W), bg)
    d = ImageDraw.Draw(img)
    m = 72 * S                                   # margin

    # brand line
    d.ellipse((m, m + 6 * S, m + 22 * S, m + 28 * S), fill=accent)
    d.text((m + 36 * S, m), "EAST COAST SOCIAL", font=_font(34), fill=ink)

    # icon, top right
    _icon(d, kind, W - m - 70 * S, m + 70 * S, 46 * S, accent, bg)

    # label chip
    f_chip = _font(30)
    cw = d.textlength(label, font=f_chip) + 48 * S
    y = m + 150 * S
    d.rounded_rectangle((m, y, m + cw, y + 64 * S), radius=32 * S, fill=accent)
    d.text((m + 24 * S, y + 14 * S), label, font=f_chip, fill=bg)

    # message: as big as fits between the chip and the waves
    area_top, area_bot = y + 110 * S, int(W * 0.76)
    max_w = W - 2 * m
    for size in range(92, 40, -4):
        f = _font(size)
        lines = _wrap(d, message, f, max_w)
        lh = int(size * S * 1.18)
        if len(lines) * lh <= area_bot - area_top:
            break
    ty = area_top + ((area_bot - area_top) - len(lines) * lh) // 2
    for i, line in enumerate(lines):
        # last line in the accent colour (on the offer card the accent is the ink)
        col = accent if (i == len(lines) - 1 and kind != "offer") else ink
        d.text((m, ty + i * lh), line, font=f, fill=col)

    _waves(d, waves)
    f_foot = _font(26, bold=True)
    foot_col = "#14213a" if kind in ("idea", "offer") else "#f2f6fa"
    d.text((m, W - 70 * S), FOOTER, font=f_foot, fill=foot_col)

    img = img.resize((SIZE, SIZE), Image.LANCZOS)
    Path(out_path).parent.mkdir(parents=True, exist_ok=True)
    img.save(out_path, optimize=True)
    return out_path


if __name__ == "__main__":
    here = Path(__file__).parent / "out" / "samples-new"
    render("tip", "Pin a post with your hours, address and phone.", here / "tip.png")
    render("idea", "Post idea for bakeries: what came out of the oven this morning.", here / "idea.png")
    render("story", "Made in Memramcook, for businesses around here.", here / "story.png")
    render("offer", "7 free sample posts. Yours to keep, either way.", here / "offer.png")
    print("samples in", here)
