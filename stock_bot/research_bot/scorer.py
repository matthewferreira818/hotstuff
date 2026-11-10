#!/usr/bin/env python3
"""The scorer: plain code grades the forecasts. No AI in here, on purpose:
the forecaster never grades itself. PRACTICE MONEY ONLY.

For every forecast whose window has closed it looks up the real price when
the window opened and when it closed (the first hourly bar at or after each
time, so the price is one a trade could actually have got), then reports,
for stocks and crypto SEPARATELY:

  - counts: ideas tried, forecasts, graded, still open, LATE (committed after
    their window opened: listed, never counted), and "no trade" days;
  - hit rate and Brier score (0 = perfect, 0.25 = coin flip, lower is better)
    against three dumb baselines:
      coin flip        - always 50/50 (also what "no change" says about direction)
      base rate        - the share of earlier graded windows that went up,
                         using only results known before this window opened
      tomorrow = today - the next move repeats the last move of the same length
                         (60/40 towards it);
  - paper P&L of the forecasts that asked for a trade, after the same fee +
    slippage model as the practice robots (paper_broker.py), against cash ($0)
    and buying the benchmark (SPY / Bitcoin) with the whole practice account;
    median trade, worst trade, and the total without the best trade;
  - the evidence bar (rules in meeting-room/notes/research-bot.md). It says NO
    until every line is met. Several lines can't be checked by code at all.

Usage:
  python3 -m stock_bot.research_bot.scorer          # writes scorecard.md/.json
  python3 -m stock_bot.research_bot.scorer --print  # also prints it
"""

import datetime as dt
import json
import math
import os
import statistics
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))

import forecasts as ledger  # noqa: E402
from paper_broker import PaperBroker  # noqa: E402

CARD_MD = os.path.join(HERE, "scorecard.md")
CARD_JSON = os.path.join(HERE, "scorecard.json")
PAPER_DIR = os.path.join(os.path.dirname(HERE), "paper")

BAR_MIN_FORECASTS = 100
BAR_MIN_DAYS = 60
PERSIST_P = 0.6


# --------------------------------------------------------------- prices

def _yahoo(asset, start, end, interval="1h"):
    q = urllib.parse.urlencode({"period1": int(start.timestamp()),
                                "period2": int(end.timestamp()),
                                "interval": interval})
    url = (f"https://query1.finance.yahoo.com/v8/finance/chart/"
           f"{urllib.parse.quote(asset)}?{q}")
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                res = json.load(r)["chart"]["result"][0]
            break
        except Exception:
            if attempt == 2:
                return []
            time.sleep(2 * (attempt + 1))
    q = res["indicators"]["quote"][0]
    out = []
    for i, ts in enumerate(res.get("timestamp") or []):
        o, c = q["open"][i], q["close"][i]
        if o is not None and c is not None:
            out.append((ts, float(o), float(c)))
    return out


def yahoo_price_at(asset, when):
    """Open of the first hourly bar starting at or after `when`, within 4
    days (weekends, holidays). None if there isn't one yet."""
    when = ledger.parse_time(when)
    bars = _yahoo(asset, when - dt.timedelta(hours=1), when + dt.timedelta(days=4))
    for ts, o, _ in bars:
        if ts >= when.timestamp():
            return o
    return None


def yahoo_daily_closes(asset, start, end):
    return [c for _, _, c in _yahoo(asset, start, end, "1d")]


# ------------------------------------------------------------- the maths

def brier(p_up, went_up):
    return (p_up - (1.0 if went_up else 0.0)) ** 2


def p_up_of(f):
    p = float(f["probability"])
    return p if f["direction"] == "up" else 1 - p


def binomial_p_value(hits, n):
    """One-sided chance of at least `hits` right out of `n` by coin flipping.
    Small n -> big p: luck explains it."""
    if n == 0:
        return 1.0
    return sum(math.comb(n, k) for k in range(hits, n + 1)) / 2 ** n


