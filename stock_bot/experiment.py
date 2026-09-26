#!/usr/bin/env python3
"""EXP-0001: dip-buying vs trend-following, on months nobody tuned for.

Research only. Nothing here touches strategy.py, the live bot or the
Practice Desk. The current dip strategy is kept as the control.

Four strategies, each with its settings DECLARED HERE BEFORE THE RUN
(no optimizer picks them, so every test window is genuinely unseen):

  A  Current dip:      buy 8% under the 20-day high; sell at +20% or -10%.
  B  Buy and hold:     buy on the window's first day, never sell.
  C  Trend breakout:   20-day average above the 50-day, price above the
                       20-day average, volume above its 20-day average,
                       and the close breaks the prior 20-day high.
                       Exit: trailing stop 10% under the best close since
                       buying. No fixed take-profit.
  D  Momentum+volume:  up 10%+ over 60 days, price above the 20-day
                       average, volume 1.5x its 20-day average.
                       Exit: trailing stop 3x the stock's typical daily
                       range (ATR) under the best close since buying.

Same costs as the practice account: $1 fee per trade, fills 0.1% worse.
$100 per buy, one position per stock at a time, one $100 slot per stock.
Test windows: the same 9 three-month windows as the walk-forward test.

Reported, not optimized: P/L, return, max drawdown, trades, win rate,
profit factor, average trade, exposure, fees, volatility, return per
unit of risk, and results against SPY and against buy-and-hold. A
robustness check reruns each strategy across a small grid of nearby
settings to show whether the result depends on the exact numbers.

  python stock_bot/experiment.py            # run, write research/experiments/
  python stock_bot/experiment.py --selftest
"""

import datetime as dt
import itertools
import json
import math
import os
import statistics
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

OUT = os.path.join(HERE, "research", "experiments")
EXP_ID = "EXP-0001"
BET, FEE, SLIP = 100.0, 1.0, 0.001
TRAIN, TEST = 126, 63   # same windows as backtest.walk_forward
WARMUP = 60             # days of history indicators need

DEFAULTS = {
    "A": {"dip": 8, "take_profit": 20, "stop_loss": 10},
    "B": {},
    "C": {"lookback": 20, "trail": 10},
    "D": {"momentum": 10, "volume_x": 1.5, "atr_x": 3},
}
GRIDS = {
    "A": {"dip": [6, 8, 10, 12], "take_profit": [10, 20, 30],
          "stop_loss": [5, 10, 100]},
    "B": {},
    "C": {"lookback": [20, 50], "trail": [8, 10, 15, 20]},
    "D": {"momentum": [0, 10, 20], "volume_x": [1.0, 1.5],
          "atr_x": [2, 3, 4]},
}
NAMES = {"A": "Current dip (control)", "B": "Buy and hold",
         "C": "Trend breakout + 10% trailing stop",
         "D": "Momentum + volume + ATR trailing stop"}


# ---------------------------------------------------------------- indicators

def indicators(c, v, h, l):
    """Per-day values known at that day's close (None = not enough data)."""
    n = len(c)
    ind = {k: [None] * n for k in ("sma20", "sma50", "vol20", "atr",
                                   "hi20", "hi50", "ret60")}
    for i in range(n):
        if c[i] is None:
            continue
        if i >= 50 and None not in c[i - 50:i + 1] and None not in v[i - 20:i]:
            ind["sma20"][i] = sum(c[i - 19:i + 1]) / 20
            ind["sma50"][i] = sum(c[i - 49:i + 1]) / 50
            ind["vol20"][i] = sum(v[i - 20:i]) / 20
            ind["hi20"][i] = max(c[i - 20:i])
            ind["hi50"][i] = max(c[i - 50:i])
            trs = [max(h[j] - l[j], abs(h[j] - c[j - 1]), abs(l[j] - c[j - 1]))
                   / c[j] * 100 for j in range(i - 13, i + 1)]
            ind["atr"][i] = sum(trs) / 14
        if i >= 60 and c[i - 60] is not None:
            ind["ret60"][i] = (c[i] / c[i - 60] - 1) * 100
    return ind


# -------------------------------------------------------------------- engine

