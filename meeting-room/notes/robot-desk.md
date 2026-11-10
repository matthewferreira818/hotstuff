# Robot Desk: one supervisor for the 7 practice stock robots (Matthew, Tue Nov 10: "can we get all the bot under one supervisor?" → "stock bots i mean")
Owner: LC-Manager (plan + gate). Strategies stay with Grok. Friday reads it to Matthew. PRACTICE MONEY ONLY.

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
