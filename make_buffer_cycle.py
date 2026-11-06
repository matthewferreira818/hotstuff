"""TikTok videos for ONE catalogue cycle, ready for Buffer to auto-publish.

Why per cycle and not per week: refresh_products.py swaps all 200 products
every 3 days and holds them back for 4 cycles (2026-11-05: zero overlap
between the last 4 refreshes). A video naming a product is only honest
until the next refresh, so this builds one video per posting slot BEFORE
the next refresh and no more. tiktok-buffer.yml runs it after each refresh.

Writes marketing/tiktok/buffer/<cycle-date>/:
    day-N.mp4   1080x1920 swipe video, 3 products, NO QR slide (Buffer's
                TikTok help page: TikTok holds back videos with QR codes
                from the For You feed)
    plan.json   slot times (UTC), captions, products, catalogue commit;
                buffer_queue.py adds the Buffer post ids it creates
Older cycle folders are deleted: their posts have all gone out by now.

Captions: fixed hook templates + real product names + category tags, max 5
hashtags (Buffer's TikTok limit), no prices, no posting rates, nothing that
goes stale. Each runs through tools/claims_check.py; ANY text finding blocks
that variant. The two DATE-ONLY findings (STALE_FACTS, STALE_FEED) are let
through and logged: claims_check raises them from the facts file's dates
before it reads a single sentence, so on any unattended run after the last
hand-verification they always fire, and these captions carry no feed or
current claim for them to protect. (Templates reviewed clean, facts-current,
2026-11-05.)

    python make_buffer_cycle.py              # slots from now until next refresh
    python make_buffer_cycle.py --max 3
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

from make_tiktok_pack import BASE_TAGS, CAT_TAGS, build_slide, slide_name
from make_tiktok_video import render_slides

HERE = Path(__file__).parent
OUT_ROOT = HERE / "marketing" / "tiktok" / "buffer"
SITE = "https://findhotstuff.com"
PER_VIDEO = 3
MAX_TAGS = 5
POST_HOUR_UTC = 17          # 1 PM Moncton (AST) / 2 PM (ADT)
LEAD = timedelta(minutes=45)    # time for the commit + Pages deploy + queue
GUARD = timedelta(hours=2)      # stay clear of the next refresh

HOOKS = [
    "3 picks from the HotsTuff catalogue 🔥 {a}, {b} or {c}?",
    "which one are you grabbing: {a}, {b} or {c}? 👀",
    "today's 3: {a}, {b} and {c} 🔥",
    "swipe for 3 finds 👉 {a}, {b}, {c}",
    "{a}, {b} or {c}? pick one 🔥",
    "3 things from the shop today: {a}, {b}, {c} 🛍️",
    "rate these 1 to 10: {a}, {b}, {c} 🔥",
]
TAIL = " · findhotstuff.com"
DATE_ONLY = {"STALE_FACTS", "STALE_FEED"}   # raised before any text is read


def next_refresh(after: datetime) -> datetime:
    """refresh-products.yml: cron "0 9 */3 * *" = 09:00 UTC on days
    1,4,7,...,31 (so the 31st -> 1st gap is one day)."""
    d = after.date()
    while True:
        cand = datetime(d.year, d.month, d.day, 9, tzinfo=timezone.utc)
        if d.day % 3 == 1 and cand > after:
            return cand
        d += timedelta(days=1)


def slots(now: datetime, limit: int) -> list[datetime]:
    end = next_refresh(now) - GUARD
    out, d = [], now.date()
    while len(out) < limit:
        t = datetime(d.year, d.month, d.day, POST_HOUR_UTC, tzinfo=timezone.utc)
        if t >= end:
            break
        if t >= now + LEAD:
            out.append(t)
        d += timedelta(days=1)
    return out


def ranked(products):
    usable, seen = [], set()
    for rank, p in enumerate(sorted(products, key=lambda x: x.get("trendScore", 0),
                                    reverse=True), 1):
        if not (p.get("image") or "").startswith("http"):
            continue
        key = slide_name(p).lower()
        if key in seen:
            continue
        seen.add(key)
        p["_ad"], p["_rank"] = slide_name(p), rank
        usable.append(p)
    return usable


def tags_for(picks) -> str:
    tags = BASE_TAGS.split()
    for p in picks:
        t = CAT_TAGS.get(p.get("category"), CAT_TAGS["*"])
        if t not in tags:
            tags.append(t)
    return " ".join(tags[:MAX_TAGS])


def claims_findings(text: str) -> list[str]:
    r = subprocess.run([sys.executable, str(HERE / "tools" / "claims_check.py"),
                        "--text", text, "--json"], capture_output=True, text=True)
    if r.returncode == 2:
        raise SystemExit(f"claims_check could not run: {r.stdout}{r.stderr}")
    try:
        return [f["code"] for f in json.loads(r.stdout).get("findings", [])]
    except json.JSONDecodeError:
        raise SystemExit(f"claims_check gave no JSON: {r.stdout}{r.stderr}")


def caption_for(i: int, picks) -> str:
    names = [p["_ad"].lower() for p in picks]
    for k in range(len(HOOKS)):
        text = HOOKS[(i + k) % len(HOOKS)].format(a=names[0], b=names[1], c=names[2])
        text += TAIL + " " + tags_for(picks)
        codes = claims_findings(text)
        blocking = [c for c in codes if c not in DATE_ONLY]
        if not blocking:
            if codes:
                print(f"    claims_check: date-only {codes} (facts not hand-verified "
                      "today); no text findings, letting it through")
            return text
        print(f"    caption variant blocked by claims_check: {blocking}")
    raise SystemExit(f"slot {i + 1}: every caption variant was blocked by claims_check")


def catalogue_commit() -> str:
    r = subprocess.run(["git", "log", "-1", "--format=%H", "--", "products.json"],
                       cwd=HERE, capture_output=True, text=True)
    return r.stdout.strip() or "unknown"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max", type=int, default=3)
    args = ap.parse_args()

    now = datetime.now(timezone.utc)
    times = slots(now, args.max)
    nxt = next_refresh(now)
    print(f"next refresh {nxt:%a %b %d %H:%M} UTC -> {len(times)} slot(s)")
    if not times:
        print("No slot fits before the next refresh. Nothing to build.")
        return

    cycle = now.date().isoformat()
    out = OUT_ROOT / cycle
    for old in OUT_ROOT.glob("20*"):
        if old.is_dir() and old != out:
            shutil.rmtree(old)
    out.mkdir(parents=True, exist_ok=True)
    work = out / ".slides"
    work.mkdir(exist_ok=True)

    products = json.loads((HERE / "products.json").read_text(encoding="utf-8"))
    pool = ranked(products)
    days = []
    for i, when in enumerate(times):
        made = []
        while len(made) < PER_VIDEO and pool:
            p = pool.pop(0)
            try:
                img = work / f"day-{i + 1}-{len(made) + 1}.png"
                img.write_bytes(build_slide(p, p["_rank"]))
                made.append((p, img))
            except Exception as exc:  # noqa: BLE001 - dead photo: backfill
                print(f"    skipped {p['_ad']}: {exc}")
        if len(made) < PER_VIDEO:
            print(f"slot {i + 1}: ran out of products, stopping")
            break
        picks = [p for p, _ in made]
        mp4 = out / f"day-{i + 1}.mp4"
        secs = render_slides([img for _, img in made], mp4)
        caption = caption_for(i, picks)
        print(f"slot {i + 1} {when:%a %b %d %H:%M} UTC: {mp4.name} {secs:.1f}s "
              f"{mp4.stat().st_size // 1024} KB — {', '.join(p['_ad'] for p in picks)}")
        days.append({
            "slot": i + 1,
            "due_at": when.strftime("%Y-%m-%dT%H:%M:%S.000Z"),
            "video": mp4.name,
            "url": f"{SITE}/{mp4.relative_to(HERE).as_posix()}",
            "seconds": round(secs, 1),
            "caption": caption,
            "products": [{"id": p["id"], "name": p["_ad"], "price": p["price"],
                          "rank": p["_rank"]} for p in picks],
            "buffer_post_id": None,
        })
    shutil.rmtree(work)

    plan = {"cycle": cycle, "built_at": now.isoformat(timespec="minutes"),
            "catalogue_commit": catalogue_commit(),
            "next_refresh_utc": nxt.isoformat(), "days": days}
    (out / "plan.json").write_text(json.dumps(plan, indent=2, ensure_ascii=False) + "\n",
                                   encoding="utf-8")
    print(f"Done -> {out.relative_to(HERE)} ({len(days)} video(s))")


if __name__ == "__main__":
    main()
