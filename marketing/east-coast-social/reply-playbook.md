# Reply Playbook — what to do when a prospect answers

The DM did its job. From here, ONE goal per step. Don't sell the whole thing
in Messenger — sell the *20-minute chat*, then sell the *samples*, then close.

## Step 1 — they replied. Answer fast, stay light.

Whatever they said (interest, skepticism, "how much?"), respond within a few
hours, never more than a day:

> Awesome — easiest way to see it is a quick 20-minute chat, no slides, no
> pressure. I'll show you my own store running on it live, and if you tell me
> a bit about your business I'll bring sample posts made for YOUR page.
> When's good — mornings or evenings?

If they just ask price in the DM, give it straight (hiding it kills trust):

> Starter is $299 setup + $49/mo (one platform, a post every day). Plus is
> $499 + $99/mo (two platforms, up to 3 posts a day, image cards + QR codes).
> No contract, cancel any month. The 20-min chat is free either way.

## Step 2 — before the chat, generate their samples

    cd marketing/east-coast-social/engine
    python sample_posts.py "Their Business Name" --type restaurant --accent "#their-brand-color" --photos <folder>

Grab 2-3 photos from their page/website for `--photos`. Send the three cards
during (or right after) the chat: **"this is what your page posts this week."**
This is the closer — they're no longer imagining it, they're looking at it.

## Step 3 — the 20-minute chat (script)

1. **Their business first (5 min):** What do you sell most? What days are
   slow? How do customers usually find you? (Their answers ARE the content
   plan — write them down.)
2. **Show, don't tell (5 min):** findhotstuff.com feed on X + the ECS page
   itself — "nobody types these, the engine does." Then THEIR sample cards.
3. **How it works (5 min):** one 20-min setup chat (this one), samples within
   48h, you approve or we adjust, then it runs. Monthly summary email. Cancel
   any month, keep everything posted.
4. **Close (5 min):** "Want me to set your engine up this week?" Then take
   the $299/$499 setup (e-transfer) and collect: logo file, brand colors,
   3-5 photos, hours, one paragraph on how they talk to customers.

## Objections

- **"I can post myself."** — "Totally — most owners can. The ones I talk to
  just don't, because 6 PM you has better things to do. That's the gap this
  closes: it happens whether you're busy or not."
- **"AI will make it sound fake."** — "You approve the style before anything
  goes live, and adjust any time. If a post ever feels off-brand, it's gone
  and the engine learns. Look at my store's feed — does it read fake?"
- **"Too expensive."** — "$49 a month is less than one quiet Tuesday. One
  customer a month who saw a post pays for it."
- **"Let me think about it."** — "Of course. I'll leave the samples with you
  — check how your page looks next Tuesday and see if it changed your mind."
  (Then follow up in 5 days, once.)

## Channel notes

- **Ducks aren't Real** → email ducksarentreal@gmail.com
- **Tidewater Books** → email tidewaterbooks@eastlink.ca
- **Viandes LeBlanc** → email leblancmeat.32@gmail.com (French first)
- Everyone else → Messenger thread where the DM lives.

## After the close

1. Mark them CLIENT in prospects.md, note plan + start date.
2. Build their card templates (post_card.py with their branding).
3. Set up their page token (same Meta app, add their Page) + their workflow.
4. First 3 samples within 48h. No exceptions — speed IS the product.
