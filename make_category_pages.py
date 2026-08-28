"""Builds evergreen category pages under /c/<slug>/.

Why this exists: the storefront rotates its entire catalogue every three
days, so no product URL ever survives long enough to accumulate search
authority — the site was, structurally, unable to rank. These pages fix
that without touching the rotation. The URL and the topic are permanent;
only the products inside change. Google gets something stable to index
while the shelf stays fresh.

Pages are generated for a FIXED list of categories and are never deleted,
even when a rotation leaves one thin — a disappearing URL is worse for
search than a quiet one. Each page links products to the store's existing
deep link (/?p=<id>), which already handles the rotated-out case, so there
is no duplicated checkout logic here.

This script also owns sitemap.xml. Category URLs have to appear there or
Google has no reason to crawl them, and a hand-maintained list would drift
the first time a category is added. STATIC_URLS below holds everything that
isn't a category page.

    python make_category_pages.py
"""

import html
import json
import re
from datetime import date
from pathlib import Path

HERE = Path(__file__).parent
PRODUCTS = HERE / "products.json"
OUT_ROOT = HERE / "c"
SITE = "https://findhotstuff.com"

# Fixed set, chosen once. Adding is safe; removing orphans a live URL.
# The blurbs are evergreen and true — they describe how this shop works,
# not the specific items, because the specific items change every 3 days.
CATEGORIES = [
    ("jewelry", "Jewelry", "Trending jewelry — rings, necklaces, bracelets",
     "Small, giftable pieces are the most-rotated corner of this shop, so this "
     "page changes often. What stays the same is how the selection is made: "
     "items are pulled from live trending data every three days, and each one "
     "is priced so the sale covers wholesale cost, worst-case shipping and "
     "payment fees before it counts as profit."),
    ("fashion", "Fashion", "Trending fashion — jackets, tops, everyday wear",
     "Clothing here follows the season and whatever is actually moving, rather "
     "than a fixed range carried year-round. Nothing is warehoused, so there is "
     "no dead stock to discount and no incentive to push an item that stopped "
     "selling."),
    ("pet", "Pet", "Trending pet supplies — beds, grooming, leashes and toys",
     "Pet gear is where product names get checked hardest. Supplier titles are "
     "translated keyword soup, and a display name here may only reorder or trim "
     "words that appear in the real supplier title — a validator rejects "
     "anything else. That rule exists because this shop once listed a roll of "
     "wallpaper as a pet bed."),
    ("kitchen", "Kitchen", "Trending kitchen gadgets and small tools",
     "Kitchen items tend to be the most practical things in the catalogue — "
     "small tools that solve one annoyance well. The lineup refreshes every "
     "three days from what is currently trending, so anything here is what was "
     "moving this week, not last season."),
    ("home", "Home", "Trending home and decor finds",
     "Lighting, storage and small decor, refreshed on the same three-day cycle "
     "as the rest of the shop. Shipping runs roughly one to three weeks because "
     "items ship directly from the supplier rather than sitting in a warehouse "
     "here — that is also why prices stay where they are."),
    ("fitness", "Fitness", "Trending fitness and workout gear",
     "Training gear that shows up in trending data, rotated every three days. "
     "As with everything in this shop, the price you see already accounts for "
     "shipping and payment fees, so there is no surprise at checkout."),
    ("bags", "Bags", "Trending bags, backpacks and purses",
     "Bags rotate with the rest of the catalogue. Every listing shows the "
     "supplier's full product title alongside the cleaned-up display name, so "
     "you can always see exactly what an item is described as at source."),
    ("footwear", "Footwear", "Trending footwear — sneakers, sandals, slippers",
     "Footwear is one of the trickier categories to buy online, so the full "
     "supplier title is kept visible on every listing and the 30-day guarantee "
     "applies here the same as everywhere else in the shop."),
    ("beauty", "Beauty", "Trending beauty — hair, makeup, skincare, nails",
     "Beauty items are described using the supplier's own words and nothing "
     "more. There are no before-and-after photos here and no results claimed, "
     "because this shop has no way to verify either — what you get is the "
     "product, the real title it ships under, and a 30-day guarantee."),
    ("wellness", "Wellness", "Trending wellness — massage, posture, recovery",
     "Braces, massagers, compression wear and posture supports, rotated with "
     "the rest of the catalogue. Nothing on this page is a medical device or a "
     "treatment, and none of it is described as one — if a supplier title makes "
     "a health claim, the claim stays in the supplier's words, not in ours."),
    ("electronics", "Electronics", "Trending electronics and small gadgets",
     "Chargers, audio, cameras and desk gear. Electronics are the category "
     "where a cheap dropshipped item most often disappoints, so the honest "
     "framing is this: these are inexpensive trending gadgets, priced like it, "
     "with the same 30-day guarantee as everything else."),
    ("toys", "Toys", "Trending toys and games",
     "Toys and games from the same three-day rotation as the rest of the shop. "
     "No age ratings or safety certifications are claimed here, because this "
     "shop can't verify them — the supplier's full product title is shown on "
     "every listing so you can see exactly what is being described."),
    ("baby", "Baby", "Trending baby gear — feeding, sleep, diapering, on the go",
     "Baby items are the ones this shop is strictest about naming, because a "
     "parent buying blind deserves the supplier's exact words. Nothing here is "
     "described as safety-tested or certified, since that isn't something this "
     "shop can verify — the full supplier title stays on every listing so you "
     "can judge it yourself."),
    ("auto", "Auto", "Trending car accessories and interior gear",
     "Mounts, interior gear, cleaning tools and lighting for a car. Fit is the "
     "usual problem with car accessories bought online, so the supplier's full "
     "title — which is where any vehicle compatibility is stated — stays "
     "visible on every listing."),
]

