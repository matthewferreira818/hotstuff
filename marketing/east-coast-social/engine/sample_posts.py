"""
Prospect sample-post generator — the closer for warm replies.

Give it a business name, their brand colors, and (optionally) a folder of
their photos; it renders three sample daily-post cards in THEIR branding so
they can see exactly what their feed would look like running on the engine.

    python sample_posts.py "Jacks Pizza" --accent "#e8590c" \
        --photos path/to/photos --type pizza

Writes to samples/<business-slug>/sample-1.png ... sample-3.png
Send them with: "Here's what your page would post this week."
"""

import argparse
import re
from pathlib import Path

from post_card import render_card

HERE = Path(__file__).parent

# Three-message arcs per business type: (what's-new, behind-the-scenes, CTA).
# "generic" covers anything unlisted; add types as prospects appear.
ARCS = {
    "pizza": ["Tonight's special: large 2-topping + garlic fingers.",
              "Fresh dough, every single morning. That's the difference.",
              "Order ahead and skip the wait — call us now."],
    "restaurant": ["This week's feature is here — come hungry.",
                   "Behind every plate: fresh, local, made today.",
                   "Book your table for the weekend before it fills."],
    "salon": ["Fresh look Friday — this week's transformations.",
              "Colour season is here. Your chair is waiting.",
              "A few openings left this week — grab yours."],
    "gym": ["Member win of the week — strength looks good on you.",
            "New class on the schedule. First one's on us.",
            "Summer memberships are open — start today."],
    "auto": ["Just landed on the lot — come kick the tires.",
             "Every vehicle inspected before it wears our name.",
             "Trade-ins welcome — find out what yours is worth."],
    "trades": ["Booked solid this week — thank you, neighbours.",
               "Before and after: another job done right.",
               "Fall bookings are opening — get on the list."],
    "bookstore": ["New arrivals just hit the shelves.",
                  "Staff pick of the week — ask us why we loved it.",
                  "Order any book — we'll have it in days."],
    "generic": ["Here's what's new this week.",
                "The story behind what we do every day.",
                "Stop in this week — we'd love to see you."],
}


def slug(s):
    return re.sub(r"[^a-z0-9]+", "-", s.lower()).strip("-")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("business")
    ap.add_argument("--type", default="generic", choices=sorted(ARCS))
    ap.add_argument("--accent", default="#f0b429")
    ap.add_argument("--bg", default="#101418")
    ap.add_argument("--photos", default=None, help="folder of their photos")
    args = ap.parse_args()

    photos = sorted(Path(args.photos).glob("*")) if args.photos else []
    out_dir = HERE / "samples" / slug(args.business)
    for i, msg in enumerate(ARCS[args.type], 1):
        render_card(args.business, msg, out_dir / f"sample-{i}.png",
                    bg=args.bg, accent=args.accent,
                    footer=f"{args.business} — posted automatically",
                    photo=str(photos[i - 1]) if len(photos) >= i else None)
    print(f"3 samples -> {out_dir}")


if __name__ == "__main__":
    main()
