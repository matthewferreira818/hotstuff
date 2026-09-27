# Price-floor sheet — build spec

The product the council landed on (2026-09-26, `.claude/council/DECISIONS.md`).
**Not a planner.** It is the price-floor calculation this store already runs
on, in a sheet somebody else can use.

This file is the source of truth. The sheet itself lives in Google Drive,
and CLAUDE.md's lore is explicit that rendered assets have been lost twice
by living only on a container's disk — so every formula is written down
here, where it survives.

---

## What it is, in one sentence

> Enter what an item costs you. It tells you the lowest price you can sell
> it at without losing money, once every fee is counted.

That is the whole hook. Everything else is support.

## Who it is for

**Etsy sellers, print-on-demand shops and small online stores** — not
"dropshippers". The Marketer's condition, and the reasoning is sound: Etsy
auto-generates market pages only for queries with real volume, and it has
them for `etsy_shop_profit_tracker`, `profit_spreadsheet` and
`bookkeeping_template`, but none for "dropshipping profit tracker". The
buyer is there under a different name. `dropshipping` stays as a tag.

## The rule that governs every cell

**Fee rates are input cells. Never constants.**

If Stripe or Etsy changes a rate and the number is baked into a formula,
every copy already sitting in a buyer's Drive becomes wrong, and rule #1
would demand a same-day fix to a file we cannot reach. Inputs make that
impossible by construction, and the maintenance tax is then zero forever.

Everything on `Start here` is editable. Nothing is locked, anywhere.

---

## Tab 1 — Start here (the fee inputs)

Pre-filled with sensible defaults and a visible note: **"These are
starting points. Change them to yours."** Pre-filled matters — the
Customer seat was blunt that assumptions filled in means value in 90
seconds, and assumptions blank means you have handed someone a grid.

| Cell | Label | Default | Note |
|---|---|---|---|
| `D7` | Platform fee % | 6.50% | Etsy transaction fee |
| `D8` | Payment processing % | 3.00% | Varies by country — check yours |
| `D9` | Offsite Ads % | 0.00% | Only on ad-attributed orders |
| `D12` | Payment processing fixed | 0.25 | Per order |
| `D13` | Listing fee | 0.20 | Per listing |
| `D14` | Shipping you absorb (worst case) | 8.00 | The one people forget |
| `D17` | Minimum profit per sale | 1.00 | Your cushion, not a fee |
| `D20` | Currency symbol | $ | Cosmetic, no conversion. Every label and verdict follows it |
| `D23` | **Total % fees** | `=D7+D8+D9` | Derived, shown for sanity |

Row numbers are never typed by hand: the script derives them from its
settings list and audits every cross-sheet reference before saving.

`Offsite Ads %` gets its own row, default **0**, with a note that it only
applies to orders attributed to Etsy's ads and that sellers under the
lifetime threshold can opt out.

## Tab 2 — Price floor (the hero tab)

This is tab 1 in the buyer's eye and the first listing image.

Inputs: **item cost** (`D7`) and **your price** (`D8`).

```
Floor  =  (cost + shipping + processing_fixed + listing_fee + min_profit)
          / (1 - total_pct_fees)
```

In sheet terms, with `S` = `Start here`:

```
=IF(S!D23>=1, "FEES ≥ 100%",
    (D7 + S!D14 + S!D12 + S!D13 + S!D17) / (1 - S!D23))
```

That is the same shape as `min_profitable_price()` in
`refresh_products.py:327`, generalised so the fee names are not
Stripe-and-CJ specific. The division is the part people get wrong: the
percentage fee applies to the *price*, not the cost, so you cannot just
add it on — you solve for it.

Below the floor, three live cells:

- **Profit per sale at your price** — `= price*(1-pct) - fixed - shipping - cost`
- **Verdict** — a big block with three answers, not two:
  - **LOSES $X** — profit is below zero. Red.
  - **UNDER $X** — still makes money, but less than the minimum profit you
    set. Red, because it's under *your* floor. (v1 called this LOSES,
    which was false.)
  - **SAFE $X** — at or above the floor. Grey.
  - Blank price shows **ENTER YOUR PRICE ABOVE**, never SAFE.

That red cell is the product. It is the screenshot, the hook and the
reason anyone pays.

## Tab 3 — Your products

One row per item. Columns: SKU, name, cost, shipping override, your price,
floor, profit per sale, verdict. Floor and verdict use the same formulas,
referencing `Start here`.

**Use a real spreadsheet table, not 200 pre-filled rows** — formulas that
break when you add a row are the top bad-review trigger in this category.

## Tab 4 — Paste your orders

The tab that stops this being data entry. Paste a CSV export from Etsy,
Shopify or Stripe; a small mapping row says which column is which. It
computes actual revenue, actual fees, actual net.

If the mapping proves fiddly, this tab ships as "paste and map once" with
written instructions rather than being dropped. **A tracker you have to
hand-feed is one nobody keeps**, and that is the single most common way
this exact product disappoints.

## Tab 5 — Ads