def wants_in(kind, p, c, v, ind, i):
    if kind == "A":
        hi = ind["hi20"][i]
        return hi is not None and (hi - c[i]) / hi * 100 >= p["dip"]
    if ind["sma20"][i] is None:
        return False
    if kind == "C":
        hi = ind["hi20" if p["lookback"] == 20 else "hi50"][i]
        return (ind["sma20"][i] > ind["sma50"][i] and c[i] > ind["sma20"][i]
                and v[i] > ind["vol20"][i] and c[i] > hi)
    if kind == "D":
        return (ind["ret60"][i] is not None
                and ind["ret60"][i] >= p["momentum"]
                and c[i] > ind["sma20"][i]
                and v[i] > p["volume_x"] * ind["vol20"][i])
    return False


def sleeve(kind, p, s, lo, hi):
    """One stock's $100 slot over days [lo, hi). Returns the daily P/L
    path (realized + unrealized) and the closed trades."""
    c, v, ind = s["c"], s["v"], s["ind"]
    pos, realized, path, trades, held = None, 0.0, [], [], 0
    for i in range(lo, hi):
        if pos is None:
            if (kind == "B" and i == lo) or (kind != "B" and
                                             wants_in(kind, p, c, v, ind, i)):
                fill = c[i] * (1 + SLIP)
                qty = (BET - FEE) / fill
                pos = {"qty": qty, "cost": BET, "entry": BET / qty,
                       "peak": c[i], "i": i,
                       "trail": (p["trail"] if kind == "C" else
                                 p["atr_x"] * ind["atr"][i] if kind == "D"
                                 else None)}
        else:
            held += 1
            pos["peak"] = max(pos["peak"], c[i])
            out = False
            if kind == "A":
                ch = (c[i] - pos["entry"]) / pos["entry"] * 100
                out = ch >= p["take_profit"] or ch <= -p["stop_loss"]
            elif kind in ("C", "D"):
                out = c[i] <= pos["peak"] * (1 - pos["trail"] / 100)
            if out:
                pnl = pos["qty"] * c[i] * (1 - SLIP) - FEE - pos["cost"]
                realized += pnl
                trades.append({"pnl": pnl, "days": i - pos["i"]})
                pos = None
        unreal = pos["qty"] * c[i] - pos["cost"] if pos else 0.0
        path.append(realized + unreal)
    if pos:  # still open at the window's end: valued at the last close
        trades.append({"pnl": path[-1] - realized, "days": hi - 1 - pos["i"],
                       "open": True})
    return path, trades, held


# ---------------------------------------------------------------- windows

def covered(c, lo, hi):
    return all(x is not None for x in c[max(0, lo - WARMUP):hi])


def windows(n):
    lo, out = 20, []
    while lo + TRAIN + TEST <= n:
        out.append((lo + TRAIN, lo + TRAIN + TEST))
        lo += TEST
    return out


def evaluate(kind, p, data, spy, dates):
    """Run one strategy with fixed settings over every test window."""
    wins = []
    for lo, hi in windows(len(dates)):
        stocks = [s for s in data.values() if covered(s["c"], lo, hi)]
        port = [0.0] * (hi - lo)
        trades, held = [], 0
        for s in stocks:
            path, t, h = sleeve(kind, p, s, lo, hi)
            port = [a + b for a, b in zip(port, path)]
            trades += t
            held += h
        cap = BET * len(stocks)
        wins.append({
            "test": f"{dates[lo]} → {dates[hi - 1]}", "stocks": len(stocks),
            "capital": cap, "path": port, "trades": trades,
            "exposure": held / (len(stocks) * (hi - lo)),
            "spy_pnl": cap * (spy[hi - 1] / spy[lo] - 1),
        })
    return wins


