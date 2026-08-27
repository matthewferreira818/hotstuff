# East Coast Social — the weekly rhythm

_The point: ECS is the business with a path to real monthly money ($79/mo
recurring, one yes matters). HotsTuff runs itself and needs zero hours — it's
the proof asset, not the job. So every human hour goes here._

**Built around Matthew's real schedule:** work 6:45–4:30 weekdays, Saturday
mornings till noon, pockets of time between tasks.

---

## What the evidence says (so we stop guessing)

| Channel | Attempts | Result |
|---|---|---|
| Facebook DMs to businesses | 20+ | **0 replies** |
| Phone calls | 5 | 1 owner conversation, 1 cell number, 2 callbacks |
| Facebook group posts | 2 | 0 engagement (Memramcook), Moncton pending |
| Google search | — | 2 strangers found the site in week one |

**Read:** calls beat DMs by a mile. DMs are near-dead — stop spending real
effort there. Calls, walk-ins and search are the channels that respond.

---

## The daily minimum (5–10 minutes, any time)

1. **~8:30 AM: TikTok drafts land in your inbox** — the engine pushes both
   packs via TikTok's API (since Aug 12). Each caption also arrives as its
   own phone ping (since Aug 13): long-press the ping text → Copy. Open each
   draft from the TikTok inbox notification, paste the caption, add a sound
   (product: upbeat, agent: calm/lofi), tap Post — product in the day, agent
   in the evening.
2. **Morning brief lands ~10 AM** — traffic, captions, callbacks due, and
   confirmation the drafts went out (with an automatic re-push if not).
3. **Posting session** — paste `marketing/daily-post-session-prompt.md` into
   Chrome Claude: X post + 2 product pins + 1 ECS pin. Click the buttons.
4. **Check for replies** — comments on group posts, DMs, texts. Reply fast;
   on Facebook, every reply lifts the post back into feeds.

That's it. If a day goes sideways, do only step 4 — replying to a real human
beats any post.

---

## One outreach action per weekday

Not five. **One.** Doable on a lunch break, and it compounds to ~5/week.

| Day | The action |
|---|---|
| **Monday** | Group-ad check: the group is **"Small business Moncton and area"** (public, ~9.0K members). Rule 4 = **one advertising post per week**, worded "refrain from spamming posts about your products or services" (rules re-read 08-26). No rule about prices either way, so the $79/mo line is fine. **Post as Matthew's personal profile, not the ECS Page** — the Page's join request is still pending, and the personal profile is what pulled 6 click-throughs on 08-19. **No promo self-comment**: a follow-up comment carrying more links is what rule 4 is aimed at; reply to real comments instead. If 7+ days since the last ad, post; otherwise note the next open date. Second venue not yet used: MONCTON BUSINESS ADVERTISING (Official Group Page) — no ECS posts there, rules unread. |
| **Tuesday** | One call. Shops 10:00–11:30, restaurants 2:00–4:00. |
| **Wednesday** | One warm-lead follow-up (a callback owed, or a text bump on someone who went quiet ≥3 days). |
| **Thursday** | One call — a fresh name off the call sheet. |
| **Friday** | Nothing scheduled. If you're up for it: a walk-in after 4:30 (taprooms, restaurants and bakeries are alive Friday evening). |

---

## Saturday morning — the power block (30 minutes)

The only window where you're free *and* businesses are open. This is worth
more than the rest of the week combined.

- **10:00–11:30 · three calls** straight down the call sheet. Log each outcome.
- Or **one walk-in** with the printed sample pack if a lead has earned it
  (owner known to be in, samples already made).

**Making a sample pack** (~5 min per prospect, do these Sunday for the week):

```
cd marketing/east-coast-social/engine
python sample_week.py --new "Their Name" --town "Shediac, NB" --category bakery
# open samples/<slug>/profile.json, fill items/hours/facts from their own page
python sample_week.py samples/<slug>/profile.json
```

Out comes seven days of posts in their colours, `captions.md`, and
`contact-sheet.png` — the one page to print and put in front of an owner.
Filling in the real details is the whole point: a pack on defaults renders,
but it pitches like a stranger, and the script says so when you skip them.

---

## Sunday — ten minutes of housekeeping

1. **Group sweep** — the C.C prompt: new comments, DMs, membership approvals,
   and a search for anyone asking for website/social/marketing help.
2. **Pick next week's five names** off the call sheet, so Tuesday–Saturday
   need no thinking.
3. **Glance at the traffic report's channel line** — once `ref-` events start
   landing, this tells you which channel to feed.

_Traffic data note: Matthew's laptop browser excluded from GoatCounter as of
Aug 11, 2026 (#toggle-goatcounter). Phone NOT yet excluded. Numbers before
Aug 11 include his own visits — treat them as inflated; the clean baseline
starts Aug 12._

---

## Rules that keep this honest

- **Max ~5 outreach touches a week.** Quality over volume; a rushed call is
  worse than no call.
- **Three touches, then rest.** A prospect who's had a call, a text and a
  follow-up without replying goes cold — log it, move on, keep the samples.
  (They can always come back; chasing costs reputation.)
- **One ad per group per week, minimum.** Respect each group's rules exactly;
  a pulled post costs more than a skipped week.
- **Never bump your own group post.** Post something *different* in 2 weeks
  instead.
- **Prices public, always.** Free setup, $79/month, no contracts. Stating it
  openly is the thing that separates us from every "DM me for pricing"
  competitor in those groups.
- **Log every outcome** in `prospects.md` / `call-kit.md`. A "no" is a
  complete result — it stops us wasting a second attempt.

---

## Standing items that aren't weekly

- **Google Business Profile** — puts ECS on Google Maps, where "social media
  help near me" gets searched. Highest-value unfinished task on the board.
  Every field is pre-written in [`google-business-profile.md`](google-business-profile.md) —
  paste it through, then be ready for the verification step (likely a live
  video call: have the business cards and a printed flyer physically in hand).
- **Business cards** — ordered Aug 8, 2026: 250 Standard Matte 2-sided, $31.99,
  Staples Moncton (233 Main St) pickup. Artwork lives in `print/`
  (`card-front-bleed.png` / `card-back-bleed.png`, 1125×675 @ 300 DPI with
  0.125" bleed). Back QR → eastcoastsocial.ca. Once they land, every walk-in
  and every call that ends in "send me something" gets one.
- **Business email** — 20 uninterrupted minutes so replies come *from*
  hello@eastcoastsocial.ca. Full steps in [`email-setup.md`](email-setup.md).
  Note: the address already *receives* (Porkbun forwarding); only sending is
  missing. Zoho's free plan covers it at $0, with the catch that there's no
  IMAP, so it won't land in your usual phone mail app.
- **SNB registration** (~$126) when the insurance money lands — unlocks the
  business bank account and the October ACOA grant path.
- **Grant follow-up** — reminder already set for late September (Cathy at
  TechImpact). Requirement will be "revenue positive with customers," so every
  client landed before October is also grant evidence.
- **Site migration to eastcoastsocial.ca** — trigger: first paying client, or
  Sept 15, whichever comes first.
- **Refill the prospect list** when the call sheet runs dry (memramcook.com,
  Shediac chamber directory, Google Maps for towns not yet worked).

---

## What "working" looks like

- **Week 1–2:** replies, not sales. A comment, a text back, a "send me info."
- **Week 3–4:** one 20-minute conversation with an owner who's genuinely
  interested. That's the real milestone — samples close deals, conversations
  earn samples.
- **First client:** everything changes. The site migrates, the grant path
  opens, and the pitch stops being hypothetical ("here's a client's feed").

One yes. That's the whole game.
