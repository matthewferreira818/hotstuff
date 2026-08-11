# HotsTuff

A landing page for a storefront whose catalog changes based on what's currently
trending — not a single fixed product.

**Live site:** https://findhotstuff.com/
**Repo:** https://github.com/matthewferreira818/hotstuff

Note: the checkout backend (Cloudflare Worker) keeps its internal name
`wavelist-checkout` — that's backend plumbing, not customer-facing, so it
wasn't renamed to avoid re-registering the live Stripe webhook.

## Running locally

Any static file server works, e.g.:

```
npx serve .
```

Then open the printed local URL. `index.html` fetches `products.json`, so the
page must be served over http(s) — opening `index.html` directly via
`file://` will block the fetch in most browsers.

## App (PWA)

The site is an installable Progressive Web App: visitors get a "📲 Get the
app" pill (Android/desktop Chrome show a real install prompt; iOS gets
Share ▸ Add to Home Screen instructions), and the installed app opens
standalone with the flame icon, works offline from cache, and always shows
the freshest catalog when online.

Pieces: `manifest.webmanifest` (identity/icons), `sw.js` (service worker:
network-first for pages + `products.json`, cached fallback offline;
stale-while-revalidate for static files and CJ product photos), icons in
`assets/icons/` (regenerate with `python make_app_icons.py` — reuses the
brand flame from `tweet_media.py`), and the install-pill block at the bottom
of `script.js`.

**If you change `index.html` / `styles.css` / `script.js`, bump `VERSION` in
`sw.js`** so installed apps fetch the new shell instead of serving the old
one from cache. (`products.json` rotations need no bump — the catalog is
always fetched network-first.)

## Automatic trending refresh

`products.json` is regenerated every 3 days at 09:00 UTC by a GitHub Actions
workflow ([`.github/workflows/refresh-products.yml`](.github/workflows/refresh-products.yml))
that runs `refresh_products.py` against the CJ Dropshipping API, commits the
result if it changed, and pushes — which triggers GitHub Pages to redeploy
automatically. The same run also regenerates the social packs from the fresh
lineup: `marketing/latest-posts.md`, the TikTok pack (`marketing/tiktok/`),
and the Pinterest pin pack (`marketing/pinterest/`, 10 pins per cycle ≈ a
3-a-day drip until the next rotation). Outbound links in all generated posts,
pins, and QR codes carry `?ref=<channel>` tags (`x`, `x-qr`, `tt`, `pin`,
`ecs`, `print`, …) which GoatCounter surfaces as campaigns, so the dashboard
shows which channel each visit came from. This runs in the cloud, independent of whether your machine
is on. (The cron `0 9 */3 * *` fires on days 1, 4, 7 … 28, 31 of each month,
so the interval around a month boundary is a little shorter than 3 days.)

The site shows **120 products** each cycle (`DISPLAY_COUNT`), selected from a
pool of the top **800** trending items (`POOL_SIZE`, fetched in pages of
`PAGE_SIZE`). `MAX_REPEATS` is **4**: up to four items carry over each cycle,
and only ones a customer actually clicked Buy on (tracked as GoatCounter
`buy-<id>` events); everything else is replaced. **No clicks means no
carry-over** — a fully fresh catalog. Carrying the top-*trending* items when
there was no click data instead made the same handful permanent: the blender,
humidifier and necklace sat on the site unchanged from Aug 4 to Aug 11. A
carried item also gets only one bonus cycle before it rotates out regardless,
so nothing becomes furniture. Previous items still reappear as backfill if the
trending pool has fewer than `DISPLAY_COUNT` new products.

**Rotation memory.** Everything shown in the last `ROTATION_MEMORY` (**4**)
cycles is held back, so an item can't return for ~12 days. The ids of those
cycles live in [`rotation-history.json`](rotation-history.json), committed
with each refresh. This matters because excluding only the *previous* cycle
is not enough: the pool is sorted by trend, so the moment last cycle's items
became eligible again the selection snapped back to the top of that order and
the catalog alternated between two fixed sets (A→B→A→B, a 6-day loop that ran
Aug 4–10). If the pool is ever too small to fill a catalog with that much
held back, the oldest remembered cycle is forgiven one at a time — the
rotation gets shallower instead of failing.

