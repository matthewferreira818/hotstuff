#!/usr/bin/env python3
"""Robot 3, "Hot hands": same-day trading of cheap, wide-swinging stocks.

Matthew's mission (2026-10-07): "live trading companies like Ondas that go
up and down about 60 cents a day." It runs next to the dip and momentum
robots on its own practice account ($1,000 of fake money, plus the same
payday deposits from 2026-10-14) so all three can be compared.

The rule is EXP-0004's "VWAP snap-back", the only day-trading rule we've
tested whose average trade rose before costs (+0.15%). It still LOST
money after Moomoo's fees in that test (research/experiments/EXP-0004.md),
so this robot is a live experiment, not a strategy we expect to win.

  Buy   after the first 15 minutes, when a stock is 2% under its
        volume-weighted average price for the day (VWAP): a dip below
        where most of the day's shares changed hands.
  Sell  when it gets back up to VWAP, at -3% from the buy, or 5 minutes
        before the close. It never holds overnight.
  Size  half the account per trade, at most 2 trades open at once, at most
        2 round trips per stock per day, no buys in the last 15 minutes.

Checks prices every 10 seconds; refreshes each stock's VWAP every minute
(Yahoo's 1-minute bars). Settings in watchlist-hot.json.

  python stock_bot/hot_bot.py             # trade through today's session
  python stock_bot/hot_bot.py --snapshot  # refresh the live page only
  python stock_bot/hot_bot.py --selftest
"""

import datetime as dt
import json
import os
import sys
import time
import urllib.parse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import live_snapshot  # noqa: E402
import paper_broker  # noqa: E402
import stock_bot  # noqa: E402

CONFIG = os.path.join(HERE, "watchlist-hot.json")
ACCOUNT = os.path.join(HERE, "paper", "account-hot.json")
LIVE_BRANCH = "stock-live-hot"
VWAP_SECONDS = 60
SAVE_SECONDS = 120  # commit the account at most every 2 min (and at the end)


def load_cfg():
    with open(CONFIG) as f:
        return json.load(f)


def day_bars(sym):
    """Today's 1-minute bars: (vwap, session start, session end) or None."""
    q = urllib.parse.urlencode({"range": "1d", "interval": "1m"})
    res = paper_broker._get("https://query1.finance.yahoo.com/v8/finance/"
                            f"chart/{sym}?{q}")["chart"]["result"][0]
    reg = res["meta"]["currentTradingPeriod"]["regular"]
    quote = res["indicators"]["quote"][0]
    pv = vol = 0.0
    for i, ts in enumerate(res.get("timestamp") or []):
        h, lo, c, v = (quote[k][i] for k in ("high", "low", "close", "volume"))
        if None in (h, lo, c, v) or not reg["start"] <= ts < reg["end"]:
            continue
        pv += (h + lo + c) / 3 * v
        vol += v
    return (pv / vol if vol else None), reg["start"], reg["end"]


def decide(cfg, now_ts, start, end, prices, vwaps, held, cash, value,
           buys_today, orders_today):
    """Pure: (sells, buys). held = {sym: fill price}. buys = [(sym, $)]."""
    r = cfg["rules"]
    mins_in, mins_left = (now_ts - start) / 60, (end - now_ts) / 60
    sells, buys = [], []
    for sym, fill in held.items():
        price, vwap = prices.get(sym), vwaps.get(sym)
        if price is None:
            continue
        if mins_left <= r["flatten_minutes_before_close"]:
            sells.append((sym, "closing time, out before the bell"))
        elif vwap and price >= vwap:
            sells.append((sym, f"back up to its day average {vwap:.2f}"))
        elif price <= fill * (1 - r["stop_pct"] / 100):
            sells.append((sym, f"down {r['stop_pct']}% from the buy, cut it"))
    open_after = len(held) - len(sells)
    orders_left = cfg["max_orders_per_day"] - orders_today - len(sells)
    if (mins_in < r["wait_minutes"]
            or mins_left <= r["last_buy_minutes_before_close"]):
        return sells, buys
    s = cfg["sizing"]
    bet = min(value * s["bet_pct_of_account"] / 100, s.get("max_bet", 1e9))
    cash_left = cash
    gaps = []
    for sym in cfg["stocks"]:
        price, vwap = prices.get(sym), vwaps.get(sym)
        if (sym in held or not price or not vwap
                or buys_today.get(sym, 0) >= r["trips_per_stock"]):
            continue
        gap = (price / vwap - 1) * 100
        if gap <= -r["under_vwap_pct"]:
            gaps.append((gap, sym))
    for gap, sym in sorted(gaps):  # deepest under VWAP first
        dollars = min(bet, cash_left)
        if (open_after >= r["max_open"] or orders_left < 2
                or dollars < s["min_bet"]):
            break
        buys.append((sym, round(dollars, 2), gap))
        cash_left -= dollars
        open_after += 1
        orders_left -= 2  # keep room to sell it
    return sells, buys


