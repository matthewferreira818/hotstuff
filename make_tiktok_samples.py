"""Three SAMPLE TikTok videos for Matthew to watch and pick a style from.

Why: the daily packs "dont look appealing" (Matthew, 2026-11-06). Before the
TikTok redo picks a style, LC-Trends turns its three ideas from trend report
#1 into real short videos so he can choose by watching, not reading.

This only RENDERS files. It posts nothing, calls no API (no Buffer, no
TikTok), and logs into nothing. Output goes wherever --out points (the
samples live in the private repo, not here).

Each video:
  - real products from the current products.json (ids checked at run time;
    a missing id stops the build rather than showing a product the store
    doesn't sell)
  - a hook on screen from the very first frame
  - motion: a slow push-in on each supplier photo, slide between products
  - no prices, no "under $X": tools/claims_check.py flags every money amount
    and ANY text finding blocks (same rule as make_buffer_cycle.py)
  - no QR, no "#N TRENDING", no "everyone's buying this", max 5 hashtags
  - vertical 1080x1920, 30 fps, silent track, 3-60 s

    python make_tiktok_samples.py --out <folder>            # all three
    python make_tiktok_samples.py --out <folder> pets       # one

Needs Pillow and ffmpeg (system ffmpeg, or `pip install imageio-ffmpeg`).
Runs on Python 3.9+.
"""
from __future__ import annotations

import argparse
import io
import json
import math
import shutil
import subprocess
import sys
import urllib.request
from datetime import date
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = Path(__file__).parent
W, H = 1080, 1920
FPS = 30
HOOK_S = 2.4          # hook card; the hook text is on screen from frame 0
ITEM_S = 3.2          # each product
END_S = 2.6           # end card
SLIDE_S = 0.35        # slide between segments
PUSH = 0.08           # push-in: photo grows 8% across its segment
MAX_TAGS = 5
DATE_ONLY = {"STALE_FACTS", "STALE_FEED"}   # raised from the facts file's dates, not the text
SITE = "findhotstuff.com"

# Names: every word comes from the supplier title (refresh_products.honest_name),
# EXCEPT ids listed in PHOTO_VERIFIED, where the title doesn't say what the item
# is and the name was checked against the supplier photo by hand.
VIDEOS = {
    "pets": {
        "idea": "Cozy gifts for pet people (hook + quick tour)",
        "format": "Product hook in the first second, then one product per beat",
        "hook": ["Pet people", "on your list?"],
        "hook_sub": "3 cozy gift ideas",
        "items": [
            ("CJJJCWMY00453", "Thickened Blanket for Cats and Dogs"),
            ("CJGY1117421", "Sniffing Ball for Dogs & Cats"),
            ("CJJJCWGY00797", "Adjustable Pet Neckerchief"),
        ],
        "end": "Gift ideas for every pet person",
        "caption": "3 cozy gift ideas for the pet people on your list: a thickened "
                   "blanket for cats and dogs, a sniffing ball, and an adjustable "
                   "pet neckerchief. See them at findhotstuff.com",
        "tags": ["#petgifts", "#doglovers", "#catlovers", "#giftideas", "#christmasgifts"],
    },
    "fix": {
        "idea": "Home fix (problem, then the fix). Stand-in for the sink idea: "
                "no sink or drain item is in the current catalogue",
        "format": "Problem first (the crack), then the fix revealed",
        "hook": ["Crack in", "the wall?"],
        "hook_sub": "Before the holiday guests arrive",
        "hook_crop": (0.0, 0.0, 0.55, 0.55),   # zoom on the cracked wall in the supplier photo
        "items": [
            ("CJQCGJQT00163", "Wall Repair Cream"),
        ],
        "end": "Small home fixes",
        "caption": "Crack in the wall before the holiday guests arrive? Wall repair "
                   "cream, at findhotstuff.com (supplier photo shown)",
        "tags": ["#homerepair", "#diy", "#homehacks", "#homeimprovement"],
    },
    "stockings": {
        "idea": "Stocking stuffers (unboxing-style reveal, one line each)",
        "format": "Hook, then a reveal per item",
        "hook": ["Stocking stuffers", "that aren't socks"],
        "hook_sub": "3 small gift ideas",
        "items": [
            ("CJLX1110450", "Frog Stud Earrings"),
            ("CJJZGJSD01838", "Anti-fog Glasses Cloth"),
            ("CJWJWJDZ00150", "Speaking Parrot Plush Toy"),
        ],
        "end": "Small gifts, big smiles",
        "caption": "Stocking stuffers that aren't socks: frog stud earrings, an "
                   "anti-fog glasses cloth, and a speaking parrot plush toy that "
                   "records and repeats. See them at findhotstuff.com",
        "tags": ["#stockingstuffers", "#giftideas", "#christmasgifts", "#giftsforher"],
    },
}
PHOTO_VERIFIED = {"CJLX1110450": "title says 'Funny Animal ... Stud Jewelry'; photo shows frog stud earrings"}