def max_drawdown_pct(closes):
    peak, worst = None, 0.0
    for c in closes:
        peak = c if peak is None or c > peak else peak
        worst = max(worst, (peak - c) / peak * 100 if peak else 0)
    return worst


def fee_model(costs):
    """A PaperBroker that only knows the fees (no account, no network), so the
    scorer charges exactly what the practice robots pay."""
    b = PaperBroker.__new__(PaperBroker)
    b.fee = float(costs.get("fee_min", costs.get("fee_per_trade", 1.0)))
    b.fee_per_share = float(costs.get("fee_per_share", 0.0))
    b.fee_pct = float(costs.get("fee_pct", 0.0)) / 100
    b.slip = float(costs.get("slippage_pct", 0.1)) / 100
    return b


def paper_trade(entry, exit_, dollars, fees):
    """Same steps as PaperBroker.buy then sell_all, from prices alone.
    Returns profit after both fees and slippage."""
    buy_px = entry * (1 + fees.slip)
    fee_in = fees.order_fee((dollars - fees.fee) / buy_px, dollars)
    qty = (dollars - fee_in) / buy_px
    sell_px = exit_ * (1 - fees.slip)
    fee_out = fees.order_fee(qty, qty * sell_px)
    return qty * sell_px - fee_out - dollars


# ---------------------------------------------------------------- grading

def grade(lines, rules, price_at, first_seen, now=None):
    """Returns the scorecard dict. `price_at(asset, time)` and `first_seen`
    (line id -> unix time of its first commit) are passed in so tests run
    offline."""
    now = ledger.parse_time(now or ledger.utcnow())
    forecasts = [l for l in lines if l.get("kind") == "forecast"]
    rows = []
    for f in forecasts:
        opens = ledger.parse_time(f["opens_at"])
        resolves = ledger.parse_time(f["resolves_at"])
        seen = first_seen.get(f["id"])
        row = {"id": f["id"], "market": f["market"], "asset": f["asset"],
               "opens": opens, "resolves": resolves, "act": f.get("act", False),
               "p_up": p_up_of(f), "status": "open"}
        if seen is None:
            row["status"] = "uncommitted" if now < opens else "late"
        elif seen >= opens.timestamp():
            row["status"] = "late"
        elif now >= resolves:
            entry, exit_ = price_at(f["asset"], opens), price_at(f["asset"], resolves)
            if entry and exit_:
                prev = price_at(f["asset"], opens - (resolves - opens))
                row.update(status="graded", entry=entry, exit=exit_,
                           went_up=exit_ > entry,
                           prev_up=None if not prev else entry > prev)
            else:
                row["status"] = "waiting for prices"
        rows.append(row)

    card = {"generated": ledger.iso(now), "markets": {}}
    for market in ledger.MARKETS:
        card["markets"][market] = _market_card(
            market, lines, [r for r in rows if r["market"] == market], rules, now)
    card["rows"] = [{k: (ledger.iso(v) if isinstance(v, dt.datetime) else v)
                     for k, v in r.items()} for r in rows]
    return card


