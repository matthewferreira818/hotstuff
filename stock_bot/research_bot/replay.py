#!/usr/bin/env python3
"""History replay + walk-forward: weak ideas die in days, not months.
PRACTICE / RESEARCH ONLY: no orders of any kind.

For every idea in ideas.py, every setting in its grid, and every horizon:
  1. walk through years of real past prices bar by bar; at each bar the idea
     sees ONLY prices up to that bar (ideas.History refuses to look ahead) and
     makes a call or not; the trade enters at the NEXT bar's open and exits at
     the open `horizon` bars later (prices a trade could really have got);
  2. walk-forward: pick the setting with the best Brier on a training window,
     then score that setting on the next window it never saw; slide and repeat.
     Only the unseen (test) windows count;
  3. grade the unseen calls the same way the forward scorer does: Brier vs coin
     flip / base rate / tomorrow = today, and $100 practice trades on 'up'
     calls with the practice broker's fee + slippage math, vs holding the
     benchmark (SPY / Bitcoin) over the same windows with the same money;
  4. apply the six-condition gate (stock-council SKILL.md) as far as history
     can: 20+ trades, beats holding after costs, the typical trade beats
     holding, no trade lost more than 2x its expected move, most unseen
     windows won. Condition 6 (the practice desk ahead of SPY) is forward-only.
     An idea PASSES the replay only if all of that holds AND its Brier beats all
     three baselines. Everything else is DEAD.

Every (idea, horizon) tried is logged in replay-log.jsonl (append-only) and
counted. Stocks and crypto are separate runs with separate verdicts.

  python3 -m stock_bot.research_bot.replay                 # both markets
  python3 -m stock_bot.research_bot.replay --market crypto --ideas momentum
"""

import argparse
import bisect
import datetime as dt
import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))

import forecasts as ledger  # noqa: E402
import ideas as idea_lib  # noqa: E402
import scorer  # noqa: E402

LOG = os.path.join(HERE, "replay-log.jsonl")
REPORT = os.path.join(HERE, "replay-report.md")
CACHE = os.path.join(HERE, ".cache")
STOCK_BOT = os.path.dirname(HERE)
TRADE = 100.0


def _symbols(path, key):
    try:
        with open(os.path.join(STOCK_BOT, path)) as f:
            d = json.load(f)
        items = d.get(key) or []
        return [s["symbol"] if isinstance(s, dict) else s for s in items]
    except (OSError, ValueError):
        return []


def settings():
    """Replay settings per market. Research config, not live caps, so it
    lives here and not in the locked rules.json."""
    stocks = list(dict.fromkeys(["SPY", "QQQ"] + _symbols("watchlist.json", "stocks")))
    crypto = _symbols("watchlist-moonshot-crypto.json", "symbols") or ["BTC-USD", "ETH-USD"]
    return {
        # Crypto trades 7 days a week: hourly bars, every day, ~2 years
        # (Yahoo keeps hourly bars for ~730 days). Horizons in hours.
        "crypto": {"interval": "1h", "days": 720, "horizons": [4, 24],
                   "train_days": 60, "test_days": 30, "assets": crypto,
                   "benchmark": "BTC-USD", "warmup": 500},
        # Stocks: daily bars over ~5 years. Horizons in trading days.
        "stock": {"interval": "1d", "days": 5 * 365, "horizons": [1, 5],
                  "train_days": 365, "test_days": 91, "assets": stocks,
                  "benchmark": "SPY", "warmup": 120},
    }


# ------------------------------------------------------------------- data

def load_bars(asset, interval, days, now=None, cache=CACHE):
    """[(unix_ts, open, close)] oldest first. Cached on disk for a day
    (the cache folder is git-ignored)."""
    now = now or ledger.utcnow()
    os.makedirs(cache, exist_ok=True)
    path = os.path.join(cache, f"{asset}-{interval}-{days}.json")
    if os.path.exists(path) and (now.timestamp() - os.path.getmtime(path)) < 86400:
        with open(path) as f:
            return [tuple(b) for b in json.load(f)]
    bars = []
    # Yahoo serves hourly bars in chunks; ask ~200 days at a time.
    step = dt.timedelta(days=200 if interval == "1h" else 10000)
    start = now - dt.timedelta(days=days)
    while start < now:
        end = min(start + step, now)
        bars += scorer._yahoo(asset, start, end, interval)
        start = end
    out, seen = [], set()
    for b in sorted(bars):
        if b[0] not in seen:
            seen.add(b[0])
            out.append(b)
    with open(path, "w") as f:
        json.dump(out, f)
    return out


