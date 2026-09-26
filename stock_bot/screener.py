#!/usr/bin/env python3
"""Volatility screener + backtest + scorecard for the stock council.

What it can honestly measure:
  - How much each stock HAS been swinging (daily moves, daily range).
    Swings tend to cluster, so recent volatility is a fair guess at
    near-term volatility. It says nothing about direction.
  - What the bot's rules WOULD have done on each stock over the last
    year (daily closes only; a backtest, not a promise).
  - How past council picks actually turned out (the scorecard).

Free data from Yahoo's public chart endpoint; no account or key.
Stdlib only.

Usage:
  python stock_bot/screener.py                # screen universe.txt
  python stock_bot/screener.py --add GME,AMC  # screen extra tickers too
  python stock_bot/screener.py --only TSLA,NVDA
  python stock_bot/screener.py --grade        # scorecard for past picks
  python stock_bot/screener.py --selftest
"""

import datetime as dt
import json
import math
import os
import statistics
import sys
import time
import urllib.error
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
UNIVERSE = os.path.join(HERE, "universe.txt")
OUT_DIR = os.path.join(HERE, "screen")
PICKS = os.path.join(HERE, "council", "picks.jsonl")
SCORECARD = os.path.join(HERE, "council", "scorecard.md")
BENCHMARK = "SPY"

# Too cheap or too thinly traded = easy to get stuck or manipulated.
MIN_PRICE = 5.0
MIN_DOLLAR_VOLUME = 20_000_000

# The bot's default rules (watchlist.json example) and a version sized to
# each stock's own daily swing (sigma = typical daily move, in %).
DEFAULT_RULES = {"dip": 8.0, "take_profit": 20.0, "stop_loss": 10.0}
SCALED = {"dip": 2.5, "take_profit": 3.0, "stop_loss": 3.0}  # x sigma
BET = 100.0  # dollars per simulated buy


# --------------------------------------------------------------------- data

def fetch(symbol, rng="1y"):
    """Daily bars: list of dicts date/high/low/close/volume, oldest first."""
    url = (f"https://query1.finance.yahoo.com/v8/finance/chart/{symbol}"
           f"?range={rng}&interval=1d")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                res = json.load(r)["chart"]["result"][0]
            break
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return []
            time.sleep(2 * (attempt + 1))
        except (urllib.error.URLError, TimeoutError, KeyError, TypeError,
                IndexError, ValueError):
            time.sleep(2 * (attempt + 1))
    else:
        return []
    q = res["indicators"]["quote"][0]
    bars = []
    for i, ts in enumerate(res.get("timestamp") or []):
        c, h, l, v = q["close"][i], q["high"][i], q["low"][i], q["volume"][i]
        if None in (c, h, l, v):
            continue
        bars.append({"date": dt.date.fromtimestamp(ts).isoformat(),
                     "high": h, "low": l, "close": c, "volume": v})
    return bars


# ------------------------------------------------------------------ metrics

def daily_moves(closes):
    return [(b - a) / a * 100 for a, b in zip(closes, closes[1:])]


def sigma(closes):
    """Typical daily move in % (standard deviation of daily returns)."""
    m = daily_moves(closes)
    return statistics.pstdev(m) if len(m) > 2 else 0.0


def atr_pct(bars, n=14):
    """Average true range over n days, as % of price: the typical
    high-to-low distance a day covers, gaps included."""
    trs = []
    for prev, b in zip(bars[-n - 1:], bars[-n:]):
        tr = max(b["high"] - b["low"], abs(b["high"] - prev["close"]),
                 abs(b["low"] - prev["close"]))
        trs.append(tr / b["close"] * 100)
    return sum(trs) / len(trs) if trs else 0.0


def max_drawdown(closes):
    peak, worst = closes[0], 0.0
    for c in closes:
        peak = max(peak, c)
        worst = min(worst, (c - peak) / peak * 100)
    return worst