Spend per product against revenue per product, and the one cell that
matters:

```
Break-even ROAS  =  1 / (profit_per_sale / price)
```

With a plain-English line beside it: *"at your margin you need Nx or you
are donating."*

## Tab 6 — This month

One number at the top: **did I make money this month, yes or no, how
much.** Then the supporting lines — revenue, fees, COGS, shipping,
refunds, and a tax set-aside bucket at a rate you set.

**Refunds and chargebacks get a real line.** Processors keep the fixed fee
on a refunded order; no free template knows that.

## Design — v2, "Grid & Signal" (2026-09-27)

v1 looked vintage: cream and amber, Calibri, italics, gridlines, a box
around every input. Four design directions were built and scored by a
panel; **swiss-grid** won (35, the only ship vote) over quiet-editorial
(33), dashboard-dark (32.5) and soft-ui-cards (29). One idea was grafted
from each runner-up.

- **Palette:** white, near-black `#111111`, grey `#6E6E6E` for notes,
  light grey `#EDEDED` for anything the sheet works out. **One colour —
  red `#E30613` — only where the sheet says you're losing money.** No
  green anywhere; SAFE is calm grey on purpose.
- **Type:** Arial on every cell (it converts to Sheets), no italics, labels
  not bold. Bold is kept for numbers, totals and verdicts.
- **Space, not boxes:** gridlines off, the canvas painted white, ten legal
  row heights (8 14 16 20 22 28 32 36 52 104), inputs marked by a single
  black underline, rows by a hairline.
- **Red is the static state** of the verdict block (graft from
  soft-ui-cards); grey is the conditional override. If Sheets ever drops
  the rule, the sheet over-warns — it can never hide a loss. The rule
  keys off the verdict word, so colour and word can't disagree.
- **Words carry the affordance** (graft from dashboard-dark): every tab's
  legend says white = type, grey = worked out; product headers say
  `COST (YOU)` / `FLOOR (AUTO)`.
- **Currency symbol is an input** (graft from quiet-editorial); no `$` is
  baked into any format or formula.

Honesty fixes found while building v2, all verified in LibreOffice and a
second formula engine:

1. Price between break-even and the floor said LOSES while earning money
   → now UNDER.
2. Fees of 100% or more made the floor negative, so every price read SAFE
   → floor shows `FEES ≥ 100%` and the verdict says LOSES.
3. A blank price used to compute a verdict → now asks for the price.
4. A fresh "This month" said BROKE EVEN on an empty month → now says
   FILL IN YOUR MONTH ABOVE.

The design spec's full measurements (382 × 229px verdict block, the
200 × 200 thumbnail crop from a **real** Sheets screenshot) are the
thumbnail procedure: default values D7 = 6.00, D8 = 12.00 put the sheet in
the red.

## What it deliberately does not have

No habit tracker, no goals page, no mood board, no calendar. The Customer
seat called that filler and said they could smell it.

---

## Honesty constraints — these are not optional

1. **No income claims anywhere.** Not in the sheet, not in the listing, not
   in a pin. The true and stronger line is *"I built this for my own
   store's pricing"*, plus a link to
   `/notes/dropshipping-price-floor` where the arithmetic is published
   under Matthew's name. Anything implying earnings is false today and
   would be checked.
2. **Listing images composited from REAL screenshots.** Pillow may draw
   frames, headlines and branding. It must never draw invented spreadsheet
   contents. A mockup showing a tab that is not in the delivered file is
   the same class of error as the wallpaper sold as a pet bed.
3. **A plain "what this is not" line**, in the sheet and the listing: *this
   is a calculator, not accounting or tax advice.*
4. **Defaults are labelled as defaults.** Every pre-filled fee says check
   your own. A buyer in another country with different processing fees must
   not be quietly given wrong numbers.

## Commercials, fixed by the council

- **$24 CAD**, listed in CAD against a CAD account — identical currencies
  avoid the conversion fee.
- Offsite Ads **off** on day one. Etsy Ads **zero** until one organic sale
  proves the listing converts.
- Mirrored on findhotstuff.com through the existing Stripe worker in the
  same build session, so `/notes` finally has something to convert to.
- **It does not go on the store's first screen.** Linked from `/notes`
  only — a fifth thing on that homepage turns a curated store into a guy
  selling whatever.

## Kill criterion, set now while it is unemotional

**Zero sales by Jan 31 → no second digital product.**

## Build order

1. This spec. ✅
2. The sheet, built in Google Drive from these formulas. Matthew verifies
   every one — his name is on them.
3. Four real screenshots of the finished sheet (~15 min, his).
4. `make_planner_assets.py` — composites those screenshots into listing
   images, writes `listing.md` with title, tags and description.
5. Etsy listing. Then the mirror on findhotstuff.com.

## Before any of it — the 30-minute demand check

Both the Operator and the Skeptic made this their would-change-my-mind.
Search Etsy for the niche query and count competing listings, then check
whether the top ones show recent sales. **Under about five listings means
the niche is empty rather than uncontested, and this does not get built.**
