#!/usr/bin/env python3
"""EXP-0004: "hot trading" cheap, wide-swinging stocks like ONDS.

Matthew's idea (2026-10-07): trade companies like Ondas that swing about
60 cents a day on a ~$7 share (~8%), in and out the same day. EXP-0003
day-traded big swingers and lost on every setting; this run asks whether
CHEAP stocks with WIDE daily ranges are different, using Moomoo's real
fee (US$1.99 minimum per order, $0.0099 per share), where a bigger bet
makes the fee lighter.

Research only; the live robots and Practice Desk are untouched.

Stocks, chosen by a rule DECLARED BEFORE THE RUN (no hand-picking):
universe.txt + the watchlist + ONDS, kept if over Yahoo's last 60 trading
days the median price is $2-$25 and the median day swings at least 5%
from low to high.

Three strategies, settings declared before the run. All decide and fill
on 5-minute closes, never buy on the last bar, and are out by the close.
  SNAP  VWAP snap-back: after the first 15 minutes, buy when the price is
        2% under the day's volume-weighted average price (VWAP). Sell when
        it gets back to VWAP, at -3%, or at the close. Up to 2 round trips
        per stock per day.
  OR    Opening-range breakout (as EXP-0003): buy a close above the first
        30 minutes' high; sell under its low, at 2x its height, or the close.
  RUN   Momentum run (as EXP-0003): buy at +2% on the day with a 2x-volume
        bar; sell on a 1% drop from the best price, or at the close.

Two views of the money:
  per trade   every signal at $100 / $500 / $1,000 bets.
  account     a realistic $1,000 practice account: $500 per trade, at most
              2 trades open at once, first come first served.
Pass condition, set before the run: the $1,000 account makes money in
BOTH halves of the 60 days AND beats holding SPY with the same $1,000,
AND the average trade moves up before costs (a real edge, not luck).

  python stock_bot/experiment4.py
  python stock_bot/experiment4.py --selftest
"""

import datetime as dt
import itertools
import json
import os
import statistics
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from experiment3 import fetch5  # noqa: E402

EXP_ID = "EXP-0004"
OUT = os.path.join(HERE, "research", "experiments")
FEE_MIN, FEE_SHARE, SLIP = 1.99, 0.0099, 0.001
PRICE_MIN, PRICE_MAX, RANGE_MIN = 2, 25, 5.0
ACCOUNT, BET, SLOTS = 1000, 500, 2
DEFAULTS = {"SNAP": {"under": 2, "stop": 3, "trips": 2},
            "OR": {"target_x": 2}, "RUN": {"trigger": 2, "trail": 1}}
GRIDS = {"SNAP": {"under": [1.5, 2, 3], "stop": [2, 3, 5], "trips": [2]},
         "OR": {"target_x": [1, 2, 3]},
         "RUN": {"trigger": [1, 2, 3], "trail": [0.5, 1, 2]}}
NAMES = {"SNAP": "VWAP snap-back", "OR": "Opening-range breakout",
         "RUN": "Momentum run"}


def trades_in_day(kind, p, bars):
    """Trades in one day: list of (entry_bar, exit_bar, entry, exit, why)."""
    out = []
    if len(bars) < 8:
        return out
    day_open = bars[0]["open"]
    pv = vol = 0.0
    hi = max(b["high"] for b in bars[:6])
    lo = min(b["low"] for b in bars[:6])
    start = {"SNAP": 3, "OR": 6, "RUN": 1}[kind]
    for i in range(start):
        pv += bars[i]["close"] * bars[i]["volume"]
        vol += bars[i]["volume"]
    pos = None
    trips = p.get("trips", 1)
    for i in range(start, len(bars)):
        b = bars[i]
        c = b["close"]
        pv += c * b["volume"]
        vol += b["volume"]
        vwap = pv / vol if vol else c
        if pos is None:
            if len(out) >= trips or i == len(bars) - 1:
                continue
            go = False
            if kind == "SNAP":
                go = c <= vwap * (1 - p["under"] / 100)
            elif kind == "OR":
                go = c > hi
            elif kind == "RUN":
                go = (c >= day_open * (1 + p["trigger"] / 100)
                      and b["volume"] >= 2 * vol / (i + 1))
            if go:
                pos = {"i": i, "entry": c, "peak": c}
            continue
        pos["peak"] = max(pos["peak"], c)
        why = None
        if kind == "SNAP":
            if c >= vwap:
                why = "target"
            elif c <= pos["entry"] * (1 - p["stop"] / 100):
                why = "stop"
        elif kind == "OR":
            if c < lo:
                why = "stop"
            elif c >= pos["entry"] + p["target_x"] * (hi - lo):
                why = "target"
        elif kind == "RUN" and c <= pos["peak"] * (1 - p["trail"] / 100):
            why = "trail"
        if why:
            out.append((pos["i"], i, pos["entry"], c, why))
            pos = None
    if pos:
        out.append((pos["i"], len(bars) - 1, pos["entry"],
                    bars[-1]["close"], "close"))
    return out