# sitemap.xml is rebuilt from this list plus the category pages, so adding a
# category can never leave the sitemap behind. (path, changefreq, priority)
STATIC_URLS = [
    ("/", "daily", "1.0"),
    ("/c/", "weekly", "0.7"),
    ("/automation/", "weekly", "0.8"),
    ("/automation/fr/", "weekly", "0.8"),
    ("/build/", "monthly", "0.5"),
    ("/links/", "monthly", "0.3"),
]


def write_sitemap(out_path):
    urls = list(STATIC_URLS) + [
        (f"/c/{slug}/", "weekly", "0.6") for slug, _, _, _ in CATEGORIES]
    # /notes/ pages are discovered from disk rather than listed here, so the
    # two generators can't disagree about what is published. make_notes.py
    # only writes a note's directory once it is out of draft.
    notes_root = out_path.parent / "notes"
    if (notes_root / "index.html").exists():
        urls.append(("/notes/", "weekly", "0.7"))
        urls += [(f"/notes/{d.name}/", "monthly", "0.6")
                 for d in sorted(notes_root.iterdir())
                 if d.is_dir() and (d / "index.html").exists()]
    body = "\n".join(
        f"  <url>\n    <loc>{SITE}{path}</loc>\n"
        f"    <changefreq>{freq}</changefreq>\n"
        f"    <priority>{pri}</priority>\n  </url>"
        for path, freq, pri in urls)
    out_path.write_text(
        '<?xml version="1.0" encoding="UTF-8"?>\n'
        "<!-- Generated by make_category_pages.py - do not hand-edit. -->\n"
        '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">\n'
        f"{body}\n</urlset>\n", encoding="utf-8")
    return len(urls)


CARD = """      <li class="cat-card">
        <a href="{site}/?p={pid}" class="cat-link">
          {img}
          <span class="cat-name">{name}</span>
          <span class="cat-price">${price} USD</span>
        </a>
      </li>"""


OTHER = "Everything else"


