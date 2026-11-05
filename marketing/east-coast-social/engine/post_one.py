"""Post ONE chosen card from the ECS rotation to the Facebook Page right now,
without touching the website feed or the daily odometer (2026-11-04: Matthew
wanted to see a new-design post live). Usage: python post_one.py <pool index>"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))
sys.path.insert(0, str(Path(__file__).parent))

import os  # noqa: E402

import generate_ecs_post as g  # noqa: E402
from ecs_card import render  # noqa: E402
from post_to_facebook import post_photo  # noqa: E402

# "intro": the page's pinned introduction (2026-11-04), so owners who come from our emails see who Matthew is first.
INTRO = ("Hi, I'm Matthew. Not an agency, just me.",
         "Welcome to East Coast Social! I'm Matthew Ferreira, from Memramcook, NB.\n\n"
         "I make daily Facebook posts for local businesses, and I'm starting small on purpose: my first two businesses, done properly. "
         "I'm not an agency: I make the posts myself, with help from AI tools, and I answer my own phone and emails.\n\n"
         "How it works:\n"
         "1. A short chat about your business.\n"
         "2. 7 sample posts, free, made from your own details. They don't go on your page, and you keep them either way.\n"
         "3. If you like them, it's $79 for a month of daily posts. You approve every post before it goes up.\n"
         "4. No password needed, and no contract: when the month ends, you decide.\n\n"
         "East Coast Social is brand new, so there are no client reviews yet. That's exactly why the samples are free.\n\n"
         "Call or text (506) 889-9737 · contact@eastcoastsocial.ca\n"
         "One-page summary: findhotstuff.com/automation")
out = Path(__file__).parent / "out" / "one-off.png"
if sys.argv[1] == "intro":
    msg, cap = INTRO
    render("story", msg, out)
else:
    i = int(sys.argv[1]) % len(g.POOL)
    msg, cap = g.POOL[i]
    cap = cap.format(site=g.SITE)
    render(g.KINDS[i], msg, out)
page_id, token = os.environ.get("FB_PAGE_ID"), os.environ.get("FB_PAGE_TOKEN")
if not page_id or not token:
    sys.exit("FB secrets not set")
print("posted:", post_photo(page_id, token, out, cap), "|", msg)
