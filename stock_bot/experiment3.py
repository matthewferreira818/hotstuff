#!/usr/bin/env python3
"""EXP-0003: day trading — in and out the same day, on 5-minute prices.

Research only; the live bot and Practice Desk are untouched.

Data: Yahoo's free 5-minute bars, the last 60 trading days (the most it
serves). Stocks: the council's 3 picks plus the 20 steadiest swingers
from today's screen. One trade per stock per day, always out by the
close. Decisions and fills on 5-minute closes.

Three strategies, settings DECLARED BEFORE THE RUN:
  OR   Opening-range breakout: note the high/low of the first 30 minutes.
       Buy when a 5-minute close breaks above that high. Sell if it falls
       back under the range's low, at a gain of 2x the range's height,
       or at the close.
  DIP  Dip bounce: buy when the price is 2% under the day's open. Sell at
       +1.5%, at -1.5%, or at the close.
  RUN  Momentum run: buy when the price is 2% over the day's open on a
       5-minute bar with at least 2x the day's average bar volume. Sell
       on a 1% drop from the best price since buying, or at the close.

Costs: $1 per order, fills 0.1% worse (same as the practice account).
Every strategy is also shown with $1,000 bets, where the same $1 fee is a
tenth as heavy. Pass condition, set before the run: positive after costs
with $100 bets in BOTH halves of the 60 days, and more than holding SPY
with the same money would have made.

  python stock_bot/experiment3.py
  python stock_bot/experiment3.py --selftest
"""

import datetime as dt
import itertools
import json
import os
import statistics
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

EXP_ID = "EXP-0003"
OUT = os.path.join(HERE, "research", "experiments")
FEE, SLIP = 1.0, 0.001
DEFAULTS = {"OR": {"target_x": 2}, "DIP": {"dip": 2, "exit": 1.5},
            "RUN": {"trigger": 2, "trail": 1, "vol_x": 2}}
GRIDS = {"OR": {"target_x": [1, 2, 3]},
         "DIP": {"dip": [1, 2, 3], "exit": [1, 1.5, 2]},
         "RUN": {"trigger": [1, 2, 3], "trail": [0.5, 1, 2], "vol_x": [2]}}
NAMES = {"OR": "Opening-range breakout", "DIP": "Dip bounce",
         "RUN": "Momentum run"}


def fetch5(sym):
    url = (f"https://query1.finance.yahoo.com/v8/finance/chart/{sym}"
           "?range=60d&interval=5m")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                res = json.load(r)["chart"]["result"][0]
            break
        except Exception:
            time.sleep(2 * (attempt + 1))
    else:
        return {}
    off = res["meta"]["gmtoffset"]
    q = res["indicators"]["quote"][0]
    days = {}
    for i, ts in enumerate(res.get("timestamp") or []):
        bar = {k: q[k][i] for k in ("open", "high", "low", "close", "volume")}
        if None in bar.values():
            continue
        d = dt.datetime.fromtimestamp(ts + off, dt.timezone.utc).date()
        days.setdefault(d.isoformat(), []).append(bar)
    return {d: b for d, b in days.items() if len(b) >= 60}  # full sessions


def day_trade(kind, p, bars):
    """At most one trade in one day's bars. Returns (gross move %, reason)
    or None. Gross = before costs; costs are applied per bet size later."""
    if len(bars) < 8:
        return None
    day_open = bars[0]["open"]
    entry = None
    if kind == "OR":
        hi = max(b["high"] for b in bars[:6])
        lo = min(b["low"] for b in bars[:6])
        start = 6
    else:
        start = 1
    vol_sum = sum(b["volume"] for b in bars[:start])
    for i in range(start, len(bars)):
        c = bars[i]["close"]
        vol_sum += bars[i]["volume"]
        if entry is None:
            if i == len(bars) - 1:
                return None  # no buying on the closing bar
            if kind == "OR" and c > hi:
                entry, peak = c, c
            elif kind == "DIP" and c <= day_open * (1 - p["dip"] / 100):
                entry, peak = c, c
            elif kind == "RUN" and c >= day_open * (1 + p["trigger"] / 100) \
                    and bars[i]["volume"] >= p["vol_x"] * vol_sum / (i + 1):
                entry, peak = c, c
            continue
        peak = max(peak, c)
        move = (c / entry - 1) * 100
        if kind == "OR":
            if c < lo:
                return move, "stop"
            if c >= entry + p["target_x"] * (hi - lo):
                return move, "target"
        elif kind == "DIP":
            if move >= p["exit"]:
                return move, "target"
            if move <= -p["exit"]:
                return move, "stop"
        elif kind == "RUN" and c <= peak * (1 - p["trail"] / 100):
            return move, "trail"
    if entry is None:
        return None
    return (bars[-1]["close"] / entry - 1) * 100, "close"