def _market_card(market, lines, rows, rules, now):
    m = rules["markets"][market]
    graded = sorted([r for r in rows if r["status"] == "graded"],
                    key=lambda r: r["resolves"])
    # Base rate: only outcomes already known when this window opened.
    for r in graded:
        known = [g["went_up"] for g in graded if g["resolves"] <= r["opens"]]
        r["p_base"] = (sum(known) + 1) / (len(known) + 2)
        r["p_persist"] = (0.5 if r["prev_up"] is None
                          else PERSIST_P if r["prev_up"] else 1 - PERSIST_P)
    n = len(graded)
    hits = sum((r["p_up"] > 0.5) == r["went_up"] for r in graded)
    mean = lambda xs: sum(xs) / len(xs) if xs else None
    scores = {
        "forecaster": mean([brier(r["p_up"], r["went_up"]) for r in graded]),
        "coin_flip": mean([brier(0.5, r["went_up"]) for r in graded]),
        "base_rate": mean([brier(r["p_base"], r["went_up"]) for r in graded]),
        "tomorrow_equals_today": mean([brier(r["p_persist"], r["went_up"])
                                       for r in graded]),
    }
    # Paper trades: graded forecasts that asked for one (all 'up', long-only).
    fees = fee_model(m["costs"])
    size = rules["start_cash"] * rules["max_position_pct"] / 100
    pnl = [paper_trade(r["entry"], r["exit"], size, fees)
           for r in graded if r["act"]]
    total = sum(pnl)
    hold = None
    if graded:
        start = min(r["opens"] for r in graded)
        end = max(r["resolves"] for r in graded)
        hold = {"start": ledger.iso(start), "end": ledger.iso(end)}
    ideas = [l for l in lines if l.get("kind") == "idea"
             and l.get("market") in (market, "both")]
    created = [ledger.parse_time(l["created"]) for l in lines
               if l.get("market") == market and l.get("created")]
    span = (now - min(created)).days if created else 0
    return {
        "ideas_tried": len(ideas),
        "forecasts": len(rows),
        "graded": n,
        "open": sum(r["status"] in ("open", "uncommitted", "waiting for prices")
                    for r in rows),
        "late_not_counted": sum(r["status"] == "late" for r in rows),
        "no_trade_days": sum(1 for l in lines if l.get("kind") == "no_trade"
                             and l.get("market") == market),
        "hits": hits,
        "hit_rate": hits / n if n else None,
        "luck_p_value": binomial_p_value(hits, n),
        "brier": scores,
        "paper_trades": len(pnl),
        "trade_size": size,
        "paper_pnl": round(total, 2),
        "median_trade": round(statistics.median(pnl), 2) if pnl else None,
        "worst_trade": round(min(pnl), 2) if pnl else None,
        "pnl_without_best": round(total - max(pnl), 2) if pnl else None,
        "cash_pnl": 0.0,
        "hold_window": hold,
        "benchmark": m["benchmark"],
        "span_days": span,
    }


def add_benchmark(card, rules, price_at, daily_closes):
    """Fills in buying the benchmark with the whole account over the graded
    period, and whether a down market happened in it. Separate from grade()
    so tests can skip the network."""
    for market, mc in card["markets"].items():
        m = rules["markets"][market]
        mc["hold_pnl"], mc["down_market_seen"], mc["max_drawdown_pct"] = None, False, None
        if not mc["hold_window"]:
            continue
        s, e = mc["hold_window"]["start"], mc["hold_window"]["end"]
        a, b = price_at(m["benchmark"], s), price_at(m["benchmark"], e)
        if a and b:
            fees = fee_model(m["costs"])
            mc["hold_pnl"] = round(paper_trade(a, b, rules["start_cash"], fees), 2)
        closes = daily_closes(m["benchmark"], ledger.parse_time(s),
                              ledger.parse_time(e))
        if closes:
            mc["max_drawdown_pct"] = round(max_drawdown_pct(closes), 2)
            mc["down_market_seen"] = mc["max_drawdown_pct"] >= m["down_market_drop_pct"]
    return card


def evidence_bar(mc):
    """Every line must be True before anyone may even PROPOSE a tiny live
    pilot. The last three can't be checked by code and stay False here."""
    b = mc["brier"]
    beats = (b["forecaster"] is not None and all(
        b[k] is not None and b["forecaster"] < b[k]
        for k in ("coin_flip", "base_rate", "tomorrow_equals_today")))
    hold = mc.get("hold_pnl")
    return {
        f"{BAR_MIN_FORECASTS}+ graded forecasts": mc["graded"] >= BAR_MIN_FORECASTS,
        f"{BAR_MIN_DAYS}+ days of forward forecasting": mc["span_days"] >= BAR_MIN_DAYS,
        "a down market happened during it": bool(mc.get("down_market_seen")),
        "Brier beats all three baselines": beats,
        "not likely luck (p < 0.05)": mc["luck_p_value"] < 0.05,
        "paper P&L after costs beats cash": mc["paper_trades"] > 0 and mc["paper_pnl"] > 0,
        "paper P&L after costs beats buy-and-hold": (
            hold is not None and mc["paper_trades"] > 0 and mc["paper_pnl"] > hold),
        "typical trade wins (median > 0)": (mc["median_trade"] or 0) > 0,
        "still ahead without the best trade": (mc["pnl_without_best"] or 0) > 0,
        "six-condition gate (stock-council SKILL.md) - human check": False,
        "client #1 has paid - human check": False,
        "Service Canada / EI answer on trading - human check": False,
    }


