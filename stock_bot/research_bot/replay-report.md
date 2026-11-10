# History replay (walk-forward) - research only, no orders

_Plain code (replay.py). 2026-11-10T13:40:33Z. Only unseen test windows count._

PASS = all five history checks of the six-condition gate AND a Brier score better than all three baselines. Condition 6 (practice desk ahead of SPY) is forward-only. PASS only earns forward forecasting; it is not a reason for real money.

## Stock

Horizon: h = hours, d = daily bars (trading days for stocks, calendar days for crypto).

| Idea | Horizon | Assets | Data | Calls | Brier (coin 0.25) | Base rate | Tomorrow=today | Trades | P&L after costs | Holding same money | Windows won | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| momentum | 1d | 12 | 2022-05..2026-11 | 10125 | 0.2499 | 0.2503 | 0.2618 | 5757 | $-22,328.49 | $+481.81 | 0/14 | **DEAD** |
| momentum | 5d | 12 | 2022-05..2026-11 | 9465 | 0.2513 | 0.2498 | 0.2562 | 5398 | $-14,321.86 | $+2,211.61 | 0/14 | **DEAD** |
| reversal | 1d | 12 | 2022-05..2026-11 | 4657 | 0.2504 | 0.2507 | 0.2650 | 1994 | $-7,662.27 | $+257.78 | 0/14 | **DEAD** |
| reversal | 5d | 12 | 2022-05..2026-11 | 5589 | 0.2511 | 0.2488 | 0.2559 | 2291 | $-6,676.16 | $+1,040.08 | 1/14 | **DEAD** |
| trend | 1d | 12 | 2022-05..2026-11 | 10125 | 0.2499 | 0.2503 | 0.2618 | 5961 | $-23,285.47 | $+455.14 | 0/14 | **DEAD** |
| trend | 5d | 12 | 2022-05..2026-11 | 9465 | 0.2506 | 0.2498 | 0.2562 | 5562 | $-16,059.97 | $+1,888.22 | 0/14 | **DEAD** |
| drift | 1d | 12 | 2022-05..2026-11 | 10125 | 0.2497 | 0.2503 | 0.2618 | 10125 | $-39,689.97 | $+828.65 | 0/14 | **DEAD** |
| drift | 5d | 12 | 2022-05..2026-11 | 9465 | 0.2491 | 0.2498 | 0.2562 | 9465 | $-27,329.02 | $+3,439.45 | 0/14 | **DEAD** |
| long_trend | 10d | 12 | 2022-05..2026-11 | 5973 | 0.2480 | 0.2496 | 0.2551 | 5973 | $-11,284.02 | $+3,424.78 | 1/14 | **DEAD** |
| long_trend | 20d | 12 | 2022-05..2026-11 | 4832 | 0.2445 | 0.2478 | 0.2475 | 4832 | $+3,328.59 | $+5,166.27 | 5/14 | **DEAD** |
| near_high | 20d | 12 | 2023-03..2026-11 | 1308 | 0.2392 | 0.2705 | 0.2377 | 1308 | $-981.37 | $+1,168.96 | 4/10 | **DEAD** |
| two_clocks | 10d | 12 | 2022-05..2026-11 | 3870 | 0.2463 | 0.2510 | 0.2457 | 3870 | $-4,288.21 | $+2,298.60 | 3/14 | **DEAD** |
| calm_momentum | 10d | 12 | 2022-12..2026-11 | 6259 | 0.2516 | 0.2513 | 0.2592 | 3793 | $-5,566.82 | $+2,965.07 | 1/11 | **DEAD** |
| losing_streak | 5d | 1 | 2022-05..2026-10 | 30 | 0.2502 | 0.2702 | 0.2733 | 30 | $-104.21 | $+21.53 | 0/13 | **DEAD** |
| cross | 20d | 12 | 2022-05..2026-10 | 62 | 0.2503 | 0.2705 | 0.2503 | 62 | $+102.76 | $+58.67 | 6/13 | **DEAD** |

- momentum @ 1: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- momentum @ 5: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- reversal @ 1: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- reversal @ 5: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- trend @ 1: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- trend @ 5: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- drift @ 1: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- drift @ 5: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- long_trend @ 10: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- long_trend @ 20: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- near_high @ 20: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- two_clocks @ 10: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- calm_momentum @ 10: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- losing_streak @ 5: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- cross @ 20: failed 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines

## Crypto

Horizon: h = hours, d = daily bars (trading days for stocks, calendar days for crypto).

