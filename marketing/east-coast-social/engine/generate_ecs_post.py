"""
Generates East Coast Social's own daily Facebook post (client #0 of its own
engine): picks today's message deterministically from the rotation pool,
renders the branded card, and writes caption.txt + card.png for the poster.

    python generate_ecs_post.py [out_dir]
"""

import datetime as dt
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))  # repo root

from ecs_site import ecs_url  # noqa: E402
from ecs_card import render  # 2026-11-04 redesign: a look per kind of post

# ?ref=ecs: the caption lands on X, Facebook, and manual posts alike, so the
# tag names the funnel (ECS daily caption), not a single platform
SITE = ecs_url("ecs", bare=True)
FEED_KEEP = 8   # how many past posts the website feed shows

# (card message, caption) pairs. Card text stays short; captions carry the CTA.
# Rewritten 2026-11-04 (Matthew: "they seem very similar to each other"): four
# kinds, interleaved so no two days in a row feel alike: a free tip, a post idea
# for one type of business, honest behind-the-scenes, and the offer as it
# stands TODAY (7 free samples, owner OKs every post, $79 for a month, no
# commitment after). The old "approve the style once / zero effort" lines were
# retired: they described an offer we no longer make. Rule 1: every line here
# must stay true; change it the day it stops being true.
POOL = [
    ("Pin a post with your hours, address and phone.",
     "Free tip for local businesses: pin one post to the top of your page with your hours, address and phone number. It's the first thing new customers look for. ➜ {site}"),
    ("Post idea for bakeries: what came out of the oven this morning.",
     "One photo, one line, every morning. \"Fresh this morning: cinnamon buns, sourdough, date squares.\" Simple posts like that remind people you're right there. ➜ {site}"),
    ("We're looking for our first two local businesses.",
     "East Coast Social is brand new, and we're starting small on purpose: two local businesses, done properly. If your Facebook page has gone quiet, we'd love to hear from you. ➜ {site}"),
    ("7 free sample posts. Yours to keep, either way.",
     "Here's how we start: we make you 7 sample posts from your own business, free. Nothing goes on your page, and you keep them whether or not you go further. ➜ {site}"),
    ("A real photo beats a stock photo.",
     "Free tip: customers want to see your actual shop, your actual team and your actual work. A slightly imperfect real photo builds more trust than a polished stock one. ➜ {site}"),
    ("Post idea for plumbers and electricians: before and after.",
     "A before-and-after photo of a job (with the customer's OK) shows your work better than any ad. Add one line: what you fixed and the town you were in. ➜ {site}"),
    ("Built on our own store first.",
     "We test everything on our own online store before we offer it to anyone else. Its feed has published a new post every day since August 7. You can check it yourself. ➜ {site}"),
    ("Nothing goes up on your page without your OK.",
     "With East Coast Social, you see every post before it's published. Don't like one? We change it or skip it. Your page, your call, always. ➜ {site}"),
    ("Answer comments within a day.",
     "Free tip: a quick reply to a comment or question tells everyone reading that you're open and you care. Even \"Thanks! See you Saturday\" counts. ➜ {site}"),
    ("Post idea for farms: what's fresh this week.",
     "A weekly \"what's fresh\" post with one photo and where to find you saves your regulars a trip for nothing and pulls in new ones. ➜ {site}"),
    ("Made in Memramcook, for businesses around here.",
     "East Coast Social is a one-person shop in Memramcook, NB, starting out making Facebook posts for local businesses in Shediac, Moncton, Dieppe, Sackville and nearby. ➜ {site}"),
    ("$79 for a month of daily posts. No commitment after.",
     "After your free samples, if you like them: $79 for a month of daily posts on your Facebook page. You approve each one. When the month ends, you decide if you want another. ➜ {site}"),
    ("Changed your hours? Post it the same day.",
     "Free tip: holiday hours, snow-day closures and winter schedules are some of the most useful posts you can make. People check your page before they drive over. ➜ {site}"),
    ("Post idea for salons and barbers: today's openings.",
     "\"Two openings left this afternoon, call or message to book.\" A quick post like that can fill a chair that would have stayed empty. ➜ {site}"),
    ("Why we started East Coast Social.",
     "So many good local businesses have Facebook pages that stopped posting, because the owner is busy running the business. That's the gap we want to fill, one business at a time. ➜ {site}"),
    ("You tell us about your business. We write the posts.",
     "How it works: a short chat about what you do, then we make your posts from your own details and photos. You OK each one before it goes up. ➜ {site}"),
    ("Show the people behind the counter.",
     "Free tip: a \"meet the team\" post, one person and one fun fact, gets people feeling like they already know you before they walk in. ➜ {site}"),
    ("Post idea for B&Bs and inns: the view this morning.",
     "A morning photo from your porch or window, plus what's happening nearby this weekend. It helps people picture their stay. ➜ {site}"),
    ("Small and local, like you.",
     "We're not an agency. It's Matthew, in Memramcook, making the posts himself with help from AI tools, and answering his own emails. ➜ {site}"),
    ("A quiet page can look like a closed business.",
     "Free tip: if your last post is months old, new customers may wonder if you're still open. Even one short post a week helps. ➜ {site}"),
    ("Post idea for restaurants: today's special, one photo.",
     "Your special board is already content. Snap it, post it, done. Regulars love knowing what's on before they come in. ➜ {site}"),
]


# The card's look for each POOL entry, same order (ecs_card.THEMES).
KINDS = ['tip', 'idea', 'story', 'offer', 'tip', 'idea', 'story', 'offer', 'tip', 'idea', 'story', 'offer', 'tip', 'idea', 'story', 'offer', 'tip', 'idea', 'story', 'tip', 'idea']
assert len(KINDS) == len(POOL)


def todays_post(today=None):
    today = today or dt.date.today()
    msg, cap = POOL[today.toordinal() % len(POOL)]
    return msg, cap.format(site=SITE)


def todays_kind(today=None):
    today = today or dt.date.today()
    return KINDS[today.toordinal() % len(POOL)]


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
    render(todays_kind(), msg, card)
    (out / "caption.txt").write_text(caption, encoding="utf-8")
    print(f"card + caption written to {out}\n{msg}")
    try:
        archive(card, msg, caption, dt.date.today())
    except Exception as exc:  # noqa: BLE001 - a feed hiccup must not block posting
        print(f"feed archive skipped ({exc})")


if __name__ == "__main__":
    main()
