#!/usr/bin/env python3
"""Robot 2, "Momentum": strategy D from EXP-0001, on its own practice account.

Runs side by side with the dip robot (stock_bot.py) so the two can be
compared on real prices. Same rules as the tested strategy, so it decides
once a day in the last ~20 minutes before the close, on the day's price
and volume, exactly as the backtest did on daily closes:

  Buy   up 10%+ over 60 days, price above its 20-day average, and today's
        volume at least 1.5x the 20-day average. Strongest momentum first.
  Sell  when the price falls 3x the stock's typical daily range (ATR, set
        on the day it was bought) below the best close since buying.

Watches every stock that passed the latest screen. Sizing and costs come
from watchlist-momentum.json (Moomoo fees, 10% of the account per buy,
$100 minimum). Payday deposits mirror the dip robot's, so the two
accounts stay comparable.

  python stock_bot/momentum_bot.py            # normal run (only acts near the close)
  python stock_bot/momentum_bot.py --now      # act now even if not near the close
  python stock_bot/momentum_bot.py --snapshot # refresh the live page only
  python stock_bot/momentum_bot.py --selftest
"""

import datetime as dt
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import experiment as e1  # noqa: E402  (indicators + the tested entry rule)
import live_snapshot  # noqa: E402
import paper_broker  # noqa: E402
import stock_bot  # noqa: E402

CONFIG = os.path.join(HERE, "watchlist-momentum.json")
ACCOUNT = os.path.join(HERE, "paper", "account-momentum.json")
LIVE_BRANCH = "stock-live-momentum"
WINDOW_MIN = 25  # act only in the last 25 minutes of the session


def load_cfg():
    with open(CONFIG) as f:
        return json.load(f)


def universe(cfg):
    if cfg.get("universe") != "screen":
        return [s.upper() for s in cfg.get("universe", [])]
    with open(os.path.join(HERE, "screen", "latest.json")) as f:
        return [r["symbol"] for r in json.load(f)["stocks"]]


def series(symbols):
    """Daily bars (today's bar is the day so far) with indicators."""
    from screener import fetch
    out = {}
    for s in symbols:
        bars = fetch(s, "6mo")
        if len(bars) < 70:
            continue
        c = [b["close"] for b in bars]
        v = [b["volume"] for b in bars]
        h = [b["high"] for b in bars]
        lo = [b["low"] for b in bars]
        out[s] = {"c": c, "v": v, "ind": e1.indicators(c, v, h, lo),
                  "date": bars[-1]["date"]}
    return out


def holdings(broker):
    """What the robot owns: the stored record (peak, trail) plus today's
    market value. broker.positions() alone drops peak and trail, which
    crashed the close check with KeyError 'trail' (REVIEW-2026-09-27)."""
    held = broker.acct["positions"]
    if held:
        broker.latest_prices(list(held))  # value at today's price
    values = broker.positions()
    return {s: dict(raw, market_value=values[s]["market_value"])
            for s, raw in held.items()}


def decide(cfg, data, positions, cash, traded_today):
    """Pure: (sells, buys). positions carry 'peak' and 'trail' (percent);
    see holdings()."""
    p = cfg["rules"]
    sells, buys = [], []
    for sym, pos in positions.items():
        s = data.get(sym)
        if not s or sym in traded_today or not pos.get("trail"):
            continue
        price = s["c"][-1]
        peak = max(float(pos.get("peak", price)), price)
        if price <= peak * (1 - float(pos["trail"]) / 100):
            sells.append((sym, f"{(price / peak - 1) * 100:.1f}% off its best "
                               f"close {peak:.2f} (trailing stop "
                               f"{pos['trail']:.1f}%)"))
    held_value = sum(float(x["market_value"]) for x in positions.values())
    freed = sum(float(positions[s]["market_value"]) for s, _ in sells)
    cash_left = cash + freed
    sizing = stock_bot.bet_size(cfg, cash + held_value)
    candidates = []
    for sym, s in data.items():
        if sym in positions or sym in traded_today:
            continue
        i = len(s["c"]) - 1
        if e1.wants_in("D", p, s["c"], s["v"], s["ind"], i) and s["ind"]["atr"][i]:
            candidates.append((s["ind"]["ret60"][i], sym, s["ind"]["atr"][i]))
    orders_left = int(cfg.get("max_orders_per_day", 8)) - len(sells)
    for mom, sym, atr in sorted(candidates, reverse=True):
        bet, cap, floor = sizing
        dollars = min(bet, cap, cash_left)
        if dollars < floor or orders_left <= 0:
            break
        buys.append((sym, round(dollars, 2), p["atr_x"] * atr,
                     f"up {mom:.0f}% in 60 days on heavy volume"))
        cash_left -= dollars
        orders_left -= 1
    return sells, buys


