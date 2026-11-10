# History replay (walk-forward) - research only, no orders

_Plain code (replay.py). 2026-11-10T13:32:56Z. Only unseen test windows count._

PASS = all five history checks of the six-condition gate AND a Brier score better than all three baselines. Condition 6 (practice desk ahead of SPY) is forward-only. PASS only earns forward forecasting; it is not a reason for real money.

## Stock (12 assets, 2022-05-06 to 2026-11-09)

| Idea | Horizon (trading days) | Calls | Brier (coin 0.25) | Base rate | Tomorrow=today | Trades | P&L after costs | Holding same money | Windows won | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| momentum | 1 | 10125 | 0.2499 | 0.2503 | 0.2618 | 5757 | $-22,328.49 | $+481.81 | 0/14 | **DEAD** |
| momentum | 5 | 9465 | 0.2513 | 0.2498 | 0.2562 | 5398 | $-14,321.86 | $+2,211.61 | 0/14 | **DEAD** |
| reversal | 1 | 4657 | 0.2504 | 0.2507 | 0.2650 | 1994 | $-7,662.27 | $+257.78 | 0/14 | **DEAD** |
| reversal | 5 | 5589 | 0.2511 | 0.2488 | 0.2559 | 2291 | $-6,676.16 | $+1,040.08 | 1/14 | **DEAD** |
| trend | 1 | 10125 | 0.2499 | 0.2503 | 0.2618 | 5961 | $-23,285.47 | $+455.14 | 0/14 | **DEAD** |
| trend | 5 | 9465 | 0.2506 | 0.2498 | 0.2562 | 5562 | $-16,059.97 | $+1,888.22 | 0/14 | **DEAD** |
| drift | 1 | 10125 | 0.2497 | 0.2503 | 0.2618 | 10125 | $-39,689.97 | $+828.65 | 0/14 | **DEAD** |
| drift | 5 | 9465 | 0.2491 | 0.2498 | 0.2562 | 9465 | $-27,329.02 | $+3,439.45 | 0/14 | **DEAD** |

- momentum @ 1: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- momentum @ 5: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- reversal @ 1: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- reversal @ 5: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- trend @ 1: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- trend @ 5: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- drift @ 1: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- drift @ 5: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows

## Crypto (19 assets, 2024-12-11 to 2026-11-10)

| Idea | Horizon (hours) | Calls | Brier (coin 0.25) | Base rate | Tomorrow=today | Trades | P&L after costs | Holding same money | Windows won | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|
| momentum | 4 | 285325 | 0.2507 | 0.2501 | 0.2618 | 138833 | $-163,467.39 | $+523.26 | 0/21 | **DEAD** |
| momentum | 24 | 277345 | 0.2509 | 0.2508 | 0.2640 | 133542 | $-167,758.36 | $+1,065.31 | 0/21 | **DEAD** |
| reversal | 4 | 20321 | 0.2485 | 0.2512 | 0.2660 | 10807 | $-12,040.20 | $-150.01 | 2/21 | **DEAD** |
| reversal | 24 | 16409 | 0.2494 | 0.2533 | 0.2666 | 7831 | $-3,745.57 | $+561.58 | 6/21 | **DEAD** |
| trend | 4 | 285325 | 0.2510 | 0.2501 | 0.2618 | 136440 | $-162,070.59 | $+20.53 | 0/21 | **DEAD** |
| trend | 24 | 277345 | 0.2513 | 0.2508 | 0.2640 | 129706 | $-169,885.63 | $-2,348.45 | 0/21 | **DEAD** |
| drift | 4 | 285325 | 0.2510 | 0.2501 | 0.2618 | 285325 | $-342,850.41 | $-531.69 | 0/21 | **DEAD** |
| drift | 24 | 277345 | 0.2515 | 0.2508 | 0.2640 | 277345 | $-346,696.99 | $-2,571.67 | 0/21 | **DEAD** |

- momentum @ 4: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- momentum @ 24: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- reversal @ 4: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- reversal @ 24: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- trend @ 4: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- trend @ 24: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- drift @ 4: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- drift @ 24: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines

**16 idea/horizon combinations tried, 0 passed.** Each one is counted in replay-log.jsonl. Caveat: the stock list is today's names (survivorship bias flatters every idea), trades are $100 each with no position cap, and Yahoo's free hourly history is ~2 years.