# ------------------------------------------------------------------- calls

def downsides(closes, horizon, samples=20):
    """typical_move_pct for every bar at once (same numbers, computed once
    per asset and horizon instead of once per idea setting)."""
    n = len(closes)
    moves = [0.0] * n
    for j in range(horizon, n):
        moves[j] = abs(closes[j] / closes[j - horizon] - 1) if closes[j - horizon] else 0.0
    out = [None] * n
    for i in range(samples * horizon, n):
        out[i] = sum(moves[i - k * horizon] for k in range(samples)) / samples * 100
    return out


def make_rows(name, params, horizon, data, bench, warmup, downs=None):
    """Every call one setting makes over all the assets.
    Row: (t_open, t_resolve, p_up, act, entry, exit, prev_up, downside_pct,
          bench_return)."""
    rows = []
    bmap = {t: o for t, o, _ in bench}
    for asset, bars in data.items():
        ts = [b[0] for b in bars]
        opens = [b[1] for b in bars]
        closes = [b[2] for b in bars]
        dn = (downs or {}).get(asset) or downsides(closes, horizon)
        for i in range(warmup, len(bars) - horizon - 1):
            h = idea_lib.History(closes, i)
            c = idea_lib.call(name, h, params)
            if c is None:
                continue
            direction, prob = c
            j, k = i + 1, i + 1 + horizon
            entry, exit_ = opens[j], opens[k]
            if not entry or not exit_:
                continue
            prev_up = None if j - horizon < 0 else entry > opens[j - horizon]
            b0, b1 = bmap.get(ts[j]), bmap.get(ts[k])
            rows.append((ts[j], ts[k], prob if direction == "up" else 1 - prob,
                         direction == "up", entry, exit_, prev_up,
                         dn[i],
                         (b1 / b0 - 1) if b0 and b1 else None))
    rows.sort()
    return rows


def windows(t_first, t_last, train_days, test_days):
    """[(train_start, train_end, test_end)] as unix times, sliding by the
    test length. Test windows never overlap."""
    out, day = [], 86400
    s = t_first
    while s + (train_days + test_days) * day <= t_last + day:
        out.append((s, s + train_days * day, s + (train_days + test_days) * day))
        s += test_days * day
    return out


def brier_of(rows):
    if not rows:
        return None
    return sum(scorer.brier(r[2], r[5] > r[4]) for r in rows) / len(rows)


def in_range(rows, t0, t1):
    """Rows whose window opens in [t0, t1) and also closes before t1, so a
    training window never uses an outcome from its test window."""
    keys = [r[0] for r in rows]
    lo, hi = bisect.bisect_left(keys, t0), bisect.bisect_left(keys, t1)
    return [r for r in rows[lo:hi] if r[1] <= t1]


# --------------------------------------------------------------- grading