def snapshot(broker, cfg, prices, vwaps, market_open, events):
    acct = broker.acct
    positions = broker.positions()
    held = sum(x["market_value"] for x in positions.values())
    spy = prices.get("SPY") or broker.latest_prices(["SPY"]).get("SPY")
    spy_value = acct["spy_units"] * spy if spy and acct.get("spy_units") else None
    stop = cfg["rules"]["stop_pct"]
    pos_rows = []
    for sym, x in positions.items():
        raw = acct["positions"][sym]
        price = prices.get(sym) or raw["avg_entry_price"]
        fill = raw.get("fill", raw["avg_entry_price"])
        pos_rows.append({"symbol": sym, "price": price, "entry": fill,
                         "value": x["market_value"],
                         "change_pct": round((price / fill - 1) * 100, 2),
                         "target": round(vwaps[sym], 2) if vwaps.get(sym) else None,
                         "stop": round(fill * (1 - stop / 100), 2)})
    watch = []
    for sym in cfg["stocks"]:
        p, v = prices.get(sym), vwaps.get(sym)
        watch.append({"symbol": sym, "price": p, "vwap": round(v, 2) if v else None,
                      "gap_pct": round((p / v - 1) * 100, 2) if p and v else None,
                      "held": sym in positions})
    sells = [o for o in acct["orders"] if o["side"] == "sell"]
    return {
        "robot": "hot",
        "updated": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "market_open": market_open,
        "account": {"started": acct["started"], "start_cash": acct["deposited"],
                    "cash": round(acct["cash"], 2), "held": round(held, 2),
                    "value": round(acct["cash"] + held, 2),
                    "spy_value": round(spy_value, 2) if spy_value else None,
                    "trades": len(acct["orders"]), "round_trips": len(sells),
                    "fees": round(sum(o.get("fee", 0) for o in acct["orders"]), 2),
                    "deposits": acct.get("deposits", [])[-10:],
                    "next_deposit": acct.get("next_deposit")},
        "positions": pos_rows,
        "watching": watch,
        "orders": list(reversed(acct["orders"]))[:30],
        "bot": {"events": events},
        "rules": cfg["rules"],
    }


