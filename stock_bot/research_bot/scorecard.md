# Research bot scorecard (PRACTICE MONEY ONLY)

_Made by plain code (scorer.py), not the AI. 2026-11-28T08:25:19Z._

Lower Brier is better: 0 is perfect, 0.25 is a coin flip.

## Stock

Ideas tried 16 · forecasts 60 · graded 48 · still open 12 · LATE (not counted) 0 · no-trade days 1 · span 17 days

| Who | Brier |
|---|---|
| Forecaster | 0.251 |
| Coin flip / no change | 0.250 |
| Base rate | 0.271 |
| Tomorrow = today | 0.248 |

Hit rate 0.48 (23 of 48); chance a coin does at least this well: 0.67.

**Note: 60 of these forecasts (and any paper trades from them) come from ideas that FAILED the replay. They are data only, not a signal.**

Paper trades 10 at $100 each, after fees + slippage: **$-24.15** · cash $+0.00 · SPY with the whole $1000: $-19.88 · median trade -2.49 · worst -7.19 · without the best -31.26

**Fast-track bar for the ~Dec 1 council re-vote: NOT MET** (judged per idea; a line says yes if any idea meets it)

- NO  - (a) walk-forward on past prices passes the six-condition gate
- NO  - (b) 100+ graded FORWARD forecasts
- NO  - (b) Brier beats all three baselines
- NO  - (b) paper P&L after costs beats cash
- NO  - (b) paper P&L after costs beats buy-and-hold
- NO  - one idea meets ALL of the above

Info, not gates: span 17 days, a down market during it: yes, chance a coin does this well: 0.67.

| Idea | Graded | Brier | Coin | Base rate | Tomorrow=today | Paper P&L | Replay |
|---|---|---|---|---|---|---|---|
| momentum h=1 {"lookback": 20, "prob": 0.52} | 48 | 0.251 | 0.250 | 0.271 | 0.248 | $-24.15 | **FAILED** (data only, not a signal) |

## Crypto

Ideas tried 19 · forecasts 13 · graded 11 · still open 2 · LATE (not counted) 0 · no-trade days 146 · span 17 days

| Who | Brier |
|---|---|
| Forecaster | 0.259 |
| Coin flip / no change | 0.250 |
| Base rate | 0.358 |
| Tomorrow = today | 0.251 |

Hit rate 0.45 (5 of 11); chance a coin does at least this well: 0.73.

**Note: 13 of these forecasts (and any paper trades from them) come from ideas that FAILED the replay. They are data only, not a signal.**

Paper trades 11 at $100 each, after fees + slippage: **$-17.33** · cash $+0.00 · BTC-USD with the whole $1000: $-17.69 · median trade -1.86 · worst -9.04 · without the best -23.30

**Fast-track bar for the ~Dec 1 council re-vote: NOT MET** (judged per idea; a line says yes if any idea meets it)

- NO  - (a) walk-forward on past prices passes the six-condition gate
- NO  - (b) 100+ graded FORWARD forecasts
- yes - (b) Brier beats all three baselines
- yes - (b) paper P&L after costs beats cash
- yes - (b) paper P&L after costs beats buy-and-hold
- NO  - one idea meets ALL of the above

Info, not gates: span 17 days, a down market during it: not yet, chance a coin does this well: 0.73.

| Idea | Graded | Brier | Coin | Base rate | Tomorrow=today | Paper P&L | Replay |
|---|---|---|---|---|---|---|---|
| reversal h=24 {"drop_pct": 8, "lookback": 5, "pr | 5 | 0.242 | 0.250 | 0.250 | 0.280 | $+0.56 | **FAILED** (data only, not a signal) |
| reversal h=4 {"drop_pct": 8, "lookback": 5, "pro | 6 | 0.274 | 0.250 | 0.292 | 0.227 | $-17.88 | **FAILED** (data only, not a signal) |

Later, before any real money (not part of the re-vote; real money is not in phase 1): six-condition #6: the practice desk is not behind SPY (forward); client #1 has paid; Service Canada / EI answer on trading; a Canadian tax check; Matthew picks a tiny cap and flips any switch himself.

Stocks and crypto are judged separately: if only one passes, only that one goes on.
"No trade" and "no edge found" are normal, honest results.