| Idea | Horizon | Assets | Data | Calls | Brier (coin 0.25) | Base rate | Tomorrow=today | Trades | P&L after costs | Holding same money | Windows won | Verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| momentum | 4h | 19 | 2024-12..2026-11 | 285325 | 0.2507 | 0.2501 | 0.2618 | 138833 | $-163,467.39 | $+523.26 | 0/21 | **DEAD** |
| momentum | 24h | 19 | 2024-12..2026-11 | 277345 | 0.2509 | 0.2508 | 0.2640 | 133542 | $-167,758.36 | $+1,065.31 | 0/21 | **DEAD** |
| reversal | 4h | 19 | 2024-12..2026-11 | 20321 | 0.2485 | 0.2512 | 0.2660 | 10807 | $-12,040.20 | $-150.01 | 2/21 | **DEAD** |
| reversal | 24h | 19 | 2024-12..2026-11 | 16409 | 0.2494 | 0.2533 | 0.2666 | 7831 | $-3,745.57 | $+561.58 | 6/21 | **DEAD** |
| trend | 4h | 19 | 2024-12..2026-11 | 285325 | 0.2510 | 0.2501 | 0.2618 | 136440 | $-162,070.59 | $+20.53 | 0/21 | **DEAD** |
| trend | 24h | 19 | 2024-12..2026-11 | 277345 | 0.2513 | 0.2508 | 0.2640 | 129706 | $-169,885.63 | $-2,348.45 | 0/21 | **DEAD** |
| drift | 4h | 19 | 2024-12..2026-11 | 285325 | 0.2510 | 0.2501 | 0.2618 | 285325 | $-342,850.41 | $-531.69 | 0/21 | **DEAD** |
| drift | 24h | 19 | 2024-12..2026-11 | 277345 | 0.2515 | 0.2508 | 0.2640 | 277345 | $-346,696.99 | $-2,571.67 | 0/21 | **DEAD** |
| long_trend | 10d | 19 | 2022-03..2026-11 | 8031 | 0.2528 | 0.2520 | 0.2612 | 8031 | $+2,950.37 | $+9,126.20 | 4/14 | **DEAD** |
| long_trend | 20d | 19 | 2022-03..2026-11 | 6931 | 0.2552 | 0.2602 | 0.2602 | 6931 | $+8,939.05 | $+15,012.90 | 4/14 | **DEAD** |
| squeeze | 3d | 19 | 2022-03..2026-10 | 160 | 0.2548 | 0.2628 | 0.2637 | 160 | $+54.08 | $+160.08 | 4/14 | **DEAD** |
| squeeze | 5d | 19 | 2022-03..2026-10 | 151 | 0.2543 | 0.2626 | 0.2593 | 151 | $+249.16 | $+180.42 | 6/14 | **DEAD** |
| big_drop | 3d | 19 | 2022-04..2026-11 | 506 | 0.2524 | 0.2588 | 0.2541 | 506 | $+145.90 | $+223.87 | 5/14 | **DEAD** |
| big_drop | 5d | 19 | 2022-04..2026-11 | 523 | 0.2544 | 0.2523 | 0.2468 | 523 | $-493.05 | $-191.02 | 4/14 | **DEAD** |
| two_clocks | 10d | 19 | 2022-03..2026-11 | 4684 | 0.2563 | 0.2546 | 0.2669 | 4684 | $+5,855.76 | $+7,728.35 | 4/14 | **DEAD** |
| calm_momentum | 10d | 19 | 2022-08..2026-11 | 15791 | 0.2519 | 0.2519 | 0.2607 | 6636 | $-3,073.31 | $+8,559.28 | 3/13 | **DEAD** |
| cross | 20d | 19 | 2022-03..2026-10 | 207 | 0.2586 | 0.2698 | 0.2663 | 207 | $+827.42 | $+527.77 | 4/14 | **DEAD** |

- momentum @ 4: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- momentum @ 24: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- reversal @ 4: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- reversal @ 24: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows
- trend @ 4: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- trend @ 24: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- drift @ 4: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- drift @ 24: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- long_trend @ 10: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- long_trend @ 20: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- squeeze @ 3: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- squeeze @ 5: failed 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- big_drop @ 3: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- big_drop @ 5: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- two_clocks @ 10: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- calm_momentum @ 10: failed 2. beats holding the benchmark after costs; 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines
- cross @ 20: failed 3. typical trade beats holding (median); 4. no loss over 2x its expected move; 5. wins most unseen windows; Brier beats all three baselines

**32 idea/horizon combinations tried, 0 passed.** Each one is counted in replay-log.jsonl. Caveat: the stock list is today's names (survivorship bias flatters every idea), trades are $100 each with no position cap, and Yahoo's free hourly history is ~2 years.
