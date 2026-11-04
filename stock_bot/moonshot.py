#!/usr/bin/env python3
"""Robots 4 and 5, "Moonshot": high risk, high reward, practice money.

Matthew's ask (2026-11-04): "a new bot that is all high risk high reward",
with fewer fees. Two copies run on their own practice accounts:
  - stocks (watchlist-moonshot.json): wild stocks and 2-3x leveraged funds,
    priced like a $0-commission broker (slippage only).
  - crypto (watchlist-moonshot-crypto.json): the big coins, 24/7, with a
    0.5% fee per trade (what Matthew's KOHO app charges for crypto).

The rule, checked once an hour:
  - Rank everything by how much it rose over the last `lookback_days`,
    keeping only things above their `trend_days` average (still climbing).
  - Hold the top `max_positions`, all in (cash split evenly).
  - Sell when the price falls `trail_pct` below its best since buying (a
    trailing stop: lets winners run, cuts losers), or when it stops
    climbing (its rise turns negative) after `min_hold_hours`.
Few trades by design: fees ate the other robots.

This has NOT been tested on past data. It's a live experiment and can
lose a lot fast. Never real money; never Moomoo.

Usage:
  python stock_bot/moonshot.py watchlist-moonshot.json
  python stock_bot/moonshot.py --selftest
"""

import datetime as dt
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import live_snapshot  # noqa: E402
import paper_broker  # noqa: E402
import stock_bot  # noqa: E402
from screener import fetch  # noqa: E402


def score(closes, price, lookback, trend):
    """Pure: % rise over `lookback` bars to `price`, or None if it isn't
    above its `trend`-bar average (not climbing) or history is short."""
    if len(closes) < max(lookback, trend) + 1 or not price:
        return None
    avg = sum(closes[-trend:]) / trend
    if price <= avg:
        return None
    return (price / closes[-lookback - 1] - 1) * 100


def decide(cfg, prices, scores, held, cash, now_ts):
    """Pure. held = {sym: {"peak", "bought_ts"}}. Returns (sells, buys):
    sells = [(sym, why)], buys = [(sym, dollars)]."""
    r = cfg["rules"]
    sells = []
    for sym, h in held.items():
        price = prices.get(sym)
        if not price:
            continue
        peak = max(h["peak"], price)
        hours = (now_ts - h["bought_ts"]) / 3600
        if price <= peak * (1 - r["trail_pct"] / 100):
            sells.append((sym, f"fell {r['trail_pct']}% from its best "
                               f"({peak:.4g}), trailing stop"))
        elif hours >= r["min_hold_hours"] and (scores.get(sym) is None
                                               or scores[sym] < 0):
            sells.append((sym, "stopped climbing"))
    sold = {s for s, _ in sells}
    open_after = len(held) - len(sold)
    slots = r["max_positions"] - open_after
    buys = []
    if slots <= 0:
        return sells, buys
    ranked = sorted(((sc, s) for s, sc in scores.items()
                     if sc is not None and sc >= r["min_rise_pct"]
                     and s not in held and prices.get(s)), reverse=True)
    pick = [s for _, s in ranked[:slots]]
    # Cash from today's sales arrives after they fill; split what's free.
    if pick:
        each = cash / slots
        for s in pick:
            if each >= cfg["sizing"]["min_bet"]:
                buys.append((s, round(each, 2)))
    return sells, buys


