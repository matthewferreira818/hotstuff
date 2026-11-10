# Keep, fix or retire? Dip and Hot hands (PRACTICE MONEY ONLY)

_Written Tue Nov 10 2026 7:29 PM by LC-Stocks, for the money council's re-vote (~Dec 1). Matthew asked via Friday for plain facts on the two
practice robots furthest behind simply holding on the first Robot Desk run. This is a review, NOT a strategy change: no rules, settings
or orders were touched. Strategy changes stay with Grok and the council; Matthew decides._

**How it was measured:** every order in `stock_bot/paper/account.json` (Dip) and `account-hot.json` (Hot hands) was replayed against
Yahoo's daily closes up to Tue Nov 10. The replay matches the accounts: Dip's cash to the cent ($76.30) and value $684.18 (the Desk shows
$684.09 from a last price instead of the close); Hot hands' cash and value to the cent ($667.71). "Hold the same names" = the robot's own
watchlist (Dip: its 10 stocks; Hot hands: its 10 fixed stocks), equal dollars on day 1, one $1.99 fee + 0.1% slippage each, valued at
Nov 10's close (Dip's $70.30 deposit, made Sep 30, is counted from day 1; that flatters holding by a few dollars). All numbers are practice dollars. Fees are already inside every figure unless it says "before fees".

## Side by side

| | Dip | Hot hands |
|---|---|---|
| Running since | Mon Sep 28 (32 trading days) | Thu Oct 8 (24 trading days) |
| Put in | $1,070.30 (incl. one $70.30 practice deposit) | $1,000.00 |
| Orders / closed trades | 74 orders, 32 closed sells (3 winners) | 130 orders, 65 round trips (24 winners) |
| Value Nov 10 | $684.18, **−$386.12 (−36.1%)** | $667.71, **−$332.29 (−33.2%)** |
| vs holding its own 10 names | **−$152.07** (holding them: $836.25, itself down 22%) | **−$203.01** (holding them: $870.72) |
| vs holding SPY | −$363.14 | −$300.30 |
| Worst drop | −35.1% (high Oct 2 → low Nov 6) | −31.9% (from day 1; the low is today) |
| Fees paid | $147.26 (38% of the loss) | $267.29 (80% of the loss), plus ~$51 slippage |
| Loss before fees | about −$247: it lost even with zero fees | about −$65 before fees, about −$14 before fees and slippage |
| Average closed trade | −$12.31 (median −$12.91) | −$5.11 (median −$3.33) |
| Rules changed Nov 4 | yes: 12% dip to buy, bigger bets | yes: aggressive all-day mode + whole-market scan |
| Before Nov 4 / from Nov 4 | −$300.47 / −$85.65 (5 trading days, 9 sells) | −$253.91 / −$78.38 (5 trading days, 21 round trips) |

## Dip (stock_bot.py)

- **Where the losses came from: bad entries caught by the stop.** 29 of its 32 sells were stop-losses (−$449.34 together); the 3
  take-profits made +$55.34. It buys a stock after a big drop, and in this stretch the drops kept going until the 10% stop sold them.
  Every stock it closed lost money except ABNB (+$21.93); the worst were RIOT −$90.88, ASTS −$86.71, ARM −$73.32. Fees ($147) made it
  worse, but even with zero fees it would be down about $247. The 4 stocks it holds now are about +$8 together.
- **It lost to its own stocks**, not just to the market: its 10 names fell about 22% and holding them would still have lost $152 less.
- **Is the sample big enough?** For "this version lost in this stretch": yes, the losses are steady (32 trades, almost all the same
  kind of loss), not one bad day. For "dip buying never works": no. It's one six-week stretch in which its stocks mostly fell, trades
  overlap in time and the stocks move together, so it is less independent evidence than 32 trades sounds like. The Nov 4 version has only
  5 trading days and 9 sells: **too thin to judge on its own.**
- **It matches the earlier research:** the walk-forward test (stock_bot/research/walk-forward.md, Sep 26) found tuned dip rules beat
  holding the same stocks in only 1 of 9 unseen windows, and the default rules lost $43 while holding made $7,373.

**One honest line:** retire it as a money-maker. The live run and the history test both say it loses to simply holding its own stocks.
A fix would have to show first, on years of past prices in the research bot (settings written down before the run, every try counted),
that a dip rule beats holding the same names after costs; nothing we have tested so far has.

## Hot hands (hot_bot.py)

- **Where the losses came from: costs.** Fees ($267) plus slippage (~$51) are about $319 of the $332 loss. Before costs its trades were
  roughly break-even (about −$14), so there is no edge underneath for cheaper trading to uncover. By exit: 16 stop-outs lost $307.83,
  17 end-of-day sell-outs lost $77.69, and 32 sells at or above the day's average made +$53.23. SMR (−$97.26) and ACHR (−$62.71) were the worst.
- **It lost to its own stocks:** holding its 10 fixed names would be $870.72, $203 better.
- **Is the sample big enough?** 65 round trips with steady small losses after costs: enough to say this version loses after costs in
  this stretch. Not enough to rule out every possible same-day rule. The aggressive Nov 4 version has 5 trading days: **too thin to
  judge on its own**, but it is losing at a similar pace.
- **It matches the earlier research:** EXP-0004 (stock_bot/research/experiments/EXP-0004.md, Oct 7) tested this exact rule (VWAP
  snap-back) on 60 days of 5-minute prices: −$757 on a $1,000 account, and 0 of 9 nearby settings made money after fees. The robot was
  started as a live experiment knowing that, at Matthew's request.
- **Honest warning for any real-money thought:** practice fills assume 0.1% slippage. Cheap stocks have wider bid/ask spreads, so real
  fills would usually be worse, not better.

**One honest line:** retire it as a money-maker; the experiment it was started for has its answer (costs eat it, before and after
Nov 4). Keeping it running as a clearly labelled "known loser" costs only practice money; that's Matthew's call. A fix would have to
show a same-day rule whose average move before costs is bigger than about 1% per round trip on its bet size; EXP-0004 found none.

## What this note does not cover
- No forward guess about next month, and no new rule was tried here (trying one would count as another idea under the council's rule).
- Moonshot, Momentum and the three younger robots aren't reviewed. The three "ahead" of holding are all under 30 days old, so they
  aren't evidence either way yet.
