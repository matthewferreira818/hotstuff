# 4. The 7 free sample posts

Takes over LC-Pixels' unfinished "made-for-you samples" job (LC-Pixels is archived).
The samples are the closer: the business stops imagining it and looks at its own week.

## Two kinds of samples
1. **Asked for** (they said yes to samples). Make them, send within a week. This is the main job.
2. **Pre-made** (nobody asked yet) for Roxy's picks. Prep only, labelled "SAMPLE DESIGN — not a client". They sit ready so a "yes" can get samples the same day.
   Pre-made samples are **never sent cold**: sending one is an outreach touch and needs the full Roxy OK + Claude OK + Matthew GO, and counts toward two touches max.

## Status (Nov 27)
- One business that said yes got its 7 samples on Nov 25 (one PDF). Waiting on their feedback. Details private (Helm-Private `ecs/replies-log.csv`).
- Roxy's picks: her list updated Nov 13 has 4 businesses (one dropped after a decline). **Asked Roxy in the room to confirm they're still current** (no DNC, no reply since) or swap in fresh ones, up to 5.

## The recipe (what worked for the Nov 25 pack)
1. **Sources first.** Save the text of their own pages (website About/services/contact, public Facebook page if readable) with the date, into a private `sources/` folder. Facts come ONLY from there.
2. **Pick 7 angles** that fit the business type. Maker (food, retail, crafts): what's fresh, the hero item, the daily rhythm. Doer (services, trades, schools): who we are, free know-how, how to book.
3. **Make the cards.** `marketing/east-coast-social/engine/sample_week.py` / `sample_posts.py`, their colours, their logo. Their own photos only; if there are none, drawn graphic cards. No stock photos passed off as theirs, no AI people, no private faces.
4. **Write captions.** Plain, local, short. Leave out on purpose: prices, staff names, pass rates, reviews, dates that change, anything time-sensitive we can't re-check.
5. **Fact pass** (Claude): every claim matched word for word to `sources/`. Run `claims_check`. Re-check the live site the day it's sent.
6. **Honesty check** (Roxy).
7. **Matthew looks** and asks for changes (he asked for touch-ups last time).
8. **Pack it**: one PDF, one page per post (image + caption). Easier to open on a phone than 7 attachments.
9. **Send** (Matthew), with the reply in [1-reply-playbook.md](1-reply-playbook.md) F. No payment ask in the samples email.
10. **Log** the send privately. Next touch: reply G, about a week later if quiet.

## Where files go
Private only: Helm-Private `ecs/samples/<business>/` (sources, make script, out/). Never in this public repo, never posted anywhere.

## Time
Target: samples in the business's hands within a week of their yes (the page promises "within a week"). Aim for 2-3 days.