# ----------------------------------------------------------------- report

def _fmt(x, nd=3):
    return "-" if x is None else (f"{x:.{nd}f}" if isinstance(x, float) else str(x))


def render(card):
    out = ["# Research bot scorecard (PRACTICE MONEY ONLY)", "",
           f"_Made by plain code (scorer.py), not the AI. {card['generated']}._", "",
           "Lower Brier is better: 0 is perfect, 0.25 is a coin flip.", ""]
    for market, mc in card["markets"].items():
        out += [f"## {market.title()}", "",
                f"Ideas tried {mc['ideas_tried']} · forecasts {mc['forecasts']} · "
                f"graded {mc['graded']} · still open {mc['open']} · "
                f"LATE (not counted) {mc['late_not_counted']} · "
                f"no-trade days {mc['no_trade_days']} · span {mc['span_days']} days", ""]
        b = mc["brier"]
        out += ["| Who | Brier |", "|---|---|"]
        for k, label in (("forecaster", "Forecaster"), ("coin_flip", "Coin flip / no change"),
                         ("base_rate", "Base rate"),
                         ("tomorrow_equals_today", "Tomorrow = today")):
            out.append(f"| {label} | {_fmt(b[k])} |")
        out += ["", f"Hit rate {_fmt(mc['hit_rate'], 2)} ({mc['hits']} of {mc['graded']}); "
                f"chance a coin does at least this well: {_fmt(mc['luck_p_value'], 2)}.", ""]
        out += [f"Paper trades {mc['paper_trades']} at ${mc['trade_size']:.0f} each, after fees + slippage: "
                f"**${mc['paper_pnl']:+.2f}** · cash $+0.00 · "
                f"{mc['benchmark']} with the whole ${1000:.0f}: "
                + (f"${mc['hold_pnl']:+.2f}" if mc.get("hold_pnl") is not None else "-")
                + f" · median trade {_fmt(mc['median_trade'], 2)} · worst {_fmt(mc['worst_trade'], 2)}"
                f" · without the best {_fmt(mc['pnl_without_best'], 2)}", ""]
        bar = evidence_bar(mc)
        out += [f"**Evidence bar for even proposing a live pilot: "
                f"{'MET' if all(bar.values()) else 'NOT MET'}**", ""]
        out += [f"- {'yes' if v else 'NO '} - {k}" for k, v in bar.items()]
        out.append("")
    out += ["Stocks and crypto are judged separately: if only one passes, only that one goes on.",
            "\"No trade\" and \"no edge found\" are normal, honest results."]
    return "\n".join(out) + "\n"


def main(argv=None):
    argv = argv or sys.argv[1:]
    rules = ledger.load_rules()
    ok, problems, first_seen = ledger.verify()
    lines = ledger.read_lines()
    card = grade(lines, rules, yahoo_price_at, first_seen)
    card = add_benchmark(card, rules, yahoo_price_at, yahoo_daily_closes)
    card["append_only_ok"], card["append_only_problems"] = ok, problems
    for mc in card["markets"].values():
        mc["evidence_bar"] = evidence_bar(mc)
    text = render(card)
    if not ok:
        text = ("**WARNING: the forecast file was edited, not just appended to. "
                "Results are not trustworthy:** " + "; ".join(problems) + "\n\n" + text)
    with open(CARD_MD, "w") as f:
        f.write(text)
    with open(CARD_JSON, "w") as f:
        json.dump(card, f, indent=1, default=str)
    if "--print" in argv:
        print(text)
    print(f"Scorecard written: {os.path.relpath(CARD_MD)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