def run():
    started = time.monotonic()
    cfg = load_cfg()
    saved = {"at": time.monotonic(), "dirty": False}

    def local_save(path, message):  # trades are frequent: batch the commits
        saved["dirty"] = True

    broker = paper_broker.PaperBroker(cfg.get("paper_costs"), path=ACCOUNT,
                                      save_hook=local_save)
    events = []

    def event(text, kind="info"):
        if kind == "quiet" and events and events[-1]["kind"] == "quiet":
            events.pop()  # one rolling "all quiet" line
        events.append({"time": dt.datetime.now(dt.timezone.utc).isoformat(
            timespec="seconds"), "kind": kind, "text": text})
        del events[:-40]

    def commit(force=False):
        if saved["dirty"] and (force or time.monotonic() - saved["at"]
                               >= SAVE_SECONDS):
            paper_broker.git_save(ACCOUNT, "Hot hands robot: trades")
            saved.update(at=time.monotonic(), dirty=False)

    if not os.path.exists(ACCOUNT):
        broker._save("Hot hands robot: account opened")
    try:
        if broker.apply_deposits(cfg.get("practice_deposits")):
            event("Payday deposit added.", "start")
    except (RuntimeError, KeyError, ValueError):
        print("Practice deposit skipped (no FX rate); retrying next run.")

    prices, vwaps = {}, {}

    def publish(market_open):
        try:
            live_snapshot.publish(snapshot(broker, cfg, prices, vwaps,
                                           market_open, events), LIVE_BRANCH)
        except Exception as e:  # the page must never stop the trading
            print(f"Live page update skipped ({type(e).__name__}).")

    if "--snapshot" in sys.argv:
        prices.update(broker.latest_prices(cfg["stocks"] + ["SPY"]))
        publish(bool(broker.clock().get("is_open")))
        commit(force=True)
        print("Live page updated.")
        return 0
    if cfg.get("paused"):
        print("Paused.")
        return 0
    if not stock_bot.wait_for_open(broker, broker.clock()):
        commit(force=True)
        print("Market closed.")
        return 0

    every = max(float(cfg.get("check_every_seconds", 10)), 5)
    event(f"Market's open. Watching {len(cfg['stocks'])} cheap swingers every "
          f"{every:g} seconds.", "start")
    start = end = None
    last_vwap = last_snap = 0.0
    checks = errors = 0
    while True:
        now = time.monotonic()
        if now - started >= stock_bot.MAX_LOOP_SECONDS:
            print("Hit the job time limit; the next scheduled run takes over.")
            break
        try:
            if now - last_vwap >= VWAP_SECONDS:
                for sym in cfg["stocks"]:
                    v, start, end = day_bars(sym)
                    if v:
                        vwaps[sym] = v
                last_vwap = now
            if end and time.time() >= end:
                event("Market closed.", "stop")
                break
            held_syms = list(broker.acct["positions"])
            prices.update(broker.latest_prices(
                list(dict.fromkeys(cfg["stocks"] + held_syms))))
            held = {s: p.get("fill", p["avg_entry_price"])
                    for s, p in broker.acct["positions"].items()}
            # Holdings bought before a stock left the list keep their VWAP.
            for s in held_syms:
                if s not in vwaps:
                    vwaps[s] = day_bars(s)[0]
            today = broker.orders_today()
            buys_today = {}
            for o in today:
                if o["side"] == "buy":
                    buys_today[o["symbol"]] = buys_today.get(o["symbol"], 0) + 1
            value = broker.cash() + sum(x["market_value"] for x in
                                        broker.positions().values())
            sells, buys = decide(cfg, time.time(), start, end, prices, vwaps,
                                 held, broker.cash(), value, buys_today,
                                 len(today))
            done = []
            for sym, why in sells:
                try:
                    fill = held[sym]
                    broker.sell_all(sym)
                    o = broker.acct["orders"][-1]
                    gain = (o["price"] / fill - 1) * 100
                    done.append(f"SELL {sym} {gain:+.1f}% — {why}")
                    event(f"Sold {sym} at {o['price']:.2f} ({gain:+.1f}% "
                          f"before fees): {why}", "sell")
                except RuntimeError as e:
                    event(f"Sell {sym} didn't go through: {e}", "error")
            for sym, dollars, gap in buys:
                try:
                    broker.buy(sym, dollars)
                    o = broker.acct["orders"][-1]
                    broker.acct["positions"][sym]["fill"] = o["price"]
                    broker._save(f"Hot hands: buy {sym}")
                    done.append(f"BUY {sym} ${dollars:,.2f} — {abs(gap):.1f}% "
                                "under its day average")
                    event(f"Bought {sym} ${dollars:,.2f} at {o['price']:.2f}, "
                          f"{abs(gap):.1f}% under its day average "
                          f"{vwaps[sym]:.2f}", "buy")
                except RuntimeError as e:
                    event(f"Buy {sym} didn't go through: {e}", "error")
            if done:
                stock_bot.notify(f"Hot hands robot (practice): {len(done)} "
                                 "trade(s)", "\n".join(done))
                publish(True)
                last_snap = now
            elif checks % 30 == 0:
                event(f"Checked {len(cfg['stocks'])} stocks. None far enough "
                      "under its day average.", "quiet")
            commit()
            checks += 1
            errors = 0
        except Exception as e:
            errors += 1
            print(f"Check failed ({type(e).__name__}), {errors} in a row.")
            if errors >= stock_bot.MAX_ERRORS_IN_A_ROW:
                commit(force=True)
                stock_bot.notify("Hot hands robot: stopped",
                                 f"{errors} failed checks in a row: {e}", "high")
                return 1
            time.sleep(30)
            continue
        if now - last_snap >= stock_bot.SNAPSHOT_SECONDS:
            publish(True)
            last_snap = now
        time.sleep(every)
    publish(False)
    commit(force=True)
    print(f"Done: {checks} checks.")
    return 0


