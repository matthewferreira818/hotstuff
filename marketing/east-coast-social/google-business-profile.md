# East Coast Social — Google Business Profile setup pack

Everything to paste, in order, plus the decisions worth getting right the
first time. Claude can't create the profile — it needs your Google sign-in and
a verification step only you can complete — so this is the copy-paste sheet.

Start at <https://business.google.com/create>, signed in as the Google account
you want to own this forever (not a throwaway).

**Why this is worth the 30 minutes:** when a Moncton restaurant owner finally
decides to fix their social media, they search — and right now ECS does not
exist on Google Maps. Cold calls reach one person at a time; this catches the
ones already looking. It is the only free channel that works while you sleep.

---

## Before you start

- The Google account that should own it long-term.
- Your **home address** — required for verification even though customers will
  never see it (see "Address" below).
- A phone that can take a code: **(506) 889-9737**.
- 10 minutes of quiet for the verification step, which may be a live video
  call. See "Verification" at the bottom — worth reading *before* you begin.

---

## Fields, in the order Google asks

### Business name
```
East Coast Social
```
Exactly that. **Do not** append keywords ("East Coast Social — Social Media
Marketing Moncton"). Keyword-stuffed names are the single most common cause of
profile suspension, and a suspension is far more painful than the ranking it
would have bought.

### Primary category
```
Internet marketing service
```
This is the decision that most affects which searches surface you, so it's
worth understanding: the primary category does the heavy lifting, and
secondary ones add reach without diluting it. "Internet marketing service" is
the closest match to how people phrase what you sell.

**Secondary categories** (add all that the picker offers):
```
Marketing agency
Advertising agency
```

Google's category list changes and is regional, so treat the live picker as
authoritative — if "Social media agency" appears, take it as primary instead,
since it's a more literal match.

### Address — enter it, then hide it
You must give a real physical address to verify. Google's own guidance for
service-area businesses is explicit: *"If you're a service-area business, you
should hide your business address from customers."* So:

1. Enter your home address when asked.
2. Answer **"No"** to "Do you want to add a location customers can visit?"
   (or untick "Show business address to customers" if it's phrased that way).

Your address is then used only for verification and distance calculations —
it never appears on the profile.

### Service areas
Google allows one service area per profile and asks that it not extend beyond
roughly two hours' driving from your base. Everything below is inside 45
minutes of Sackville, so you're well within it:

```
Sackville, NB
Memramcook, NB
Dorchester, NB
Shediac, NB
Dieppe, NB
Moncton, NB
Riverview, NB
Salisbury, NB
```

Add Amherst, NS only if you actually want Nova Scotia leads — it's 20 minutes
away but a different province for invoicing.

### Phone
```
(506) 889-9737
```

### Website
```
https://findhotstuff.com/automation/?ref=gbp
```

Deliberately **not** `eastcoastsocial.ca`, even though that matches the
business name: that domain 301s to the automation page but **drops the query
string**, so the `?ref=gbp` tag is lost and GBP traffic becomes
unattributable. Using the direct URL keeps the tag, so the traffic check can
tell you whether Google is actually delivering.

Switch to `https://eastcoastsocial.ca/?ref=gbp` once that redirect preserves
query strings *and* the site has migrated (trigger: first paying client, or
Sept 15). See "Loose end" at the bottom.

### Hours

Honest hours beat impressive ones — a listed-open profile that never answers
earns "didn't pick up," which is worse than being closed. You work 6:45–4:30,
so:

```
Monday–Friday    5:00 PM – 8:00 PM
Saturday         9:00 AM – 12:00 PM
Sunday           Closed
```

The trade-off, stated plainly: business owners often search during *their*
workday, and "open now" filters will skip you then. If that starts costing
you, the fix is not fake hours — it's adding "Online appointments" as an
attribute (below) so people book instead of calling.

### Description (750-character limit — this is 611)

```
East Coast Social keeps your business page posting every day, without you lifting a finger.

Most local pages go quiet because nobody has time to feed them. We set up a posting engine tuned to your shop — your logo, your colours, your specials — that writes, designs and publishes a branded post daily. You approve the style once; after that it runs.

Proven on our own store first: findhotstuff.com has posted three times a day, every day, hands-free.

Serving Sackville, Memramcook, Dorchester, Shediac, Dieppe, Riverview and greater Moncton.

Free setup. $79/month, no contracts. You see sample posts before anything goes live.
```

### Services

Add each with its own description — services are searchable and they're where
the pricing objection gets answered before a call:

| Service | Price | Description |
|---|---|---|
| Daily social media posting | $79/month | One platform, one branded post every day, in your colours. Free setup, no contract. |
| Two-platform posting | $129/month | Up to 3 posts a day across two platforms, plus scannable QR image cards. |
| Free sample week | Free | Seven days of posts built for your business before you pay anything — see exactly what your feed would look like. |
| Social media setup | Free | Page setup, branding and posting schedule configured for you. |

### Attributes
Tick these where offered:
- **Online appointments** — yes
- **Onsite services** — yes
- **Identifies as locally owned** — yes
- **Language: English / French** — both, this is a bilingual market

---

## Photos to upload

All already in the repo — upload in this order (Google shows the logo and
cover most, and profiles with photos get materially more clicks than those
without):

| Slot | File |
|---|---|
| Logo | `marketing/east-coast-social/fb-logo.png` |
| Cover | `marketing/east-coast-social/fb-cover.png` |
| Photo | `marketing/east-coast-social/print/flyer.png` |
| Photo | `marketing/east-coast-social/print/card-front.png` |
| Photos | any `engine/samples/<prospect>/day-*.png` — real sample cards are the most persuasive thing you own |

---

## Verification — read this before you start

Google picks the method automatically (phone, email, postcard, or a live video
call) and you can't choose. Service-area businesses without a storefront
frequently get **video**, so be ready for it. Review can take up to 5 business
days; some verify instantly.

If you get video, you'll be asked to show three things. What to have ready:

1. **That the location is real** — step outside, show the street sign or house
   number, then walk back in. This is why the home address matters.
2. **That the business operates** — branded materials and tools. Your business
   cards, a printed flyer from `print/`, and the laptop with the engine
   actually running (`findhotstuff.com` posting, or a sample pack rendering)
   are exactly what they're asking for.
3. **That you're the one who runs it** — show the ECS accounts logged in, the
   repo, the scheduled posts.

Have the business cards and one printed flyer physically in hand before you
start the call. Fumbling for proof mid-call is the usual reason these fail.

---

## The first week after it goes live

1. **Post once** (GBP Posts behave like a mini feed and signal an active
   profile): reuse the pinned intro from `facebook-page-info.md`.
2. **Seed the Q&A** — you can ask and answer your own questions, and this is
   where you pre-empt the two objections that kill calls:
   - *"How much does it cost?"* → "Free setup, $79/month for daily posting on
     one platform. $129/month for two platforms and up to 3 posts a day. No
     contracts."
   - *"Do I have to write anything?"* → "No. You approve the style once at
     setup. After that the posts write, design and publish themselves."
   - *"What areas do you serve?"* → "Sackville, Memramcook, Dorchester,
     Shediac, Dieppe, Riverview and greater Moncton."
3. **First review matters more than the next ten.** The first client you land,
   ask for one — a profile with zero reviews looks abandoned regardless of how
   good the description is.

---

## Loose end worth fixing

`eastcoastsocial.ca` 301s to `findhotstuff.com/automation/` but **strips the
query string**. Anything tagged that points at the branded domain loses its
attribution — including the **business-card QR code**, which points at
eastcoastsocial.ca. So card-driven visits currently arrive untagged and are
invisible in the traffic check.

Fix it wherever that redirect is configured (registrar / Cloudflare / DNS
host) by enabling "preserve query string" — usually a checkbox. Once done, the
GBP website field can switch to `https://eastcoastsocial.ca/?ref=gbp` and the
cards can carry `?ref=card` on their next print run.