def net(move_pct, bet):
    """Dollars after a $1 fee each way and 0.1% worse fills each way."""
    qty = (bet - FEE) / (1 + SLIP)
    return qty * (1 + move_pct / 100) * (1 - SLIP) - FEE - bet


def run(kind, p, data, dates):
    trades = []
    for sym, days in data.items():
        for d in dates:
            if d in days:
                t = day_trade(kind, p, days[d])
                if t:
                    trades.append({"sym": sym, "date": d, "move": t[0],
                                   "why": t[1]})
    return trades


def stats(trades, dates):
    half = dates[len(dates) // 2]
    out = {"trades": len(trades)}
    if not trades:
        return out
    for bet in (100, 1000):
        pnl = [net(t["move"], bet) for t in trades]
        out[f"pnl_{bet}"] = round(sum(pnl), 2)
        out[f"first_half_{bet}"] = round(sum(
            x for x, t in zip(pnl, trades) if t["date"] < half), 2)
        out[f"second_half_{bet}"] = round(sum(
            x for x, t in zip(pnl, trades) if t["date"] >= half), 2)
        out[f"win_rate_{bet}"] = round(sum(x > 0 for x in pnl)
                                       / len(pnl) * 100)
    out["gross_avg_move"] = round(statistics.mean(t["move"]
                                                  for t in trades), 3)
    out["fees_100"] = round(len(trades) * (2 * FEE + 2 * 100 * SLIP), 2)
    days = {}
    for t in trades:
        days[t["date"]] = days.get(t["date"], 0) + net(t["move"], 100)
    out["green_days"] = f"{sum(v > 0 for v in days.values())}/{len(days)}"
    reasons = {}
    for t in trades:
        reasons[t["why"]] = reasons.get(t["why"], 0) + 1
    out["exits"] = reasons
    return out


def combos(kind):
    g = GRIDS[kind]
    return [dict(zip(g, v)) for v in itertools.product(*g.values())]


def main():
    with open(os.path.join(HERE, "screen", "latest.json")) as f:
        screen = json.load(f)["stocks"]
    with open(os.path.join(HERE, "watchlist.json")) as f:
        picks = [s["symbol"] for s in json.load(f)["stocks"]]
    steady = [r["symbol"] for r in sorted(
        screen, key=lambda r: -r["steady_sigma"])[:20]]
    symbols = list(dict.fromkeys(picks + steady))
    data = {}
    for s in symbols:
        d = fetch5(s)
        if d:
            data[s] = d
        time.sleep(0.3)
    spy = fetch5("SPY")
    dates = sorted(set(spy) & set().union(*(set(d) for d in data.values())))
    res = {k: stats(run(k, DEFAULTS[k], data, dates), dates) for k in NAMES}
    grid = {k: [dict(q, pnl_100=stats(run(k, q, data, dates), dates)
                     .get("pnl_100", 0)) for q in combos(k)] for k in NAMES}
    # Holding SPY: the same pot as one $100 slot per stock, all period.
    pot = 100 * len(data)
    spy_hold = pot * (spy[dates[-1]][-1]["close"] / spy[dates[0]][0]["open"]
                      - 1)
    stock_hold = sum(100 * (d[dates[-1]][-1]["close"] / d[dates[0]][0]["open"]
                            - 1) for d in data.values()
                     if dates[0] in d and dates[-1] in d)
    passed = {k: (r.get("first_half_100", -1) > 0
                  and r.get("second_half_100", -1) > 0
                  and r.get("pnl_100", -1) > spy_hold)
              for k, r in res.items()}

    today = dt.date.today().isoformat()
    L = [f"# {EXP_ID}: day trading on 5-minute prices — {today}", "",
         f"{len(dates)} trading days ({dates[0]} to {dates[-1]}), "
         f"{len(data)} stocks, one trade per stock per day, always out by "
         "the close. $1 per order and 0.1% worse fills. Settings fixed "
         "before the run.", "",
         "**Pass condition (set before the run):** profit after costs with "
         "$100 bets in both halves of the period, and more than holding SPY "
         f"with the same ${pot:,} (${spy_hold:+,.0f}).", "",
         "| Strategy | Trades | P/L, $100 bets | Win rate | Green days | "
         "P/L, $1,000 bets | 1st half / 2nd half ($100) | Avg move before "
         "costs | Costs ($100 bets) | Passed? |",
         "|---|---|---|---|---|---|---|---|---|---|"]
    for k in NAMES:
        r = res[k]
        if not r.get("trades"):
            L.append(f"| {NAMES[k]} | 0 | — | — | — | — | — | — | — | no |")
            continue
        L.append(
            f"| {NAMES[k]} | {r['trades']} | ${r['pnl_100']:+,.0f} | "
            f"{r['win_rate_100']}% | {r['green_days']} | "
            f"${r['pnl_1000']:+,.0f} | ${r['first_half_100']:+,.0f} / "
            f"${r['second_half_100']:+,.0f} | {r['gross_avg_move']:+.2f}% | "
            f"${r['fees_100']:,.0f} | {'yes' if passed[k] else 'no'} |")
    L += ["", f"Holding SPY with ${pot:,}: **${spy_hold:+,.0f}**. Holding the "
          f"same stocks, $100 each: **${stock_hold:+,.0f}**.", "",
          "### Why costs decide day trading", "",
          "With $100 bets a round trip costs about $2.20 ($1 each way plus "
          "slippage), so a trade has to move about **+2.2% just to break "
          "even**. With $1,000 bets it's about +0.3%. Day-trading moves are "
          "small, so the bet size matters as much as the strategy.", "",
          "### Robustness: nearby settings ($100 bets)", "",
          "| Strategy | Settings tried | Median P/L | Worst | Best | "
          "Settings that made money |", "|---|---|---|---|---|---|"]
    for k in NAMES:
        v = [x["pnl_100"] for x in grid[k]]
        L.append(f"| {NAMES[k]} | {len(v)} | ${statistics.median(v):+,.0f} "
                 f"| ${min(v):+,.0f} | ${max(v):+,.0f} | "
                 f"{sum(x > 0 for x in v)}/{len(v)} |")
    L += ["", "### Caveats", "",
          "- 60 days is a short sample, and a single market mood.",
          "- Fills on 5-minute closes; real day-trading fills are usually "
          "worse in fast moves.",
          "- Stocks chosen from today's screen of big swingers.",
          "- Taxes: frequent day trading is what CRA treats as business "
          "income, even in a TFSA."]
    text = "\n".join(L) + "\n"
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, f"{EXP_ID}.md"), "w") as f:
        f.write(text)
    with open(os.path.join(OUT, f"{EXP_ID}.json"), "w") as f:
        json.dump({"id": EXP_ID, "run": today, "defaults": DEFAULTS,
                   "names": NAMES, "results": res, "passed": passed,
                   "spy_hold": round(spy_hold, 2),
                   "stock_hold": round(stock_hold, 2), "pot": pot,
                   "days": len(dates), "stocks": len(data),
                   "robustness": grid}, f, indent=1)
    print(text)


def selftest():
    bar = lambda c, v=100: {"open": c, "high": c, "low": c, "close": c,
                            "volume": v}
    # Dip bounce: open 100, drops to 98 (buy), recovers to 99.5 (+1.53%).
    bars = [bar(100)] * 5 + [bar(98), bar(99), bar(99.5)] + [bar(99.5)] * 60
    move, why = day_trade("DIP", DEFAULTS["DIP"], bars)
    assert why == "target" and abs(move - 1.53) < 0.01, (move, why)
    # $100 bet: +1.53% still loses after costs; $1,000 bet makes money.
    assert net(move, 100) < 0 < net(move, 1000)
    # Opening range 99-101; breakout at 102; falls under 99 -> stop.
    bars = ([bar(100), bar(101), bar(99)] + [bar(100)] * 3 + [bar(102)]
            + [bar(98.5)] + [bar(98.5)] * 60)
    move, why = day_trade("OR", DEFAULTS["OR"], bars)
    assert why == "stop" and move < 0, (move, why)
    # Nothing triggers -> no trade.
    assert day_trade("RUN", DEFAULTS["RUN"], [bar(100)] * 70) is None
    print("selftest OK")


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else main()
