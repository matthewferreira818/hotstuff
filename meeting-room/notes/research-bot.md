# Research bot: phase 1 spec (PRACTICE MONEY ONLY)

_Written 2026-11-10 by Local Claude (LC-Research). Owner from Nov 11: Grok (on grok/* branches; Claude/NB2 review and merge)._
_Public-safe: no account names, no balances, nothing private. Private notes: Helm-Private `research-bot/`._

## What it is, in one breath

A diary of predictions written down **before** the fact, graded afterwards by plain code against dumb baselines, with an
optional practice trade per prediction that can only go through the existing practice broker and a hard-capped rule checker.
It exists to answer one question honestly: **does anything we try have an edge after costs?** "No edge found" and "no trade
today" are normal, good answers. No deadline, no profit target.

Money council 2026-11-10 (12 seats): GO on this $0 research + paper version, real money NO-GO. Matthew: "Yes, start it."
**Fast track (Matthew's GO via NB2, same day, "streamline this"):** test ideas on years of past prices FIRST so weak ones die in
days; short horizons (hours to a day) on several assets so 100+ forward forecasts can be graded in 1-2 weeks; crypto 7 days a week.
Priority: history replay → forecast logger + scorer → short-horizon paper runs. The council re-votes at about 3 weeks (~Tue Dec 1).

## What phase 1 does NOT have

- **No real-money path at all.** No exchange or broker connection, no keys, no live mode, nothing that can place a real order.
  A test (`NoRealMoneyPath`) fails if research_bot code even names a live broker, an exchange library, or a key.
- **Never on GitHub Actions** (the executor refuses to run there). No scheduled workflow: adding one needs NB2's OK.
- No AI inside the scorer or the checker. The AI (a Claude chat, Grok) may only **propose**: write forecasts, log ideas,
  and file rule-change proposals. It never grades itself and never edits the live rules.
- The Helm screen (Friday shows it, PAUSE/STOP only) is phase 2.

## The files (`stock_bot/research_bot/`)

| File | What it is |
|---|---|
| `forecasts.jsonl` | The ledger. One JSON line per idea, forecast or no-trade day. **Append-only, never edited.** |
| `forecasts.py` | The only writer of the ledger (+ `verify`: the append-only and timing proof from git history). |
| `proposals.jsonl` | Rule-change proposals from the AI. A human reads them; they change nothing by themselves. |
| `rules.json` + `rules.lock` | The live caps, and their fingerprint. If they don't match, every order is refused. |
| `checker.py` | Plain-code yes/no on every paper order. |
| `executor.py` | Turns committed forecasts into practice trades through `paper_broker.py`, only if the checker says yes. |
| `scorer.py` | Plain-code grading; writes `scorecard.md` + `scorecard.json`, per market and per idea. |
| `ideas.py` | The plain-code ideas (momentum, reversal, trend, drift to start). The SAME functions run in the replay and live. |
| `replay.py` | History replay + walk-forward over years of past prices; writes `replay-report.md`, appends `replay-log.jsonl`. |
| `generate.py` | The live forecaster: runs the chosen idea variants (`forward.json`) on the latest finished bars and logs forecasts. |
| `orders.jsonl`, `equity.jsonl`, `AUTO_PAUSE` | Created by the executor: order log (idempotency), account value snapshots, auto-pause flag. |
| Practice accounts | `stock_bot/paper/account-research-stocks.json` and `account-research-crypto.json` ($1,000 practice each). |

## A forecast

`asset` (e.g. SPY, BTC-USD; "-USD" means crypto), `direction` (up/down), `probability` that the direction is right
(above 0.5, at most 0.99), `opens_at` / `resolves_at` (UTC, 1 hour to 30 days apart), `expected_downside_pct` (how far it could
go against us), a short `reason` (280 characters), the `idea` it tests, and `act` (ask for a practice trade; up only, because
phase 1 can't short). The code stamps `created` and an id.

**The proof it came first:** the window must open at least 15 minutes after the forecast is written, and the forecast only
counts if the first git commit containing it is **before** the window opened. A late one is listed as LATE and never counts.
After writing a forecast: commit and push `forecasts.jsonl` right away.
Honest limit: git commit times come from our own machine's clock. GitHub's push record (the branch's activity log) is the
independent witness; if a result ever matters, check the push times there too.

**Every idea is counted.** A forecast must name an idea already in the ledger, so the scorecard shows how many ideas were tried,
not just the ones that worked (the cure for fooling ourselves by trying 50 things and showing the best).

## How it's graded (scorer.py)

For each forecast whose window has closed: the price is the open of the first hourly bar **at or after** each time (a price a
trade could really have got; for stocks outside market hours that's the next open). Up = the closing price is higher.

- **Brier score** (0 perfect, 0.25 coin flip, lower is better) vs three baselines: **coin flip** (50/50; for direction this is
  also what "no change" says), **base rate** (share of earlier graded windows that went up, using only results known before this
  window opened), **tomorrow = today** (the next move repeats the last move of the same length, at 60/40).
- **Hit rate** and the chance a coin would do at least as well (small samples = luck can explain it).
- **Paper P&L** of the forecasts that asked for a trade: $100 each (10% of $1,000), with the practice broker's own fee and
  slippage math (stocks: US$1.99 minimum per order + per-share above that + 0.1% slippage, about $4 per $100 round trip;
  crypto: 0.5% each way + 0.1% slippage). Compared with **cash ($0)** and **buying the benchmark with the whole $1,000**
  (SPY for stocks, Bitcoin for crypto) over the same period. Also: median trade, worst trade, total without the best trade.
- **Stocks and crypto are separate.** If only one passes, only that one goes on.

## The caps (rules.json v2; v1 gated 2026-11-10, v2 adds the stop, at NB2's gate on 1b)

| Cap | Value |
|---|---|
| Practice only | `practice_only: true`, or every order is refused |
| Size | max 10% of the account per position, min $50 (fees eat smaller), never more than the cash |
| Positions | max 3 open, one per stock/coin |
| New orders | max 2 new positions a day across both accounts (closing a due position doesn't count) |
| Daily loss | 3% down since the day started (08:00 UTC) → AUTO-PAUSE |
| Weekly drawdown | 6% below the 7-day high → AUTO-PAUSE |
| Stale data | price older than 5 minutes → halt (stocks are naturally halted outside market hours) |
| Big jump | moved more than 5% (stocks) / 8% (crypto) in 15 minutes → halt |
| Double orders | every order has a fixed id (`<forecast>:buy` / `:sell`) logged BEFORE placing; a repeat is refused; a half-done order stops that market until a human looks |
| Per-bet stop | the stop sits 2× the asset's typical daily high-low range (median of 20 days) below the entry; if that's more than $15 per $100 (15%), the bet is skipped. Checked every executor run (no exchange stop: a gap can blow through it). Order id `<forecast>:stop` |
| One run at a time | `RUN_LOCK` is made atomically; a second run does nothing; a lock older than 30 minutes (crashed run) is taken over and logged |
| Manual stop | `stock_bot/PAUSE` (all robots) or `stock_bot/research_bot/PAUSE` (this one): nothing at all happens |
| Auto-pause | `AUTO_PAUSE` file: no new buys; closing due positions still allowed. **A human deletes it** after reading why |

**Changing a cap:** the AI files `forecasts.py propose-rule`. A change needs the NB2 gate + Matthew's GO; then a human edits
`rules.json` and runs `python3 -m stock_bot.research_bot.checker --lock`. Honest limit: the lock catches an unreviewed edit, but
anyone who can push could also re-lock, so the real lock is review (NB2 gate before merge). The phase 1 build created the
first `rules.lock` (v1 above) as part of the branch NB2 is gating.

## First replay result, in plain words (2026-11-10)

**No idea beat just holding after costs, in stocks or in crypto.** 16 idea/horizon combinations tried (momentum, reversal,
trend, always-up; 1 and 5 trading days for 12 stocks over ~4.5 years; 4 and 24 hours for 19 coins over ~2 years, every day of
the week): **0 passed.** Every one lost money after fees on the unseen windows, and none won most of its unseen windows.
- **Crypto:** one real-looking but small signal. "Reversal" (after an 8%+ move in 5 hours, call the opposite) was right 55% of
  the time at 4 hours and 53% at 24 hours, a Brier a little better than a coin flip. But after the 0.5%-a-side fee and slippage it
  still lost about $1.11 (4 h) and $0.48 (24 h) per $100 trade, and won 2 and 6 of 21 unseen months. The hit rates look
  "unlikely to be luck" on paper, but calls overlap in time and the coins move together, so that is overstated.
- **Stocks:** nothing better than a coin. The best (20-day momentum, 1 day ahead) tied a coin flip (0.2499 vs 0.25) and lost
  about $3.88 per $100 trade: the ~$4 round-trip fee on a $100 order eats everything.
- What that means: with today's fees, small bets on these simple patterns lose. "No edge found" is the honest answer so far.
- Next: Friday's 10-idea list (Helm-Private research-bot/ideas-list.md) goes through the replay next. Forward forecasting runs anyway on the
  three closest variants (`forward.json`, all labelled DEAD) to test whether the crypto direction signal is real.
- The first 12 forward forecasts (stocks, 1 day) were logged and pushed 2026-11-10 at 13:35 UTC, before their 14:30 UTC windows
  opened. Until a schedule is approved, forecasts only come in when someone runs `generate --commit` by hand.

## History replay first (replay.py)

Each idea × setting × horizon walks through past prices bar by bar. At each bar the idea sees ONLY prices up to that bar
(`ideas.History` raises an error if code asks for a later one); a call enters at the NEXT bar's open and exits at the open
`horizon` bars later. Walk-forward: pick the setting with the best Brier on a training window, score it on the next window it never
saw, slide, repeat; a training window never uses an outcome that lands in its test window. Only unseen windows count.
- **Crypto:** hourly bars, every day of the week, ~2 years (Yahoo's free hourly limit), horizons 4 and 24 hours, train 60 days /
  test 30. Assets: the Moonshot crypto list (19 coins).
- **Stocks:** daily bars, ~5 years, horizons 1 and 5 trading days, train 365 days / test 91. Assets: SPY, QQQ and the dip robot's list.
- **Verdict PASS** = Brier beats all three baselines on the unseen windows AND the history part of the six-condition gate:
  (1) 20+ trades, (2) beats holding the benchmark with the same money after costs, (3) the median trade beats holding,
  (4) no trade lost more than 2× its expected move (the idea's typical move over that horizon, measured from past bars only),
  (5) wins most unseen windows. Condition 6 (practice desk ahead of SPY) can only be checked forward. Everything else is DEAD.
- Every idea/horizon tried is appended to `replay-log.jsonl` and counted in the scorecard's "ideas tried".
- Honest limits: today's stock list (survivorship bias flatters every idea), $100 per trade with no position cap in the replay,
  hourly history only ~2 years, Yahoo's free data.

## Forward forecasts (generate.py)

`forward.json` lists which idea variants forecast live, on which assets. Each run: finished bars only; one forecast per variant per
asset unless that variant already has an open forecast on it; crypto windows open at the next whole hour (≥20 minutes away),
stocks at the next New York 9:30 open and close at the open N trading days later. `--commit` commits and pushes straight away.
A variant that is DEAD in the replay may still forecast forward while the data comes in, but it can't pass the bar (line (a)).
**Merging:** merge the branch with a MERGE COMMIT, never squash: a squash erases the git history that proves each forecast came
first. The proof uses git's author time (it survives a rebase). One writer at a time: forecasts are only added on one branch.

## The evidence bar (fast track, set 2026-11-10; the council re-votes ~Dec 1)

Judged **per idea variant**, stocks and crypto **separately**. To pass, one idea must meet ALL of:

- **(a)** its walk-forward on past prices passes the six-condition gate (replay verdict PASS above), and
- **(b)** 100+ graded FORWARD forecasts that beat all three baselines (Brier), with paper P&L after costs beating cash AND buying
  the benchmark.

Shown for information, not gates: days covered, whether a down market happened, the chance a coin does as well.
Real money is not part of phase 1 or of this bar. Before any real money, later and separately: six-condition #6 (the practice desk
not behind SPY), client #1 paid, the Service Canada / EI answer, a Canadian tax check, and Matthew picking a tiny cap and flipping
any switch himself. Practice results that look great after a lucky week are not proof: say so out loud when it happens.

## Schedule (PROPOSAL, waiting for NB2's OK; nothing is installed)

`stock_bot/research_bot/mac/install.sh` would run `mac/cycle.sh` on Matthew's Mac **every hour at :25** via launchd (the same way
the Moomoo robot starts). Each cycle: pull master → `generate --commit` (forward forecasts, pushed before any window opens) →
`executor` (stops, due closes, new buys under the caps) → `scorer` → commit + push the order log, equity, practice accounts and
scorecard. Why :25: the next whole hour, when crypto windows open, is 35 minutes away. Plain Python: **no Claude usage**.
- Runs in its own folder (`~/Claude/research-bot-runner`, a detached worktree of master), never in `~/Claude/hotstuff`.
- Never on GitHub Actions (the code refuses). A Mac asleep at :25 runs it once on waking; a Mac that is off misses cycles (the
  forecasts that do get made are still valid; the gap shows in the scorecard as fewer forecasts).
- Off: `mac/uninstall.sh`. Pause trading only: add `stock_bot/research_bot/PAUSE` and push.
- The replay is NOT scheduled: run it by hand when an idea is added (it takes several minutes of CPU).

## Files other tools read (keep stable: add fields, never rename)

LC-Pixels' "Research bot" tab in The Helm reads these. Any change gets a line here.

| File | Shape |
|---|---|
| `scorecard.json` | `generated`, `append_only_ok`, `append_only_problems`, `markets.{stock,crypto}` with `ideas_tried`, `forecasts`, `graded`, `open`, `late_not_counted`, `no_trade_days`, `hits`, `hit_rate`, `luck_p_value`, `brier.{forecaster,coin_flip,base_rate,tomorrow_equals_today}`, `paper_trades`, `trade_size`, `paper_pnl`, `median_trade`, `worst_trade`, `pnl_without_best`, `cash_pnl`, `hold_pnl`, `hold_window`, `benchmark`, `span_days`, `down_market_seen`, `max_drawdown_pct`, `evidence_bar` ({line: true/false}), and `rows` (one per forecast: `id`, `idea`, `market`, `asset`, `status`, ...) |
| `forecasts.jsonl` | lines with `kind` = `idea` / `forecast` / `no_trade` (fields in "A forecast" above) |
| `orders.jsonl` | `id` (`<forecast>:buy` / `:sell` / `:stop`), `side`, `asset`, `market`, `forecast_id`, `dollars` (buys), `stop_pct` (buys), `status` (`intent` / `filled` / `failed`), `time`, `practice: true`, `profit` (sells) |
| `equity.jsonl` | `time`, `market`, `value` |
| `PAUSE`, `AUTO_PAUSE`, `RUN_LOCK` | present = paused / auto-paused (text says why) / a run is going |
| `replay-log.jsonl`, `replay-report.md` | one line per idea/horizon replayed: `market`, `idea`, `horizon`, `verdict` (PASS/DEAD), `why`, `brier`, `pnl`, `windows`, `windows_won`, `run` |

Changes since phase 1 merged (6fb2f0b), all in 1b: `evidence_bar` keys are now the fast-track lines plus
`"one idea meets ALL of the above"` (the old keys are gone, because the bar changed); added `by_idea` (same fields per idea, plus
`text` and `replay_pass`), `ideas_in_ledger`, `ideas_in_replay`; `rows[].idea`; orders gain `stop_pct` and `:stop` ids.

## How to run it (from the repo root)

```
python3 -m stock_bot.research_bot.replay                 # history first: which ideas die?
python3 -m stock_bot.research_bot.generate --dry-run     # what the live forecaster would log now
python3 -m stock_bot.research_bot.generate --commit      # log + commit + push forward forecasts
python3 -m stock_bot.research_bot.forecasts idea --market crypto --text "..." --author Grok
python3 -m stock_bot.research_bot.forecasts add --idea I-... --asset BTC-USD --direction up \
    --probability 0.55 --opens 2026-11-12T14:00:00Z --resolves 2026-11-13T14:00:00Z \
    --downside 6 --reason "..." --author Grok [--act]
python3 -m stock_bot.research_bot.forecasts no-trade --market stock --reason "..." --author Grok
git add stock_bot/research_bot/forecasts.jsonl && git commit -m "Forecast(s)" && git push   # BEFORE the window opens
python3 -m stock_bot.research_bot.executor --dry-run    # what it would do
python3 -m stock_bot.research_bot.executor              # practice orders (commit the files it changes)
python3 -m stock_bot.research_bot.scorer --print        # the scorecard
python3 -m unittest stock_bot/research_bot/test_research_bot.py -v
```

## Rollback

- **Stop now:** add `stock_bot/research_bot/PAUSE` (or `stock_bot/PAUSE`) and push. Nothing runs on a schedule anyway.
- **Undo the code:** `git revert` the merge commit of `claude/research-bot-*`. It only adds files under
  `stock_bot/research_bot/`, this note and the board line; it changes no existing robot, workflow or the app.
- **Practice accounts:** fake money; delete the two `account-research-*.json` files to reset. The forecast ledger is never
  deleted or edited (that's the point); if the project ends, it stays as the record.

## For Grok (taking over Nov 11)

- New ideas go in `ideas.py` (function + plain description + small grid), then `replay.py`. Only replay PASSes can meet the bar.
  Keep grids small: every setting tried is another chance to fool ourselves.
- `generate.py --commit` needs a regular rhythm (crypto several times a day) to reach 100 forward forecasts in 1-2 weeks. A
  schedule needs NB2's OK; it must run on the Mac (never GitHub Actions) and use no Claude usage (it's plain Python).
- Don't recycle the old dip rules as "new ideas": they won 1 of 9 unseen walk-forward windows (`stock_bot/research/walk-forward.md`),
  and hot hands lost ~$757 of $1,000 in 60 days after fees (EXP-0004).
- Next pieces worth building (each needs NB2's OK): the generate/executor/scorer schedule on the Mac, the Helm
  screen (phase 2, Friday: PAUSE/STOP only), a permutation test in the scorer, and a correlated-group cap (one position per
  group, Goalie's ask).
- Not tested in phase 1: a real multi-day forward run, the scorer on real resolved forecasts, Yahoo outages mid-run (the code
  fails closed, but it has only been tested offline).
