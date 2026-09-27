# Etsy demand check — prompt for Chrome-extension Claude (C.C)

_The 30-minute gate from spec.md, done in a real browser because Etsy
blocks server-side lookups. Paste the block below into Chrome Claude's side
panel. Read-only: nothing gets bought, favourited, messaged or posted._

**The gate:** fewer than about 5 real competing listings, or top listings
with no recent sales → the sheet does not get listed.

---

Help me check whether people are buying Etsy pricing/profit calculator
spreadsheets. This is READ-ONLY research: do not favourite, add to cart,
message, follow, buy, or change any setting. If Etsy shows a captcha or
asks me to sign in, stop and tell me — I'll handle it.

**1. Run these six searches on etsy.com** (default "Relevancy" sort, don't
change filters):

1. etsy profit calculator
2. etsy fee calculator
3. etsy pricing calculator
4. price calculator spreadsheet
5. etsy shop profit tracker
6. product pricing template google sheets

For each search write down:
- The result count Etsy shows (e.g. "1,000+ results"), exactly as shown.
- How many of the first 12 listings are labelled **Ad**.
- The **first 10 listings that are NOT ads** and are a spreadsheet/digital
  calculator (skip physical items and unrelated stuff): title (shortened),
  price, star rating and number of reviews, and any badge or signal
  exactly as shown — "Bestseller", "Popular now", "In 20+ carts",
  "Star Seller", "X sold".

**2. For searches 1, 2 and 3 only, open the top 3 non-ad listings.** For
each one write down:
- The shop's total sales number (shown near the shop name, e.g. "4,210 sales").
- The dates of the 3 most recent reviews **of that item** (not the whole
  shop, if Etsy lets you switch).
- One line: does it work out a MINIMUM price for you, or does it only show
  profit at a price you type in?

**3. Give it back to me as one plain table per search**, then three lines at
the bottom:
- How many distinct calculator listings you saw across all six searches.
- The price range (lowest to highest).
- Your honest read: are the top ones selling recently (reviews in the last
  60 days), yes or no?

Don't guess any number you can't see on screen — write "not shown" instead.
