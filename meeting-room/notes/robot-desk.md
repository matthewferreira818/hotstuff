# Robot Desk: one supervisor for the 7 practice stock robots (Matthew, Tue Nov 10: "can we get all the bot under one supervisor?" → "stock bots i mean")
Owner: LC-Stocks (builder, from Nov 10 night; LC-Manager wrote the plan and is parked). NB2 gates. Strategies stay with Grok. Friday reads it to Matthew. PRACTICE MONEY ONLY.

## What it is
A small piece of CODE (not an AI chat), so it keeps working when every chat is closed:
1. **Health:** for each robot (stock-bot, momentum, hot, moonshot, moonshot-crypto, quality, volatility): ran today? running? last run failed?
   snapshot older than 2 h during market hours (crypto: any hour)? trades today.
2. **Scoreboard:** each robot vs simply holding the benchmark it already tracks (spy_units / bench_units in stock_bot/paper/account-*.json),
   after fees, since its start; plus "beats holding: yes/no".
3. **Shared limits (practice):** a total trades-per-day cap across all 7, and a STOP rule (e.g. 3 failed runs in a row, or the whole desk
   down more than X% today). When a STOP rule trips, the Desk may ONLY create stock_bot/PAUSE (the existing switch that stops every robot)
   and say why. It can NEVER resume; removing PAUSE is Matthew's.
4. **One file:** stock_bot/live/desk.json (numbers labelled "paper", "as of <time>"). The Helm's Stock bot tab shows one row per robot
   (running / stale / failed / paused · vs holding · trades today) and one PAUSE status line (read-only in the app).
5. **One standup line:** LC-Manager's 9:35 standup reads desk.json: "7/7 running, N beat holding, paused: no".

## Where it runs
- desk.py runs in a GitHub Actions workflow (robot-desk.yml) every 30 min, weekdays 9-17 Moncton + every 2 h for crypto. Lateness is OK here
  (it only watches); the robot STARTER stays on the Mac (~/Claude/bin/robot-start.sh v2 in the 9:35 standup), because GitHub's cron is unreliable.
- Read-only on everything except: write stock_bot/live/desk.json, and create stock_bot/PAUSE on a STOP rule.

## Hard lines
- Never touches Moomoo files, real-money settings, keys or switches (those are Matthew's; they're on the crew's deny list too).
- No strategy changes (Grok's), no new robots, no orders. It never starts a robot (the Mac starter does that).
- Checks: offline tests for the health rules (ran today in Moncton time, stale, failed), the scoreboard math (one robot by hand), and the
  STOP → PAUSE rule (creates the file, never deletes it). Rollback = delete robot-desk.yml + desk.py; PAUSE behaviour is unchanged.

## Build notes (LC-Stocks, Tue Nov 10 night, branch stocks/robot-desk)
- Files: `stock_bot/desk.py`, `stock_bot/test_desk.py` (27 offline tests), `.github/workflows/robot-desk.yml`.
- **desk.json goes to its own branch, `stock-live-desk`** (path stock_bot/live/desk.json inside it), the same way each robot's live.json
  has its own branch: no commit on master every 30 minutes and no site rebuild. Normal push, never forced; a refused push just waits for the
  next run. The Helm reads it from raw.githubusercontent.com/matthewferreira818/hotstuff/stock-live-desk/stock_bot/live/desk.json.
- Data it reads (read-only): each robot's workflow runs (GitHub API, the workflow's own token, actions: read), each robot's live.json
  branch, and the practice account files on master (for trades today). Uses no secrets.
- Health: ran today = a run created on today's Moncton date that is running or succeeded. "Cancelled" runs are queue swaps, not failures.
  Stale = snapshot older than 2 h while its market is open (NYSE hours, 2026-27 holidays and 1 PM early closes built in; crypto any hour).
- Scoreboard: account value (fees already taken out) vs holding its own benchmark (SPY, or Bitcoin for Moonshot crypto) since its own start.
  A robot under 30 days old that's ahead is labelled "too early": a lucky week is not evidence.
- STOP rules (first values, NB2 gate + Matthew GO to change): more than 40 practice trades in a day across all 7 (busiest day so far ~20);
  one robot's last 3 finished runs all failed; all 7 together down more than 5% since the Moncton day began. Missing data never trips a rule.
  On a STOP the desk creates stock_bot/PAUSE (create-only, reason inside) and the workflow commits only that file to master.
  Note: stock_bot/PAUSE also stops the research bot (it obeys the same file).
- Verified Nov 10 ~7:30 PM: 27/27 tests pass; a dry run on live data (no publish, no PAUSE) gave "7/7 ran today, 3 beat holding
  (3 under 30 days old), paused: no", matching the GitHub run list.
- Not done yet: the workflow hasn't run on GitHub (it can't until merged); the standup line still needs a reader (New beginning's
  standup now, since LC-Manager is parked); LC-Pixels' Helm row.
