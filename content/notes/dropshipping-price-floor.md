title: Pricing dropshipped products so no sale can lose money — the three costs people forget
description: A 2x markup on wholesale cost loses money on most small dropshipped orders. Here is the arithmetic, the formula I price from, and three worked examples.
date: 2026-08-26
draft: false
---

The advice everyone gets is "mark it up 2x, or 3x if you can." I built my
store's pricing on that and it is, for small dropshipped goods, quietly
wrong. Not "leaves money on the table" wrong — actually-loses-money wrong.

Here's the arithmetic.

## A sale has three costs, and the markup rule only covers one

**1. Wholesale cost.** The obvious one. You know it before you list the
item.

**2. Shipping.** Not the customer's shipping — my store shows free shipping,
so this comes out of my side. The supplier charges it to my account when
the order is placed, and I don't know the exact amount until then. For small
parcels to Canada and the US it typically runs $2–6, occasionally $6–8 for
bulkier items, remote provinces, or peak-season surcharges.

**3. The payment fee.** Stripe takes 2.9% of the charge plus a flat $0.30.
The flat 30 cents is the part that hurts: on a $10 order it's 3% on its own,
so the effective take is closer to 6%.

Two of those three are invisible when you're setting a price. That's why the
markup rule fails — it prices against the only cost you can see.

## What that does to a $6 item

Wholesale $6. Naive 2x markup, so it lists at $12.

```
  $12.00   charged to the customer
-  $0.35   Stripe (2.9% of $12.00, plus $0.30)
-  $6.00   wholesale
-  $8.00   shipping, worst case
= -$2.65   per sale
```

Every one of those sells at a loss, and the store looks like it's working
while it does it. If shipping happens to come in cheap that day you might
scrape to break-even; you have priced yourself a coin flip.

## The fix: solve for the price instead of guessing it

Rather than marking up a cost, state the condition you actually want and
solve for price:

```
price - (price × 0.029 + 0.30) - cost - shipping ≥ minimum profit
```

Rearranged, that's the lowest price that cannot lose:

```python
def min_profitable_price(cost):
    needed = cost + SHIPPING_WORST_CASE + STRIPE_FIXED_FEE + MIN_NET_MARGIN
    return needed / (1 - STRIPE_PCT_FEE)
```

Two choices in there are mine, not arithmetic:

**Shipping is priced at the worst case, $8.00** — the top of the range I've
actually seen, not the average. Averages are the wrong tool here. If I price
at the average, then by definition roughly half of my orders lose money, and
they'll be the heavy, far-away ones. Pricing at the ceiling means the real
charge can only ever come in *under* what I already priced for.

**Minimum profit is $1.00, not $0.01.** A guarantee that lands on a penny
isn't a guarantee — exchange-rate slop, a rounding difference, or one
miscellaneous fee wipes it out. A dollar is small, but it's a cushion that
survives contact with reality.

## Three worked examples

| Wholesale | Floor | Listed at | Profit after everything |
|---|---|---|---|
| $4.00 | $13.70 | $13.99 | $1.28 |
| $6.00 | $15.76 | $15.99 | $1.23 |
| $12.00 | $21.94 | $21.99 | $1.05 |

Note what that does to the low end: a $4 item cannot be sold for under about
$13.70. Not because I'm greedy — because $8 of shipping and $0.42 of card
fees exist whether or not the price acknowledges them.

That was the uncomfortable finding. My original price ladder started at
$3.99, and everything on the cheap end of it was structurally incapable of
making money. The ladder now starts at $9.99, and prices below the floor
aren't discounted — they're impossible.

## How it runs

Each product gets a price picked deterministically from a fixed ladder
(hashed off its SKU, so an item keeps the same price every time it comes
back around), and then raised to the floor if the floor is higher. If even
the top of the ladder can't clear the floor — an unusually expensive item —
the code breaks the ladder and rounds up rather than list at a loss.

It's about fifteen lines. It runs on every catalogue rebuild, on 120
products, with nobody watching. That's the actual point: the guarantee isn't
that I'm careful, it's that a losing price can't be written to the file.

## If you take one thing

Write down the condition you want to be true — "no sale loses money" — and
make it something the code enforces, not something you check. A markup
multiplier is a habit. A floor is a promise you can't accidentally break.