`POOL_SIZE` must stay comfortably above `ROTATION_MEMORY × DISPLAY_COUNT`
(480) or the rotation collapses to a shallow cycle. To check what CJ can
actually serve before changing either number:

```
CJ_API_KEY=... python measure_pool.py
```

It pages until CJ runs out and reports the unique-product count plus how many
distinct catalogs that supports (last measured: **1082 products → 9
catalogs**). Read-only; it changes nothing.

- **Trigger it manually:** GitHub repo → Actions tab → "Refresh trending
  products" → Run workflow. Or: `gh workflow run refresh-products.yml`.
- **The API key** is stored as a GitHub Actions secret (`CJ_API_KEY`), not in
  the repo. To rotate it: `gh secret set CJ_API_KEY --repo matthewferreira818/hotstuff`.

To run the refresh manually on your own machine instead:

```
python refresh_products.py
```

Requires a `.env` file (not committed — see `.gitignore`) containing:

```
CJ_API_KEY=CJUserNum@api@xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Known limitations of the auto-refresh:**
- Each product is assigned a stable retail price from `PRICE_LADDER`
  (a spread of points across ~$4–$25), chosen deterministically from its SKU
  so its price stays the same across cycles. The price is then raised if
  needed so it never drops below the supplier cost marked up by
  `MARKUP_MULTIPLIER` (1.6x) — this protects margin. Because the ladder is
  seeded by SKU, the exact prices on the site depend on which items are
  trending. Edit `PRICE_LADDER` / `MARKUP_MULTIPLIER` to change the range.
- Category and emoji are guessed from keywords in the product title (CJ's
  list endpoint doesn't return category names), so occasionally a product
  lands in the generic "Trending Finds" bucket — check `NAME_KEYWORD_CATEGORIES`
  in `refresh_products.py` to add more keyword mappings.
- Product titles are supplier SEO titles, truncated to 55 characters — not
  copywritten.
- Product photos come straight from CJ's `bigImage` field; if a URL 404s the
  card silently falls back to the emoji treatment (see `script.js`).

## Managing content manually (add / delete products)

All catalog content lives in [`products.json`](products.json). You can also
edit this file directly any time — the next scheduled refresh will overwrite
manual edits, so for permanent manual entries, disable the Actions workflow
or accept the change won't survive the next Monday refresh.

Each entry looks like:

```json
{
  "id": "p7",
  "name": "Product Name",
  "category": "Category",
  "price": 24.99,
  "trendScore": 85,
  "badge": "🔥 Trending",
  "emoji": "🎧",
  "image": "https://example.com/product.jpg",
  "gradient": "linear-gradient(135deg, #6366f1, #ec4899)",
  "description": "One sentence on why it's trending."
}
```

- **Add a product**: append a new object to the array in `products.json`
  with a unique `id`.
- **Remove a product**: delete its object from the array.
- **Reorder**: not needed — the page always sorts by `trendScore`
  (highest first) automatically.
- `badge` is free text shown as a pill on the card (e.g. `"New"`,
  `"Best Seller"`, `"🔥 Trending"`).
- `image` is optional — omit it (or set to `null`) to fall back to the
  `emoji` + `gradient` thumbnail.
- `gradient` is any valid CSS `background` value for the card's thumbnail.

No build step or restart is required — the page re-fetches `products.json`
on every load.

## Checkout / payments (live)

Each product card has a "Buy now" button that:
1. Calls the `checkout-worker` (Cloudflare Worker, deployed at
   https://wavelist-checkout.wavelist-mf818.workers.dev) with the product id.
2. The Worker looks the product up in the live `products.json` (never trusts
   client-supplied price), creates a **live** Stripe Checkout Session, and
   returns the redirect URL.
3. Customer pays on Stripe's hosted checkout page (card + shipping address).
4. Stripe sends a `checkout.session.completed` webhook back to the Worker,
   which verifies the signature and places the matching order with CJ
   Dropshipping (`payType=2`, auto-deducted from your CJ account balance) so
   it actually ships.

**This uses real Stripe live-mode payments — real money moves.**

### Required before taking real sales
- **Your CJ Dropshipping account balance must be funded.** Order fulfillment
  auto-deducts the wholesale cost from your CJ balance on every sale
  (`payType=2` in `checkout-worker/src/index.js`). If the balance is
  insufficient, Stripe will have collected the customer's payment but CJ
  will **not** ship the item — fund this before announcing the store.

### Worker project layout
- `checkout-worker/src/index.js` — both endpoints (`/create-checkout-session`,
  `/webhook`)
- `checkout-worker/wrangler.toml` — Worker config + KV namespace binding
  (`ORDERS_KV`, used to make webhook processing idempotent against Stripe's
  retries)
- Secrets (`STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`, `CJ_API_KEY`) live in
  Cloudflare, not in this repo. To rotate:
  ```
  cd checkout-worker
  npx wrangler secret put STRIPE_SECRET_KEY
  npx wrangler secret put STRIPE_WEBHOOK_SECRET
  npx wrangler secret put CJ_API_KEY
  npx wrangler deploy
  ```
- To check a specific order's fulfillment result: it's stored in the
  `ORDERS_KV` namespace keyed by the Stripe Checkout Session id
  (`npx wrangler kv key get <session_id> --binding ORDERS_KV --remote`).

### Custom-design merch (middleman model)
The site's Merch section lets customers upload their own art (`/upload-design`
on the Worker → stored in `ORDERS_KV` as `design:<uuid>`, 90-day TTL) and buy a
"Your Design Tee" ($32.99, size + colour picked on the Stripe page via
custom_fields). **Fulfillment is manual:** open the `/orders` dashboard — custom
orders show a "customer design file" link (token-protected download). Download
the art, create the product in Printify (or any print service) with the
customer's size/colour, and ship to the address shown. Price clears worst-case
POD base + shipping + Stripe fees. Logo merch is sold through the live Printify
pop-up store (hotstuff-store.printify.me) — Printify hosts checkout, production,
shipping, and end-customer support for those orders. The merch tweet's ad card
is regenerated with `python make_merch_card.py`.

### Known limitations
- Only ships to the US (`shipping_address_collection` in the Worker).
- No inventory/stock check against CJ before accepting payment — if a
  product goes out of stock at CJ between page load and purchase, the CJ
  order call will fail (logged in `ORDERS_KV`, not currently surfaced back
  to the customer or you — check KV or Worker logs periodically for now).
- No refund automation — refunds are manual via the Stripe dashboard.
- Pop-up merch sales (Printify store): the owner is the Merchant of Record —
  Printify does not collect or remit sales tax on those orders. Shipping is
  charged at Printify's checkout, so the site's free-shipping promise is
  scoped to main-store orders (see the merch-section note).

## The decision council (Claude Code)

The repo ships a five-seat advisory council for business decisions, run
inside Claude Code. Say `/council <decision>` (e.g. `/council should we
open the Printify pop-up store this month?`) and five advisor agents weigh
in **in parallel**, each through a different lens:

| Seat | Lens |
| --- | --- |
| The Operator | Can the automation stack actually run it; what breaks |
| The Marketer | Which channel it feeds; how GoatCounter will measure it |
| The Treasurer | Unit economics, cash exposure, founder-hours, grants |
| The Skeptic | The strongest honest case against |
| The Customer | Would a findhotstuff.com visitor actually care |

Claude acts as the **Right Hand**: it frames the question, convenes the
seats, then gives its own decisive call (it may overrule the majority) and
logs the session to `.claude/council/DECISIONS.md` so future sessions have
precedent. Individual seats can be consulted solo ("ask the Skeptic…").

Definitions live in `.claude/agents/` (one file per seat) and
`.claude/skills/council/` (the session playbook) — edit those to change
how a seat thinks or add a new chair.