def anchor(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def grid_of(items):
    return "\n".join(
        CARD.format(
            site=SITE, pid=html.escape(str(p.get("id", ""))),
            name=html.escape(p.get("name", "")),
            price=f'{float(p.get("price", 0)):.2f}',
            img=(f'<img src="{html.escape(p["image"])}" alt="{html.escape(p.get("name",""))}" '
                 f'loading="lazy" width="240" height="240">') if p.get("image") else
                '<span class="cat-noimg" aria-hidden="true">🛍️</span>',
        ) for p in items)


def sectioned(items):
    """Split a category into subgroup sections, or return a single unlabelled
    grid when the rotation didn't leave enough to divide. Two subgroups is the
    threshold: one heading over the whole page is just a louder title."""
    groups = {}
    for p in items:
        groups.setdefault(p.get("subgroup") or OTHER, []).append(p)
    named = [g for g in groups if g != OTHER]
    if len(named) < 2:
        return "", f'  <ul class="grid">\n{grid_of(items)}\n  </ul>'

    order = sorted(named, key=lambda g: -len(groups[g]))
    if OTHER in groups:
        order.append(OTHER)
    nav = ('  <nav class="subnav">In this category: '
           + " · ".join(f'<a href="#{anchor(g)}">{html.escape(g)}</a> '
                        f'<span>{len(groups[g])}</span>' for g in order)
           + "</nav>")
    body = "\n".join(
        f'  <section>\n    <h2 id="{anchor(g)}">{html.escape(g)} '
        f'<span class="n">{len(groups[g])}</span></h2>\n'
        f'    <ul class="grid">\n{grid_of(groups[g])}\n    </ul>\n  </section>'
        for g in order)
    return nav, body


def render(slug, label, title, blurb, products, siblings):
    items = [p for p in products if p.get("category") == label]
    subnav, cards = sectioned(items)

    if items:
        count_line = (f"<strong>{len(items)}</strong> in this category right now. "
                      "The selection changes every three days.")
    else:
        count_line = ("Nothing in this category in the current rotation — the "
                      "catalogue refreshes every three days, so check back.")

    sib = " · ".join(
        f'<a href="{SITE}/c/{s}/">{l}</a>' for s, l in siblings if s != slug)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} · HotsTuff</title>
<meta name="description" content="{html.escape(blurb[:155])}">
<link rel="canonical" href="{SITE}/c/{slug}/">
<meta property="og:title" content="{html.escape(title)} · HotsTuff">
<meta property="og:description" content="{html.escape(blurb[:155])}">
<meta property="og:url" content="{SITE}/c/{slug}/">
<meta property="og:image" content="{SITE}/assets/og-card.png">
<script type="application/ld+json">
{{"@context":"https://schema.org","@type":"CollectionPage",
 "name":{json.dumps(title)},"description":{json.dumps(blurb)},
 "url":"{SITE}/c/{slug}/","isPartOf":{{"@type":"WebSite","name":"HotsTuff","url":"{SITE}"}}}}