def grade_rows(rows, fees, n_windows_won=0, n_windows=0):
    """Same maths as the forward scorer, on compact replay rows."""
    n = len(rows)
    out = {"calls": n, "windows": n_windows, "windows_won": n_windows_won}
    if not n:
        out.update(brier=None, verdict="DEAD", why=["no calls at all"])
        return out
    ups = [r[5] > r[4] for r in rows]
    by_res = sorted(range(n), key=lambda i: rows[i][1])
    res_times = [rows[i][1] for i in by_res]
    cum = [0]
    for i in by_res:
        cum.append(cum[-1] + ups[i])
    b = {"forecaster": 0.0, "coin_flip": 0.0, "base_rate": 0.0,
         "tomorrow_equals_today": 0.0}
    for i, r in enumerate(rows):
        k = bisect.bisect_right(res_times, r[0])  # outcomes known at open
        p_base = (cum[k] + 1) / (k + 2)
        p_pers = 0.5 if r[6] is None else (scorer.PERSIST_P if r[6] else 1 - scorer.PERSIST_P)
        b["forecaster"] += scorer.brier(r[2], ups[i])
        b["coin_flip"] += 0.25
        b["base_rate"] += scorer.brier(p_base, ups[i])
        b["tomorrow_equals_today"] += scorer.brier(p_pers, ups[i])
    b = {k: v / n for k, v in b.items()}
    hits = sum((r[2] > 0.5) == u for r, u in zip(rows, ups))
    trades = [r for r in rows if r[3]]
    pnl = [scorer.paper_trade(r[4], r[5], TRADE, fees) for r in trades]
    excess = [p - TRADE * r[8] for p, r in zip(pnl, trades) if r[8] is not None]
    blow = [r for p, r in zip(pnl, trades)
            if r[7] is not None and -p / TRADE * 100 > 2 * r[7]]
    out.update(
        brier={k: round(v, 4) for k, v in b.items()}, hits=hits,
        hit_rate=round(hits / n, 4), luck_p_value=scorer.binomial_p_value(hits, n),
        trades=len(trades), pnl=round(sum(pnl), 2),
        hold_same_money=round(sum(TRADE * r[8] for r in trades if r[8] is not None), 2),
        excess=round(sum(excess), 2),
        median_excess=round(statistics.median(excess), 3) if excess else None,
        blow_throughs=len(blow))
    gate = {
        "1. 20+ trades": len(trades) >= 20,
        "2. beats holding the benchmark after costs": bool(excess) and sum(excess) > 0,
        "3. typical trade beats holding (median)": bool(excess) and statistics.median(excess) > 0,
        "4. no loss over 2x its expected move": len(trades) > 0 and not blow,
        "5. wins most unseen windows": n_windows > 0 and n_windows_won * 2 > n_windows,
        "Brier beats all three baselines": all(
            b["forecaster"] < b[k] for k in ("coin_flip", "base_rate", "tomorrow_equals_today")),
    }
    out["gate"] = gate
    out["verdict"] = "PASS" if all(gate.values()) else "DEAD"
    out["why"] = [k for k, v in gate.items() if not v]
    return out


def walk_forward(name, horizon, data, bench, cfg, fees):
    """Pick the best setting on each training window, score it on the next
    unseen window. Returns (graded test result, chosen settings, range)."""
    grid = idea_lib.IDEAS[name]["grid"]
    downs = {a: downsides([b[2] for b in bars], horizon) for a, bars in data.items()}
    all_rows = [make_rows(name, p, horizon, data, bench, cfg["warmup"], downs) for p in grid]
    firsts = [r[0][0] for r in all_rows if r]
    if not firsts:
        return grade_rows([], fees), [], None
    t0 = min(firsts)
    t1 = max(r[-1][1] for r in all_rows if r)
    test, won, chosen = [], 0, []
    wins = windows(t0, t1, cfg["train_days"], cfg["test_days"])
    for a, b, c in wins:
        scores = [brier_of(in_range(rows, a, b)) for rows in all_rows]
        ok = [(s, i) for i, s in enumerate(scores) if s is not None]
        if not ok:
            continue
        best = min(ok)[1]
        chosen.append(grid[best])
        part = in_range(all_rows[best], b, c)
        test += part
        ex = [scorer.paper_trade(r[4], r[5], TRADE, fees) - TRADE * r[8]
              for r in part if r[3] and r[8] is not None]
        won += sum(ex) > 0
    test.sort()
    res = grade_rows(test, fees, won, len(wins))
    span = (ledger.iso(dt.datetime.fromtimestamp(t0, dt.timezone.utc))[:10],
            ledger.iso(dt.datetime.fromtimestamp(t1, dt.timezone.utc))[:10])
    return res, chosen, span


# ----------------------------------------------------------------- running

