#!/usr/bin/env python3
"""EXP-0002: momentum (EXP-0001's strategy D) with idle cash parked in SPY.

Research only; the live bot and Practice Desk are untouched.

Why: in EXP-0001, strategy D made money at every setting tried but had
money in stocks only 28% of the time. The other 72% sat in cash earning
nothing. This test parks that idle cash in SPY instead.

Declared before the run:

  Hypothesis: "D + idle cash in SPY" beats simply holding SPY, on months
  no one tuned for.

  It passes only if ALL of these hold:
    1. More profit than holding SPY over the 9 test windows.
    2. Better risk-adjusted return (Sharpe) than holding SPY.
    3. Beats SPY in at least 5 of the 9 windows.
    4. Most of the 18 nearby settings also beat holding SPY (not luck).

Compared side by side (same windows, same costs):
  SPY      Hold SPY: all the money in SPY, bought once per window.
  D-cash   Momentum, idle money in cash (EXP-0001's D, but each $100 slot
           reinvests its own winnings, so it's comparable with D-SPY).
  D-SPY    Momentum, idle money in SPY. Every switch between SPY and a
           stock is a real order: $1 fee each way.
  STOCKS   Buy and hold all the screened stocks (EXP-0001's B).

Costs: $1 per order; fills 0.1% worse for stocks, 0.02% worse for SPY
(SPY's buy/sell gap is about a penny on a ~$700 share, so 0.1% would
overcharge it). Momentum settings are EXP-0001's D defaults.

  python stock_bot/experiment2.py
  python stock_bot/experiment2.py --selftest
"""

import datetime as dt
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import experiment as e1  # noqa: E402

EXP_ID = "EXP-0002"
SLOT, FEE, SLIP, SPY_SLIP = 100.0, 1.0, 0.001, 0.0002
NAMES = {"SPY": "Just hold SPY", "D-cash": "Momentum, idle cash sits",
         "D-SPY": "Momentum, idle cash in SPY",
         "STOCKS": "Just hold all the stocks"}
ORDER = ["SPY", "D-SPY", "D-cash", "STOCKS"]


def slot(p, s, spy, lo, hi, idle):
    """One stock's $100 slot, reinvesting its own money. `idle` says where
    the money waits between momentum trades: "cash" or "spy"."""
    c, v, ind = s["c"], s["v"], s["ind"]
    cash, spy_qty, pos = SLOT, 0.0, None
    trades, held, path, orders = [], 0, [], 0
    if idle == "spy":
        spy_qty = (cash - FEE) / (spy[lo] * (1 + SPY_SLIP))
        cash, orders = 0.0, 1
    for i in range(lo, hi):
        if pos is None:
            if e1.wants_in("D", p, c, v, ind, i):
                if spy_qty:
                    cash = spy_qty * spy[i] * (1 - SPY_SLIP) - FEE
                    spy_qty, orders = 0.0, orders + 1
                qty = (cash - FEE) / (c[i] * (1 + SLIP))
                pos = {"qty": qty, "cost": cash, "peak": c[i], "i": i,
                       "trail": p["atr_x"] * ind["atr"][i]}
                cash, orders = 0.0, orders + 1
        else:
            held += 1
            pos["peak"] = max(pos["peak"], c[i])
            if c[i] <= pos["peak"] * (1 - pos["trail"] / 100):
                cash = pos["qty"] * c[i] * (1 - SLIP) - FEE
                trades.append({"pnl": cash - pos["cost"],
                               "days": i - pos["i"]})
                pos, orders = None, orders + 1
                if idle == "spy":
                    spy_qty = (cash - FEE) / (spy[i] * (1 + SPY_SLIP))
                    cash, orders = 0.0, orders + 1
        value = cash + spy_qty * spy[i] + (pos["qty"] * c[i] if pos else 0)
        path.append(value - SLOT)
    if pos:
        trades.append({"pnl": pos["qty"] * c[hi - 1] - pos["cost"],
                       "days": hi - 1 - pos["i"], "open": True})
    return path, trades, held, orders