</script>
<style>
  :root {{ --bg:#12090d; --card:#1d1116; --ink:#f6eef1; --muted:#b9a4ac;
          --line:rgba(246,238,241,.14); --hot:#ff4d6d; --amber:#ffa62b; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--ink); line-height:1.6;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }}
  a {{ color:var(--amber); }}
  .wrap {{ max-width:1040px; margin:0 auto; padding:0 20px; }}
  header.bar {{ border-bottom:1px solid var(--line); padding:14px 0; }}
  header.bar a {{ color:var(--ink); text-decoration:none; font-weight:700; }}
  h1 {{ font-size:clamp(1.6rem,4.5vw,2.3rem); margin:28px 0 10px; }}
  .blurb {{ color:var(--muted); max-width:60ch; margin:0 0 6px; }}
  .count {{ color:var(--muted); font-size:.92rem; margin:0 0 26px; }}
  ul.grid {{ list-style:none; padding:0; margin:0 0 40px;
            display:grid; gap:16px;
            grid-template-columns:repeat(auto-fill,minmax(160px,1fr)); }}
  .cat-card {{ background:var(--card); border:1px solid var(--line);
              border-radius:14px; overflow:hidden; }}
  .cat-link {{ display:block; text-decoration:none; color:inherit; padding-bottom:12px; }}
  .cat-card img {{ width:100%; height:auto; aspect-ratio:1/1; object-fit:cover; display:block; }}
  .cat-noimg {{ display:grid; place-items:center; aspect-ratio:1/1; font-size:2.4rem;
               background:linear-gradient(135deg,#2a1620,#1d1116); }}
  .cat-name {{ display:block; padding:10px 12px 2px; font-weight:600; font-size:.95rem; }}
  .cat-price {{ display:block; padding:0 12px; color:var(--amber); font-weight:700; }}
  nav.subnav {{ margin:0 0 30px; color:var(--muted); font-size:.92rem; }}
  nav.subnav a {{ text-decoration:none; }}
  nav.subnav span {{ opacity:.6; }}
  section h2 {{ font-size:1.1rem; margin:34px 0 12px; scroll-margin-top:14px; }}
  section h2 .n {{ color:var(--muted); font-weight:400; font-size:.85rem; }}
  nav.sib {{ border-top:1px solid var(--line); padding:22px 0; color:var(--muted); font-size:.94rem; }}
  footer {{ color:var(--muted); font-size:.86rem; padding:10px 0 40px; }}
</style>
</head>
<body>
<header class="bar"><div class="wrap"><a href="{SITE}/">← HotsTuff</a></div></header>
<main class="wrap">
  <h1>{html.escape(title)}</h1>
  <p class="blurb">{html.escape(blurb)}</p>
  <p class="count">{count_line}</p>
{subnav}
{cards}
</main>
<nav class="sib"><div class="wrap">More categories: {sib}</div></nav>
<footer class="wrap">
  Prices in USD · free shipping · 30-day guarantee ·
  <a href="{SITE}/">see the full shop</a><br>
  Selection last refreshed {date.today().isoformat()}.
</footer>
<script data-goatcounter="https://theycallmemattyb.goatcounter.com/count" async src="//gc.zgo.at/count.js"></script>
</body>
</html>
"""


def hub(siblings, counts):
    rows = "\n".join(
        f'    <li><a href="{SITE}/c/{s}/">{l}</a> '
        f'<span>{counts.get(l, 0)} right now</span></li>'
        for s, l in siblings)
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Shop by category · HotsTuff</title>
<meta name="description" content="Browse HotsTuff by category. The lineup refreshes every three days from live trending data; these category pages stay put.">
<link rel="canonical" href="{SITE}/c/">
<style>
  body {{ margin:0; background:#12090d; color:#f6eef1; line-height:1.6;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,sans-serif; }}
  .wrap {{ max-width:720px; margin:0 auto; padding:0 20px; }}
  a {{ color:#ffa62b; }}
  h1 {{ margin:30px 0 8px; }}
  p.lede {{ color:#b9a4ac; }}
  ul {{ list-style:none; padding:0; }}
  li {{ border-bottom:1px solid rgba(246,238,241,.14); padding:14px 0;
       display:flex; justify-content:space-between; gap:12px; }}
  li span {{ color:#b9a4ac; font-size:.9rem; }}
  header.bar {{ border-bottom:1px solid rgba(246,238,241,.14); padding:14px 0; }}
  header.bar a {{ color:#f6eef1; text-decoration:none; font-weight:700; }}
</style>
</head>
<body>
<header class="bar"><div class="wrap"><a href="{SITE}/">← HotsTuff</a></div></header>
<main class="wrap">
  <h1>Shop by category</h1>
  <p class="lede">The shop's lineup is rebuilt every three days from live
     trending data. These category pages don't move — only what's inside them
     does.</p>
  <ul>
{rows}
  </ul>
</main>
<script data-goatcounter="https://theycallmemattyb.goatcounter.com/count" async src="//gc.zgo.at/count.js"></script>
</body>
</html>
"""


def main():
    products = json.loads(PRODUCTS.read_text(encoding="utf-8"))
    siblings = [(slug, label) for slug, label, _, _ in CATEGORIES]
    counts = {}
    for slug, label, title, blurb in CATEGORIES:
        page = render(slug, label, title, blurb, products, siblings)
        out = OUT_ROOT / slug
        out.mkdir(parents=True, exist_ok=True)
        (out / "index.html").write_text(page, encoding="utf-8")
        counts[label] = sum(1 for p in products if p.get("category") == label)
        print(f"  /c/{slug}/  {counts[label]} products")
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / "index.html").write_text(hub(siblings, counts), encoding="utf-8")
    print(f"  /c/  hub with {len(CATEGORIES)} categories")
    n = write_sitemap(HERE / "sitemap.xml")
    print(f"  sitemap.xml  {n} URLs")


if __name__ == "__main__":
    main()
