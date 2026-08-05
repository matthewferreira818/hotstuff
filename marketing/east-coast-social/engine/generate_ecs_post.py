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

# (card message, caption) pairs. Card text stays short; captions carry the CTA.
# Rotates by day-of-year so the feed never repeats back-to-back weeks.
POOL = [
    ("Your customers check your page before they choose you.",
     "Quiet page, lost customer — it's that simple. East Coast Social keeps your business posting every single day, automatically. You approve the style once. 📍 Sackville · Memramcook · Shediac · Moncton ➜ {site}"),
    ("A page that posts daily looks open. A quiet one looks closed.",
     "When did your business last post? If you have to think about it, that's the problem we fix — daily posts, zero effort from you. ➜ {site}"),
    ("This post was written, designed, and published by a machine.",
     "Really. Nobody typed this. The East Coast Social engine wrote it, built the card, and published it on schedule — the same way it can for your business, every day. ➜ {site}"),
    ("Most local pages die because nobody has time. Yours doesn't have to.",
     "You run the business. The engine runs the feed. You approve the style once and never touch it again. ➜ {site}"),
    ("180+ posts a month. Zero minutes of the owner's time.",
     "That's what our own store runs on — findhotstuff.com posts 3x a day, every day, hands-free. Your business could too. ➜ {site}"),
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
     "We don't sell anything we don't run ourselves — findhotstuff.com has posted 3x a day on full autopilot since launch. ➜ {site}"),
]


def todays_post(today=None):
    today = today or dt.date.today()
    msg, cap = POOL[today.toordinal() % len(POOL)]
    return msg, cap.format(site=SITE)


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).parent / "out"
    out.mkdir(parents=True, exist_ok=True)
    msg, caption = todays_post()
    render_card("East Coast Social", msg, out / "card.png",
                footer=SITE, tagline="Done-for-you social media · NB")
    (out / "caption.txt").write_text(caption, encoding="utf-8")
    print(f"card + caption written to {out}\n{msg}")


if __name__ == "__main__":
    main()
