# Helm: Stock bot area revamp + Research bot tab (LC-Pixels, Tue Nov 10 2026; job from NB2 for Matthew; Roxy = design partner)

## Stock bot area revamp (added later the same day, Matthew's pick of Roxy's "Robot fleet" concept)
- **Layout:**
  - Left column: ROBOT FLEET (7 robots, each with a freshness dot, snapshot age and $ vs holding), then RESEARCH (the research bot, amber,
    its own entry).
  - Robot page: "Stocks / Hot hands" with PAPER ONLY and the snapshot time; 4 cards (Portfolio, Net return $ with % vs money put in,
    Ahead of holding, Cash).
  - Sub-tabs: **Overview** (Portfolio trajectory with 1D/1W/1M/1Y/ALL, the strip with positions / trades / fees, the Trade journal, and
    "Why it acted or waited" from the robot's own notes), **Holdings** (a price chart per position with Bought at / Peak / Stop lines and
    its buys and sells), **Trade journal** (every order, result after fees on sells), **Rules & risk** (the snapshot's rules + stop distances).
  - Friday's column on this page: **Fleet comparison** (7 ranked vs holding) and **Research notes** (the research bot's latest guesses).
    In a compact window or Simple mode, both sit under the page and the fleet becomes chips.
- **Where the numbers come from:**
  - The cards and the fleet come from each robot's live snapshot.
  - The trajectory is **rebuilt** from the robot's paper account file on master (every filled order) plus public Yahoo prices, and the
    caption says so. Snapshots are replaced every run, so no recorded value history exists.
  - Replaying the orders lands within a few cents of the recorded cash on all 7 accounts (checks/stockhistory_check.swift).
  - The last point is the live snapshot itself.
- **Dips:** shaded where the line is more than 1.5% / 3% / 5% / 10% (1D / 1W / 1M / 1Y-ALL) below its high of the past 2 hours / day /
  5 days / 30 days. A rolling high, so one long slide isn't shaded end to end.