def snapshot(broker, cfg, data, market_open, events):
    acct = broker.acct
    syms = list(acct["positions"]) + ["SPY"]
    prices = broker.latest_prices(syms)
    positions = broker.positions()
    held = sum(x["market_value"] for x in positions.values())
    spy_value = (acct["spy_units"] * prices["SPY"]
                 if prices.get("SPY") and acct.get("spy_units") else None)
    pos_rows = []
    for sym, x in positions.items():
        raw = acct["positions"][sym]
        price = prices.get(sym, raw["avg_entry_price"])
        peak = max(raw.get("peak", price), price)
        pos_rows.append({
            "symbol": sym, "price": price, "entry": raw["avg_entry_price"],
            "value": x["market_value"],
            "change_pct": round((price / raw["avg_entry_price"] - 1) * 100, 2),
            "stop": round(peak * (1 - raw["trail"] / 100), 2),
            "trail": round(raw["trail"], 1)})
    near = []
    for sym, s in (data or {}).items():
        i = len(s["c"]) - 1
        ind = s["ind"]
        if ind["ret60"][i] is None or ind["sma20"][i] is None:
            continue
        near.append({"symbol": sym, "ret60": round(ind["ret60"][i], 1),
                     "above_avg": s["c"][i] > ind["sma20"][i],
                     "volume_x": round(s["v"][i] / ind["vol20"][i], 2)
                     if ind["vol20"][i] else None})
    near.sort(key=lambda r: -r["ret60"])
    return {
        "robot": "momentum",
        "updated": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "market_open": market_open,
        "account": {"started": acct["started"],
                    "start_cash": acct["deposited"],
                    "cash": round(acct["cash"], 2), "held": round(held, 2),
                    "value": round(acct["cash"] + held, 2),
                    "spy_value": round(spy_value, 2) if spy_value else None,
                    "trades": len(acct["orders"]),
                    "fees": round(sum(o.get("fee", 0) for o in acct["orders"]), 2),
                    "deposits": acct.get("deposits", [])[-10:],
                    "next_deposit": acct.get("next_deposit")},
        "positions": pos_rows,
        "leaders": near[:12],
        "watching": len(data or {}),
        "orders": list(reversed(acct["orders"]))[:20],
        "bot": {"events": events},
        "rules": cfg["rules"],
    }


def intraday_exits(broker, traded_today):
    """Between the daily checks: sell any holding whose live price has
    fallen to its stop line (best close x (1 - trail)). Returns
    [(symbol, reason)]. The best close only moves at the daily check, as
    in the backtest; this just stops waiting for 4pm to act on a drop."""
    held = broker.acct["positions"]
    if not held:
        return []
    prices = broker.latest_prices(list(held))
    out = []
    for sym, raw in held.items():
        price = prices.get(sym)
        if price is None or sym in traded_today or "trail" not in raw:
            continue
        stop = raw["peak"] * (1 - raw["trail"] / 100)
        if price <= stop:
            out.append((sym, f"hit its stop at {price:.2f} mid-day (best "
                             f"close {raw['peak']:.2f}, {raw['trail']:.1f}% "
                             "trailing stop)"))
    return out