def evaluate(kind, p, data, spy, dates):
    out = []
    for lo, hi in e1.windows(len(dates)):
        stocks = [s for s in data.values() if e1.covered(s["c"], lo, hi)]
        cap = SLOT * len(stocks)
        port, trades, held, orders = [0.0] * (hi - lo), [], 0, 0
        if kind == "SPY":  # one position for the whole pot
            qty = (cap - FEE) / (spy[lo] * (1 + SPY_SLIP))
            port = [qty * spy[i] - cap for i in range(lo, hi)]
            held, orders = len(stocks) * (hi - lo), 1
        elif kind == "STOCKS":
            for s in stocks:
                path, t, h = e1.sleeve("B", {}, s, lo, hi)
                port = [a + b for a, b in zip(port, path)]
                trades += t
                held += h
                orders += 1
        else:
            for s in stocks:
                path, t, h, o = slot(p, s, spy, lo, hi,
                                     "spy" if kind == "D-SPY" else "cash")
                port = [a + b for a, b in zip(port, path)]
                trades += t
                held += h
                orders += o
        out.append({"test": f"{dates[lo]} → {dates[hi - 1]}",
                    "stocks": len(stocks), "capital": cap, "path": port,
                    "trades": trades, "orders": orders,
                    "exposure": held / (len(stocks) * (hi - lo)),
                    "spy_pnl": cap * (spy[hi - 1] / spy[lo] - 1)})
    return out


def summary(wins):
    r = e1.summarize(wins)
    r["orders"] = sum(w["orders"] for w in wins)
    r["fees"] = round(r["orders"] * FEE)  # dollar fees; slippage on top
    return r


def verdict(res, grid):
    d, s = res["D-SPY"], res["SPY"]
    beat_windows = sum(a > b for a, b in zip(d["per_window"],
                                             s["per_window"]))
    robust = sum(x["pnl"] > s["pnl"] for x in grid)
    checks = [
        ("More profit than holding SPY", d["pnl"] > s["pnl"],
         f"${d['pnl']:+,.0f} vs ${s['pnl']:+,.0f}"),
        ("Better risk-adjusted return (Sharpe)", d["sharpe"] > s["sharpe"],
         f"{d['sharpe']} vs {s['sharpe']}"),
        ("Beats SPY in 5+ of 9 windows", beat_windows >= 5,
         f"{beat_windows} of {len(d['per_window'])}"),
        ("Most nearby settings beat SPY", robust > len(grid) / 2,
         f"{robust} of {len(grid)}"),
    ]
    return checks, all(ok for _, ok, _ in checks)


