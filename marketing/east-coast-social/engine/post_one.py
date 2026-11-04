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

i = int(sys.argv[1]) % len(g.POOL)
msg, cap = g.POOL[i]
cap = cap.format(site=g.SITE)
out = Path(__file__).parent / "out" / "one-off.png"
render(g.KINDS[i], msg, out)
page_id, token = os.environ.get("FB_PAGE_ID"), os.environ.get("FB_PAGE_TOKEN")
if not page_id or not token:
    sys.exit("FB secrets not set")
print("posted:", post_photo(page_id, token, out, cap), "|", g.KINDS[i], "|", msg)
