# Research bot scorecard (PRACTICE MONEY ONLY)

_Made by plain code (scorer.py), not the AI. 2026-11-15T03:26:16Z._

Lower Brier is better: 0 is perfect, 0.25 is a coin flip.

## Stock

Ideas tried 16 · forecasts 36 · graded 24 · still open 12 · LATE (not counted) 0 · no-trade days 1 · span 4 days

| Who | Brier |
|---|---|
| Forecaster | 0.259 |
| Coin flip / no change | 0.250 |
| Base rate | 0.237 |
| Tomorrow = today | 0.243 |

Hit rate 0.29 (7 of 24); chance a coin does at least this well: 0.99.

**Note: 36 of these forecasts (and any paper trades from them) come from ideas that FAILED the replay. They are data only, not a signal.**

Paper trades 6 at $100 each, after fees + slippage: **$-23.04** · cash $+0.00 · SPY with the whole $1000: $+8.76 · median trade -3.49 · worst -7.19 · without the best -23.04

**Fast-track bar for the ~Dec 1 council re-vote: NOT MET** (judged per idea; a line says yes if any idea meets it)

- NO  - (a) walk-forward on past prices passes the six-condition gate
- NO  - (b) 100+ graded FORWARD forecasts
- NO  - (b) Brier beats all three baselines
- NO  - (b) paper P&L after costs beats cash
- NO  - (b) paper P&L after costs beats buy-and-hold
- NO  - one idea meets ALL of the above

Info, not gates: span 4 days, a down market during it: not yet, chance a coin does this well: 0.99.

| Idea | Graded | Brier | Coin | Base rate | Tomorrow=today | Paper P&L | Replay |
|---|---|---|---|---|---|---|---|
| momentum h=1 {"lookback": 20, "prob": 0.52} | 24 | 0.259 | 0.250 | 0.237 | 0.243 | $-23.04 | **FAILED** (data only, not a signal) |

## Crypto

Ideas tried 19 · forecasts 11 · graded 5 · still open 6 · LATE (not counted) 0 · no-trade days 90 · span 4 days

| Who | Brier |
|---|---|
| Forecaster | 0.290 |
| Coin flip / no change | 0.250 |
| Base rate | 0.237 |
| Tomorrow = today | 0.200 |

Hit rate 0.20 (1 of 5); chance a coin does at least this well: 0.97.

**Note: 11 of these forecasts (and any paper trades from them) come from ideas that FAILED the replay. They are data only, not a signal.**

Paper trades 5 at $100 each, after fees + slippage: **$-18.87** · cash $+0.00 · BTC-USD with the whole $1000: $-58.41 · median trade -1.93 · worst -7.39 · without the best -17.84

**Fast-track bar for the ~Dec 1 council re-vote: NOT MET** (judged per idea; a line says yes if any idea meets it)

- NO  - (a) walk-forward on past prices passes the six-condition gate
- NO  - (b) 100+ graded FORWARD forecasts
- NO  - (b) Brier beats all three baselines
- NO  - (b) paper P&L after costs beats cash
- yes - (b) paper P&L after costs beats buy-and-hold
- NO  - one idea meets ALL of the above

Info, not gates: span 4 days, a down market during it: not yet, chance a coin does this well: 0.97.

| Idea | Graded | Brier | Coin | Base rate | Tomorrow=today | Paper P&L | Replay |
|---|---|---|---|---|---|---|---|
| reversal h=24 {"drop_pct": 8, "lookback": 5, "pr | 0 | - | - | - | - | $+0.00 | **FAILED** (data only, not a signal) |
| reversal h=4 {"drop_pct": 8, "lookback": 5, "pro | 5 | 0.290 | 0.250 | 0.237 | 0.200 | $-18.87 | **FAILED** (data only, not a signal) |

Later, before any real money (not part of the re-vote; real money is not in phase 1): six-condition #6: the practice desk is not behind SPY (forward); client #1 has paid; Service Canada / EI answer on trading; a Canadian tax check; Matthew picks a tiny cap and flips any switch himself.

Stocks and crypto are judged separately: if only one passes, only that one goes on.
"No trade" and "no edge found" are normal, honest results.