def net(entry, exit_, bet):
    """Dollars after Moomoo's fee each way and 0.1% worse fills each way."""
    buy = entry * (1 + SLIP)
    qty = bet / buy
    fee_buy = max(FEE_MIN, FEE_SHARE * qty)
    qty = (bet - fee_buy) / buy
    fee_sell = max(FEE_MIN, FEE_SHARE * qty)
    return qty * exit_ * (1 - SLIP) - fee_sell - bet


def run(kind, p, data, dates):
    trades = []
    for sym, days in data.items():
        for d in dates:
            for t in trades_in_day(kind, p, days.get(d, [])):
                trades.append({"sym": sym, "date": d, "in": t[0],
                               "out": t[1], "entry": t[2], "exit": t[3],
                               "why": t[4]})
    return trades


def account(trades, dates):
    """$1,000 account, $500 a trade, 2 open at most, first come first
    served (ties by symbol, so the run is repeatable). Returns per-day P/L."""
    by_day = {}
    for t in trades:
        by_day.setdefault(t["date"], []).append(t)
    daily, taken = {}, 0
    for d in dates:
        pnl, open_until = 0.0, []
        for t in sorted(by_day.get(d, []), key=lambda t: (t["in"], t["sym"])):
            open_until = [x for x in open_until if x > t["in"]]
            if len(open_until) < SLOTS:
                open_until.append(t["out"])
                pnl += net(t["entry"], t["exit"], BET)
                taken += 1
        daily[d] = pnl
    return daily, taken