def run(cfg_name):
    cfg_path = os.path.join(HERE, cfg_name)
    with open(cfg_path) as f:
        cfg = json.load(f)
    acct_path = os.path.join(HERE, "paper", cfg["account_file"])
    broker = paper_broker.PaperBroker(cfg.get("paper_costs"), acct_path)
    label, bench, r = cfg["label"], cfg["benchmark"], cfg["rules"]
    syms = cfg["symbols"]
    crypto = cfg.get("market") == "crypto"
    events = broker.acct.setdefault("events", [])

    def event(text, kind="info"):
        events.append({"time": paper_broker._now(), "kind": kind, "text": text})
        del events[:-40]
        print(text if kind != "quiet" else "quiet")

    market_open = True if crypto else bool(broker.clock().get("is_open"))
    held_syms = list(broker.acct["positions"])
    prices = broker.latest_prices(list(dict.fromkeys(syms + held_syms + [bench])))
    acct = broker.acct
    if "bench_units" not in acct and prices.get(bench):
        acct["bench_units"] = acct["deposited"] / prices[bench]
        event(f"{label} robot started with {paper_broker.START_CASH:,.0f} "
              f"practice dollars.", "start")

    scores, closes_by = {}, {}
    if market_open and not cfg.get("paused"):
        for s in dict.fromkeys(syms + held_syms):
            try:
                bars = fetch(s, "3mo")
            except Exception:
                continue
            # Today's bar is still forming: rank on finished days + live price.
            closes = [b["close"] for b in bars if b["date"] <
                      dt.datetime.now(dt.timezone.utc).date().isoformat()]
            closes_by[s] = closes
            scores[s] = score(closes, prices.get(s), r["lookback_days"],
                              r["trend_days"])
        held = {}
        for s, p in acct["positions"].items():
            if prices.get(s):
                p["peak"] = max(p.get("peak", 0), prices[s])
            held[s] = {"peak": p.get("peak", p["avg_entry_price"]),
                       "bought_ts": dt.datetime.fromisoformat(
                           p.get("bought", paper_broker._now())).timestamp()}
        now_ts = dt.datetime.now(dt.timezone.utc).timestamp()
        sells, _ = decide(cfg, prices, scores, held, broker.cash(), now_ts)
        done = []
        for s, why in sells:
            try:
                entry = acct["positions"][s].get("fill", acct["positions"][s]["avg_entry_price"])
                broker.sell_all(s)
                o = acct["orders"][-1]
                gain = (o["price"] / entry - 1) * 100
                event(f"Sold {s} at {o['price']:.4g} ({gain:+.1f}%): {why}", "sell")
                done.append(f"SELL {s} {gain:+.1f}%: {why}")
            except RuntimeError as e:
                event(f"Sell {s} didn't go through: {e}", "error")
        held = {s: held[s] for s in acct["positions"] if s in held}
        _, buys = decide(cfg, prices, scores, held, broker.cash(), now_ts)
        for s, dollars in buys:
            try:
                broker.buy(s, dollars)
                o = acct["orders"][-1]
                p = acct["positions"][s]
                p.update(fill=o["price"], peak=o["price"],
                         bought=paper_broker._now())
                event(f"Bought {s} ${dollars:,.2f} at {o['price']:.4g}: up "
                      f"{scores[s]:.1f}% in {r['lookback_days']} days, the "
                      "hottest on the list", "buy")
                done.append(f"BUY {s} ${dollars:,.2f}")
            except RuntimeError as e:
                event(f"Buy {s} didn't go through: {e}", "error")
        if done:
            stock_bot.notify(f"{label} robot (practice): {len(done)} trade(s)",
                             "\n".join(done))
        else:
            event(f"Checked {len(syms)}. Holding steady.", "quiet")
        broker._save(f"{label}: hourly check")

    # ------------------------------------------------------ live page
    positions = broker.positions()
    held_value = sum(x["market_value"] for x in positions.values())
    pos_rows = []
    for s, x in positions.items():
        raw = acct["positions"][s]
        price = prices.get(s) or raw["avg_entry_price"]
        fill = raw.get("fill", raw["avg_entry_price"])
        peak = raw.get("peak", fill)
        pos_rows.append({"symbol": s, "price": price, "entry": fill,
                         "value": x["market_value"], "peak": peak,
                         "change_pct": round((price / fill - 1) * 100, 2),
                         "stop": peak * (1 - r["trail_pct"] / 100)})
    lead = sorted(((v, s) for s, v in scores.items() if v is not None),
                  reverse=True)[:8]
    bu = acct.get("bench_units")
    snap = {
        "robot": cfg["robot_id"], "label": label,
        "updated": paper_broker._now(), "market_open": market_open,
        "benchmark": cfg["benchmark_name"],
        "account": {"started": acct["started"], "start_cash": acct["deposited"],
                    "cash": round(acct["cash"], 2), "held": round(held_value, 2),
                    "value": round(acct["cash"] + held_value, 2),
                    "bench_value": round(bu * prices[bench], 2)
                    if bu and prices.get(bench) else None,
                    "trades": len(acct["orders"]),
                    "fees": round(sum(o.get("fee", 0) for o in acct["orders"]), 2)},
        "positions": pos_rows,
        "leaders": [{"symbol": s, "rise_pct": round(v, 1), "price": prices.get(s)}
                    for v, s in lead],
        "orders": list(reversed(acct["orders"]))[:30],
        "bot": {"events": events[-25:]},
        "rules": r,
    }
    try:
        live_snapshot.publish(snap, cfg["live_branch"])
    except Exception as e:
        print(f"Live page update skipped ({type(e).__name__}).")
    if not market_open:
        print("Market closed; live page refreshed.")
    return 0