def run_market(market, cfg, rules, idea_names, loader=load_bars):
    fees = scorer.fee_model(rules["markets"][market]["costs"])
    data = {}
    print(f"[{market}] loading {len(cfg['assets'])} assets", file=sys.stderr, flush=True)
    for a in cfg["assets"]:
        bars = loader(a, cfg["interval"], cfg["days"])
        if len(bars) > cfg["warmup"] + 50:
            data[a] = bars
    bench = data.get(cfg["benchmark"]) or loader(cfg["benchmark"], cfg["interval"], cfg["days"])
    results = []
    for name in idea_names:
        for hz in cfg["horizons"]:
            print(f"  replaying {market} {name} h={hz} ...", file=sys.stderr, flush=True)
            res, chosen, span = walk_forward(name, hz, data, bench, cfg, fees)
            res.update(market=market, idea=name, horizon=hz, interval=cfg["interval"],
                       settings_tried=len(idea_lib.IDEAS[name]["grid"]),
                       assets=len(data), span=span,
                       chosen=chosen[-1] if chosen else None)
            results.append(res)
    return results


def render(results, generated):
    out = ["# History replay (walk-forward) - research only, no orders", "",
           f"_Plain code (replay.py). {generated}. Only unseen test windows count._", "",
           "PASS = all five history checks of the six-condition gate AND a Brier score "
           "better than all three baselines. Condition 6 (practice desk ahead of SPY) is "
           "forward-only. PASS only earns forward forecasting; it is not a reason for real money.", ""]
    for market in ("stock", "crypto"):
        rs = [r for r in results if r["market"] == market]
        if not rs:
            continue
        unit = "trading days" if rs[0]["interval"] == "1d" else "hours"
        out += [f"## {market.title()} ({rs[0]['assets']} assets, "
                f"{rs[0]['span'][0] if rs[0]['span'] else '-'} to "
                f"{rs[0]['span'][1] if rs[0]['span'] else '-'})", "",
                f"| Idea | Horizon ({unit}) | Calls | Brier (coin 0.25) | Base rate | Tomorrow=today "
                "| Trades | P&L after costs | Holding same money | Windows won | Verdict |",
                "|---|---|---|---|---|---|---|---|---|---|---|"]
        for r in rs:
            b = r.get("brier") or {}
            f3 = lambda x: "-" if x is None else f"{x:.4f}"
            out.append(
                f"| {r['idea']} | {r['horizon']} | {r['calls']} | {f3(b.get('forecaster'))} | "
                f"{f3(b.get('base_rate'))} | {f3(b.get('tomorrow_equals_today'))} | "
                f"{r.get('trades', 0)} | ${r.get('pnl', 0):+,.2f} | "
                f"${r.get('hold_same_money', 0):+,.2f} | {r['windows_won']}/{r['windows']} | "
                f"**{r['verdict']}** |")
        out.append("")
        for r in rs:
            if r["verdict"] == "DEAD" and r.get("why"):
                out.append(f"- {r['idea']} @ {r['horizon']}: failed {'; '.join(r['why'])}")
        out.append("")
    n = len(results)
    p = sum(r["verdict"] == "PASS" for r in results)
    out += [f"**{n} idea/horizon combinations tried, {p} passed.** Each one is counted in "
            "replay-log.jsonl. Caveat: the stock list is today's names (survivorship bias "
            "flatters every idea), trades are $100 each with no position cap, and Yahoo's "
            "free hourly history is ~2 years."]
    return "\n".join(out) + "\n"


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--market", default="both", choices=("both", "stock", "crypto"))
    ap.add_argument("--ideas", default=",".join(idea_lib.IDEAS))
    args = ap.parse_args(argv)
    rules = ledger.load_rules()
    names = [n for n in args.ideas.split(",") if n in idea_lib.IDEAS]
    now = ledger.iso(ledger.utcnow())
    results = []
    for market, cfg in settings().items():
        if args.market in ("both", market):
            results += run_market(market, cfg, rules, names)
    with open(LOG, "a") as f:
        for r in results:
            f.write(json.dumps(dict(r, run=now), sort_keys=True, default=str) + "\n")
    text = render(results, now)
    with open(REPORT, "w") as f:
        f.write(text)
    print(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
