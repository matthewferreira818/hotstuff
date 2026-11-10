# Research bot: phase 1 spec (PRACTICE MONEY ONLY)

_Written 2026-11-10 by Local Claude (LC-Research). Owner from Nov 11: Grok (on grok/* branches; Claude/NB2 review and merge)._
_Public-safe: no account names, no balances, nothing private. Private notes: Helm-Private `research-bot/`._

## What it is, in one breath

A diary of predictions written down **before** the fact, graded afterwards by plain code against dumb baselines, with an
optional practice trade per prediction that can only go through the existing practice broker and a hard-capped rule checker.
It exists to answer one question honestly: **does anything we try have an edge after costs?** "No edge found" and "no trade
today" are normal, good answers. No deadline, no profit target.

Money council 2026-11-10 (12 seats): GO on this $0 research + paper version, real money NO-GO. Matthew: "Yes, start it."

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
| `scorer.py` | Plain-code grading; writes `scorecard.md` + `scorecard.json`. |
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

## The caps (rules.json v1)

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
| Manual stop | `stock_bot/PAUSE` (all robots) or `stock_bot/research_bot/PAUSE` (this one): nothing at all happens |
| Auto-pause | `AUTO_PAUSE` file: no new buys; closing due positions still allowed. **A human deletes it** after reading why |

**Changing a cap:** the AI files `forecasts.py propose-rule`. A change needs the NB2 gate + Matthew's GO; then a human edits
`rules.json` and runs `python3 -m stock_bot.research_bot.checker --lock`. Honest limit: the lock catches an unreviewed edit, but
anyone who can push could also re-lock, so the real lock is review (NB2 gate before merge). The phase 1 build created the
first `rules.lock` (v1 above) as part of the branch NB2 is gating.

## The evidence bar (before anyone may even PROPOSE a tiny live pilot)

The scorecard shows each line per market and says NOT MET until all are true:

1. 100+ graded forecasts, over 60+ days of forward forecasting, including a down market (benchmark fell 5%+ for stocks /
   10%+ for crypto from a high during the period).
2. Brier beats **all three** baselines, and the hit rate is unlikely to be luck (p < 0.05).
3. Paper P&L after costs beats cash **and** buying the benchmark; the median trade wins; still ahead without the best trade.
4. The six-condition gate in `.claude/skills/stock-council/SKILL.md` (human check).
5. Client #1 has paid (human check).
6. The Service Canada / EI answer about trading is in (human check). A tax check (Bear) before any real money too.

Then, and only then, Matthew picks a tiny cap and flips any switch himself. Meeting the bar is a reason to discuss, never an
automatic go. Practice results that look great after a lucky week are not proof: say so out loud when it happens.

## How to run it (from the repo root)

```
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

- Phase 1 is plumbing: the ledger is empty on purpose. The first job is a written list of ideas to test (log each with
  `idea`), then a small, regular rhythm of forecasts (say a few a day across both markets), each committed before its window.
- Don't recycle the old dip rules as "new ideas": they won 1 of 9 unseen walk-forward windows (`stock_bot/research/walk-forward.md`),
  and hot hands lost ~$757 of $1,000 in 60 days after fees (EXP-0004).
- Next pieces worth building (each needs NB2's OK): a once-a-day run (not all day; it must not eat Matthew's plan), the Helm
  screen (phase 2, Friday: PAUSE/STOP only), a permutation test in the scorer, and a correlated-group cap (one position per
  group, Goalie's ask).
- Not tested in phase 1: a real multi-day forward run, the scorer on real resolved forecasts, Yahoo outages mid-run (the code
  fails closed, but it has only been tested offline), and two executors running at once (don't: no lock file yet).