def run():
    started = time.monotonic()
    cfg = load_cfg()
    broker = paper_broker.PaperBroker(cfg.get("paper_costs"), path=ACCOUNT)
    events = []

    def event(text, kind="info"):
        events.append({"time": dt.datetime.now(dt.timezone.utc).isoformat(
            timespec="seconds"), "kind": kind, "text": text})
        del events[:-40]

    try:
        if broker.apply_deposits(cfg.get("practice_deposits")):
            event("Payday deposit added.", "start")
    except (RuntimeError, KeyError, ValueError):
        print("Practice deposit skipped (no FX rate); retrying next run.")

    data = {}

    def publish(market_open):
        try:
            live_snapshot.publish(snapshot(broker, cfg, data, market_open,
                                           events), LIVE_BRANCH)
        except Exception as e:  # the page must never stop the trading
            print(f"Live page update skipped ({type(e).__name__}).")

    if "--snapshot" in sys.argv:
        data = series(universe(cfg))
        publish(bool(broker.clock().get("is_open")))
        print("Live page updated.")
        return 0
    if cfg.get("paused"):
        print("Paused.")
        return 0

    def daily_check():
        nonlocal data
        # Held stocks are fetched even if they dropped out of the screen,
        # so their best close keeps moving and the close check guards them.
        data = series(sorted(set(universe(cfg)) | set(broker.acct["positions"])))
        traded = {o["symbol"] for o in broker.orders_today()}
        for sym, raw in broker.acct["positions"].items():
            if sym in data:  # the best close moves only here, as tested
                raw["peak"] = max(raw.get("peak", 0), data[sym]["c"][-1])
                atr = data[sym]["ind"]["atr"][-1]
                if not raw.get("trail") and atr:
                    # A buy saved before its stop was set (a crash between
                    # the two saves): set the stop now, as at entry.
                    raw["trail"] = round(cfg["rules"]["atr_x"] * atr, 2)
        sells, buys = decide(cfg, data, holdings(broker), broker.cash(),
                             traded)
        done = sell_all(sells)
        for sym, dollars, trail, why in buys:
            try:
                broker.buy(sym, dollars)
                raw = broker.acct["positions"][sym]
                raw["peak"], raw["trail"] = data[sym]["c"][-1], round(trail, 2)
                done.append(f"BUY {sym} ${dollars:,.2f} — {why}")
                event(f"Bought {sym} ${dollars:,.2f}: {why}", "buy")
            except RuntimeError as e:
                event(f"Buy {sym} didn't go through: {e}", "error")
        broker.acct["last_close_check"] = today_ny()
        broker._save("Momentum robot: close check")
        if not done:
            event(f"Close check: {len(data)} stocks, nothing met the rules "
                  "today.", "quiet")
        report(done)
        print(f"Close check: {len(data)} stocks, {len(done)} trade(s).")

    def sell_all(sells):
        done = []
        for sym, why in sells:
            try:
                broker.sell_all(sym)
                done.append(f"SELL {sym} — {why}")
                event(f"Sold {sym}: {why}", "sell")
            except RuntimeError as e:
                event(f"Sell {sym} didn't go through: {e}", "error")
        return done

    def report(done):
        if done:
            stock_bot.notify("Momentum robot (practice): "
                             f"{len(done)} trade(s)", "\n".join(done))

    if "--now" in sys.argv:  # testing: one close check right now
        daily_check()
        publish(bool(broker.clock().get("is_open")))
        return 0

    if not stock_bot.wait_for_open(broker, broker.clock()):
        print("Market closed.")
        return 0
    closes_at = dt.datetime.fromisoformat(broker.clock()["next_close"])
    every = max(float(cfg.get("check_every_seconds", 10)), 5)
    event(f"Market's open. Guarding holdings every {every:g} seconds; "
          "buying decisions come near the close.", "start")
    last_snap, checks, errors = 0.0, 0, 0
    while True:
        now = time.monotonic()
        left = (closes_at - dt.datetime.now(dt.timezone.utc)).total_seconds()
        if left <= 0:
            event("Market closed.", "stop")
            break
        if now - started >= stock_bot.MAX_LOOP_SECONDS:
            print("Hit the job time limit; the next scheduled run takes over.")
            break
        try:
            if (left <= WINDOW_MIN * 60
                    and broker.acct.get("last_close_check") != today_ny()):
                daily_check()
            else:
                traded = {o["symbol"] for o in broker.orders_today()}
                done = sell_all(intraday_exits(broker, traded))
                if done:
                    broker._save("Momentum robot: mid-day stop")
                    report(done)
            checks += 1
            errors = 0
        except Exception as e:
            errors += 1
            print(f"Check failed ({type(e).__name__}), {errors} in a row.")
            if errors >= stock_bot.MAX_ERRORS_IN_A_ROW:
                stock_bot.notify("Momentum robot: stopped",
                                 f"{errors} failed checks in a row: {e}",
                                 "high")
                return 1
            time.sleep(30)
            continue
        if now - last_snap >= stock_bot.SNAPSHOT_SECONDS:
            publish(True)
            last_snap = now
        time.sleep(every)
    publish(False)
    print(f"Done: {checks} checks.")
    return 0


