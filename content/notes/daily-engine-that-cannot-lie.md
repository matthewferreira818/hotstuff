title: A posting engine that has run 51 days without me — and the twelve characters that stop it lying
description: The architecture of a daily automated posting pipeline on GitHub Actions, why the scheduler runs hours late, and the one condition that makes the streak claim retract itself the day it stops being true.
date: 2026-09-26
draft: true
---

My store's companion page publishes a new post every day. As I write this
it has done so **51 days running, since August 7th, 2026** — you can check
the live count and the dated feed at
[findhotstuff.com/automation](https://findhotstuff.com/automation).

The interesting part is not the automation. Cron has existed for fifty
years. The interesting part is what happens the day it breaks, because a
page that boasts about a streak is one outage away from being a liar.

## The shape of it

No servers, nothing paid:

- **GitHub Actions** on a cron fires each morning.
- **A Python script** builds the day's card with Pillow — no LLM, just a
  fixed set of hooks and a deterministic pick keyed off the date, so the
  same day always produces the same card.
- **The card is committed to the repo** into a dated feed folder, and a
  small `stats.json` gets the running total.
- **GitHub Pages** serves it. The page fetches the feed and draws it.

That is the whole thing. The total cost is zero a month.

## The first surprise: GitHub's scheduler is not punctual

Cron in Actions is best-effort, and for this repo it has been drifting
badly. Measured, first fire of the day against an 08:09 UTC schedule:

```
  Sept 12   12:07   (3h58m late)
  Sept 13   13:16   (5h07m late)
  Sept 14   14:58   (6h49m late)
```

Not skipped — late. Which is a different bug and needs a different fix.

I got this wrong twice. I saw "no post yet" at my usual check time,
concluded the run had been dropped, and triggered it by hand. The second
time I checked properly and found the scheduled run had fired eleven
minutes after my manual one, then correctly no-opped on the duplicate
guard. I had not saved anything. I had just been impatient.

So the rule got written into the workflow itself:

> Do not hand-dispatch at 13:05. Wait. If nothing has landed by ~16:00
> UTC, that is a real miss and worth a dispatch; there are still eight
> hours of margin at that point. Chasing the drift with more cron shifts
> is a treadmill.

Three backup crons cover a genuine miss, and a gate step makes whichever
fires first win so the rest no-op.

## The part I actually want to tell you about

Here is the problem. The page says the feed has published every single day
since August 7th. That is true today. The day a run genuinely fails, it
becomes false — and it becomes false *silently*, on a live page, in front
of the exact people I am asking to trust me.

You cannot fix that with discipline. You will not be at a keyboard the
morning it breaks.

So the claim is not stored anywhere. It is computed, and it is conditional:

```javascript
var span = Math.round((new Date(s.last) - new Date(s.since)) / day) + 1;
if (total === span) text += el.dataset.streak;
```

The page only renders "one every single day" when the number of posts
equals the number of calendar days elapsed. Miss one day and `total` falls
behind `span`, the condition fails, and the sentence simply does not
appear. Same for the headline counter above it.

**Twelve characters — `total === span` — and the page cannot overstate
itself.** Not because I remembered to fix it, but because the claim was
never separable from its own evidence.

## What that costs

It is not free. The streak, once broken, can never come back honestly
without restarting the count from one. There is no "back to 54 tomorrow."
That is the correct behaviour and it is still uncomfortable, and it makes
the pause switch I built later genuinely expensive to use.

I think that discomfort is the point. A claim that is cheap to make is
worth what it costs.

## If you build something similar

Three things I would do again:

1. **Make the boast conditional on its own data.** If you find yourself
   writing a number into HTML by hand, you have just taken on a permanent
   obligation to remember something.
2. **Separate the counter from the artifacts.** My feed only keeps the
   last eight cards on the page, but `stats.json` counts every one. Display
   and truth are different concerns.
3. **Measure your scheduler before you trust it.** I built three backup
   crons to fix a skipping problem that turned out to be a lateness
   problem. Right instinct, wrong diagnosis, and I only found out by
   reading actual run timestamps instead of assuming.
