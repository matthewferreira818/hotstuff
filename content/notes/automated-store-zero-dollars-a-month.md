title: What it costs to run an automated store at $0 a month
description: The full stack behind an automated dropshipping storefront, line by line, with the one bill that isn't free and the two things I switched off because they weren't.
date: 2026-08-28
draft: false
---

Every "start a store for free" post I read left something out. Usually the
hosting was free but the automation wasn't, or the automation was free but
it needed a $29/month app to actually run. So here is the whole thing, line
by line, with nothing left out — including the parts I turned off because
they cost money I don't have yet.

## The bill

| Piece | What it does | What it costs |
|---|---|---|
| GitHub Pages | Serves the storefront | $0 — free for public repositories |
| GitHub Actions | Runs every scheduled job below | $0 — free for public repositories |
| Cloudflare Workers | Stripe checkout, lead capture, order alerts | $0 — free tier is 100,000 requests a day |
| Stripe | Takes the payment | $0/month, then 2.9% + $0.30 per transaction |
| CJ Dropshipping | Supplier and fulfilment | $0/month, then wholesale + shipping per order |
| GoatCounter | Traffic analytics | $0 |
| ntfy | Pushes order and lead alerts to my phone | $0 |
| A domain name | findhotstuff.com | **The only recurring bill. Billed once a year.** |

So the honest version of "$0 a month" is: everything that runs costs
nothing, and the domain is a yearly bill in the ballpark of a large coffee
per month. I'm not going to pretend that's zero, because it isn't.

## What "automated" actually means here

There are thirteen scheduled jobs. They are ordinary GitHub Actions
workflows — YAML files in the repository, not a SaaS product:

- Rebuild the product catalogue from live trending data every three days
- Generate the social posts for the new catalogue in the same run
- Build the daily TikTok photo packs and push them as drafts
- Publish the daily post to the East Coast Social feed
- Pull a traffic report
- Relay phone alerts (more on that below)
- Smoke-test the site after every deploy

The whole store is static files. There is no server to keep alive, no
database to back up, and nothing to patch. That is the actual reason it
costs nothing — not a clever free tier, just an architecture with very few
moving parts that can bill you.

## The two things I switched off because they cost money

I'd rather show you the switched-off list than pretend the stack is
complete.

**Automatic posting to X.** The poster is written and works. X's API
charges per post, and at my current traffic that's money spent to reach
almost nobody. The workflow sits idle until there's a reason to turn it on.

**AI-polished product names.** Supplier titles are keyword soup. A model
can tidy them into readable names in seconds, and the code to do it is in
the repo behind an optional API key. Without the key the code skips
silently and the store falls back to mechanical name cleanup. It costs a
few dollars a month, which is a few dollars a month I don't have committed
yet, so: mechanical names.

Both of those are one secret away from running. Neither is pretended to be
running in the meantime.

## The one place free tiers actually bit

Cloudflare Workers can't reliably send push notifications to my phone.

The Worker handles checkout, and when an order lands I want to know
immediately. The obvious move is to have the Worker call the push service
directly. That fails intermittently, and the reason is that Cloudflare
Workers share outbound IP addresses across an enormous number of
customers — so from the push service's side, the request looks like it's
coming from an address that's already sent a flood of traffic, and it gets
rate-limited.

The fix was a hop: the Worker fires a `repository_dispatch` event at
GitHub, and a tiny workflow does the actual push from a GitHub runner. It
adds a few seconds of latency to a notification I read minutes later
anyway, and it costs nothing.

## What it actually cost

Evenings. I have a full-time job that runs from about 6:45 in the morning
to 4:30 in the afternoon, so all of this was built after that. The money
column is genuinely near zero. The time column is not, and anyone telling
you otherwise is selling something.

## Would I recommend this stack?

For a store you're testing rather than betting on, yes, with one honest
caveat: it is a *developer's* free stack. Every piece is free because
you're doing the work a paid product would do for you. If you don't want to
touch YAML or Python, Shopify's monthly fee is buying you something real.

What you get in exchange for the work is that nothing can raise its price
on you, nothing can change its terms, and nothing can turn your store off.
