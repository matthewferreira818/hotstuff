# Moving East Coast Social to its own domain

**Status: PREPPED, NOT EXECUTED.** Trigger per the standing decision: first
paying client, or Sept 15 — whichever comes first. Nothing here is urgent;
it exists so the switch is an afternoon, not an investigation.

## Why bother

ECS is a business-to-business service currently living at
`findhotstuff.com/automation/` — a subfolder of a dropshipping storefront.
A prospect who looks closely finds their social-media provider is a page
inside a gadget shop, and the two brands clash visually (hot-pink storefront
chrome wrapping a navy/gold service). The store being the *proof* is an
asset; the store being the *address* is not.

## Verified facts (checked 2026-08-28, re-check before executing)

- `eastcoastsocial.ca` and `www.` both **301 to** `https://findhotstuff.com/automation/`
- The redirect is served by **openresty** — a registrar URL-forward, not
  Cloudflare, not GitHub
- **It strips the query string.** `eastcoastsocial.ca/?ref=card` arrives as
  `findhotstuff.com/automation/` with no tag. Every business-card QR scan to
  date has therefore been invisible in the traffic report
- GitHub Pages allows **one custom domain per repository**, and
  `findhotstuff.com` holds it

## Registrar: Porkbun (confirmed by Matthew 2026-08-28)

Porkbun's URL-forwarding advanced settings offer a redirect type and
"Include the requested URI path in the redirection" — **no query-string
option is documented**, which matches the observed stripping. So option C
below is probably not available here; the 30-second test is to enable the
URI-path toggle and re-check `eastcoastsocial.ca/?ref=card`, but expect it
to change nothing for query strings.

That collapses the decision: **the card-tracking fix and the separation are
the same project.** Once the domain serves the site directly instead of
forwarding to it, `?ref=` works natively because no forward is involved.

Porkbun's own DNS is free and sufficient — an apex domain on GitHub Pages
needs four A records (GitHub publishes the addresses; re-check them at
migration time rather than trusting a copy here) plus a CNAME for `www`.
No need to move nameservers anywhere.

## The two real options

**A — Second GitHub repo (cleanest, and the recommendation now that the
registrar is known).**
A new repo serves `eastcoastsocial.ca` with its own CNAME. Proper separate
site, correct SEO, no proxy tricks. Cost: the daily engine writes feed cards
into *this* repo, so `ecs-daily-post.yml` must publish those assets to both
repos (it already holds a token that can do it).

**B — Cloudflare in front.** *(now the weaker option — Porkbun's own DNS
already does what's needed, so this adds a moving part for no gain.)*
Move the domain's nameservers to the existing Cloudflare account, then serve
ECS at the apex. Keeps one repo. Cost: a nameserver change at the registrar,
and if done as a proxy, relative links and canonical tags need care to avoid
duplicate-content penalties.

**C — Do nothing but fix the forward.** ~~Enable query-string forwarding.~~
**Likely unavailable on Porkbun** — the documented advanced settings cover
redirect type and URI path only. Worth a 30-second test of the URI-path
toggle, but do not plan around it.

## Execution order (when triggered)

1. **Decide A or B.** Registrar is Porkbun; option A is recommended.
2. Point the domain at the new host; confirm HTTPS issues correctly.
3. Change `HOST` and `PATH` in `/ecs_site.py` — the only code edit required.
4. Re-run the generators that bake the URL into artwork:
   - `python marketing/east-coast-social/make_ecs_pins.py` (Pinterest pins)
   - `python marketing/east-coast-social/make_merch_art.py` (hoodie QR)
   - `python make_print_materials.py` (cards, flyers)
   - `python marketing/east-coast-social/engine/sample_week.py <profile>` per
     rendered pack (7 exist)
5. Update the places no script owns:
   - Google Business Profile website field + appointment link
   - Facebook page, X bio, TikTok bio, Pinterest claimed site
   - `sitemap.xml`, `links/index.html`, `build/index.html`
   - `automation/index.html` + `/fr/` self-references and JSON-LD
6. Leave `findhotstuff.com/automation/` in place as a **301 to the new home**
   for at least 90 days — old Pinterest pins, group posts and the printed
   cards all point at it.
7. Re-run `python smoke_test.py` and fix whatever it flags.

## What cannot be migrated

**Already-printed business cards** carry a QR to `eastcoastsocial.ca`. They
keep working (the forward will still land somewhere valid), but their scans
stay untagged unless option C is done. Cards printed *after* this prep will
carry a trackable URL automatically — `make_print_materials.py` now asks
`ecs_site.brand_url("card")`, which refuses to hand out the tag-eating
address while `BRAND_DOMAIN_PRESERVES_QUERY` is False.

## Rollback

Revert `ecs_site.py`, re-run the generators, repoint DNS. Because every
address flows from one constant, a rollback is the same three steps as the
migration.