def summarize(wins):
    """One row of metrics across all test windows, chained in order."""
    equity, base = [], wins[0]["capital"]
    offset = 0.0
    daily = []
    for w in wins:
        for x in w["path"]:
            val = base + offset + x
            if equity:
                daily.append(val / equity[-1] - 1)
            equity.append(val)
        offset += w["path"][-1]
    peak, mdd = equity[0], 0.0
    for e in equity:
        peak = max(peak, e)
        mdd = min(mdd, (e - peak) / peak * 100)
    closed = [t for w in wins for t in w["trades"] if not t.get("open")]
    allt = [t for w in wins for t in w["trades"]]
    pnl = sum(w["path"][-1] for w in wins)
    ret = pnl / base * 100
    g = sum(t["pnl"] for t in closed if t["pnl"] > 0)
    lss = -sum(t["pnl"] for t in closed if t["pnl"] <= 0)
    vol = statistics.pstdev(daily) * math.sqrt(252) * 100 if daily else 0
    sharpe = (statistics.mean(daily) / statistics.pstdev(daily)
              * math.sqrt(252)) if daily and statistics.pstdev(daily) else 0
    spy = sum(w["spy_pnl"] for w in wins)
    return {
        "pnl": round(pnl, 2), "return_pct": round(ret, 1),
        "max_drawdown_pct": round(mdd, 1),
        "return_per_drawdown": round(ret / -mdd, 2) if mdd < 0 else None,
        "sharpe": round(sharpe, 2), "volatility_pct": round(vol, 1),
        "trades": len(closed),
        "win_rate": round(sum(t["pnl"] > 0 for t in closed) / len(closed)
                          * 100) if closed else None,
        "profit_factor": round(g / lss, 2) if lss else None,
        "avg_trade": round(statistics.mean(t["pnl"] for t in allt), 2)
        if allt else 0,
        "exposure_pct": round(statistics.mean(w["exposure"] for w in wins)
                              * 100),
        "fees": round(len(allt) * FEE + len(closed) * FEE
                      + sum(2 * BET * SLIP for _ in allt), 0),
        "spy_pnl": round(spy, 2),
        "windows_beat_spy": sum(w["path"][-1] > w["spy_pnl"] for w in wins),
        "windows": len(wins),
        "per_window": [round(w["path"][-1], 2) for w in wins],
    }


def combos(kind):
    g = GRIDS[kind]
    if not g:
        return [{}]
    keys = list(g)
    return [dict(zip(keys, vals)) for vals in itertools.product(*g.values())]


# ------------------------------------------------------------------- data

def load(symbols):
    from screener import fetch
    raw = {}
    for s in symbols + ["SPY"]:
        bars = fetch(s, "3y")
        if len(bars) >= 200:
            raw[s] = bars
        time.sleep(0.25)
    cal = [b["date"] for b in raw["SPY"]]
    data = {}
    for s, bars in raw.items():
        by = {b["date"]: b for b in bars}
        col = lambda k: [by[d][k] if d in by else None for d in cal]
        c, v, h, l = col("close"), col("volume"), col("high"), col("low")
        data[s] = {"c": c, "v": v, "h": h, "l": l,
                   "ind": indicators(c, v, h, l)}
    spy = data.pop("SPY")["c"]
    return data, spy, cal


# ------------------------------------------------------------------ report

