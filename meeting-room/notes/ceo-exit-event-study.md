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

## Part 2: the events, fixed and committed BEFORE any prices were pulled

28 cases found that meet the rule. "News" = when it became public (ET); "Entry" = first close after that. M = misconduct/scandal sub-group.
Timing comes from the linked reports (pre-market / after the close / weekend); one case (Duke) has uncertain timing, so its entry is the
first close that was certainly after the news.

| # | Company (ticker) | CEO | News | Entry | M | Source |
|---|---|---|---|---|---|---|
| 1 | Hewlett-Packard (HPQ) | Mark Hurd | Fri 2010-08-06, after close | 2010-08-09 | M | [AP via Washington Times](https://m.washingtontimes.com/news/2010/aug/6/hp-ceo-forced-to-resign-amid-harassment-claims/) |
| 2 | Hewlett-Packard (HPQ) | Léo Apotheker | Thu 2011-09-22, after close | 2011-09-23 | | [CBS News](https://www.cbsnews.com/news/apotheker-out-whitman-in-as-new-hp-ceo/) |
| 3 | Best Buy (BBY) | Brian Dunn | Tue 2012-04-10, pre-market | 2012-04-10 | M | [CNN Money](https://money.cnn.com/2012/04/10/markets/best-buy/index.htm) |
| 4 | Duke Energy (DUK) | Bill Johnson | Tue 2012-07-03 (time unclear; half day) | 2012-07-05 | | [Fortune](https://fortune.com/2012/07/11/duke-ceo-on-turnover-turmoil-hey-it-happens/) |
| 5 | Wells Fargo (WFC) | John Stumpf | Wed 2016-10-12, after close | 2016-10-13 | M | [Bloomberg](https://www.bloomberg.com/news/articles/2016-10-12/wells-fargo-ceo-stumpf-steps-down-in-fallout-from-fake-accounts) |
| 6 | Ford (F) | Mark Fields | Mon 2017-05-22, pre-market | 2017-05-22 | | [Automotive Fleet](https://www.automotive-fleet.com/140556/ford-replaces-ceo-fields-with-hackett) |
| 7 | Equifax (EFX) | Richard Smith | Tue 2017-09-26, pre-market | 2017-09-26 | M | [TechCrunch](https://techcrunch.com/2017/09/26/equifax-ceo-richard-smith-has-retired-following-huge-data-breach) |
| 8 | Lululemon (LULU) | Laurent Potdevin | Mon 2018-02-05, after close | 2018-02-06 | M | [Fox Business / AP](https://www.foxbusiness.com/markets/lululemons-ceo-resigns-over-issue-of-conduct) |
| 9 | Wynn Resorts (WYNN) | Steve Wynn | Tue 2018-02-06, late evening | 2018-02-07 | M | [Wynn press release / 8-K](https://www.sec.gov/Archives/edgar/data/0001174922/000119312518033939/d538506dex991.htm) |
| 10 | Intel (INTC) | Brian Krzanich | Thu 2018-06-21, pre-market | 2018-06-21 | M | [SiliconANGLE](https://siliconangle.com/blog/2018/06/21/intel-ceo-brian-krzanich-resigns-past-consensual-relationship-employee/) |
| 11 | Texas Instruments (TXN) | Brian Crutcher | Tue 2018-07-17, after close | 2018-07-18 | M | [CNN Money](https://money.cnn.com/2018/07/17/news/companies/texas-instruments-ceo-resigns) |
| 12 | CBS (CBS, now Paramount Skydance) | Les Moonves | Sun 2018-09-09 | 2018-09-10 | M | [NPR](https://www.npr.org/2018/09/09/646092685/les-moonves-out-at-cbs-after-harassment-allegations) |
| 13 | General Electric (GE) | John Flannery | Mon 2018-10-01, pre-market | 2018-10-01 | | [Yahoo News](https://www.yahoo.com/news/ge-stock-soars-ceo-john-115645840.html) |
| 14 | Wells Fargo (WFC) | Tim Sloan | Thu 2019-03-28, after close | 2019-03-29 | M | [Motley Fool](https://www.fool.com/investing/2019/03/28/after-hours-news-rh-reports-earnings-and-wells-far.aspx) |
| 15 | McDonald's (MCD) | Steve Easterbrook | Sun 2019-11-03 | 2019-11-04 | M | [Bloomberg](https://www.bloomberg.com/news/articles/2019-11-03/mcdonald-s-fires-ceo-easterbrook-over-relationship-with-employee) |
| 16 | Expedia (EXPE) | Mark Okerstrom | Wed 2019-12-04, after close | 2019-12-05 | | [CNBC](https://www.cnbc.com/2019/12/04/expedia-replaces-ceo-and-cfo-in-leadership-shakeup.html) |
| 17 | Boeing (BA) | Dennis Muilenburg | Mon 2019-12-23, pre-market | 2019-12-23 | M | [Bloomberg](https://www.bloomberg.com/news/articles/2019-12-23/boeing-ceo-dennis-muilenburg-resigns-david-calhoun-named-president-and-ceo) |
| 18 | Disney (DIS) | Bob Chapek | Sun 2022-11-20 | 2022-11-21 | | [The Week](https://theweek.com/disney/1018615/bob-iger-makes-a-surprise-return-to-disney-as-ceo-bob-chapek-is-ousted) |
| 19 | Walgreens (WBA) | Rosalind Brewer | Fri 2023-09-01, pre-market | 2023-09-01 | | [CNBC](https://www.cnbc.com/2023/09/01/walgreens-ceo-roz-brewer-steps-down.html) |
| 20 | Dollar General (DG) | Jeff Owen | Thu 2023-10-12, pre-market | 2023-10-12 | | [Dollar General 8-K](https://www.sec.gov/Archives/edgar/data/29534/000110465923108865/tm2328316d1_8k.htm) |
| 21 | Paramount Global (PARA) | Bob Bakish | Mon 2024-04-29, after close | 2024-04-30 | | [CNBC](https://www.cnbc.com/2024/04/29/paramount-ceo-bob-bakish-stepping-down.html) |
| 22 | Starbucks (SBUX) | Laxman Narasimhan | Tue 2024-08-13, pre-market | 2024-08-13 | | [CBS News](https://www.cbsnews.com/news/starbucks-new-ceo-brian-niccol-chipotle-laxman-narasimhan) |
| 23 | Norfolk Southern (NSC) | Alan Shaw | Wed 2024-09-11, late evening | 2024-09-12 | M | [Fortune](https://fortune.com/2024/09/11/norfolk-southern-fires-ceo-over-inappropriate-workplace-relationship) |
| 24 | CVS Health (CVS) | Karen Lynch | Fri 2024-10-18, pre-market | 2024-10-18 | | [Healthcare Dive](https://www.healthcaredive.com/news/cvs-replaces-ceo-karen-lynch-caremark-head-david-joyner/730275/) |
| 25 | Intel (INTC) | Pat Gelsinger | Mon 2024-12-02, pre-market | 2024-12-02 | | [Intel press release](https://d1io3yog0oux5.cloudfront.net/_b41bf7d82b2dbbf7f3f1c5737292af81/intel/news/2024-12-02_Intel_Announces_Retirement_of_CEO_Pat_1719.pdf) |
| 26 | Kroger (KR) | Rodney McMullen | Mon 2025-03-03, pre-market | 2025-03-03 | M | [KSL / AP](https://www.ksl.com/article/51266269/kroger-chairman-and-ceo-resigns-following-investigation-into-personal-conduct) |
| 27 | Kohl's (KSS) | Ashley Buchanan | Thu 2025-05-01, pre-market | 2025-05-01 | M | [Retail Dive](https://www.retaildive.com/news/kohls-ceo-fired-over-conflicts-of-interest/746843) |
| 28 | UnitedHealth (UNH) | Andrew Witty | Tue 2025-05-13, pre-market | 2025-05-13 | | [CBS News](https://www.cbsnews.com/amp/news/unitedhealth-ceo-andrew-witty-resigns) |

**Looked at and left out under the rule (before prices):** Hertz (Scherr, Mar 2024: effective two weeks later), Chipotle (Niccol, Aug 2024:
left for Starbucks, effective Aug 31), Yahoo (Thompson, 2012) and J.C. Penney (Johnson, 2013): no price history left on Yahoo; NVDA
(the live case). If a ticker below turns out to have no usable Yahoo history, it is dropped and named, not replaced.