def stats(trades, dates):
    half = dates[len(dates) // 2]
    out = {"trades": len(trades)}
    if not trades:
        return out
    moves = [(t["exit"] / t["entry"] - 1) * 100 for t in trades]
    out["gross_avg_move"] = round(statistics.mean(moves), 3)
    out["gross_win_rate"] = round(sum(m > 0 for m in moves) / len(moves) * 100)
    for bet in (100, 500, 1000):
        out[f"pnl_{bet}"] = round(sum(net(t["entry"], t["exit"], bet)
                                      for t in trades), 2)
    out["win_rate_500"] = round(sum(net(t["entry"], t["exit"], 500) > 0
                                    for t in trades) / len(trades) * 100)
    daily, taken = account(trades, dates)
    out["acct_trades"] = taken
    out["acct_pnl"] = round(sum(daily.values()), 2)
    out["acct_first"] = round(sum(v for d, v in daily.items() if d < half), 2)
    out["acct_second"] = round(sum(v for d, v in daily.items()
                                   if d >= half), 2)
    out["acct_fees"] = round(taken * 2 * FEE_MIN, 2)
    out["acct_green_days"] = (f"{sum(v > 0 for v in daily.values())}/"
                              f"{sum(v != 0 for v in daily.values())}")
    reasons = {}
    for t in trades:
        reasons[t["why"]] = reasons.get(t["why"], 0) + 1
    out["exits"] = reasons
    return out


def combos(kind):
    g = GRIDS[kind]
    return [dict(zip(g, v)) for v in itertools.product(*g.values())]


def pick(data):
    """The pre-declared filter: cheap and wide-swinging."""
    keep, why = {}, {}
    for s, days in data.items():
        closes = [b[-1]["close"] for b in days.values()]
        ranges = [(max(x["high"] for x in b) - min(x["low"] for x in b))
                  / b[0]["open"] * 100 for b in days.values()]
        price, rng = statistics.median(closes), statistics.median(ranges)
        why[s] = {"price": round(price, 2), "range_pct": round(rng, 1),
                  "range_cents": round(price * rng, 1)}
        if PRICE_MIN <= price <= PRICE_MAX and rng >= RANGE_MIN:
            keep[s] = days
    return keep, why


def main():
    with open(os.path.join(HERE, "universe.txt")) as f:
        uni = [ln.split("#")[0].strip() for ln in f]
    with open(os.path.join(HERE, "watchlist.json")) as f:
        picks = [s["symbol"] for s in json.load(f)["stocks"]]
    symbols = list(dict.fromkeys(["ONDS"] + picks + [u for u in uni if u]))
    raw = {}
    for s in symbols:
        d = fetch5(s)
        if d:
            raw[s] = d
        time.sleep(0.3)
    data, measured = pick(raw)
    spy = fetch5("SPY")
    dates = sorted(set(spy) & set().union(*(set(d) for d in data.values())))
    spy_hold = ACCOUNT * (spy[dates[-1]][-1]["close"]
                          / spy[dates[0]][0]["open"] - 1)
    res = {k: stats(run(k, DEFAULTS[k], data, dates), dates) for k in NAMES}
    grid = {k: [dict(q, acct_pnl=stats(run(k, q, data, dates), dates)
                     .get("acct_pnl", 0)) for q in combos(k)] for k in NAMES}
    passed = {k: (r.get("acct_first", -1) > 0 and r.get("acct_second", -1) > 0
                  and r.get("acct_pnl", -1) > spy_hold
                  and r.get("gross_avg_move", -1) > 0)
              for k, r in res.items()}

    today = dt.date.today().isoformat()
    kept = sorted(data, key=lambda s: -measured[s]["range_pct"])
    L = [f"# {EXP_ID}: hot trading cheap, wide-swinging stocks — {today}", "",
         f"{len(dates)} trading days ({dates[0]} to {dates[-1]}) of 5-minute "
         f"prices. Moomoo fees (US$1.99 minimum per order) and 0.1% worse "
         "fills. Settings and stock filter fixed before the run.", "",
         f"**Stocks** (median price ${PRICE_MIN}-${PRICE_MAX}, median day "
         f"swings ≥{RANGE_MIN:.0f}% low to high): {len(kept)} of "
         f"{len(raw)} checked.", "",
         "| Stock | Price | Typical day's swing |", "|---|---|---|"]
    for s in kept:
        m = measured[s]
        L.append(f"| {s} | ${m['price']:.2f} | {m['range_pct']:.1f}% "
                 f"(~{m['range_cents']:.0f}¢) |")
    L += ["", "**Pass condition (set before the run):** a $1,000 account "
          "($500 a trade, 2 at once) makes money in both halves, beats "
          f"holding SPY with $1,000 (${spy_hold:+,.0f}), and the average "
          "trade rises before costs.", "",
          "## The $1,000 practice account", "",
          "| Strategy | Trades taken | P/L | 1st half / 2nd half | Green days "
          "| Fees | Passed? |", "|---|---|---|---|---|---|---|"]
    for k in NAMES:
        r = res[k]
        if not r.get("trades"):
            L.append(f"| {NAMES[k]} | 0 | — | — | — | — | no |")
            continue
        L.append(f"| {NAMES[k]} | {r['acct_trades']} | ${r['acct_pnl']:+,.0f}"
                 f" | ${r['acct_first']:+,.0f} / ${r['acct_second']:+,.0f} | "
                 f"{r['acct_green_days']} | ${r['acct_fees']:,.0f} | "
                 f"{'yes' if passed[k] else 'no'} |")
    L += ["", f"Holding SPY with $1,000 over the same days: "
          f"**${spy_hold:+,.0f}**.", "",
          "## Every signal, by bet size", "",
          "| Strategy | Signals | Avg move before costs | Rose before costs "
          "| P/L $100 bets | P/L $500 bets | P/L $1,000 bets |",
          "|---|---|---|---|---|---|---|"]
    for k in NAMES:
        r = res[k]
        if r.get("trades"):
            L.append(f"| {NAMES[k]} | {r['trades']} | "
                     f"{r['gross_avg_move']:+.2f}% | {r['gross_win_rate']}% | "
                     f"${r['pnl_100']:+,.0f} | ${r['pnl_500']:+,.0f} | "
                     f"${r['pnl_1000']:+,.0f} |")
    L += ["", "With $500 bets a round trip costs about $5 (two $1.99 fees plus "
          "slippage), so a trade must rise about **1%** to break even; with "
          "$100 bets it's about **4.2%**.", "",
          "## Robustness: nearby settings ($1,000 account)", "",
          "| Strategy | Settings tried | Median P/L | Worst | Best | Made money "
          "|", "|---|---|---|---|---|---|"]
    for k in NAMES:
        v = [x["acct_pnl"] for x in grid[k]]
        L.append(f"| {NAMES[k]} | {len(v)} | ${statistics.median(v):+,.0f} | "
                 f"${min(v):+,.0f} | ${max(v):+,.0f} | "
                 f"{sum(x > 0 for x in v)}/{len(v)} |")
    L += ["", "### Caveats", "",
          "- 60 days is a short sample and one market mood.",
          "- Fills on 5-minute closes. Cheap stocks have wider bid/ask "
          "spreads, so real fills are usually worse than 0.1%.",
          "- The stock list comes from today's universe (survivorship bias).",
          "- US rule: in a margin account under US$25,000, more than 3 day "
          "trades in 5 business days can get the account restricted "
          "(pattern day trader rule). A cash account avoids that but must "
          "wait for sold money to settle (1 business day) before reusing it. "
          "Check Moomoo's current rules before any real money.",
          "- Taxes: frequent day trading is what CRA treats as business "
          "income, even in a TFSA."]
    text = "\n".join(L) + "\n"
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, f"{EXP_ID}.md"), "w") as f:
        f.write(text)
    with open(os.path.join(OUT, f"{EXP_ID}.json"), "w") as f:
        json.dump({"id": EXP_ID, "run": today, "defaults": DEFAULTS,
                   "names": NAMES, "stocks": kept, "measured": measured,
                   "results": res, "passed": passed,
                   "spy_hold": round(spy_hold, 2), "days": len(dates),
                   "robustness": grid}, f, indent=1)
    print(text)