def backtest(closes, dip, take_profit, stop_loss, bet=BET):
    """The bot's rules replayed on daily closes, costs included — a thin
    wrapper over backtest.run (the one engine; see backtest.py)."""
    import backtest as engine
    import strategy
    r = engine.run(closes, strategy.rules_from(dip, take_profit, stop_loss),
                   bet=bet)
    return {"trades": r["n"], "wins": r["wins"], "pnl": r["pnl"],
            "open": any(t["reason"] == "still_open" for t in r["trades"]),
            "days_in_market": round(r["exposure"] * max(1, len(closes) - 20))}


def analyze(symbol, bars):
    closes = [b["close"] for b in bars]
    if len(closes) < 80:
        return None
    last = bars[-1]
    s20, s60 = sigma(closes[-21:]), sigma(closes[-61:])
    # One freak day (a buyout, a trial result) inflates sigma60; the smaller
    # of the two is the swing it has kept up — that's what we rank on.
    steady = min(s20, s60)
    dollar_vol = statistics.mean(b["close"] * b["volume"] for b in bars[-20:])
    scaled = {k: round(v * max(steady, 0.5), 1) for k, v in SCALED.items()}
    return {
        "symbol": symbol,
        "price": round(last["close"], 2),
        "as_of": last["date"],
        "sigma20": round(s20, 2),
        "sigma60": round(s60, 2),
        "steady_sigma": round(steady, 2),
        "biggest_day_60d": round(max(daily_moves(closes[-61:]), key=abs), 1),
        "atr_pct": round(atr_pct(bars), 2),
        "dollar_volume_m": round(dollar_vol / 1e6, 1),
        "return_60d": round((closes[-1] / closes[-61] - 1) * 100, 1),
        "return_1y": round((closes[-1] / closes[0] - 1) * 100, 1),
        "max_drawdown_1y": round(max_drawdown(closes), 1),
        "buy_hold_pnl": round(BET * (closes[-1] / closes[20] - 1), 2),
        "bt_default": backtest(closes, **{
            "dip": DEFAULT_RULES["dip"],
            "take_profit": DEFAULT_RULES["take_profit"],
            "stop_loss": DEFAULT_RULES["stop_loss"]}),
        "scaled_rules": scaled,
        "bt_scaled": backtest(closes, scaled["dip"], scaled["take_profit"],
                              scaled["stop_loss"]),
        "passes_filters": (last["close"] >= MIN_PRICE
                           and dollar_vol >= MIN_DOLLAR_VOLUME),
    }


# ------------------------------------------------------------------ outputs

def read_universe():
    with open(UNIVERSE) as f:
        return [l.split("#")[0].strip().upper() for l in f
                if l.split("#")[0].strip()]


def fmt_bt(bt):
    if not bt["trades"] and not bt["open"]:
        return "no trades"
    tail = " +open" if bt["open"] else ""
    return f"${bt['pnl']:+.0f} ({bt['wins']}/{bt['trades']} won{tail})"


