# EXP-0001-moomoo-fees: dip-buying vs trend-following — 2026-09-27

> **Rerun of the original with Moomoo's real minimum fee (US$1.99 per order instead of $1).** Everything else is identical.

**Question:** does buying strength with a trailing exit (C, D) do better than the current dip strategy (A) or plain buy-and-hold (B), on months no one tuned for?

Settings were fixed before the run. Up to 58 stocks, one $100 slot each, US$1.99 fee per order (Moomoo Canada's minimum), fills 0.1% worse. Same 9 three-month test windows as the walk-forward test. Daily closes (data from 2023-09-26).

| Strategy | P/L | Return | Max drawdown | Return ÷ drawdown | Sharpe | Trades | Win rate | Profit factor | Avg trade | Exposure | Fees + slippage | Windows beating SPY |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **A** Current dip (control) | $-3,456 | -60.6% | -69.2% | -0.88 | -0.69 | 1575 | 32% | 0.74 | $-1.75 | 73% | $7,457 | 2/9 |
| **B** Buy and hold | $+6,145 | +107.8% | -27.1% | 3.98 | 1.29 | 0 | — | — | $+11.82 | 98% | $1,139 | 5/9 |
| **C** Trend breakout + 10% trailing stop | $-146 | -2.6% | -15.4% | -0.17 | -0.04 | 414 | 28% | 0.6 | $-0.27 | 23% | $2,000 | 1/9 |
| **D** Momentum + volume + ATR trailing stop | $+2,416 | +42.4% | -20.9% | 2.03 | 0.94 | 247 | 29% | 0.96 | $+5.86 | 28% | $1,394 | 4/9 |

SPY with the same money over the same windows: **$+2,147**.

### Window by window (P/L, unseen months)

| Window | A dip | B hold | C breakout | D momentum |
|---|---|---|---|---|
| 2024-04-25 → 2024-07-25 | $+271 | $+1,133 | $-114 | $+326 |
| 2024-07-26 → 2024-10-23 | $-149 | $+547 | $+158 | $+532 |
| 2024-10-24 → 2025-01-27 | $+683 | $+2,810 | $+139 | $+1,653 |
| 2025-01-28 → 2025-04-28 | $-1,852 | $-772 | $-68 | $-442 |
| 2025-04-29 → 2025-07-29 | $+847 | $+2,528 | $+486 | $+646 |
| 2025-07-30 → 2025-10-27 | $+397 | $+1,099 | $-51 | $+471 |
| 2025-10-28 → 2026-01-28 | $-1,414 | $-781 | $-292 | $-337 |
| 2026-01-29 → 2026-04-29 | $-1,170 | $-486 | $-96 | $-92 |
| 2026-04-30 → 2026-07-30 | $-1,070 | $+68 | $-307 | $-340 |

### Robustness: nearby settings

Same test, rerun across a small grid of settings around each default. If only the exact default works, the result is luck.

| Strategy | Settings tried | Median P/L | Worst | Best | Settings that beat buy-and-hold |
|---|---|---|---|---|---|
| A | 36 | $-2,979 | $-13,503 | $+3,063 | 0/36 |
| C | 8 | $+199 | $-469 | $+1,752 | 0/8 |
| D | 18 | $+2,420 | $+286 | $+3,504 | 0/18 |

### Caveats

- **Survivorship bias.** The stock list is today's survivors. That flatters every stock strategy, and trend-following most of all (survivors are the stocks that trended up). Comparing C/D against B on the same list cancels some of it, not all.
- Daily closes only: a real trailing stop can fill worse after an overnight gap.
- Positions still open at a window's end are valued at the last close, without the selling fee.
- Nine windows is a small sample.
