# Wavelist

A landing page for a storefront whose catalog changes based on what's currently
trending — not a single fixed product.

## Running locally

Any static file server works, e.g.:

```
npx serve .
```

Then open the printed local URL. `index.html` fetches `products.json`, so the
page must be served over http(s) — opening `index.html` directly via
`file://` will block the fetch in most browsers.

## Automatic trending refresh

`products.json` is regenerated weekly (Mondays 9am) by `refresh_products.py`,
which pulls the current top trending products from the CJ Dropshipping API
and rewrites the file. This runs via a Windows Scheduled Task named
`WavelistWeeklyRefresh`:

```
schtasks /query /tn "WavelistWeeklyRefresh" /v
schtasks /run /tn "WavelistWeeklyRefresh"     # run it manually right now
schtasks /delete /tn "WavelistWeeklyRefresh"  # stop the automation
```

To run the refresh manually:

```
python refresh_products.py
```

Requires a `.env` file (not committed — see `.gitignore`) containing:

```
CJ_API_KEY=CJUserNum@api@xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

**Known limitations of the auto-refresh:**
- Prices are the *lowest* variant cost from CJ's price range, marked up by
  `MARKUP_MULTIPLIER` (1.6x) in `refresh_products.py` — real per-variant
  pricing will vary, adjust the multiplier as needed.
- Category and emoji are guessed from keywords in the product title (CJ's
  list endpoint doesn't return category names), so occasionally a product
  lands in the generic "Trending Finds" bucket — check `NAME_KEYWORD_CATEGORIES`
  in `refresh_products.py` to add more keyword mappings.
- Product titles are supplier SEO titles, truncated to 55 characters — not
  copywritten.

## Managing content manually (add / delete products)

All catalog content lives in [`products.json`](products.json). You can also
edit this file directly any time — the next scheduled refresh will overwrite
manual edits, so for permanent manual entries either disable the scheduled
task or note the change won't survive the next Monday refresh.

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
- `gradient` is any valid CSS `background` value for the card's thumbnail.

No build step or restart is required — the page re-fetches `products.json`
on every load.