def write_report(rows, bench, missing):
    os.makedirs(OUT_DIR, exist_ok=True)
    today = dt.date.today().isoformat()
    ok = sorted((r for r in rows if r["passes_filters"]),
                key=lambda r: r["steady_sigma"], reverse=True)
    cut = [r for r in rows if not r["passes_filters"]]
    with open(os.path.join(OUT_DIR, "latest.json"), "w") as f:
        json.dump({"generated": today, "benchmark": bench,
                   "rules": {"default": DEFAULT_RULES,
                             "scaled_x_sigma60": SCALED, "bet": BET},
                   "stocks": ok, "filtered_out": cut, "missing": missing},
                  f, indent=1)

    lines = [
        f"# Volatility screen — {today}",
        "",
        "Measured, not predicted. **σ** = typical daily move (%), over the "
        "last 20 and 60 trading days; ranked by the smaller of the two, so "
        "one freak day can't top the list. **Big day** = largest single-day "
        "move in 60 days. **ATR** = typical high-to-low range "
        "in a day (%). Backtests replay the bot's rules on the past year of "
        f"daily closes with ${BET:.0f} per buy; they are a sanity check, "
        "not a forecast.",
        "",
    ]
    if bench:
        lines += [f"Benchmark {BENCHMARK}: σ60 {bench['sigma60']}% · 1y "
                  f"{bench['return_1y']:+}% · ${BET:.0f} held all year "
                  f"→ ${bench['buy_hold_pnl']:+.0f}", ""]
    lines += [
        "| # | Stock | Price | σ20 | σ60 | Big day | ATR | $Vol/day | 60d | "
        "1y | Worst drop | Hold $100 | Default rules | "
        "Scaled rules (dip/TP/SL %) |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ]
    for i, r in enumerate(ok, 1):
        s = r["scaled_rules"]
        lines.append(
            f"| {i} | {r['symbol']} | {r['price']} | {r['sigma20']} | "
            f"{r['sigma60']} | {r['biggest_day_60d']:+}% | {r['atr_pct']} | "
            f"${r['dollar_volume_m']:.0f}M | "
            f"{r['return_60d']:+}% | {r['return_1y']:+}% | "
            f"{r['max_drawdown_1y']}% | ${r['buy_hold_pnl']:+.0f} | "
            f"{fmt_bt(r['bt_default'])} | {fmt_bt(r['bt_scaled'])} "
            f"({s['dip']}/{s['take_profit']}/{s['stop_loss']}) |")
    if cut:
        lines += ["", "Filtered out (price under "
                  f"${MIN_PRICE:.0f} or under ${MIN_DOLLAR_VOLUME / 1e6:.0f}M "
                  "traded a day): " + ", ".join(r["symbol"] for r in cut)]
    if missing:
        lines += ["", "No data: " + ", ".join(missing)]
    tot_d = sum(r["bt_default"]["pnl"] for r in ok)
    tot_s = sum(r["bt_scaled"]["pnl"] for r in ok)
    tot_h = sum(r["buy_hold_pnl"] for r in ok)
    lines += ["", f"All {len(ok)} stocks together, ${BET:.0f} each: "
              f"default rules ${tot_d:+,.0f} · scaled rules ${tot_s:+,.0f} · "
              f"just holding ${tot_h:+,.0f}.",
              "", "Caveat: this list was hand-picked from names that are "
              "still around, which flatters every number above."]
    with open(os.path.join(OUT_DIR, "latest.md"), "w") as f:
        f.write("\n".join(lines) + "\n")
    return ok


def screen(symbols):
    rows, missing = [], []
    bench = analyze(BENCHMARK, fetch(BENCHMARK))
    for sym in symbols:
        bars = fetch(sym)
        row = analyze(sym, bars) if bars else None
        (rows.append(row) if row else missing.append(sym))
        time.sleep(0.25)  # be polite to a free endpoint
    ok = write_report(rows, bench, missing)
    print(f"Screened {len(symbols)}: {len(ok)} pass filters, "
          f"{len(rows) - len(ok)} filtered out, {len(missing)} no data.")
    print("Wrote stock_bot/screen/latest.md and latest.json")


# ---------------------------------------------------------------- scorecard

def grade():
    """How did each past pick actually go? The honest test is two-part:
    did it really turn out volatile (the thing we claim to predict), and
    would the rules have made money vs just holding SPY."""
    if not os.path.exists(PICKS):
        print("No picks logged yet.")
        return
    with open(PICKS) as f:
        picks = [json.loads(l) for l in f if l.strip()]
    cache = {}

    def bars_for(sym):
        if sym not in cache:
            cache[sym] = fetch(sym, "2y")
        return cache[sym]

    rows, vol_hits, rule_total, hold_total, spy_total = [], 0, 0.0, 0.0, 0.0
    graded = 0
    for p in picks:
        bars = [b for b in bars_for(p["symbol"]) if b["date"] >= p["date"]]
        spy = [b for b in bars_for(BENCHMARK) if b["date"] >= p["date"]]
        if len(bars) < 6 or len(spy) < 6:
            rows.append(f"| {p['date']} | {p['symbol']} | too early to grade "
                        f"({len(bars)} trading days) | | | | |")
            continue
        graded += 1
        closes = [b["close"] for b in bars]
        realized = sigma(closes)
        hit = realized >= 0.8 * p["steady_sigma"]
        vol_hits += hit
        r = p["rules"]
        # Warm up the 20-day high with the bars before the pick date.
        before = [b["close"] for b in bars_for(p["symbol"])
                  if b["date"] < p["date"]][-20:]
        bt = backtest(before + closes, r["dip"], r["take_profit"],
                      r["stop_loss"])
        hold = BET * (closes[-1] / closes[0] - 1)
        spy_hold = BET * (spy[-1]["close"] / spy[0]["close"] - 1)
        rule_total += bt["pnl"]
        hold_total += hold
        spy_total += spy_hold
        rows.append(
            f"| {p['date']} | {p['symbol']} | {len(closes)} days | "
            f"{p['steady_sigma']}% → {realized:.2f}% {'✅' if hit else '❌'} | "
            f"{fmt_bt(bt)} | ${hold:+.0f} | ${spy_hold:+.0f} |")
    lines = [
        f"# Stock council scorecard — {dt.date.today().isoformat()}", "",
        "Each pick is graded from the day it was made, with $100 per buy. "
        "✅ means it really did stay volatile (swing at least 80% as big as "
        "predicted).", "",
        "| Picked | Stock | Since | Swing: predicted → actual | Rules would "
        "have made | Just holding it | Holding SPY instead |",
        "|---|---|---|---|---|---|---|",
    ] + rows
    if graded:
        lines += ["", f"**Record: {vol_hits}/{graded} picks stayed "
                  f"volatile. Rules ${rule_total:+,.0f} · holding the picks "
                  f"${hold_total:+,.0f} · holding SPY ${spy_total:+,.0f}.**"]
    lines += ["", *seat_grades(bars_for)]
    os.makedirs(os.path.dirname(SCORECARD), exist_ok=True)
    with open(SCORECARD, "w") as f:
        f.write("\n".join(lines) + "\n")
    print(f"Graded {graded} of {len(picks)} picks → "
          "stock_bot/council/scorecard.md")


def grade_one(bars, spy, date, predicted_sigma):
    """One stock from a council date: did it swing as predicted, and did
    it beat SPY? None until there are 5+ trading days to judge."""
    after = [b["close"] for b in bars if b["date"] > date]
    spy_after = [b["close"] for b in spy if b["date"] > date]
    before = [b["close"] for b in bars if b["date"] <= date]
    spy_before = [b["close"] for b in spy if b["date"] <= date]
    if len(after) < 5 or not before or not spy_before or len(spy_after) < 5:
        return None
    ret = after[-1] / before[-1] - 1
    spy_ret = spy_after[-1] / spy_before[-1] - 1
    realized = sigma([before[-1]] + after)
    return {"excess": (ret - spy_ret) * 100,
            "swung": (realized >= 0.8 * predicted_sigma
                      if predicted_sigma else None)}


def seat_grades(bars_for):
    """Grade every seat on its own picks and vetoes, from the saved vote
    files and the screen as it stood that day."""
    vdir = os.path.join(HERE, "council", "votes")
    sdir = os.path.join(HERE, "council", "screens")
    if not os.path.isdir(vdir):
        return []
    seats = {}
    for name in sorted(os.listdir(vdir)):
        with open(os.path.join(vdir, name)) as f:
            votes = json.load(f)
        date, screen = votes["date"], {}
        spath = os.path.join(sdir, f"{date}.json")
        if os.path.exists(spath):
            with open(spath) as f:
                sj = json.load(f)
            screen = {r["symbol"]: r for r in
                      sj.get("stocks", []) + sj.get("filtered_out", [])}
        for seat, v in votes["seats"].items():
            g = seats.setdefault(seat, {"picks": [], "vetoes": []})
            for kind in ("picks", "vetoes"):
                for item in v.get(kind, []):
                    sym = item["symbol"].upper()
                    r = grade_one(bars_for(sym), bars_for(BENCHMARK), date,
                                  screen.get(sym, {}).get("steady_sigma"))
                    g[kind].append(r)
    lines = ["## Each seat's record", "",
             "Picks: did the stock swing as much as expected, and did it beat "
             "SPY? Vetoes: did the vetoed stock trail SPY (veto was right)?",
             "", "| Seat | Picks graded | Swung as expected | Picks beat SPY "
             "| Avg vs SPY | Vetoes graded | Vetoes right |",
             "|---|---|---|---|---|---|---|"]
    for seat, g in seats.items():
        p = [r for r in g["picks"] if r]
        x = [r for r in g["vetoes"] if r]
        swung = [r["swung"] for r in p if r["swung"] is not None]
        pending = len(g["picks"]) + len(g["vetoes"]) - len(p) - len(x)
        lines.append(
            f"| {seat} | {len(p)} | "
            + (f"{sum(swung)}/{len(swung)}" if swung else "—") + " | "
            + (f"{sum(r['excess'] > 0 for r in p)}/{len(p)}" if p else "—")
            + " | "
            + (f"{statistics.mean(r['excess'] for r in p):+.1f}%" if p
               else "—") + f" | {len(x)} | "
            + (f"{sum(r['excess'] < 0 for r in x)}/{len(x)}" if x else "—")
            + " |" + (f" ({pending} still too early)" if pending else ""))
    return lines


# ----------------------------------------------------------------- selftest

def selftest():
    # Staircase: dips 10%, then jumps 20%+, twice -> two winning trades.
    # (Jumps are 23%+ because costs take ~2% off every round trip.)
    closes = [100.0] * 25 + [90, 111] + [111] * 20 + [98, 121] + [121] * 20
    bt = backtest(closes, 8, 20, 10)
    assert bt["trades"] == 2 and bt["wins"] == 2 and not bt["open"], bt
    # Straight collapse -> the dip rule catches the falling knife twice and
    # the stop-loss fires twice. (A real weakness of dip-buying.)
    bt = backtest([100.0] * 25 + [90, 85, 80, 70, 60], 8, 20, 10)
    assert bt["trades"] == 2 and bt["wins"] == 0 and bt["pnl"] < -20, bt
    assert abs(sigma([100, 110, 99, 108.9, 98.01]) - 10) < 0.01  # ±10%/day
    assert max_drawdown([100, 120, 60, 90]) == -50
    bars = [{"date": f"d{i}", "high": 101, "low": 99, "close": 100,
             "volume": 1e6} for i in range(90)]
    row = analyze("TEST", bars)
    assert row["sigma60"] == 0 and row["atr_pct"] == 2.0, row
    assert row["passes_filters"]  # $100 price, $100M a day
    # Seat grading: stock +10% vs SPY +1% over 6 days after the pick.
    mk = lambda px: [{"date": f"2026-01-{d:02d}", "close": c, "high": c,
                      "low": c, "volume": 1} for d, c in px]
    stock = mk([(1, 100), (2, 104), (3, 98), (4, 106), (5, 101), (6, 108),
                (7, 110)])
    spy = mk([(d, 100 + (d > 1)) for d in range(1, 8)])
    g = grade_one(stock, spy, "2026-01-01", 2.0)
    assert abs(g["excess"] - 9.0) < 1e-9 and g["swung"] is True, g
    assert grade_one(stock, spy, "2026-01-05", 2.0) is None  # too early
    print("selftest OK")


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--selftest" in args:
        selftest()
    elif "--grade" in args:
        grade()
    else:
        def arg(name):
            return ([s.strip().upper() for s in
                     args[args.index(name) + 1].split(",") if s.strip()]
                    if name in args else [])
        syms = arg("--only") or read_universe()
        syms += [s for s in arg("--add") if s not in syms]
        screen(syms)
