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
    ("jewelry", "Jewelry", "Jewelry finds — rings, necklaces, bracelets",
     "Small, giftable pieces are the most-rotated corner of this shop, so this "
     "page changes often. What stays the same is how the selection is made: "
     "items come from our supplier's trending list every three days, and each one "
     "is priced so the sale covers wholesale cost, worst-case shipping and "
     "payment fees before it counts as profit."),
    ("fashion", "Fashion", "Fashion finds — jackets, tops, everyday wear",
     "Clothing here follows the season and our supplier's trending list, rather "
     "than a fixed range carried year-round. Nothing is warehoused, so there is "
     "no dead stock to discount and no incentive to push an item that stopped "
     "selling."),
    ("pet", "Pet", "Pet finds — beds, grooming, leashes and toys",
     "Pet gear is where product names get checked hardest. Supplier titles are "
     "translated keyword soup, and a display name here may only reorder or trim "
     "words that appear in the real supplier title — a validator rejects "
     "anything else. That rule exists because this shop once listed a roll of "
     "wallpaper as a pet bed."),
    ("kitchen", "Kitchen", "Kitchen gadgets and small tools",
     "Kitchen items tend to be the most practical things in the catalogue — "
     "small tools that solve one annoyance well. The lineup refreshes every "
     "three days from our supplier's trending list, so what's here is this "
     "week's lineup, not last season's."),
    ("home", "Home", "Home and decor finds",
     "Lighting, storage and small decor, refreshed on the same three-day cycle "
     "as the rest of the shop. Shipping runs roughly one to three weeks because "
     "items ship directly from the supplier rather than sitting in a warehouse "
     "here — that is also why prices stay where they are."),
    ("fitness", "Fitness", "Fitness and workout gear",
     "Training gear from our supplier's trending list, rotated every three days. "
     "As with everything in this shop, the price you see already accounts for "
     "shipping and payment fees, so there is no surprise at checkout."),
    ("bags", "Bags", "Bags, backpacks and purses",
     "Bags rotate with the rest of the catalogue. Every listing shows the "
     "supplier's full product title alongside the cleaned-up display name, so "
     "you can always see exactly what an item is described as at source."),
    ("footwear", "Footwear", "Footwear finds — sneakers, sandals, slippers",
     "Footwear is one of the trickier categories to buy online, so the full "
     "supplier title is kept visible on every listing and the 30-day guarantee "
     "applies here the same as everywhere else in the shop."),
    ("beauty", "Beauty", "Beauty finds — hair, makeup, skincare, nails",
     "Beauty items are described using the supplier's own words and nothing "
     "more. There are no before-and-after photos here and no results claimed, "
     "because this shop has no way to verify either — what you get is the "
     "product, the real title it ships under, and a 30-day guarantee."),
    ("wellness", "Wellness", "Wellness finds — massage, posture, recovery",
     "Braces, massagers, compression wear and posture supports, rotated with "
     "the rest of the catalogue. Nothing on this page is a medical device or a "
     "treatment, and none of it is described as one — if a supplier title makes "
     "a health claim, the claim stays in the supplier's words, not in ours."),
    ("electronics", "Electronics", "Electronics and small gadgets",
     "Chargers, audio, cameras and desk gear. Electronics are the category "
     "where a cheap dropshipped item most often disappoints, so the honest "
     "framing is this: these are inexpensive gadgets, priced like it, "
     "with the same 30-day guarantee as everything else."),
    ("toys", "Toys", "Toys and games",
     "Toys and games from the same three-day rotation as the rest of the shop. "
     "No age ratings or safety certifications are claimed here, because this "
     "shop can't verify them — the supplier's full product title is shown on "
     "every listing so you can see exactly what is being described."),
    ("baby", "Baby", "Baby gear — feeding, sleep, diapering, on the go",
     "Baby items are the ones this shop is strictest about naming, because a "
     "parent buying blind deserves the supplier's exact words. Nothing here is "
     "described as safety-tested or certified, since that isn't something this "
     "shop can verify — the full supplier title stays on every listing so you "
     "can judge it yourself."),
    ("auto", "Auto", "Car accessories and interior gear",
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
    ("/gifts/", "weekly", "0.7"),
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
        <a href="{site}/?p={pid}&amp;ref={ref}" class="cat-link">
          {img}
          <span class="cat-name">{name}</span>
          <span class="cat-price">${price} USD</span>
        </a>
      </li>"""


OTHER = "Everything else"


def anchor(name):
    return re.sub(r"[^a-z0-9]+", "-", name.lower()).strip("-")


def grid_of(items, ref="cat"):
    # ?ref= lets GoatCounter tell category/gift visits apart (council 2026-11-05).
    # The store only reads ?p=, so the extra tag never changes which product opens.
    return "\n".join(
        CARD.format(
            site=SITE, ref=ref, pid=html.escape(str(p.get("id", ""))),
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
    sib += f' · <a href="{SITE}/gifts/">Gifts under ${GIFT_MAX}</a>'
    return page_html(f"/c/{slug}/", title, blurb, count_line, subnav, cards,
                     f"More categories: {sib}")


def page_html(path, title, blurb, count_line, subnav, cards, sib_line, note=""):
    """One page layout for category pages and the gift page."""
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{html.escape(title)} · HotsTuff</title>
<meta name="description" content="{html.escape(blurb[:155])}">
<link rel="canonical" href="{SITE}{path}">
<meta property="og:title" content="{html.escape(title)} · HotsTuff">
<meta property="og:description" content="{html.escape(blurb[:155])}">
<meta property="og:url" content="{SITE}{path}">
<meta property="og:image" content="{SITE}/assets/og-card.png">
<script type="application/ld+json">
{{"@context":"https://schema.org","@type":"CollectionPage",
 "name":{json.dumps(title)},"description":{json.dumps(blurb)},
 "url":"{SITE}{path}","isPartOf":{{"@type":"WebSite","name":"HotsTuff","url":"{SITE}"}}}}
</script>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,600&display=swap">
<style>
  /* Boutique look, matching the store front (2026-11-06). Content unchanged. */
  :root {{ --bg:#fbf8f3; --card:#ffffff; --ink:#2b2622; --muted:#7d746b;
          --line:rgba(43,38,34,.12); --hot:#e11d48; --amber:#f59e0b;
          --serif:"Fraunces",Georgia,"Times New Roman",serif; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--bg); color:var(--ink); line-height:1.6;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,sans-serif; }}
  a {{ color:var(--hot); }}
  .wrap {{ max-width:1120px; margin:0 auto; padding:0 20px; }}
  header.bar {{ position:sticky; top:0; z-index:5; background:rgba(251,248,243,.92); backdrop-filter:blur(10px);
               border-bottom:1px solid var(--line); padding:12px 0; }}
  header.bar a {{ color:var(--ink); text-decoration:none; font-weight:700; display:inline-flex; align-items:center; gap:8px; }}
  header.bar a::before {{ content:"H"; display:inline-grid; place-items:center; width:28px; height:28px; border-radius:8px;
               background:linear-gradient(135deg,var(--hot),var(--amber)); color:#fff; font-size:14px; font-weight:800; }}
  h1 {{ font-family:var(--serif); font-weight:600; letter-spacing:-.01em;
       font-size:clamp(1.9rem,4.5vw,2.7rem); line-height:1.15; margin:30px 0 10px; }}
  .blurb {{ color:var(--muted); max-width:62ch; margin:0 0 6px; }}
  .count {{ color:var(--muted); font-size:.92rem; margin:0 0 26px; }}
  ul.grid {{ list-style:none; padding:0; margin:0 0 40px;
            display:grid; gap:22px 16px;
            grid-template-columns:repeat(auto-fill,minmax(170px,1fr)); }}
  .cat-card {{ background:none; border:0; }}
  .cat-link {{ display:block; text-decoration:none; color:inherit; }}
  .cat-card img {{ width:100%; height:auto; aspect-ratio:1/1; object-fit:cover; display:block;
                  border-radius:18px; border:1px solid var(--line); background:#fff; transition:transform .25s; }}
  .cat-link:hover img {{ transform:scale(1.02); }}
  .cat-noimg {{ display:grid; place-items:center; aspect-ratio:1/1; font-size:2.4rem; border-radius:18px;
               background:#efe9df; border:1px solid var(--line); }}
  .cat-name {{ display:-webkit-box; -webkit-line-clamp:2; -webkit-box-orient:vertical; overflow:hidden;
              padding:10px 2px 2px; font-weight:500; font-size:.93rem; line-height:1.35; }}
  .cat-price {{ display:block; padding:2px 2px 0; color:var(--ink); font-weight:700; }}
  nav.subnav {{ margin:0 0 30px; color:var(--muted); font-size:.92rem; }}
  nav.subnav a {{ text-decoration:none; font-weight:600; }}
  .note {{ color:var(--muted); font-size:.92rem; margin:-14px 0 26px; max-width:62ch;
          background:#fff; border:1px solid var(--line); border-radius:14px; padding:12px 14px; }}
  nav.subnav span {{ opacity:.6; }}
  section h2 {{ font-family:var(--serif); font-weight:600; font-size:1.5rem; margin:34px 0 14px; scroll-margin-top:70px; }}
  section h2 .n {{ color:var(--muted); font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif; font-weight:400; font-size:.85rem; }}
  nav.sib {{ border-top:1px solid var(--line); padding:22px 0; color:var(--muted); font-size:.94rem; }}
  footer {{ color:var(--muted); font-size:.86rem; padding:10px 0 40px; }}
  @media (max-width:640px) {{
    ul.grid {{ grid-template-columns:1fr 1fr; gap:18px 12px; }}
    .cat-card img, .cat-noimg {{ border-radius:14px; }}
    h1 {{ margin-top:22px; }}
  }}
</style>
</head>
<body>
<header class="bar"><div class="wrap"><a href="{SITE}/">← HotsTuff</a></div></header>
<main class="wrap">
  <h1>{html.escape(title)}</h1>
  <p class="blurb">{html.escape(blurb)}</p>
  <p class="count">{count_line}</p>
{note}{subnav}
{cards}
</main>
<nav class="sib"><div class="wrap">{sib_line}</div></nav>
<footer class="wrap">
  Prices in USD · free shipping on store products (merch ships separately) · 30-day guarantee ·
  <a href="{SITE}/">see the full shop</a><br>
  Selection last refreshed {REFRESH_DATE.isoformat()}.
</footer>
<script data-goatcounter="https://theycallmemattyb.goatcounter.com/count" async src="//gc.zgo.at/count.js"></script>
</body>
</html>
"""


# Gift page (Matthew, 2026-11-05: "build the gift page"). Rebuilt with the
# category pages on every 3-day refresh, straight from products.json, so every
# price on it is the real one. No "perfect gift" or delivery-date promises:
# shipping takes 1-3 weeks (terms page), and the page says so.
GIFT_MAX = 25
GIFT_SKIP_CATEGORIES = {"Wellness", "Beauty"}          # personal-care items
GIFT_SKIP_WORDS = ("diaper", "weight loss", "bandage", "toothbrush", "slimming")


def gift_items(products):
    out = []
    for p in products:
        try:
            price = float(p.get("price", 0))
        except (TypeError, ValueError):
            continue
        name = (p.get("name", "") + " " + p.get("fullName", "")).lower()
        if (0 < price < GIFT_MAX and p.get("category") not in GIFT_SKIP_CATEGORIES
                and not any(w in name for w in GIFT_SKIP_WORDS)):
            out.append(p)
    return sorted(out, key=lambda p: float(p.get("price", 0)))


def holiday_note(today=None):
    """Honest Christmas order-by line (council 2026-11-05). No guarantee, because
    delivery is 1-3 weeks from the supplier. The page is rebuilt every 3 days, so
    the date is checked here AND in the browser (data-until), which hides a stale
    line even if a refresh is late."""
    today = today or date.today()
    y = today.year
    if today.month < 11 or today >= date(y, 12, 10):
        return ""
    if today <= date(y, 11, 30):
        text = ("For Christmas, order by about November 30 to give it the best chance. "
                "We can't guarantee delivery dates.")
        until = f"{y}-12-01"
    else:
        text = ("For Christmas: delivery takes 1–3 weeks, so an order now may not arrive "
                "by December 25. We can't guarantee delivery dates.")
        until = f"{y}-12-10"
    return (f'  <p class="note holiday" data-until="{until}">🎄 {text}</p>\n'
            '  <script>document.querySelectorAll("[data-until]").forEach(function(e){'
            'if(new Date()>=new Date(e.dataset.until+"T00:00:00"))e.remove();});</script>\n')


def write_catalog_meta(out_path, today=None):
    """catalog-meta.json: when this lineup went up and when the next one is due,
    so the store can say "New lineup in X days" from the real schedule. The
    refresh cron is "0 9 */3 * *" (days 1,4,7,...,31, 09:00 UTC). The store hides
    the line if this file is missing, older than 4 days, or the date has passed."""
    from datetime import datetime, timedelta, timezone
    now = today or datetime.now(timezone.utc)
    d = now.date() + timedelta(days=1)
    while (d.day - 1) % 3 != 0:
        d += timedelta(days=1)
    nxt = datetime(d.year, d.month, d.day, 9, 0, tzinfo=timezone.utc)
    out_path.write_text(json.dumps({
        "refreshed_at": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "next_refresh": nxt.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "schedule": "0 9 */3 * * (UTC)",
    }, indent=2) + "\n", encoding="utf-8")
    return nxt


def render_gifts(products, siblings):
    items = gift_items(products)
    bands = [("Under $15", [p for p in items if float(p["price"]) < 15]),
             (f"$15 to ${GIFT_MAX}", [p for p in items if float(p["price"]) >= 15])]
    bands = [(h, ps) for h, ps in bands if ps]
    subnav = ""
    if len(bands) > 1:
        subnav = ('  <nav class="subnav">Jump to: '
                  + " · ".join(f'<a href="#{anchor(h)}">{html.escape(h)}</a> <span>{len(ps)}</span>'
                               for h, ps in bands) + "</nav>")
    cards = "\n".join(
        f'  <section>\n    <h2 id="{anchor(h)}">{html.escape(h)} <span class="n">{len(ps)}</span></h2>\n'
        f'    <ul class="grid">\n{grid_of(ps, "gifts")}\n    </ul>\n  </section>' for h, ps in bands)
    if items:
        count_line = (f"<strong>{len(items)}</strong> gift ideas under ${GIFT_MAX} right now, "
                      "cheapest first. The selection changes every three days.")
    else:
        count_line = ("Nothing under the gift limit in the current rotation. The "
                      "catalogue refreshes every three days, so check back.")
    note = ('  <p class="note">Delivery typically takes 1–3 weeks '
            f'(<a href="{SITE}/terms/">see our terms</a>), so if it\'s for a '
            "certain date, order early.</p>\n") + holiday_note()
    sib = " · ".join(f'<a href="{SITE}/c/{s}/">{l}</a>' for s, l in siblings)
    return page_html("/gifts/", f"Gifts under ${GIFT_MAX}",
                     f"Gift ideas from the current HotsTuff lineup, all under ${GIFT_MAX} USD "
                     "with free shipping. Picked automatically from the real prices.",
                     count_line, subnav, cards, f"Shop by category: {sib}", note)


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
<meta name="description" content="Browse HotsTuff by category. The lineup refreshes every three days from our supplier's trending list; these category pages stay put.">
<link rel="canonical" href="{SITE}/c/">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,600&display=swap">
<style>
  /* Boutique look (2026-11-06). Content unchanged. */
  body {{ margin:0; background:#fbf8f3; color:#2b2622; line-height:1.6;
         font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,sans-serif; }}
  .wrap {{ max-width:720px; margin:0 auto; padding:0 20px; }}
  a {{ color:#e11d48; }}
  h1 {{ font-family:"Fraunces",Georgia,serif; font-weight:600; font-size:clamp(1.9rem,4.5vw,2.6rem); margin:30px 0 8px; }}
  p.lede {{ color:#7d746b; }}
  ul {{ list-style:none; padding:0; }}
  li {{ border-bottom:1px solid rgba(43,38,34,.12); padding:14px 0;
       display:flex; justify-content:space-between; gap:12px; }}
  li a {{ font-weight:600; text-decoration:none; }}
  li span {{ color:#7d746b; font-size:.9rem; }}
  header.bar {{ border-bottom:1px solid rgba(43,38,34,.12); padding:12px 0; background:#fbf8f3; }}
  header.bar a {{ color:#2b2622; text-decoration:none; font-weight:700; display:inline-flex; align-items:center; gap:8px; }}
  header.bar a::before {{ content:"H"; display:inline-grid; place-items:center; width:28px; height:28px; border-radius:8px;
               background:linear-gradient(135deg,#e11d48,#f59e0b); color:#fff; font-size:14px; font-weight:800; }}
</style>
</head>
<body>
<header class="bar"><div class="wrap"><a href="{SITE}/">← HotsTuff</a></div></header>
<main class="wrap">
  <h1>Shop by category</h1>
  <p class="lede">The shop's lineup is rebuilt every three days from our
     supplier's trending list. These category pages don't move — only what's inside them
     does.</p>
  <p><a href="{SITE}/gifts/">🎁 Gifts under ${GIFT_MAX}</a></p>
  <ul>
{rows}
  </ul>
</main>
<script data-goatcounter="https://theycallmemattyb.goatcounter.com/count" async src="//gc.zgo.at/count.js"></script>
</body>
</html>
"""


# The footer's "last refreshed" date. A real refresh (the 3-day cron) is today;
# a look-only rebuild (--no-meta) keeps the date of the lineup actually on the
# site, read from catalog-meta.json, so the page never claims a refresh that
# didn't happen (2026-11-06).
REFRESH_DATE = date.today()


def main():
    global REFRESH_DATE
    if "--no-meta" in __import__("sys").argv:
        try:
            meta = json.loads((HERE / "catalog-meta.json").read_text(encoding="utf-8"))
            REFRESH_DATE = date.fromisoformat(meta["refreshed_at"][:10])
        except Exception:
            pass
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
    gifts_dir = HERE / "gifts"
    gifts_dir.mkdir(parents=True, exist_ok=True)
    (gifts_dir / "index.html").write_text(render_gifts(products, siblings), encoding="utf-8")
    print(f"  /gifts/  {len(gift_items(products))} products")
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / "index.html").write_text(hub(siblings, counts), encoding="utf-8")
    print(f"  /c/  hub with {len(CATEGORIES)} categories")
    n = write_sitemap(HERE / "sitemap.xml")
    if "--no-meta" not in __import__("sys").argv:
        nxt = write_catalog_meta(HERE / "catalog-meta.json")
        print(f"  catalog-meta.json  next refresh {nxt:%Y-%m-%d %H:%M} UTC")
    print(f"  sitemap.xml  {n} URLs")


if __name__ == "__main__":
    main()
