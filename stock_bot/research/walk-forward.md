# Walk-forward test — 2026-09-26

Each row: find the best rules on 6 months of history, then test them on the next 3 months, which they never saw. Then slide forward 3 months and repeat. Only the test columns count. Same rules for every stock, costs included, daily closes.

| Tuned on | Tested on (unseen) | Stocks | Best rules on training (dip/TP/SL) | Training P/L | Test: tuned | Test: default 8/20/10 | Test: hold stocks | Test: hold SPY |
|---|---|---|---|---|---|---|---|---|
| 2023-10-24 → 2024-04-24 | 2024-04-25 → 2024-07-25 | 57 | 4/30/none | $+1,833 | $+823 | $+726 | $+1,278 | $+395 |
| 2024-01-25 → 2024-07-25 | 2024-07-26 → 2024-10-23 | 57 | 4/30/none | $+1,240 | $+414 | $+205 | $+680 | $+351 |
| 2024-04-25 → 2024-10-23 | 2024-10-24 → 2025-01-27 | 57 | 4/30/15% | $+1,493 | $+1,611 | $+1,052 | $+2,981 | $+198 |
| 2024-07-26 → 2025-01-27 | 2025-01-28 → 2025-04-28 | 58 | 6/30/none | $+2,477 | $-697 | $-1,293 | $-665 | $-515 |
| 2024-10-24 → 2025-04-28 | 2025-04-29 → 2025-07-29 | 58 | 6/30/none | $+1,370 | $+1,559 | $+1,026 | $+2,706 | $+847 |
| 2025-01-28 → 2025-07-29 | 2025-07-30 → 2025-10-27 | 58 | 15/30/none | $+1,260 | $+757 | $+604 | $+1,246 | $+464 |
| 2025-04-29 → 2025-10-27 | 2025-10-28 → 2026-01-28 | 58 | 4/30/none | $+2,925 | $-647 | $-954 | $-674 | $+71 |
| 2025-07-30 → 2026-01-28 | 2026-01-29 → 2026-04-29 | 58 | 6/30/none | $+290 | $-430 | $-791 | $-373 | $+147 |
| 2025-10-28 → 2026-04-29 | 2026-04-30 → 2026-07-30 | 58 | 15/30/none | $-776 | $-136 | $-619 | $+193 | $+186 |

**Unseen months, all windows added up (up to 58 stocks, $100 each): tuned rules $+3,253 · default rules $-43 · holding the stocks $+7,373 · holding SPY $+2,144.**
Tuned rules beat holding the stocks in 1 of 9 test windows.
On average the tuned rules kept 20% of their training profit once tested on months they hadn't seen. The gap is how much of the tuning was fitting noise.

Caveat: the stock list was hand-picked from names that exist today (survivorship bias), which flatters every column except SPY.