def selftest():
    bar = lambda c, v=100: {"open": c, "high": c, "low": c, "close": c,
                            "volume": v}
    # SNAP: VWAP ~10; drop to 9.7 (-3% buy), back to 10 -> target.
    bars = [bar(10)] * 10 + [bar(9.7), bar(9.9), bar(10.2)] + [bar(10.2)] * 60
    t = trades_in_day("SNAP", DEFAULTS["SNAP"], bars)
    assert t and t[0][4] == "target" and t[0][2] == 9.7, t
    # Fees: $500 bet on a flat trade loses about $5; $100 bet about $4.2.
    assert -5.1 < net(10, 10, 500) < -4.9, net(10, 10, 500)
    assert -4.3 < net(10, 10, 100) < -4.1, net(10, 10, 100)
    # Account: three overlapping trades, only 2 slots -> 2 taken.
    tr = [{"sym": s, "date": "d", "in": 1, "out": 9, "entry": 10,
           "exit": 11, "why": "x"} for s in "ABC"]
    daily, taken = account(tr, ["d"])
    assert taken == 2 and daily["d"] > 0, (taken, daily)
    # Filter: cheap + 8% swing kept, $100 stock dropped.
    day = [{"open": 7, "high": 7.3, "low": 6.75, "close": 7, "volume": 1}]
    keep, _ = pick({"ONDS": {"d1": day * 60},
                    "BIG": {"d1": [{"open": 100, "high": 108, "low": 100,
                                    "close": 104, "volume": 1}] * 60}})
    assert list(keep) == ["ONDS"], keep
    print("selftest OK")


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else main()