FONTS = {
    True: ["/System/Library/Fonts/Supplemental/Arial Black.ttf",
           "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
           r"C:\Windows\Fonts\ariblk.ttf"],
    False: ["/System/Library/Fonts/Supplemental/Arial Bold.ttf",
            "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
            r"C:\Windows\Fonts\arialbd.ttf"],
}


def font(size: int, heavy: bool = False):
    for f in FONTS[heavy]:
        if Path(f).exists():
            return ImageFont.truetype(f, size)
    return ImageFont.load_default()


def ffmpeg_bin() -> str:
    found = shutil.which("ffmpeg")
    if found:
        return found
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        raise SystemExit("ffmpeg not found. Install it, or `pip install imageio-ffmpeg`.")


# ---------- honesty checks ----------

def load_honest_name():
    """refresh_products.honest_name, the store's own naming rule. Imported
    normally where that works (3.10+); on older Pythons (the Mac's 3.9) its
    module-level `X | None` hints fail, so pull just the naming functions and
    their word lists out of the source and run those. Same code either way."""
    try:
        sys.path.insert(0, str(HERE))
        from refresh_products import honest_name
        return honest_name
    except Exception:  # noqa: BLE001 - fall through to the source copy
        pass
    import ast
    src = (HERE / "refresh_products.py").read_text()
    want = {"honest_name", "_honest_key", "_honest_vocab", "GLUE_WORDS", "_WORD_EQUIVALENTS"}
    keep = []
    for node in ast.parse(src).body:
        names = ({node.name} if isinstance(node, ast.FunctionDef) else
                 {t.id for t in getattr(node, "targets", []) if isinstance(t, ast.Name)} |
                 ({node.target.id} if isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name) else set()))
        if names & want:
            keep.append(ast.get_source_segment(src, node))
    ns: dict = {}
    exec("from __future__ import annotations\n" + "\n\n".join(keep), ns)
    missing = want - set(ns)
    if missing:
        raise SystemExit(f"can't load the store's naming rule: {sorted(missing)} not found")
    return ns["honest_name"]


def name_ok(pid: str, name: str, title: str) -> str:
    if pid in PHOTO_VERIFIED:
        return "photo-verified: " + PHOTO_VERIFIED[pid]
    honest_name = load_honest_name()
    plain = name.replace("(", " ").replace(")", " ").replace("+", " ")
    if not honest_name(plain, title):
        raise SystemExit(f"{pid}: name {name!r} uses words not in the supplier title {title!r}")
    return "honest_name: every word is in the supplier title"


def claims(text: str) -> list[str]:
    r = subprocess.run([sys.executable, str(HERE / "tools" / "claims_check.py"),
                        "--text", text, "--json"], capture_output=True, text=True)
    try:
        return [f["code"] for f in json.loads(r.stdout).get("findings", [])]
    except json.JSONDecodeError:
        raise SystemExit(f"claims_check gave no JSON: {r.stdout}{r.stderr}")


BANNED = ["trending", "tiktokmademebuyit", "everyone", "viral", "best seller",
          "bestseller", "sold out", "selling fast", "#1", "$", "qr"]


def lint(text: str) -> list[str]:
    low = text.lower()
    return [b for b in BANNED if b in low]


# ---------- drawing ----------

