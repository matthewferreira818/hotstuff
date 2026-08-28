# LinkedIn — copy-paste kit

Written 2026-08-28 from what is actually true and checkable. Nothing here
claims a credential Matthew doesn't hold or a result the sites can't show.
Rule of thumb for every edit: if an interviewer opened findhotstuff.com
mid-sentence, the claim should survive.

**Tune before sending.** These are written for a general audience. Once a
target role is known (marketing ops? small-business consulting? automation?),
the About section's second paragraph should be re-pointed at it.

---

## Headline (220 char limit)

Pick one:

```
Founder, East Coast Social · I build automation that keeps small-business pages posting daily — proven on my own store first
```

```
Founder at East Coast Social (Memramcook, NB) · Marketing automation, AI-assisted builds, and systems that run without me
```

```
I automate the marketing small businesses don't have time for · Founder, East Coast Social · Atlantic Canada
```

---

## About (2,600 char limit — this is ~1,750)

```
I build systems that do the work when nobody's watching.

I'm not a developer by training. I run a full-time job and, around it, I built and operate an automation engine that runs an online storefront and a done-for-you social media service for local businesses in southeastern New Brunswick.

What that engine actually does, unattended:
• Refreshes a 120-product storefront every three days from a supplier API — including pricing rules that guarantee no sale can lose money after wholesale cost, worst-case shipping and payment fees
• Publishes a branded post every single day and archives it to a public feed with a live counter anyone can check
• Renders social packs and delivers them into TikTok through the Content Posting API
• Handles Stripe checkout, lead capture and phone alerts through a Cloudflare Worker
• Runs 14 health checks a day against the live sites and raises an alarm when anything goes stale

It runs on $0/month — every component sits inside a free tier deliberately, because a pre-revenue business shouldn't have a burn rate.

The code was written in partnership with an AI assistant. What I bring is the part that doesn't automate: specifying a system precisely enough that it behaves correctly with no one supervising it, and noticing when it doesn't. One early example — the system was generating polished product names from a template and listed a roll of wallpaper as a "Cozy 2-in-1 Pet Bed." I caught it, and the fix wasn't a better template: it was a validator that rejects any product name containing a word the real supplier title doesn't contain. Marketing copy that a machine can refuse to publish is an unusual thing to build. I'd rather have it than the extra sale.

I'm interested in work where somebody needs a process to run reliably without being babysat — marketing operations, automation, or small-business systems.

The build is documented, with live proof, at findhotstuff.com/build
```

---

## Experience entry

**Founder & Operator — East Coast Social** · Memramcook, NB · Jul 2026 – Present

```
Founded a done-for-you social media service for small businesses in southeastern New Brunswick, and built the automation platform it runs on.

• Designed and operate an engine that publishes a branded post daily, unattended — running continuously since August 2026 with a public, verifiable counter
• Built a self-refreshing 120-product e-commerce storefront with automated supplier integration, rotation logic, and margin-protected pricing
• Implemented payments, lead capture and abuse limiting on a Cloudflare Worker with Stripe; alerts routed to mobile
• Instrumented every marketing channel with tracked attribution, so spend and effort are judged on measured click-throughs rather than impressions
• Established an enforced honesty constraint in code: automated product naming and marketing claims are validated against source data and rejected when unsupported
• Entire stack operates at $0/month recurring cost
```

---

## Skills to list

Marketing Automation · Process Automation · Small Business Marketing ·
E-commerce Operations · Content Strategy · Analytics & Attribution ·
Python (AI-assisted) · GitHub Actions · Stripe · Cloudflare Workers ·
Bilingual market experience (English/French, New Brunswick)

---

## What NOT to write

- Do not claim a developer/engineer title. "Built with an AI assistant, I
  own the system design" is both true and more interesting in 2026.
- Do not imply clients or revenue before they exist. The proof is the
  working engine and the streak, not a customer list.
- Do not inflate "CEO." Founder & Operator of a small service reads as
  honest; CEO of a pre-revenue company invites an eye-roll.
- No invented metrics. Every number above is checkable on the live sites.
