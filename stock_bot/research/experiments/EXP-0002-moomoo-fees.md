# EXP-0002-moomoo-fees: momentum with idle cash in SPY — 2026-09-27

> **Rerun of the original with Moomoo's real minimum fee (US$1.99 per order instead of $1).** Everything else is identical.

**Question:** if the momentum strategy's idle money sits in SPY instead of cash, does it beat just holding SPY?

**Result: DID NOT PASS** (all four conditions were set before the run).

| Condition | Met? | Numbers |
|---|---|---|
| More profit than holding SPY | no | $+1,525 vs $+2,118 |
| Better risk-adjusted return (Sharpe) | no | 0.61 vs 1.07 |
| Beats SPY in 5+ of 9 windows | no | 4 of 9 |
| Most nearby settings beat SPY | no | 2 of 18 |

Up to 58 stocks, $100 slot each (the same total goes into SPY for the SPY row). US$1.99 per order (Moomoo Canada's minimum), 0.1% slippage on stocks, 0.02% on SPY. Same 9 unseen three-month windows as EXP-0001.

| Strategy | P/L | Return | Worst drop | Sharpe | Stock trades | Orders | Fees | Money in stocks | Windows beating SPY |
|---|---|---|---|---|---|---|---|---|---|
| Just hold SPY | $+2,118 | +37.2% | -17.0% | 1.07 | 0 | 9 | $18 | 0% | — |
| Momentum, idle cash in SPY | $+1,525 | +26.7% | -31.6% | 0.61 | 247 | 1,838 | $3,658 | 28% | 4/9 |
| Momentum, idle cash sits | $+2,413 | +42.3% | -21.0% | 0.93 | 247 | 659 | $1,311 | 28% | 4/9 |
| Just hold all the stocks | $+6,145 | +107.8% | -27.1% | 1.29 | 0 | 520 | $1,035 | 98% | 5/9 |

### Window by window

| Window | Just hold SPY | Momentum, idle cash in SPY | Momentum, idle cash sits | Just hold all the stocks |
|---|---|---|---|---|
| 2024-04-25 → 2024-07-25 | $+392 | $+426 | $+330 | $+1,133 |
| 2024-07-26 → 2024-10-23 | $+348 | $+598 | $+532 | $+547 |
| 2024-10-24 → 2025-01-27 | $+198 | $+1,393 | $+1,653 | $+2,810 |
| 2025-01-28 → 2025-04-28 | $-518 | $-1,086 | $-439 | $-772 |
| 2025-04-29 → 2025-07-29 | $+843 | $+902 | $+644 | $+2,528 |
| 2025-07-30 → 2025-10-27 | $+461 | $+433 | $+476 | $+1,099 |
| 2025-10-28 → 2026-01-28 | $+67 | $-530 | $-352 | $-781 |
| 2026-01-29 → 2026-04-29 | $+143 | $-130 | $-93 | $-486 |
| 2026-04-30 → 2026-07-30 | $+183 | $-483 | $-338 | $+68 |

### Robustness

Momentum + SPY across 18 nearby settings: median $+1,397, worst $-2,754, best $+2,173. Holding SPY: $+2,118.

### Caveats

- The stock list is today's survivors, which flatters the stock strategies (not SPY).
- Daily closes; stops can fill worse after overnight gaps.
- Nine windows is a small sample.
- Taxes aren't modelled. Every switch in and out of SPY is a taxable sale outside a TFSA.