- **Prices:** cached in memory and on disk (the app's Caches folder). Offline shows the last saved prices, marked in amber. With none
  saved, it says nothing is drawn rather than guess.
- **Honesty:** no buy or sell control, no money switch. Every empty state says what's missing.
- **Not done (backend, flagged to Roxy):**
  - Recorded value history.
  - Next review time.
  - Per-decision reasons beyond the notes.
  - Unseen-data test results per robot.
  - Markets/watchlist.
- **Files:** StockHistoryData.swift (data, replay, dips, cache), HubStockArea.swift (the area), HubStocks.swift (now just the entry
  point), StockData.swift (position price/entry/peak/stop, rules, timed notes), Hub.swift (`StockHub.all`), HubDeck.swift (no page
  header on this page; Friday's column shows the two cards here).
- **Test hooks** (test copies only, behind the `SwitchboardTestHooks.active` guard): `stocks.testRobot`, `stocks.testTab`,
  `stocks.testRange`, `hub.testWindowSize`.
- **Shots:** Helm-Private real-app/stockbot-revamp/shots/v2-*.jpg (background test copy, own app ID).
- **v3 (NB2 + Roxy feedback, Nov 10 ~10 AM):**
  - The fleet column says "vs holding".
  - Research reads no longer turn a SwiftUI task cancellation into "no connection". A cancelled load is thrown away, and both panels
    read one model (tests added).
  - Copy: the bot runs hourly (:25) and pulls master each run.
  - Reasons: LC-Research's `plain_reason` first. Older lines get our reading, labelled "our plain reading of its rule". The raw text
    sits under "Technical details · technical reason only".
  - Rules show the exact value + unit with a meaning checked against the robot's code. Anything else says "Meaning not verified".
  - Dips: a lighter tint, with each dip's depth printed on it.
  - A sources line under the overview.
  - Pause wording: "PAUSE REQUESTED (not confirmed)".
- **Not shot:** the offline price state. It's code-path only, because the test copy can't be taken offline without touching the Mac's
  network.
- **Rollback:** `git revert` the merge. The old single-page dashboard comes back, and nothing saved changes (the price cache is
  disposable).

# Research bot tab
Branch `pixels/research-tab`. PRACTICE MONEY ONLY. Spec of the bot itself: `meeting-room/notes/research-bot.md` (phase 2 "Helm screen").
Nothing under `stock_bot/` was changed.

## What it is
On the Stock bot page, below the 7 robot buttons, there's a big **Research bot** button (flask icon, "practice money only"). It opens the
bot's own tab:
- **A PRACTICE MONEY ONLY label** at the top, plus one plain line on what the bot is ("No edge found" is a normal answer).
- **Status:** NOT PAUSED / PAUSED / AUTO-PAUSED / CAN'T TELL, always with the reason:
  - PAUSED means `stock_bot/research_bot/PAUSE` or the all-robots `stock_bot/PAUSE` is there, and it quotes the file's own words.
  - AUTO-PAUSED quotes `AUTO_PAUSE` (the bot's own reason).
  - NOT PAUSED says honestly that "it works only when someone runs it on this Mac. Nothing runs on a schedule yet."
  - If a pause file can't be read, it says CAN'T TELL. It never says "not paused" by mistake.
- **Scorecard, stocks and crypto as separate cards** (any new market LC-Research adds shows up after them). Each card has:
  - The counts: guesses written, graded and open; ideas tried; no-trade days; LATE guesses.
  - **"Are its guesses better than simple ones?"** The Brier score of the bot vs a coin flip / no change, the base rate, and
    tomorrow = today, with one plain sentence. Under 30 graded, it says out loud that this is too few to tell skill from luck.
  - **Practice money, after fees:** the bot's P&L vs doing nothing (cash) and vs just holding SPY / BTC-USD, plus the typical and
    worst trade and the P&L without the best trade.
  - **The evidence bar:** "NOT MET (n of 12)". Even when it's MET, it says "a reason to talk, never an automatic go".
- **Latest guesses:** the asset, up/down, how sure, the window, waiting / open now / window closed, **the reason**, whether it asks
  for a practice trade, and the author. It also shows the latest no-trade day with its reason.
- **Practice orders:** one row per order with its final word (filled / failed). An order with only its "intent" logged shows
  **HALF-DONE: that market is stopped until a person checks the account** (same rule as the executor).
- **Empty state (today's real state):** "No guesses yet: no trade is a normal day".
- **The caps in one line**, read from `rules.json`. If `practice_only` is ever not true, a red line says the bot's checker refuses
  every order.

## Where the data comes from
The tab reads the bot's own files from GitHub master (`raw.githubusercontent.com`, public repo, cache-busted): `scorecard.json`,
`forecasts.jsonl`, `orders.jsonl`, `rules.json`, `PAUSE`, `AUTO_PAUSE` and `stock_bot/PAUSE`. That's the same idea as the other robots'
snapshots.

It reads defensively, because phase 1b is still adding fields:
- Missing, null or wrong-typed fields show "-".
- A field that's a number in a string still reads as a number.
- Unknown new fields are ignored.
- New evidence-bar items are kept, with the human checks listed last.
- A new market gets its own card.
- Broken lines in a .jsonl file are skipped.

## Pause: READ-ONLY now (NB2's call, Nov 10)
The write path described below was **removed**. The tab shows a disabled Pause spot ("coming when the bot runs on a schedule") and a
How to pause box. Status says "PAUSE FILE ON GITHUB" (not "paused") until the runner can report that it saw it (Roxy's point).
The text below is kept as history of the first design.

## (Superseded) The one control: Pause
The Stock bot page had **no** PAUSE control to reuse. It only shows "robot marked paused" from each snapshot. So the tab has one
Pause button:
1. It asks first: "Pause the research bot?"
2. It adds ONLY `stock_bot/research_bot/PAUSE` to GitHub master, as one commit. The file holds a note saying how to undo it.
3. The commit is built with git's plumbing (fetch to a private ref, temporary index, commit-tree, a normal push). So the shared
   `~/Claude/hotstuff` folder's files, branch and index are **never touched**, and no PAUSE file is written there, because an
   untracked one would block that folder's next pull.
4. It never force-pushes. If master moved meanwhile, it rebuilds once on the new master. If GitHub can't be reached, it says
   plainly that nothing was paused.
5. If it's already paused on GitHub, it does nothing.

**There is no resume button.** A person deletes the file. The all-robots `stock_bot/PAUSE` is shown but never written, because it
would also stop the 7 other robots.

**Honest limit:** the bot's checker looks for PAUSE in the folder it runs from, without fetching first. So a run on this Mac sees the
pause once that folder pulls (every chat pulls when it starts). Suggestion for LC-Research's phase 1b, not done here: have the
executor `git fetch` and check `FETCH_HEAD:stock_bot/research_bot/PAUSE` before running, the way `stock_bot.py` already does for
`stock_bot/PAUSE`.

What the tab does NOT have: no order button, no keys, no real-money switch, no Moomoo, no resume. A check scans the tab's source
for these.

## Files
- `ResearchBotData.swift` (new): parsing, plain words, the Pause push.
- `HubResearchBot.swift` (new): the tab.
- `HubStocks.swift`: the big button and the switch to the tab.
- `rebuild.sh`: the 2 new files.
- `checks/research_check.swift` and `checks/run.sh`.

Test-copy-only hooks, dead in the real Helm (same `SwitchboardTestHooks.active` guard as the Switchboard's):
- `research.testDir`: read fixtures instead of GitHub.
- `research.repoPath`: Pause pushes from a throwaway clone.
- `stocks.testResearch`: open on the tab.

## Tested
- Full-app typecheck: 0 errors.
- `zsh checks/run.sh`: 177 PASS. 1 FAIL is the old "Roxy herself is away until Nov 9" date check, which also fails on master.
- `research_check.swift`, 30 offline checks:
  - Today's real files show the honest empty state, with stocks and crypto separate.
  - Future fields, nulls and a new market don't break it.
  - The ledger and orders parse, including half-done orders.
  - A pause file that can't be read gives CAN'T TELL.
  - AUTO_PAUSE quotes its reason, and stock_bot/PAUSE counts as paused.
  - The Pause push, against a throwaway git repo:
    - Only PAUSE is added to the remote.
    - The local folder's HEAD, files and index are untouched (it had an uncommitted edit).
    - No second commit when already paused.
    - The temporary ref is removed.
    - No connection means "nothing was paused".
  - The source scan finds no buy/sell button, toggle, key field, Moomoo, resume or force.
- Shots on a background test copy (its own app ID): see the section below.

## Rollback
`git revert` the merge commit. The change only adds 2 files, the button in `HubStocks.swift`, 2 lines in `rebuild.sh`, the check and
this note. No saved settings change: the tab index lives only in memory. If someone pressed Pause, the PAUSE file stays on master
until a person deletes it, which is the point.
