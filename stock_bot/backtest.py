#!/usr/bin/env python3
"""Deterministic backtests, trade-by-trade explanations, walk-forward tests.

Same rules as the live bot (strategy.py), same costs as the practice
account ($1 fee per trade, fills 0.1% worse than the quote). Daily closes
only, so a real intraday stop can fill better or (after a gap) worse.

  python stock_bot/backtest.py --why            # why do the rules trail holding?
  python stock_bot/backtest.py --walk-forward   # does tuning survive unseen months?
  python stock_bot/backtest.py --selftest

Reports land in stock_bot/research/.
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
import strategy  # noqa: E402

OUT = os.path.join(HERE, "research")
BET, FEE, SLIP = 100.0, 1.0, 0.001


# ------------------------------------------------------------------ engine

def run(closes, rules, start=20, end=None, dates=None, bet=BET, fee=FEE,
        slip=SLIP):
    """Replay the rules over closes[start:end], one position at a time.

    Entries need 20 prior closes for the 20-day high, so pass history
    before `start`. Returns a dict with every trade and the totals. The
    same inputs always give the same result."""
    end = len(closes) if end is None else end
    dates = dates or [str(i) for i in range(len(closes))]
    trades, pos = [], None
    in_market = 0
    for i in range(max(start, 20), end):
        c = closes[i]
        if pos is None:
            if strategy.buy_reason(c, max(closes[i - 20:i]), rules):
                fill = c * (1 + slip)
                pos = {"i": i, "qty": (bet - fee) / fill, "fill": fill,
                       "fee": fee,
                       "entry": bet / ((bet - fee) / fill)}  # fee-inclusive
            continue
        in_market += 1
        hit = strategy.sell_reason(c, pos["entry"], rules)
        if hit:
            trades.append(_close(pos, i, c, hit[0], closes, dates, fee, slip))
            pos = None
    if pos is not None:
        trades.append(_close(pos, end - 1, closes[end - 1], "still_open",
                             closes, dates, 0.0, 0.0))
    days = max(1, end - max(start, 20))
    pnl = sum(t["pnl"] for t in trades)
    closed = [t for t in trades if t["reason"] != "still_open"]
    wins = [t["pnl"] for t in closed if t["pnl"] > 0]
    losses = [t["pnl"] for t in closed if t["pnl"] <= 0]
    first = max(start, 20)
    return {
        "trades": trades,
        "pnl": round(pnl, 2),
        "n": len(closed),
        "wins": len(wins),
        "avg_win": round(statistics.mean(wins), 2) if wins else 0.0,
        "avg_loss": round(statistics.mean(losses), 2) if losses else 0.0,
        "profit_factor": (round(sum(wins) / -sum(losses), 2)
                          if losses and sum(losses) < 0 else None),
        "fees": round(sum(t["costs"] for t in trades), 2),
        "exposure": round(in_market / days, 3),
        "hold_pnl": round(bet * (closes[end - 1] / closes[first] - 1), 2),
    }


def _close(pos, i, c, reason, closes, dates, fee, slip):
    fill = c * (1 - slip)
    proceeds = pos["qty"] * fill - fee
    after = [x for x in closes[i:i + 21] if x is not None]
    return {
        "entry_date": dates[pos["i"]], "exit_date": dates[i],
        "entry_price": round(pos["fill"], 4), "exit_price": round(fill, 4),
        "reason": reason, "days_held": i - pos["i"],
        "pnl": round(proceeds - BET, 2),
        "costs": round(pos["fee"] + fee
                       + pos["qty"] * (pos["fill"] - closes[pos["i"]])
                       + pos["qty"] * (c - fill), 2),
        # What the stock did in the 20 days after we sold: money left on
        # the table (take-profit) or dodged (stop-loss).
        "next_20d_pct": (round((max(after) / c - 1) * 100, 1)
                         if reason == "take_profit" and len(after) > 1 else
                         round((after[-1] / c - 1) * 100, 1)
                         if len(after) > 1 else None),
    }


# ------------------------------------------------------------------- data

def load(symbols, rng="1y"):
    from screener import fetch
    out = {}
    for s in symbols:
        bars = fetch(s, rng)
        if len(bars) >= 80:
            out[s] = ([b["close"] for b in bars], [b["date"] for b in bars])
        time.sleep(0.25)
    return out


def universe():
    """The stocks that passed today's screen (price and volume filters),
    so research runs on the same list the council picks from."""
    path = os.path.join(HERE, "screen", "latest.json")
    if os.path.exists(path):
        with open(path) as f:
            return [r["symbol"] for r in json.load(f)["stocks"]]
    from screener import read_universe
    return read_universe()


# -------------------------------------------------------------- attribution

def why(data, rules, label):
    """Break the gap between the rules and just holding into causes."""
    rows, all_trades = [], []
    for sym, (closes, dates) in sorted(data.items()):
        r = run(closes, rules, dates=dates)
        for t in r["trades"]:
            t["symbol"] = sym
        all_trades += r["trades"]
        rows.append((sym, r))
    by_reason = {}
    for t in all_trades:
        b = by_reason.setdefault(t["reason"], {"n": 0, "pnl": 0.0})
        b["n"] += 1
        b["pnl"] += t["pnl"]
    rules_total = sum(r["pnl"] for _, r in rows)
    hold_total = sum(r["hold_pnl"] for _, r in rows)
    costs = sum(t["costs"] for t in all_trades)
    exposure = statistics.mean(r["exposure"] for _, r in rows)
    tp = [t for t in all_trades if t["reason"] == "take_profit"
          and t["next_20d_pct"] is not None]
    sl = [t for t in all_trades if t["reason"] == "stop_loss"
          and t["next_20d_pct"] is not None]
    never = [s for s, r in rows if not r["trades"]]
    return {
        "label": label, "rules": rules, "stocks": len(rows),
        "rules_total": round(rules_total, 2),
        "hold_total": round(hold_total, 2),
        "by_reason": {k: {"n": v["n"], "pnl": round(v["pnl"], 2)}
                      for k, v in by_reason.items()},
        "costs": round(costs, 2),
        "avg_exposure": round(exposure, 3),
        "never_bought": never,
        "tp_left_on_table_median": (statistics.median(
            t["next_20d_pct"] for t in tp) if tp else None),
        "sl_after_median": (statistics.median(
            t["next_20d_pct"] for t in sl) if sl else None),
        "sl_recovered_share": (round(sum(t["next_20d_pct"] > 0 for t in sl)
                                     / len(sl), 2) if sl else None),
        "per_stock": {s: {k: r[k] for k in ("pnl", "hold_pnl", "n", "wins",
                                             "exposure", "fees")}
                      for s, r in rows},
        "trades": all_trades,
    }


def why_report(res):
    br = res["by_reason"]
    line = lambda k, name: (f"- **{name}:** {br[k]['n']} trades, "
                            f"${br[k]['pnl']:+,.0f}") if k in br else None
    parts = [
        f"### {res['label']} — dip {res['rules']['buy_dip_pct']}% / "
        f"take-profit {res['rules']['take_profit_pct']}% / stop "
        f"{res['rules']['stop_loss_pct']}%", "",
        f"Rules **${res['rules_total']:+,.0f}** vs just holding "
        f"**${res['hold_total']:+,.0f}** across {res['stocks']} stocks "
        f"($100 each, costs included).", "",
        "Where the rules' money came from:",
    ]
    parts += [l for l in (line("take_profit", "Take-profit sells"),
                          line("stop_loss", "Stop-loss sells"),
                          line("sell_above", "Sell-above sells"),
                          line("still_open", "Still holding at the end"))
              if l]
    parts += [
        "", "Why it trails holding:",
        f"- **Sitting in cash:** on average the money was in a stock only "
        f"{res['avg_exposure'] * 100:.0f}% of the days. Holding is in 100% "
        f"of them. {len(res['never_bought'])} stocks never dipped enough to "
        "buy at all.",
        f"- **Costs:** fees and slippage took ${res['costs']:,.0f}.",
    ]
    if res["tp_left_on_table_median"] is not None:
        parts.append(
            f"- **Selling winners early:** after a take-profit sale, the "
            f"typical stock rose another {res['tp_left_on_table_median']}% "
            "at some point in the next 20 days.")
    if res["sl_after_median"] is not None:
        parts.append(
            f"- **Stop-losses:** {res['sl_recovered_share'] * 100:.0f}% of "
            "stopped-out stocks were higher 20 days later (typical move "
            f"{res['sl_after_median']:+}%). The rest kept falling, which is "
            "what the stop is for.")
    return "\n".join(parts)


# ------------------------------------------------------------ walk-forward

GRID = {"dip": [4, 6, 8, 10, 12, 15], "take_profit": [6, 10, 15, 20, 30],
        "stop_loss": [5, 8, 10, 15, 100]}  # 100 = effectively no stop


def align(data):
    """Line every stock up on SPY's trading calendar (None = no data that
    day, e.g. before a newer stock listed)."""
    cal = data["SPY"][1]
    out = {}
    for s, (closes, dates) in data.items():
        by = dict(zip(dates, closes))
        out[s] = ([by.get(d) for d in cal], cal)
    return out


def covered(c, lo, hi):
    return all(x is not None for x in c[max(0, lo - 20):hi])


def score(data, rules, lo, hi):
    """Total P/L of the rules across stocks with full data for [lo, hi)."""
    return sum(run(c, rules, start=lo, end=hi)["pnl"]
               for s, (c, _) in data.items()
               if s != "SPY" and covered(c, lo, hi))


def walk_forward(data, train=126, test=63):
    """Pick the best rules on `train` days, then judge them on the next
    `test` days they never saw. Slide forward by `test` and repeat.
    Each window uses only the stocks that traded through all of it."""
    data = align(data)
    n = len(data["SPY"][0])
    combos = [strategy.rules_from(*c) for c in itertools.product(
        GRID["dip"], GRID["take_profit"], GRID["stop_loss"])]
    default = strategy.rules_from(8, 20, 10)
    spy = data.get("SPY")
    windows = []
    lo = 20
    while lo + train + test <= n:
        tr_lo, tr_hi, te_hi = lo, lo + train, lo + train + test
        best = max(combos, key=lambda r: score(data, r, tr_lo, tr_hi))
        stocks = {s: v for s, v in data.items()
                  if s != "SPY" and covered(v[0], tr_lo, te_hi)}
        test_best = sum(run(c, best, start=tr_hi, end=te_hi)["pnl"]
                        for c, _ in stocks.values())
        test_default = sum(run(c, default, start=tr_hi, end=te_hi)["pnl"]
                           for c, _ in stocks.values())
        test_hold = sum(BET * (c[te_hi - 1] / c[tr_hi] - 1)
                        for c, _ in stocks.values())
        spy_hold = (BET * len(stocks) * (spy[0][te_hi - 1] / spy[0][tr_hi]
                                         - 1)) if spy else None
        dates = next(iter(data.values()))[1]
        windows.append({
            "train": f"{dates[tr_lo]} → {dates[tr_hi - 1]}",
            "test": f"{dates[tr_hi]} → {dates[te_hi - 1]}",
            "stocks": len(stocks),
            "best_on_train": {"dip": best["buy_dip_pct"],
                              "take_profit": best["take_profit_pct"],
                              "stop_loss": best["stop_loss_pct"]},
            "train_pnl": round(score(data, best, tr_lo, tr_hi), 2),
            "test_tuned": round(test_best, 2),
            "test_default": round(test_default, 2),
            "test_hold": round(test_hold, 2),
            "test_spy": round(spy_hold, 2) if spy_hold is not None else None,
        })
        lo += test
    return windows



def wf_report(windows, n_stocks):
    lines = [
        "| Tuned on | Tested on (unseen) | Stocks | Best rules on training "
        "(dip/TP/SL) | Training P/L | Test: tuned | Test: default 8/20/10 "
        "| Test: hold stocks | Test: hold SPY |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for w in windows:
        b = w["best_on_train"]
        sl = "none" if b["stop_loss"] >= 100 else f"{b['stop_loss']}%"
        lines.append(
            f"| {w['train']} | {w['test']} | {w['stocks']} | "
            f"{b['dip']}/{b['take_profit']}/"
            f"{sl} | ${w['train_pnl']:+,.0f} | ${w['test_tuned']:+,.0f} | "
            f"${w['test_default']:+,.0f} | ${w['test_hold']:+,.0f} | "
            + (f"${w['test_spy']:+,.0f}" if w["test_spy"] is not None
               else "—") + " |")
    tot = lambda k: sum(w[k] for w in windows if w[k] is not None)
    tuned, default, hold = tot("test_tuned"), tot("test_default"), \
        tot("test_hold")
    spy = tot("test_spy")
    beat = sum(w["test_tuned"] > w["test_hold"] for w in windows)
    shrink = [w["test_tuned"] / w["train_pnl"] for w in windows
              if w["train_pnl"] > 0]
    lines += [
        "",
        f"**Unseen months, all windows added up (up to {n_stocks} stocks, "
        f"$100 each): tuned rules ${tuned:+,.0f} · default rules "
        f"${default:+,.0f} · holding the stocks ${hold:+,.0f} · holding "
        f"SPY ${spy:+,.0f}.**",
        f"Tuned rules beat holding the stocks in {beat} of {len(windows)} "
        "test windows.",
    ]
    if shrink:
        lines.append(
            "On average the tuned rules kept "
            f"{statistics.mean(shrink) * 100:.0f}% of their training profit "
            "once tested on months they hadn't seen. The gap is how much "
            "of the tuning was fitting noise.")
    return "\n".join(lines)


# -------------------------------------------------------------------- main

def main():
    os.makedirs(OUT, exist_ok=True)
    today = dt.date.today().isoformat()
    if "--why" in sys.argv:
        data = load(universe(), "1y")
        from screener import DEFAULT_RULES
        default = strategy.rules_from(DEFAULT_RULES["dip"],
                                      DEFAULT_RULES["take_profit"],
                                      DEFAULT_RULES["stop_loss"])
        res = why(data, default, "Default rules")
        with open(os.path.join(OUT, "why-trades.json"), "w") as f:
            json.dump(res, f, indent=1)
        text = (f"# Why the rules trail holding — {today}\n\n"
                "Past year, daily closes, $100 per buy, $1 fee per trade "
                "and 0.1% slippage (the practice account's costs).\n\n"
                + why_report(res) + "\n\nEvery trade is in "
                "`why-trades.json`.\n")
        with open(os.path.join(OUT, "why.md"), "w") as f:
            f.write(text)
        print(text)
    if "--walk-forward" in sys.argv:
        data = load(universe() + ["SPY"], "3y")
        windows = walk_forward(data)
        n = len(data) - ("SPY" in data)
        with open(os.path.join(OUT, "walk-forward.json"), "w") as f:
            json.dump({"generated": today, "grid": GRID, "windows": windows},
                      f, indent=1)
        text = (f"# Walk-forward test — {today}\n\n"
                "Each row: find the best rules on 6 months of history, then "
                "test them on the next 3 months, which they never saw. Then "
                "slide forward 3 months and repeat. Only the test columns "
                "count. Same rules for every stock, costs included, daily "
                "closes.\n\n" + wf_report(windows, n) +
                "\n\nCaveat: the stock list was hand-picked from names that "
                "exist today (survivorship bias), which flatters every "
                "column except SPY.\n")
        with open(os.path.join(OUT, "walk-forward.md"), "w") as f:
            f.write(text)
        print(text)


def selftest():
    r = strategy.rules_from(8, 20, 10)
    # Dip 10% then +23%: one winning trade; costs eat ~$3 of it. (+21%
    # wouldn't do: after costs that's only +19.8%, short of the target.)
    closes = [100.0] * 25 + [90, 111] + [111] * 5
    out = run(closes, r)
    t = out["trades"][0]
    assert out["n"] == 1 and t["reason"] == "take_profit", out
    assert 19 < t["pnl"] < 23 and t["costs"] > 2, t
    # Same inputs, same answer.
    assert run(closes, r) == out
    # Crash: dip rule buys twice, stop fires twice.
    out = run([100.0] * 25 + [90, 85, 80, 70, 60], r)
    assert out["n"] == 2 and out["wins"] == 0, out
    # Start/end window: no entries before `start`.
    out = run([100.0] * 25 + [90] + [100] * 10 + [90, 109], r, start=30)
    assert out["trades"][0]["entry_date"] == "36", out
    # Exposure counts days held.
    out = run([100.0] * 25 + [90] + [95] * 9, r)
    assert out["exposure"] == 0.6 and out["trades"][0]["reason"] == \
        "still_open", out
    print("selftest OK")


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else main()
