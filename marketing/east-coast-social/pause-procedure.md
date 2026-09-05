# The pause procedure — how everything stops, in about a minute

Written 2026-09-05, because we did not have one. The Skeptic's line was
right: *never promise a brake before it exists.* This is the brake. It works
today, before any promise about it goes on a public page.

## The scenario this exists for

It is a Tuesday. There is a fatal on Route 106, or a funeral in the family
of the shop next door, or a client's building floods overnight. Matthew is
at work until 4:30. At 5:09am the engine already queued a cheerful card, and
at 10:00 it goes up on a business page in a town of 5,000 people where
everybody knows.

Nobody gets fired for a slow week. This is the one that costs a client, and
it never announces itself in advance.

---

## Level 0 — a client's page (today, this is instant)

**There is no automation on a client's page yet.** `post_to_facebook.py`
reads a single `FB_PAGE_ID` / `FB_PAGE_TOKEN` — our own ECS page. Every
client card is posted **by Matthew's hand** each morning (see
`leblanc-yes-runbook.md`, Step 4).

So pausing a client is: **don't post.** Zero seconds, zero mechanism,
no way for it to fail. Then text them:

> Saw the news. I've stopped your posts — nothing goes up until you tell me.
> Take your time.

That is the whole procedure at Level 0, and it will stay true until the Meta
auto-post token is installed. **When that day comes, this section has to be
rewritten before the token goes in, not after.**

---

## Level 1 — `PAUSE` — everything we publish goes quiet

Stops: the ECS Facebook page, ECS on X, the HotsTuff product spotlights
(X + Instagram), the TikTok pack build, and the TikTok draft push.

Keeps running: **the daily card still lands in `automation/feed`.** That is
deliberate. The odometer measures the site feed, not any social page —
that's non-negotiable #1, and the page says so out loud. Silencing our
social accounts during a bad week does not make the site-feed claim untrue,
so the counter keeps counting honestly.

### From the phone, one hand, about 60 seconds

1. Open **`github.com/matthewferreira818/hotstuff/new/master`**
   (bookmark this — it opens straight onto the new-file screen).
2. Filename: **`PAUSE`** — capitals, no extension.
3. Body: **the date and your initials. Nothing else.**
   ```
   2026-09-05 MF
   ```
   **This repo is public and the file is served from the website.** Never
   put a name, a business, a death, an address or a reason in it. "Paused
   — MF" tells us everything we need and tells a stranger nothing.
4. **Commit changes** → *Commit directly to the `master` branch*.

It takes effect on the **next scheduled fire**. The morning crons are 05:09,
06:39 and 08:21 Atlantic, so anything you decide the night before, or before
you leave for work, lands before that day's post.

### While it's on

Every morning your phone gets one ntfy note: *"PAUSE has been in the repo
since <date>. Nothing is going out. Delete the file to resume."* That
reminder exists because the real failure mode of a pause is not the pause —
it's forgetting you pressed it and quietly going out of business.

### To resume

Open **`github.com/matthewferreira818/hotstuff/blob/master/PAUSE`** → the
trash-can icon → **Commit changes**. The next cron posts normally. Nothing
else to switch back on, no secrets to re-paste, no workflows to re-enable.

---

## Level 2 — `PAUSE-ALL` — stops the site feed too

Same steps, filename **`PAUSE-ALL`**.

**Read this before you use it.** The site feed is the proof the whole
business stands on. `automation/feed/stats.json` reads `total 32, since
2026-08-04` today, and the page renders "32 days straight" **only while the
count equals the number of calendar days** (`automation/index.html:617`).
Miss one day and that test fails forever: the hero line and the streak
sentence disappear on their own — which is the code being honest, exactly as
designed — and the only way to ever show a streak again is to restart the
count at 1.

So `PAUSE-ALL` costs the strongest asset on the money page, permanently. Use
`PAUSE` unless the site feed itself is the problem.

---

## What the switch cannot do

- **It cannot un-post something already up.** That is a manual delete on the
  platform, from Matthew's own hand — rule #3, he clicks every final button.
  Pause first (60 seconds), then delete the post; in that order, because the
  next cron is the thing that can still make it worse.
- **It cannot stop the Cloudflare Worker.** Store checkout, `/lead` capture
  and order alerts are separate and keep working. That's correct: a pause is
  about what we *say* in public, not about refusing a customer's money.
- **It cannot survive a force-push that clobbers the file.** Unlikely, but
  the daily ntfy reminder is how you'd notice.

---

## The billing rule that goes with it

Decided with the Treasurer, 2026-09-05:

- A pause **stops the posting the day it's asked for.**
- The month already paid is **not prorated and not refunded** — chasing
  half-months costs more in bookkeeping than the $39.50 it recovers.
- They are **never charged again** unless they ask to start.
- A client paused **60 days** gets closed out with a friendly note; the slot
  goes back in the pipeline. Nobody sits in limbo, nobody is billed for
  silence.
- Plan the model on **9 paid months a year, not 12** — seasonal businesses
  pause, and every number we quote should already assume it.

Client-facing, one sentence:

> Text me STOP and the posting stops that day — the month you've already
> paid isn't prorated or refunded, and you're never charged again unless you
> text me START.

---

## What to say to a client (once it's live, not before)

The promise only lands if it's framed as **their** control, not as our fuse.
"Text STOP if something goes wrong" plants a doubt they didn't have. This
doesn't:

> **What if I need it to stop?**
> Text me STOP and posting pauses that day — no questions, no reason needed.
> A death in the family, a flood, a bad week, or you just changed your mind:
> your page goes quiet until you text me GO. It's your name on it, so you
> keep the brake.

Every owner in this town has had that week. Nobody else selling daily
posting thinks to mention it.

---

## The mechanism, for whoever maintains it

`.github/workflows/pause-gate.yml` is a reusable workflow. It checks out the
repo, looks for `PAUSE-ALL` then `PAUSE`, and returns two outputs.

| Workflow | Gated on |
|---|---|
| `ecs-daily-post.yml` | job runs unless `PAUSE-ALL`; the **Facebook** and **X** steps additionally skip on `PAUSE` |
| `daily-tweet.yml` | job skips on `PAUSE` |
| `daily-tiktok.yml` | job skips on `PAUSE` |
| `tiktok-draft.yml` | job skips on `PAUSE` |
| `merch-tweet.yml` | job skips on `PAUSE` |

One wrinkle worth knowing: `daily-tweet.yml` and `tiktok-draft.yml` dedupe
backup-cron fires by looking for "a successful run today". A run halted by
the switch *also* concludes success — its publishing job is merely skipped —
so both guards now check the **job's** conclusion, not the run's. Without
that, deleting `PAUSE` at 9am would still have cost the whole day.
