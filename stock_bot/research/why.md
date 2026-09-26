# Why the rules trail holding — 2026-09-26

Past year, daily closes, $100 per buy, $1 fee per trade and 0.1% slippage (the practice account's costs).

### Default rules — dip 8.0% / take-profit 20.0% / stop 10.0%

Rules **$-1,481** vs just holding **$+596** across 58 stocks ($100 each, costs included).

Where the rules' money came from:
- **Take-profit sells:** 211 trades, $+5,075
- **Stop-loss sells:** 476 trades, $-6,657
- **Still holding at the end:** 43 trades, $+100

Why it trails holding:
- **Sitting in cash:** on average the money was in a stock only 80% of the days. Holding is in 100% of them. 0 stocks never dipped enough to buy at all.
- **Costs:** fees and slippage took $1,558.
- **Selling winners early:** after a take-profit sale, the typical stock rose another 9.1% at some point in the next 20 days.
- **Stop-losses:** 52% of stopped-out stocks were higher 20 days later (typical move +1.9%). The rest kept falling, which is what the stop is for.

Every trade is in `why-trades.json`.
