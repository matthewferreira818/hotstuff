title: Catalog rotation versus SEO — the tradeoff I did not understand when I built my store
description: A storefront that refreshes every three days can never rank, because nothing stays at one URL long enough. Here is the mistake, why freshness and search are opposites, and the fix that did not require giving up either.
date: 2026-09-26
draft: true
---

I built my store to feel alive. The whole catalogue rotates every three
days — new products in, old ones out, automatically. It is genuinely the
best thing about the site and it is the reason anyone comes back.

It also made the store architecturally incapable of ranking on Google, and
I did not work that out until months in.

## Why freshness and SEO are opposites

Search engines rank *URLs*, not sites. A URL earns its position slowly:
it gets crawled, it accumulates signals, other pages link to it, and over
months it climbs.

Every one of those mechanisms needs the page to still be there.

On a rotating storefront, a product page exists for three days. It might
not even get crawled in that window. If it does, whatever authority it
starts to accumulate is thrown away when the product rotates out. There is
no page old enough to rank, ever, by design.

I had built a site that resets its own progress twice a week.

## The bit that makes it worse

The instinct is to fix it by rotating less. That is the wrong trade,
because the rotation is the product. "There is always something new here"
is why the store is worth a second visit, and a static catalogue of 200
items is a worse store that still would not rank for anything competitive.

So the answer is not to choose. It is to notice that **these need to be
different pages.**

## What I actually did

Two kinds of URL, doing two different jobs:

**Pages that rotate.** The storefront and its product cards. Fast, fresh,
and honestly not trying to rank. Their job is to be good when someone is
already looking at them.

**Pages that persist.** Two sorts:

- **Category pages** at `/c/<slug>/` — one per category, generated from
  whatever is currently in stock. The URL never changes even though its
  contents do. A category page is an address that can accumulate
  authority while the things inside it come and go.
- **Notes** like the one you are reading. One URL, one topic, written
  once, true indefinitely. No rotation at all.

The sitemap lists the persistent ones. The rotating ones are for people
who already arrived.

## What I would tell myself at the start

**Decide which pages are permanent before you build anything that
regenerates.** Not after. I had a working store, a working refresh
pipeline and a category structure before I understood that none of it
could ever appear in a search result, and retrofitting the permanent layer
was more work than designing it in would have been.

And the honest postscript: this fix is recent, so I cannot yet tell you it
worked. The category pages and the notes are live and in the sitemap; the
traffic they earn, if any, takes months to show up. I will come back and
update this page with the real number rather than quietly leaving it
implying a success I have not had.