def report(results, grid, n_stocks, dates):
    today = dt.date.today().isoformat()
    L = [f"# {EXP_ID}: dip-buying vs trend-following — {today}", "",
         "**Question:** does buying strength with a trailing exit (C, D) do "
         "better than the current dip strategy (A) or plain buy-and-hold "
         "(B), on months no one tuned for?", "",
         f"Settings were fixed before the run. Up to {n_stocks} stocks, one "
         "$100 slot each, $1 fee per trade, fills 0.1% worse. Same 9 "
         "three-month test windows as the walk-forward test. Daily closes "
         f"(data from {dates[0]}).", "",
         "| Strategy | P/L | Return | Max drawdown | Return ÷ drawdown | "
         "Sharpe | Trades | Win rate | Profit factor | Avg trade | Exposure "
         "| Fees + slippage | Windows beating SPY |",
         "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for k in "ABCD":
        r = results[k]
        L.append(
            f"| **{k}** {NAMES[k]} | ${r['pnl']:+,.0f} | "
            f"{r['return_pct']:+.1f}% | {r['max_drawdown_pct']}% | "
            f"{r['return_per_drawdown'] if r['return_per_drawdown'] is not None else '—'} | "
            f"{r['sharpe']} | {r['trades']} | "
            f"{str(r['win_rate']) + '%' if r['win_rate'] is not None else '—'} | "
            f"{r['profit_factor'] if r['profit_factor'] is not None else '—'} | "
            f"${r['avg_trade']:+.2f} | {r['exposure_pct']}% | "
            f"${r['fees']:,.0f} | {r['windows_beat_spy']}/{r['windows']} |")
    spy = results["A"]["spy_pnl"]
    L += ["", f"SPY with the same money over the same windows: "
          f"**${spy:+,.0f}**.", "",
          "### Window by window (P/L, unseen months)", "",
          "| Window | A dip | B hold | C breakout | D momentum |",
          "|---|---|---|---|---|"]
    for i in range(results["A"]["windows"]):
        L.append(f"| {results['_windows'][i]} | " + " | ".join(
            f"${results[k]['per_window'][i]:+,.0f}" for k in "ABCD") + " |")
    L += ["", "### Robustness: nearby settings", "",
          "Same test, rerun across a small grid of settings around each "
          "default. If only the exact default works, the result is luck.",
          "", "| Strategy | Settings tried | Median P/L | Worst | Best | "
          "Settings that beat buy-and-hold |", "|---|---|---|---|---|---|"]
    hold = results["B"]["pnl"]
    for k in "ACD":
        vals = [x["pnl"] for x in grid[k]]
        L.append(f"| {k} | {len(vals)} | ${statistics.median(vals):+,.0f} | "
                 f"${min(vals):+,.0f} | ${max(vals):+,.0f} | "
                 f"{sum(x > hold for x in vals)}/{len(vals)} |")
    L += ["", "### Caveats", "",
          "- **Survivorship bias.** The stock list is today's survivors. That "
          "flatters every stock strategy, and trend-following most of all "
          "(survivors are the stocks that trended up). Comparing C/D against "
          "B on the same list cancels some of it, not all.",
          "- Daily closes only: a real trailing stop can fill worse after an "
          "overnight gap.",
          "- Positions still open at a window's end are valued at the last "
          "close, without the selling fee.",
          "- Nine windows is a small sample."]
    return "\n".join(L) + "\n"


def main():
    from backtest import universe
    os.makedirs(OUT, exist_ok=True)
    data, spy, dates = load(universe())
    results, grid = {}, {}
    wins_labels = None
    for k in "ABCD":
        w = evaluate(k, DEFAULTS[k], data, spy, dates)
        wins_labels = [x["test"] for x in w]
        results[k] = summarize(w)
        if k != "B":
            grid[k] = [dict(p, pnl=summarize(evaluate(k, p, data, spy,
                                                      dates))["pnl"])
                       for p in combos(k)]
    results["_windows"] = wins_labels
    text = report(results, grid, len(data), dates)
    with open(os.path.join(OUT, f"{EXP_ID}.md"), "w") as f:
        f.write(text)
    with open(os.path.join(OUT, f"{EXP_ID}.json"), "w") as f:
        json.dump({"id": EXP_ID, "run": dt.date.today().isoformat(),
                   "hypothesis": "Trend/momentum entries with trailing "
                   "exits beat the dip strategy and buy-and-hold on unseen "
                   "windows.", "defaults": DEFAULTS, "grids": GRIDS,
                   "costs": {"fee": FEE, "slippage": SLIP, "bet": BET},
                   "results": results, "robustness": grid}, f, indent=1)
    print(text)


# ---------------------------------------------------------------- selftest

def selftest():
    import backtest
    import strategy
    # A in this engine must match the main backtest engine exactly.
    c = [100.0] * 60 + [90, 111, 111, 100, 90, 80, 100, 102, 125, 125]
    n = len(c)
    s = {"c": c, "v": [1.0] * n, "h": c, "l": c}
    s["ind"] = indicators(c, s["v"], c, c)
    path, trades, _ = sleeve("A", DEFAULTS["A"], s, 60, n)
    ref = backtest.run(c, strategy.rules_from(8, 20, 10), start=60)
    assert abs(path[-1] - ref["pnl"]) < 0.02, (path[-1], ref["pnl"])
    # Trailing stop: rises to 150 then falls 10% -> sells at 135.
    c = [100.0] * 70 + [110, 130, 150, 140, 135, 120]
    v = [1.0] * 70 + [5.0] * 6
    s = {"c": c, "v": v, "h": c, "l": c}
    s["ind"] = indicators(c, v, c, c)
    path, trades, _ = sleeve("C", DEFAULTS["C"], s, 60, len(c))
    assert len(trades) == 1 and not trades[0].get("open"), trades
    exp = (99 / 110.11) * 135 * 0.999 - 1 - 100
    assert abs(trades[0]["pnl"] - exp) < 0.01, (trades[0], exp)
    # Buy and hold: bought on the first day, open at the end.
    path, trades, held = sleeve("B", {}, s, 60, len(c))
    assert trades[0].get("open") and held == len(c) - 61, (trades, held)
    print("selftest OK")


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else main()