def selftest():
    # score: needs history, must be above its average, measures the rise.
    closes = [10.0] * 20 + [11.0] * 5
    assert abs(score(closes, 12.0, 10, 20) - 20.0) < 1e-9
    assert score(closes, 9.0, 10, 20) is None          # under its average
    assert score(closes[:5], 12.0, 10, 20) is None     # too little history
    cfg = {"rules": {"max_positions": 2, "trail_pct": 15, "min_hold_hours": 24,
                     "min_rise_pct": 0, "lookback_days": 10, "trend_days": 20},
           "sizing": {"min_bet": 50}}
    now = 1_000_000.0
    # Empty account: buys the 2 hottest, half the cash each.
    sc = {"A": 30.0, "B": 50.0, "C": 10.0, "D": None}
    pr = {"A": 1, "B": 1, "C": 1, "D": 1}
    s, b = decide(cfg, pr, sc, {}, 1000, now)
    assert s == [] and b == [("B", 500.0), ("A", 500.0)], (s, b)
    # Trailing stop: best was 100, now 84 -> sell; 86 -> keep.
    held = {"B": {"peak": 100.0, "bought_ts": now - 3600}}
    assert decide(cfg, {"B": 84}, {"B": 5.0}, held, 0, now)[0]
    assert not decide(cfg, {"B": 86}, {"B": 5.0}, held, 0, now)[0]
    # Stopped climbing: only after the minimum hold.
    assert not decide(cfg, {"B": 99}, {"B": None}, held, 0, now)[0]
    held_old = {"B": {"peak": 100.0, "bought_ts": now - 25 * 3600}}
    assert decide(cfg, {"B": 99}, {"B": None}, held_old, 0, now)[0]
    # One slot open: one buy with all the cash; never re-buys what it holds.
    s, b = decide(cfg, {"A": 1, "B": 99}, {"A": 30.0, "B": 50.0}, held, 400, now)
    assert b == [("A", 400.0)], b
    # Too little cash -> no buy.
    assert decide(cfg, pr, sc, held, 40, now)[1] == []
    # Percent fee (crypto, 0.5%): $500 buy pays $2.50.
    pb = paper_broker.PaperBroker.__new__(paper_broker.PaperBroker)
    pb.fee, pb.fee_per_share, pb.fee_pct = 0.0, 0.0, 0.005
    assert abs(pb.order_fee(5, 500) - 2.5) < 1e-9
    print("selftest OK")
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(run(sys.argv[1] if len(sys.argv) > 1 else "watchlist-moonshot.json"))
