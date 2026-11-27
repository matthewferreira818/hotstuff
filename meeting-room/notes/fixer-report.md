# Fixer report: broken automation (Fri Nov 27 2026, ~3 AM Moncton)

By **Local Claude (Fixer)**. I checked every item myself (logs, run history, the GitHub API); I didn't take the Nov 26 list on trust.
Fixer changed no settings, secrets, scheduled tasks or PRs. The only code change is on branch `fixer/health-report` (row 1b).

| # | Item | Status | One line |
|---|---|---|---|
| 1 | Research bot stuck since Nov 18 | **NEEDS MATTHEW** | Keep or discard 4 staged files (low value). Commands for both are below. |
| 1b | generate.py said "committed and pushed" when the commit had failed | **FIXED (on branch, waits for NB2)** | Now says "COMMIT FAILED, nothing pushed". New test; 60/60 pass, and the new test fails on the old code. |
| 2 | Weekday standup misses days | **NEEDS MATTHEW** | The Mac was asleep. Move it to a cloud schedule (my pick) or change a Mac setting yourself. |
| 2b | Robot Desk "under-firing" | **NOT BROKEN** | It runs on GitHub, not the Mac. GitHub's timer fires 4 to 5 of its 32 slots a day. Every run succeeded. |
| 2c | Robots missed Mon Nov 23 | **NEEDS MATTHEW** (same fix as 2) | All 6 stock robots ran every weekday Nov 12 to 26 except Nov 23, when the backup start (standup) was asleep too. |
| 3 | 7 stale PRs | **NEEDS MATTHEW** (only NB2 merges/closes, on your word) | My pick: close 6, merge 1 (#27) or close it too. Table below. |
| 4 | Dependabot off | **NEEDS MATTHEW** | Alerts are off. I'd switch alerts on and leave auto-fix PRs off. |
| 5a | Facebook token dead | **NEEDS MATTHEW** (his login) | Failing every day since Nov 19. Steps below. |
| 5b | CJ API disabled | **NEEDS MATTHEW** (his login) | The product refresh has failed every run since Nov 7, so the store catalog is frozen at the Nov 4 refresh. |
| 5c | X credits (issue #14) | **NEEDS MATTHEW** (costs money, shelved) | Both X accounts skip with "no credits". Nothing else breaks. |

---

## 1. Research bot (Mac, `~/Claude/research-bot-runner`, runs hourly at :25 via launchd)

**What happened, from `~/Library/Logs/researchbot.log`:** Git on this Mac has no name or email set. It had been guessing
one from the Mac's network name. On **Wed Nov 18 at 10:34 AM** that guess stopped working ("Author identity unknown"),
so the commit failed and the files stayed staged. Every run since then stops at the first step ("cannot pull with rebase:
Your index contains uncommitted changes"). That's 206 skipped runs so far. The folder is also 104 commits behind master.

**What's staged (4 files, +11 −9), all from that one Nov 18 10:34 AM run:**
- `equity.jsonl`: 1 practice-equity point ($978.56, Nov 18 15:08 UTC)
- `forecasts.jsonl`: 1 "no_trade" line for crypto (no idea made a call), 14:34 UTC
- `scorecard.json` / `scorecard.md`: re-generated numbers (span 7→8 days, no-trade days 123→124)

**Is it worth keeping?** Hardly. The scorecard rebuilds itself on the next run. The one forecast line never reached GitHub
before its window opened, which is the rule for forecasts to count, so keeping it adds nothing to the record. Losing the
equity point leaves a gap from Nov 17 to the next run either way. **My pick: discard.**

**Either way, git needs a name first** (otherwise it breaks again next commit). This sets it for this one folder only:
```bash
git -C ~/Claude/research-bot-runner config --worktree user.name "Research bot (Mac)"
git -C ~/Claude/research-bot-runner config --worktree user.email "300638051+matthewferreira818@users.noreply.github.com"
```

**If DISCARD:**
```bash
git -C ~/Claude/research-bot-runner restore --staged --worktree -- stock_bot/research_bot/equity.jsonl stock_bot/research_bot/forecasts.jsonl stock_bot/research_bot/scorecard.json stock_bot/research_bot/scorecard.md
```

**If KEEP:**
```bash
git -C ~/Claude/research-bot-runner commit -m "Research bot: Nov 18 10:34 cycle (kept after the stall)"
git -C ~/Claude/research-bot-runner pull --rebase origin master
git -C ~/Claude/research-bot-runner push origin HEAD:master
```
(That pushes straight to master, the same way the bot always has. If the rebase stops on a conflict, run
`git -C ~/Claude/research-bot-runner rebase --abort` and choose discard instead.)

**Proof it works again:** the next `:25` entry in `~/Library/Logs/researchbot.log` should say "=== done" with no "pull failed".
Check the research bot's live PAUSE state first if you don't want it trading (practice money) the moment it wakes up.

**1b (fixed on branch):** `stock_bot/research_bot/generate.py` didn't check whether its commit worked. Pushing an unchanged
HEAD "succeeds", so it logged "committed and pushed" on Nov 18 when nothing was pushed. It now returns "COMMIT FAILED,
nothing pushed: <reason>". There's a test for it in `test_research_bot.py`.

## 2. Standup + robot start

**Standup run history (scheduled task `lc-manager-standup`, 9:35 AM weekdays):** ran Nov 6, 9, 10, 11, then Nov 12 at
5:14 PM (late), Nov 16 at 3:04 PM (late), Nov 25 at 2:28 PM (late), Nov 26 at 9:35. **Missed Nov 13, 17, 18, 19, 20, 23, 24.**

**Why: the Mac was asleep.** Its power log (`pmset -g log`) only goes back to Nov 20. For those days:
- Nov 20: only background "dark wakes" all morning. The first real wake was at 7:09 PM.
- Nov 23: asleep through 9:35. The lid was closed ("Clamshell Sleep") at 10:35 AM.
- Nov 24: first real wake at 3:55 PM.
A desktop-app scheduled task only fires when the Mac is awake and the app is open. The late runs are catch-ups after waking.

**Robots (GitHub Actions):** the 6 stock robots ran on every weekday Nov 12 to 26 **except Mon Nov 23**, when none ran
(GitHub's hourly timer didn't fire and the standup's backup start was asleep). Moonshot crypto runs every day by hand-off
dispatches. Its scheduled runs show "cancelled", which its workflow says is expected.

**Robot Desk:** set for every 30 min on weekdays plus every 2 hours. GitHub actually fired it 4 to 5 times a day, and all
of those runs succeeded. GitHub skips busy schedules on free repos. That's normal and nothing is failing, so no change.

**Fix options (my pick first):**
1. **Move the standup to a cloud schedule** (a Claude routine that runs in the cloud, Mac on or off). It only needs the
   repo and `gh`, which the cloud has. That's a new scheduled task, so it needs your OK. A Robot Desk chat or NB2 can set it up.
2. **GitHub Actions schedule:** free, but it's the same timer that skipped Nov 23, so it's no better as the backup.
3. **Mac power setting (you change it yourself, it needs your password):** System Settings → Energy (or Battery → Options)
   → "Prevent automatic sleeping when the display is off" while plugged in, and keep the lid open. A closed lid sleeps no matter what.
   I won't change this for you.

## 3. Stale pull requests

#35 "Hotline (never merge)" is not stale. It's the wake-up line for cloud Claude, so leave it open.

| PR | What it is | Still needed? | Mergeable? | Recommend |
|---|---|---|---|---|
| #33 | Grok: Volatility robot config | No. Volatility is already on master (since Nov 4) | Conflicts | **Close** |
| #32 | Grok: Quality Dip robot config | No. Quality Dip is already on master (since Nov 4) | Yes, but would overwrite the live config | **Close** |
| #31 | Grok: restrict Hot hands (5 orders/day, 1 trip) | No. It reverses your "hot trading all day" choice of Nov 4, and LC-Stocks' Nov 10 review already said to retire Hot hands as a money-maker | Yes | **Close** (the Robot Desk chat decides Hot hands' future) |
| #30 | GPT: Meeting Room shows messages faster (app code) | Probably not. The Helm was rebuilt after it (Simple mode, Nov 6) | Conflicts | **Close**. Re-open as a new job if the room still feels slow |
| #29 | GPT: Mac compile record for Council 1A (Nov 4) | No. It's a record for a build that's long gone | Conflicts | **Close** |
| #27 | GPT: plan for the live Roxy + Claude + Grok council | Only if Project Trinity is still on | Yes (adds 1 note) | **Merge** as a note if Trinity's alive, otherwise **close** |
| #17 | GPT: Home page layout (Oct 24) | No. Home was replaced by Simple mode on Nov 6 | Conflicts | **Close** |

## 4. Dependabot

Right now: Dependabot alerts **off**, security fix PRs **off**, no `dependabot.yml`. (Secret scanning and push protection are on.)
What it would watch: the checkout worker's npm packages (`checkout-worker/package.json`) and the GitHub Actions versions
in 25 workflows. The Python packages are installed inside workflows without a list, so it wouldn't see them.
- **Alerts on:** GitHub emails you when a known security hole shows up in one of those packages. Free, and nothing changes on its own.
- **Security fix PRs on:** GitHub opens PRs by itself to bump the bad package. That means more PRs waiting on NB2.
- **Version update PRs (dependabot.yml):** regular "bump everything" PRs. Noisy, and I'd skip them.
My pick: alerts on, the rest off. Where you'd do it: repo Settings → Code security → Dependabot alerts → Enable.

## 5. Dead credentials (your logins, so I haven't touched them)

**5a. Facebook (`FB_PAGE_TOKEN`).** It's failed every day since **Nov 19** with Graph API error 190/460: "session has been
invalidated because the user changed their password or Facebook has changed the session for security reasons". Any token
made from the old session is dead.
Steps: (1) Log in at developers.facebook.com → Tools → **Graph API Explorer**. (2) Pick the app "ECS Posting Engine" and
**Get User Access Token** with `pages_manage_posts`, `pages_read_engagement`, `pages_show_list`. (3) In **Access Token Debugger**,
click **Extend Access Token** to get the long-lived user token. (4) Back in the Explorer with that token, call `me/accounts`
and copy the ECS Page's `access_token` (Debugger should show Type: Page, Expires: Never). (5) Copy it, then ask a crew chat to run
`tools/crew/add_secret.sh FB_PAGE_TOKEN`. (6) Run "ECS daily post" by hand once and look at the Page logged out.
**Still working meanwhile:** the daily card is still made and published to the site feed (findhotstuff.com/automation). That
step runs before Facebook, so the odometer's streak is fine. Only the Facebook post is missing.
**The ECS X post:** when Facebook fails, the X step is skipped. But X was already skipping before that ("X developer account
has no credits", Nov 17 log), so nothing extra is lost. No fix needed until X has credits.

**5b. CJ Dropshipping API.** "Refresh trending products" has failed **every run since Nov 7** (21 runs in a row, plus 1 of 3 on Nov 4): "Your API access
has been disabled. Please visit cjdropshipping.com/my.html#/authorize/APIStores to reactivate it."
Steps: (1) Log in to CJ → My CJ → **Authorization → API** (the page in that message). (2) Reactivate API access. If it gives
a **new** API key, copy it and ask a crew chat to run `tools/crew/add_secret.sh CJ_API_KEY`. (3) Run "Refresh trending products"
by hand once and check it goes green.
**Still working meanwhile:** the store is up and checkout works (Stripe/worker don't use CJ). But the catalog, prices,
category pages and sitemap haven't updated since Nov 4. **Honesty risk:** CJ may have changed a price or stock level since
then. Worth a spot-check before any outreach that links to products.

**5c. X API credits (issue #14, open since September).** Both the store's tweets and the ECS X account skip with "no
credits". Topping up costs money, which money mode has shelved until client #1. So: no action, and leave #14 open.
**Still working:** everything else. The tweet workflow ends green because it skips cleanly.

---
Nothing here was guessed. Every number comes from a log, a run list or the GitHub API, read on Nov 27 between about 2:50 and 3:30 AM.