def report(res, grid, checks, passed, n):
    today = dt.date.today().isoformat()
    L = [f"# {EXP_ID}: momentum with idle cash in SPY — {today}", "",
         "**Question:** if the momentum strategy's idle money sits in SPY "
         "instead of cash, does it beat just holding SPY?", "",
         f"**Result: {'PASSED' if passed else 'DID NOT PASS'}** "
         "(all four conditions were set before the run).", "",
         "| Condition | Met? | Numbers |", "|---|---|---|"]
    L += [f"| {name} | {'yes' if ok else 'no'} | {nums} |"
          for name, ok, nums in checks]
    L += ["", f"Up to {n} stocks, $100 slot each (the same total goes into "
          "SPY for the SPY row). $1 per order, 0.1% slippage on stocks, "
          "0.02% on SPY. Same 9 unseen three-month windows as EXP-0001.",
          "", "| Strategy | P/L | Return | Worst drop | Sharpe | Stock trades "
          "| Orders | Fees | Money in stocks | Windows beating SPY |",
          "|---|---|---|---|---|---|---|---|---|---|"]
    for k in ORDER:
        r = res[k]
        L.append(
            f"| {NAMES[k]} | ${r['pnl']:+,.0f} | {r['return_pct']:+.1f}% | "
            f"{r['max_drawdown_pct']}% | {r['sharpe']} | {r['trades']} | "
            f"{r['orders']:,} | ${r['fees']:,} | "
            f"{r['exposure_pct'] if k not in ('SPY',) else 0}% | "
            f"{r['windows_beat_spy'] if k != 'SPY' else '—'}"
            f"{'/' + str(r['windows']) if k != 'SPY' else ''} |")
    L += ["", "### Window by window", "",
          "| Window | " + " | ".join(NAMES[k] for k in ORDER) + " |",
          "|---|" + "---|" * len(ORDER)]
    for i, label in enumerate(res["_windows"]):
        L.append(f"| {label} | " + " | ".join(
            f"${res[k]['per_window'][i]:+,.0f}" for k in ORDER) + " |")
    vals = [x["pnl"] for x in grid]
    L += ["", "### Robustness", "",
          f"Momentum + SPY across {len(vals)} nearby settings: median "
          f"${statistics.median(vals):+,.0f}, worst ${min(vals):+,.0f}, best "
          f"${max(vals):+,.0f}. Holding SPY: ${res['SPY']['pnl']:+,.0f}.",
          "", "### Caveats", "",
          "- The stock list is today's survivors, which flatters the stock "
          "strategies (not SPY).",
          "- Daily closes; stops can fill worse after overnight gaps.",
          "- Nine windows is a small sample.",
          "- Taxes aren't modelled. Every switch in and out of SPY is a "
          "taxable sale outside a TFSA."]
    return "\n".join(L) + "\n"


def main():
    from backtest import universe
    data, spy, dates = e1.load(universe())
    p = e1.DEFAULTS["D"]
    res = {}
    for k in ORDER:
        w = evaluate(k, p, data, spy, dates)
        res[k] = summary(w)
        res["_windows"] = [x["test"] for x in w]
    grid = [dict(q, pnl=summary(evaluate("D-SPY", q, data, spy, dates))["pnl"])
            for q in e1.combos("D")]
    checks, passed = verdict(res, grid)
    text = report(res, grid, checks, passed, len(data))
    os.makedirs(e1.OUT, exist_ok=True)
    with open(os.path.join(e1.OUT, f"{EXP_ID}.md"), "w") as f:
        f.write(text)
    with open(os.path.join(e1.OUT, f"{EXP_ID}.json"), "w") as f:
        json.dump({"id": EXP_ID, "run": dt.date.today().isoformat(),
                   "hypothesis": "Momentum with idle cash in SPY beats "
                   "holding SPY on unseen windows.",
                   "passed": passed,
                   "checks": [{"name": a, "met": b, "numbers": c}
                              for a, b, c in checks],
                   "names": NAMES, "order": ORDER, "settings": p,
                   "costs": {"fee": FEE, "stock_slippage": SLIP,
                             "spy_slippage": SPY_SLIP},
                   "results": res, "robustness": grid}, f, indent=1)
    print(text)


def selftest():
    # Flat SPY and a stock that never qualifies: SPY-idle slot only pays
    # its one $1 SPY purchase plus a sliver of slippage.
    n = 80
    c = [50.0] * n
    s = {"c": c, "v": [1.0] * n, "h": c, "l": c}
    s["ind"] = e1.indicators(c, s["v"], c, c)
    spy = [400.0] * n
    path, trades, held, orders = slot(e1.DEFAULTS["D"], s, spy, 60, n, "spy")
    assert orders == 1 and not trades and -1.1 < path[-1] < -1.0, path[-1]
    # Idle cash in cash: nothing happens, nothing is lost.
    path, *_ = slot(e1.DEFAULTS["D"], s, spy, 60, n, "cash")
    assert path[-1] == 0.0
    # SPY rises 10% while waiting: the SPY-idle slot keeps the gain.
    spy = [400.0] * 61 + [440.0] * (n - 61)
    path, *_ = slot(e1.DEFAULTS["D"], s, spy, 60, n, "spy")
    assert 8.8 < path[-1] < 9.0, path[-1]
    print("selftest OK")


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else main()
