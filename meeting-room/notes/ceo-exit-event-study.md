# Event study: what a stock does after its CEO leaves suddenly (PRACTICE / HISTORY ONLY)

_LC-Stocks, Thu Nov 12 2026. Matthew: "Yes, test it" (~5:30 PM, via Friday). Research only: no robot, no rule or setting change, no
orders, no forward.json entry. Not a buy or sell call on any stock, NVDA included._

## Part 1: the plan, written and committed BEFORE any prices were looked at

**Question.** After a large, well-known US company's CEO leaves suddenly (resigns or is fired, effective immediately, not a planned
retirement), does the stock keep falling or bounce back over the next 5, 20 and 60 trading days, compared with SPY over the same days?

**Which events count (fixed now):**
1. US-listed company that was large and widely known at the time (S&P 500 member or similar size), with daily prices still on Yahoo.
2. The sitting CEO resigned or was removed with effect immediately or within a few days, and it was NOT announced in advance as a
   planned retirement or succession. Death and illness are excluded.
3. A public source for the date: a news report or the company's 8-K / press release. Each event lists its link.
4. Event dates from 2010 up to 60 trading days before today, so every window can be measured.
5. NVDA (Nov 11 2026, the live case that prompted this) is NOT in the results. It is the case being watched, not data.
6. Every case found that meets 1-4 is kept, whatever its result. Cases are picked from memory and news searches before any returns
   are pulled. Honest limit: the picker has general memory of how some of these stocks did, which this rule can't fully remove.
7. A sub-group is marked in advance: **misconduct/scandal** exits (personal conduct, fraud, a scandal the CEO is blamed for), versus
   other sudden exits (board ousters over results, abrupt "personal reasons" resignations). The main result uses all events.

**Entry day.** The first close after the news was public: if the news came before 4 PM New York on a trading day, that day's close;
if it came after 4 PM or on a non-trading day, the next trading day's close. The first-day reaction (prior close to entry close) is
shown for context but is NOT part of any test, because you couldn't trade at the price before the news.

**Windows.** Close on the entry day to the close 5, 20 and 60 trading days later. **20 days is the main test**; 5 and 60 are
secondary (three windows means three looks, so a lone pass on one of them is weak).

**Comparison.** Excess return = the stock's return minus SPY's return over the exact same days. Two versions:
- *Before costs* (does the pattern exist at all?).
- *After costs, long ("bounce" trade):* a $100 practice position, as rules.json sizes it (10% of $1,000), paying $1.99 per order
  (buy and sell) plus 0.1% slippage each way = about 4.18% round trip, against holding SPY with no extra cost.
- A "keep falling" trade would be a short. The practice desk can't short, so the "keep falling" side is reported before costs only.

**What counts (fixed now):**
- *Bounce edge* (after costs): at least 20 events, AND average and median after-cost excess return both above 0, AND more than half
  beat SPY after costs, AND the average is at least 2 standard errors above 0. All four, on the 20-day window.
- *Keep-falling pattern* (before costs): at least 20 events, AND average and median excess both below 0, AND the average is at least
  2 standard errors below 0, on the 20-day window.
- Anything else is **no edge**. With fewer than 20 events the answer is **inconclusive: anecdotes, not evidence**, whatever the numbers.
- Even a pass would be one look at one stretch of history with overlapping market moods; it would earn a forward watch, not money.

**Scorecard.** This counts as **ONE idea tried** (the research bot's running count, 32 before this, so 33). The ledger line is added
with the tool (`forecasts.py idea`), never by hand, once this branch is merged.

**Reported for every window:** number of events, average, median, spread (lowest, highest, standard deviation), how many beat SPY,
plus the misconduct sub-group on its own.