def fetch(url: str) -> Image.Image:
    req = urllib.request.Request(url, headers={"User-Agent": "hotstuff-sample-builder"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return Image.open(io.BytesIO(r.read())).convert("RGB")


def cover(im: Image.Image, w: int, h: int) -> Image.Image:
    s = max(w / im.width, h / im.height)
    im = im.resize((math.ceil(im.width * s), math.ceil(im.height * s)), Image.BICUBIC)
    x, y = (im.width - w) // 2, (im.height - h) // 2
    return im.crop((x, y, x + w, y + h))


def backdrop(im: Image.Image) -> Image.Image:
    bg = cover(im, W // 4, H // 4).filter(ImageFilter.GaussianBlur(10)).resize((W, H), Image.BICUBIC)
    return Image.blend(bg, Image.new("RGB", (W, H), (10, 10, 18)), 0.55)


def wrap(draw, text, fnt, max_w):
    words, lines, cur = text.split(), [], ""
    for w in words:
        trial = (cur + " " + w).strip()
        if draw.textlength(trial, font=fnt) <= max_w or not cur:
            cur = trial
        else:
            lines.append(cur)
            cur = w
    if cur:
        lines.append(cur)
    return lines


def text_center(draw, lines, fnt, y, fill="white", gap=12, stroke=0):
    for ln in lines:
        w = draw.textlength(ln, font=fnt)
        draw.text(((W - w) / 2, y), ln, font=fnt, fill=fill,
                  stroke_width=stroke, stroke_fill=(0, 0, 0))
        y += fnt.size + gap
    return y


def ease(p: float) -> float:
    return 1 - (1 - p) ** 3


class Segment:
    def __init__(self, dur: float, draw_fn):
        self.dur, self.draw_fn = dur, draw_fn


def photo_frame(photo: Image.Image, bg: Image.Image, p: float, crop=None) -> Image.Image:
    """Blurred backdrop + the supplier photo, pushing in over p in [0,1]."""
    frame = bg.copy()
    src = photo
    if crop:
        l, t, r, b = crop
        src = photo.crop((int(l * photo.width), int(t * photo.height),
                          int(r * photo.width), int(b * photo.height)))
    box = 1000 * (1 + PUSH * ease(p))
    s = box / max(src.width, src.height)
    im = src.resize((int(src.width * s), int(src.height * s)), Image.BICUBIC)
    # keep the photo inside the frame width; overflow is cropped evenly
    if im.width > W:
        x = (im.width - W) // 2
        im = im.crop((x, 0, x + W, im.height))
    frame.paste(im, ((W - im.width) // 2, 430 + int((1000 - im.height) / 2)))
    return frame


def hook_segment(v, photo, bg):
    big, sub = font(108, True), font(52)

    def draw(t):
        p = t / HOOK_S
        f = photo_frame(photo, bg, p, v.get("hook_crop"))
        f = Image.blend(f, Image.new("RGB", (W, H), (0, 0, 0)), 0.45)
        d = ImageDraw.Draw(f)
        y = 640
        for ln in v["hook"]:
            y = text_center(d, wrap(d, ln, big, 960), big, y, stroke=4)
        text_center(d, [v["hook_sub"]], sub, y + 30, fill=(255, 214, 102), stroke=3)
        return f
    return Segment(HOOK_S, draw)


def item_segment(i, n, name, photo, bg, dur):
    nm, small, tag = font(76, True), font(40), font(30)

    def draw(t):
        f = photo_frame(photo, bg, t / dur)
        d = ImageDraw.Draw(f)
        if n > 1:
            pill = f"{i + 1} / {n}"
            pw = d.textlength(pill, font=small) + 56
            d.rounded_rectangle(((W - pw) / 2, 250, (W + pw) / 2, 322), 36, fill=(255, 255, 255))
            text_center(d, [pill], small, 262, fill=(20, 20, 30))
        # name panel; slides up a touch in the first 0.3 s
        rise = int(40 * (1 - ease(min(1.0, t / 0.3))))
        d.rounded_rectangle((60, 1470 + rise, W - 60, 1760 + rise), 40, fill=(15, 15, 25))
        lines = wrap(d, name, nm, W - 200)[:3]
        lh = nm.size + 10
        y0 = 1470 + rise + (290 - lh * len(lines)) // 2
        text_center(d, lines, nm, y0, gap=10)
        d.text((80, 1400), "Supplier photo", font=tag, fill=(235, 235, 235),
                stroke_width=2, stroke_fill=(0, 0, 0))
        return f
    return Segment(dur, draw)


def end_segment(v):
    big, mid = font(84, True), font(50)
    top, bot = (99, 102, 241), (236, 72, 153)        # the store's gradient
    grad = Image.new("RGB", (W, H))
    gd = ImageDraw.Draw(grad)
    for y in range(H):
        k = y / H
        gd.line([(0, y), (W, y)], fill=tuple(int(a + (b - a) * k) for a, b in zip(top, bot)))

    def draw(t):
        f = grad.copy()
        d = ImageDraw.Draw(f)
        y = text_center(d, wrap(d, v["end"], mid, 900), mid, 760)
        text_center(d, [SITE], big, y + 40)
        return f
    return Segment(END_S, draw)


def render(segs: list[Segment], out: Path) -> float:
    total = sum(s.dur for s in segs)
    frames = int(round(total * FPS))
    cmd = [ffmpeg_bin(), "-y", "-loglevel", "error",
           "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-",
           "-f", "lavfi", "-t", f"{total:.3f}", "-i", "anullsrc=r=44100:cl=stereo",
           "-map", "0:v", "-map", "1:a",
           "-c:v", "libx264", "-preset", "medium", "-crf", "21", "-pix_fmt", "yuv420p",
           "-c:a", "aac", "-b:a", "64k", "-shortest", "-movflags", "+faststart", str(out)]
    proc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    starts, acc = [], 0.0
    for s in segs:
        starts.append(acc)
        acc += s.dur
    for fi in range(frames):
        t = fi / FPS
        k = max(i for i, st in enumerate(starts) if st <= t + 1e-9)
        lt = t - starts[k]
        cur = segs[k].draw_fn(lt)
        if k > 0 and lt < SLIDE_S:   # slide in from the right, old one out to the left
            p = ease(lt / SLIDE_S)
            prev = segs[k - 1].draw_fn(segs[k - 1].dur)
            frame = Image.new("RGB", (W, H))
            off = int(W * p)
            frame.paste(prev, (-off, 0))
            frame.paste(cur, (W - off, 0))
            cur = frame
        proc.stdin.write(cur.tobytes())
    proc.stdin.close()
    if proc.wait() != 0:
        raise SystemExit(f"ffmpeg failed for {out}")
    return total


def build(key: str, catalogue: dict, out_dir: Path) -> dict:
    v = VIDEOS[key]
    report = {"key": key, "idea": v["idea"], "format": v["format"], "products": [],
              "on_screen": [], "caption": None, "claims": {}, "lint": {}}
    if len(v["tags"]) > MAX_TAGS:
        raise SystemExit(f"{key}: {len(v['tags'])} hashtags, max {MAX_TAGS}")

    photos, segs = [], []
    for pid, name in v["items"]:
        p = catalogue.get(pid)
        if not p:
            raise SystemExit(f"{key}: {pid} is not in products.json any more; pick again")
        report["products"].append({"id": pid, "name": name, "store_price_usd": p["price"],
                                   "supplier_title": p["fullName"], "image": p["image"],
                                   "link": f"https://{SITE}/?p={pid}",
                                   "name_check": name_ok(pid, name, p["fullName"])})
        photos.append(fetch(p["image"]))

    texts = [" ".join(v["hook"]), v["hook_sub"], v["end"], SITE, "Supplier photo"] + [n for _, n in v["items"]]
    caption = v["caption"] + "\n" + " ".join(v["tags"])
    report["on_screen"], report["caption"] = texts, caption
    for label, text in [("on_screen", " | ".join(texts)), ("caption", caption)]:
        codes = claims(text)
        blocking = [c for c in codes if c not in DATE_ONLY]
        report["claims"][label] = {"codes": codes, "blocking": blocking}
        report["lint"][label] = lint(text.replace(SITE, ""))
        if blocking or report["lint"][label]:
            raise SystemExit(f"{key} {label} BLOCKED: claims {blocking}, words {report['lint'][label]}")

    bg0 = backdrop(photos[0])
    segs.append(hook_segment(v, photos[0], bg0))
    n = len(photos)
    dur = ITEM_S if n > 1 else ITEM_S + 1.4
    for i, ((pid, name), ph) in enumerate(zip(v["items"], photos)):
        segs.append(item_segment(i, n, name, ph, backdrop(ph), dur))
    segs.append(end_segment(v))

    out = out_dir / f"{key}.mp4"
    report["seconds"] = round(render(segs, out), 2)
    report["file"] = out.name
    report["kb"] = out.stat().st_size // 1024
    if not 3 <= report["seconds"] <= 60:
        raise SystemExit(f"{key}: {report['seconds']} s is outside 3-60 s")
    print(f"  {key}: {out.name} {report['seconds']} s, {report['kb']} KB, claims {report['claims']}")
    return report


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("which", nargs="*", default=list(VIDEOS))
    ap.add_argument("--out", type=Path, required=True)
    a = ap.parse_args()
    a.out.mkdir(parents=True, exist_ok=True)
    catalogue = {p["id"]: p for p in json.loads((HERE / "products.json").read_text())}
    meta = json.loads((HERE / "catalog-meta.json").read_text())
    reports = [build(k, catalogue, a.out) for k in a.which]
    (a.out / "samples.json").write_text(json.dumps(
        {"built": date.today().isoformat(), "catalogue_refreshed_at": meta.get("refreshed_at"),
         "next_refresh": meta.get("next_refresh"), "videos": reports}, indent=1))
    print(f"done: {len(reports)} video(s) in {a.out}")


if __name__ == "__main__":
    main()
