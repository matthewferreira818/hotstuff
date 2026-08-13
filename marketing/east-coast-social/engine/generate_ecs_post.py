"""
Generates East Coast Social's own daily Facebook post (client #0 of its own
engine): picks today's message deterministically from the rotation pool,
renders the branded card, and writes caption.txt + card.png for the poster.

    python generate_ecs_post.py [out_dir]
"""

import datetime as dt
import sys
from pathlib import Path

from post_card import render_card

# ?ref=ecs: the caption lands on X, Facebook, and manual posts alike, so the
# tag names the funnel (ECS daily caption), not a single platform
SITE = "findhotstuff.com/automation/?ref=ecs"
FEED_KEEP = 8   # how many past posts the website feed shows

# (card message, caption) pairs. Card text stays short; captions carry the CTA.
# Rotates by day-of-year so the feed never repeats back-to-back weeks.
POOL = [
    ("Your customers check your page before they choose you.",
     "Quiet page, lost customer — it's that simple. East Coast Social keeps your business posting every single day, automatically. You approve the style once. 📍 Sackville · Memramcook · Shediac · Moncton ➜ {site}"),
    ("A page that posts daily looks open. A quiet one looks closed.",
     "When did your business last post? If you have to think about it, that's the problem we fix — daily posts, zero effort from you. ➜ {site}"),
    ("Your day off shouldn't mean your page's day off.",
     "The engine keeps posting when you're closed, on vacation, or slammed — daily branded posts, approved by you once. ➜ {site}"),
    ("Most local pages die because nobody has time. Yours doesn't have to.",
     "You run the business. The engine runs the feed. You approve the style once and never touch it again. ➜ {site}"),
    ("One less job every single morning.",
     "Posting daily is a part-time job nobody hired for. The engine does it — you approve the style once, then it's handled. ➜ {site}"),
    ("Daily specials could announce themselves.",
     "Restaurants, cafés, food trucks: your feature board is content. The engine turns it into daily posts your customers actually see. ➜ {site}"),
    ("Fresh cuts, new arrivals, today's bake — that's a feed, not a chore.",
     "Whatever you make every day is worth posting every day. We automate exactly that. ➜ {site}"),
    ("What's your page been doing since spring?",
     "If the answer is 'nothing', your customers noticed too. Daily automated posts, tuned to your business, approved by you once. ➜ {site}"),
    ("Posting every day isn't discipline. It's automation.",
     "The businesses that post daily aren't trying harder — they've stopped doing it by hand. ➜ {site}"),
    ("Your competition posted today. Did you?",
     "The engine never forgets, never gets busy, never takes a vacation. Daily branded posts for your business. ➜ {site}"),
    ("One 20-minute chat. Then your page runs itself.",
     "That's the whole setup: we talk about your business, you approve sample posts, the engine takes it from there. ➜ {site}"),
    ("Built on our own store first. Proven every single day.",
     "We don't sell anything we don't run ourselves — our own store's feed, catalog and daily cards run on this exact engine. ➜ {site}"),
]


def todays_post(today=None):
    today = today or dt.date.today()
    msg, cap = POOL[today.toordinal() % len(POOL)]
    return msg, cap.format(site=SITE)


def archive(card_path, msg, caption, today):
    """Keep a dated copy so the automation page can show a live feed of what
    the engine actually published. Newest first, capped at FEED_KEEP entries."""
    import json
    import shutil

    repo = Path(__file__).resolve().parents[3]
    feed = repo / "automation" / "feed"
    feed.mkdir(parents=True, exist_ok=True)

    stamp = today.isoformat()
    shutil.copyfile(card_path, feed / f"{stamp}.png")

    index_file = feed / "index.json"
    try:
        entries = json.loads(index_file.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        entries = []

    entries = [e for e in entries if e.get("date") != stamp]
    entries.insert(0, {"date": stamp, "image": f"{stamp}.png",
                       "message": msg, "caption": caption})
    entries = entries[:FEED_KEEP]

    # drop image files that fell off the end of the feed
    keep = {e["image"] for e in entries}
    for old in feed.glob("*.png"):
        if old.name not in keep:
            old.unlink()

    index_file.write_text(json.dumps(entries, indent=1, ensure_ascii=False), encoding="utf-8")
    print(f"feed archive updated: {len(entries)} posts")

    # odometer: all-time distinct-day count for the honest proof line on the
    # automation page — the rolling index above can't say it. Bumps once per
    # calendar day (re-runs and re-renders of the same day never double-count).
    stats_file = feed / "stats.json"
    try:
        stats = json.loads(stats_file.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        stats = {"total": 0, "since": stamp, "last": ""}
    if stamp > stats.get("last", ""):
        stats["total"] = int(stats.get("total", 0)) + 1
        stats["last"] = stamp
        stats.setdefault("since", stamp)
        stats_file.write_text(json.dumps(stats), encoding="utf-8")
        print(f"odometer: {stats['total']} posts since {stats['since']}")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "out"
    out.mkdir(parents=True, exist_ok=True)
    msg, caption = todays_post()
    card = out / "card.png"
    render_card("East Coast Social", msg, card,
                footer=SITE, tagline="Done-for-you social media · NB")
    (out / "caption.txt").write_text(caption, encoding="utf-8")
    print(f"card + caption written to {out}\n{msg}")
    try:
        archive(card, msg, caption, dt.date.today())
    except Exception as exc:  # noqa: BLE001 - a feed hiccup must not block posting
        print(f"feed archive skipped ({exc})")


if __name__ == "__main__":
    main()