def today_ny():
    """Today's date in New York (the trading day)."""
    ny = dt.timezone(dt.timedelta(hours=-4))  # EDT; a day boundary at 8pm
    return dt.datetime.now(dt.timezone.utc).astimezone(ny).date().isoformat()


def selftest():
    cfg = {"rules": {"momentum": 10, "volume_x": 1.5, "atr_x": 3},
           "max_orders_per_day": 8,
           "sizing": {"bet_pct_of_account": 10, "min_bet": 100,
                      "max_per_stock_pct": 20}}

    def mk(closes, vols):
        n = len(closes)
        return {"c": closes, "v": vols,
                "ind": e1.indicators(closes, vols, closes, closes)}
    # UP: steady climb then a heavy-volume day -> buy. FLAT: no momentum.
    up = mk([100 + i * 0.5 for i in range(80)], [1.0] * 79 + [3.0])
    flat = mk([100.0] * 80, [1.0] * 79 + [3.0])
    sells, buys = decide(cfg, {"UP": up, "FLAT": flat}, {}, 1000.0, set())
    assert [b[0] for b in buys] == ["UP"] and buys[0][1] == 100.0, buys
    # Trailing stop: best close 150, trail 10% -> price 134 sells.
    held = {"UP": {"market_value": "90", "peak": 150.0, "trail": 10.0,
                   "avg_entry_price": "120"}}
    drop = mk([100 + i * 0.5 for i in range(79)] + [134.0], [1.0] * 80)
    sells, buys = decide(cfg, {"UP": drop}, held, 1000.0, set())
    assert [s[0] for s in sells] == ["UP"], sells
    # Too little cash for a $100 bet -> no buy.
    sells, buys = decide(cfg, {"UP": up}, {}, 60.0, set())
    assert buys == [], buys
    # Mid-day guard: best close 150, 10% trail -> live 134 sells, 140 doesn't.
    class FakeBroker:
        def __init__(self, price):
            self.acct = {"positions": {"UP": {"peak": 150.0, "trail": 10.0}}}
            self.price = price

        def latest_prices(self, syms):
            return {"UP": self.price}
    assert [x[0] for x in intraday_exits(FakeBroker(134.0), set())] == ["UP"]
    assert intraday_exits(FakeBroker(140.0), set()) == []
    assert intraday_exits(FakeBroker(134.0), {"UP"}) == []  # traded today
    # Through a real PaperBroker, the way daily_check calls it: the stored
    # peak and trail must reach decide(). Before 2026-09-27 this path raised
    # KeyError 'trail' at the first close check after a buy.
    import tempfile
    b = paper_broker.PaperBroker.__new__(paper_broker.PaperBroker)
    b.fee, b.fee_per_share, b.slip = 1.99, 0.0099, 0.001
    b.path = os.path.join(tempfile.mkdtemp(), "acct.json")
    b.save_hook = lambda *a: None
    b._clock_cache, b._last_prices = (0, None), {}
    b.acct = paper_broker.new_account(500.0, paper_broker._now())
    b.acct["positions"]["UP"] = {"qty": 0.7, "avg_entry_price": 120.0,
                                 "peak": 150.0, "trail": 10.0}
    b.latest_prices = lambda syms: (b._last_prices.update(UP=134.0),
                                    {"UP": 134.0})[1]
    held = holdings(b)
    assert abs(held["UP"]["market_value"] - 0.7 * 134) < 0.01, held
    sells, buys = decide(cfg, {"UP": drop}, held, b.cash(), set())
    assert [s[0] for s in sells] == ["UP"], sells
    # A holding with no stop recorded is skipped, not a crash.
    del b.acct["positions"]["UP"]["trail"]
    assert decide(cfg, {"UP": drop}, holdings(b), b.cash(), set())[0] == []
    print("selftest OK")


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