def selftest():
    cfg = {"stocks": ["ONDS", "LCID", "MARA"], "max_orders_per_day": 20,
           "rules": {"under_vwap_pct": 2, "stop_pct": 3, "trips_per_stock": 2,
                     "max_open": 2, "wait_minutes": 15,
                     "last_buy_minutes_before_close": 15,
                     "flatten_minutes_before_close": 5},
           "sizing": {"bet_pct_of_account": 50, "min_bet": 100}}
    start, end = 0, 390 * 60
    mid = 120 * 60
    vw = {"ONDS": 7.0, "LCID": 5.0, "MARA": 11.0}
    # ONDS 3% under VWAP and LCID 2.4% under -> both bought, deepest first.
    p = {"ONDS": 6.79, "LCID": 4.88, "MARA": 11.0}
    sells, buys = decide(cfg, mid, start, end, p, vw, {}, 1000, 1000, {}, 0)
    assert sells == [] and [b[0] for b in buys] == ["ONDS", "LCID"], buys
    assert buys[0][1] == 500.0, buys
    # Too early (first 15 min) -> no buys.
    assert decide(cfg, 10 * 60, start, end, p, vw, {}, 1000, 1000, {}, 0)[1] == []
    # 2 trips already today -> ONDS skipped.
    b = decide(cfg, mid, start, end, p, vw, {}, 1000, 1000, {"ONDS": 2}, 0)[1]
    assert [x[0] for x in b] == ["LCID"], b
    # Held: back to VWAP -> sell; -3% -> sell; in between -> hold.
    held = {"ONDS": 6.8}
    assert decide(cfg, mid, start, end, {"ONDS": 7.01}, vw, held, 0, 0, {}, 1)[0]
    assert decide(cfg, mid, start, end, {"ONDS": 6.59}, vw, held, 0, 0, {}, 1)[0]
    assert not decide(cfg, mid, start, end, {"ONDS": 6.9}, vw, held, 0, 0, {}, 1)[0]
    # 4 minutes before the close -> sell everything, buy nothing.
    s, b = decide(cfg, end - 240, start, end, dict(p, ONDS=6.9), vw, held,
                  1000, 1000, {}, 1)
    assert [x[0] for x in s] == ["ONDS"] and b == [], (s, b)
    # Already 2 open -> no third buy.
    held2 = {"ONDS": 6.8, "MARA": 11.2}
    b = decide(cfg, mid, start, end, dict(p, ONDS=6.85, MARA=10.9), vw, held2,
               1000, 1000, {}, 2)[1]
    assert b == [], b
    # Little cash -> one buy at what's left; under $100 -> none.
    b = decide(cfg, mid, start, end, p, vw, {}, 150, 1000, {}, 0)[1]
    assert [(x[0], x[1]) for x in b] == [("ONDS", 150)], b
    assert decide(cfg, mid, start, end, p, vw, {}, 90, 1000, {}, 0)[1] == []
    print("selftest OK")


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
