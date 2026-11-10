#!/usr/bin/env python3
"""The rule checker: plain code that says yes or no to every paper order.
PRACTICE MONEY ONLY. The AI never calls this to "ask nicely"; the executor
runs every order through it and obeys the answer.

It refuses when:
  - rules.json says anything but practice_only, or doesn't match rules.lock
    (so nobody, AI included, can quietly loosen a cap);
  - stock_bot/PAUSE or stock_bot/research_bot/PAUSE exists (everything stops);
  - the order id was seen before (a retry can never double-buy);
  - the price is stale, missing, or just jumped more than max_jump_pct;
  - for a BUY: the auto-pause is on, the forecast wasn't committed before its
    window opened, the window isn't open, it isn't an 'up' forecast that asked
    for a trade, the stock/coin is already held, too many positions, the day's
    new-order cap is used, the size is over max_position_pct of the account,
    under min_order_dollars or over the cash, or the day's loss / week's
    drawdown cap is hit (which also turns the auto-pause on);
  - for a BUY without a safe stop: the asset's typical daily range is unknown,
    the order's stop is tighter than stop_daily_ranges x that range, or a stop
    that wide would risk more than max_loss_per_100 (then the bet is skipped);
  - for a SELL: there is no position, or its forecast's window hasn't closed
    and its stop wasn't hit.
    Closing a due position is allowed during an auto-pause (it lowers risk);
    a manual PAUSE stops sells too, same as the other robots.

  python3 -m stock_bot.research_bot.checker --check   # rules match the lock?
  python3 -m stock_bot.research_bot.checker --lock    # HUMAN ONLY, after GO
"""

import datetime as dt
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import forecasts as ledger  # noqa: E402

RULES_LOCK = os.path.join(HERE, "rules.lock")
PAUSE_FILES = (os.path.join(os.path.dirname(HERE), "PAUSE"),
               os.path.join(HERE, "PAUSE"))
AUTO_PAUSE = os.path.join(HERE, "AUTO_PAUSE")


def rules_hash(path=ledger.RULES):
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def rules_locked_ok(rules_path=ledger.RULES, lock_path=RULES_LOCK):
    if not os.path.exists(lock_path):
        return False
    with open(lock_path) as f:
        return f.read().split()[0:1] == [rules_hash(rules_path)]


def manual_pause_on(files=PAUSE_FILES):
    return any(os.path.exists(p) for p in files)


def day_start(now):
    """Same trading-day cut as the practice broker: the latest 08:00 UTC."""
    cut = now.replace(hour=8, minute=0, second=0, microsecond=0)
    return cut if now >= cut else cut - dt.timedelta(days=1)


def risk_pause_reason(equity, rules, now):
    """equity: [(datetime, value)] for one account, oldest first, the latest
    being now. Returns a reason string if a loss cap is hit, else None."""
    if not equity:
        return None
    value = equity[-1][1]
    today = [v for t, v in equity if t >= day_start(now)]
    if today and today[0] > 0:
        drop = (today[0] - value) / today[0] * 100
        if drop >= rules["daily_loss_cap_pct"]:
            return f"daily loss {drop:.1f}% hit the {rules['daily_loss_cap_pct']}% cap"
    week = [v for t, v in equity if t >= now - dt.timedelta(days=7)]
    if week and max(week) > 0:
        dd = (max(week) - value) / max(week) * 100
        if dd >= rules["weekly_drawdown_cap_pct"]:
            return f"7-day drawdown {dd:.1f}% hit the {rules['weekly_drawdown_cap_pct']}% cap"
    return None


def check_order(order, ctx):
    """order: {id, side, asset, market, dollars, forecast_id}
    ctx: rules, rules_ok, manual_pause, auto_pause (reason or None), now,
         forecast (ledger line or None), committed_before_open (bool),
         quote {price, time, price_ago} or None, account {value, cash,
         positions}, equity [(t, value)], seen_ids (set), new_orders_today (int)
    Returns (ok, reasons, pause_reason). pause_reason, when set, means the
    executor must turn the auto-pause on."""
    rules, now = ctx["rules"], ctx["now"]
    no = lambda *r: (False, list(r), None)
    if rules.get("practice_only") is not True:
        return no("rules.json is not practice_only: refusing everything")
    if not ctx.get("rules_ok"):
        return no("rules.json does not match rules.lock (changed without a GO)")
    if ctx.get("manual_pause"):
        return no("PAUSE file is present")
    if order["id"] in ctx.get("seen_ids", set()):
        return no(f"order {order['id']} was already tried (no double orders)")
    market = order.get("market")
    m = rules["markets"].get(market)
    if not m:
        return no(f"unknown market {market}")
    q = ctx.get("quote")
    if not q or not q.get("price") or q["price"] <= 0:
        return no("no live price: halt")
    age = (now - q["time"]).total_seconds()
    if age > m["max_price_age_seconds"] or age < -60:
        return no(f"price is {age:.0f}s old (max {m['max_price_age_seconds']}s): halt")
    if q.get("price_ago"):
        jump = abs(q["price"] / q["price_ago"] - 1) * 100
        if jump > m["max_jump_pct"]:
            return no(f"price moved {jump:.1f}% in {rules['jump_lookback_minutes']} min "
                      f"(max {m['max_jump_pct']}%): halt")

    f = ctx.get("forecast")
    acct = ctx["account"]
    held = acct["positions"]
    if order["side"] == "sell":
        if order["asset"] not in held:
            return no(f"no paper position in {order['asset']}")
        if ctx.get("stop_hit"):
            return True, ["stop hit: close the position"], None
        if not f or now < ledger.parse_time(f["resolves_at"]):
            return no("its forecast window has not closed yet")
        return True, ["close a due position"], None
    if order["side"] != "buy":
        return no("side must be buy or sell")

    if ctx.get("auto_pause"):
        return no(f"auto-pause is on ({ctx['auto_pause']}); a human removes AUTO_PAUSE")
    if not f or f.get("kind") != "forecast":
        return no("no such forecast")
    if f.get("market") != market or f.get("asset") != order["asset"]:
        return no("order does not match its forecast")
    if not f.get("act") or f.get("direction") != "up" or not rules.get("long_only"):
        return no("only 'up' forecasts that asked for a trade can buy (long-only)")
    if not ctx.get("committed_before_open"):
        return no("forecast was not committed before its window opened")
    if not ledger.parse_time(f["opens_at"]) <= now < ledger.parse_time(f["resolves_at"]):
        return no("forecast window is not open")
    if order["asset"] in held:
        return no(f"already holding {order['asset']}")
    if len(held) >= rules["max_open_positions"]:
        return no(f"already {len(held)} positions (max {rules['max_open_positions']})")
    if ctx.get("new_orders_today", 0) >= rules["max_new_orders_per_day"]:
        return no(f"day's cap of {rules['max_new_orders_per_day']} new orders used")
    cap = acct["value"] * rules["max_position_pct"] / 100
    d = float(order["dollars"])
    if d > cap + 1e-9:
        return no(f"${d:.2f} is over {rules['max_position_pct']:g}% of the account (${cap:.2f})")
    if d < rules["min_order_dollars"]:
        return no(f"${d:.2f} is under the ${rules['min_order_dollars']:.0f} minimum (fees eat it)")
    if d > acct["cash"] + 1e-9:
        return no("not enough practice cash")
    rng = ctx.get("daily_range_pct")
    if not rng or rng <= 0:
        return no("no typical daily range for this asset: can't set a safe stop")
    stop = order.get("stop_pct")
    need = rules["stop_daily_ranges"] * rng
    if stop is None or stop < need - 1e-9:
        return no(f"stop must be at least {rules['stop_daily_ranges']:g}x the daily range ({need:.1f}%)")
    if stop > rules["max_loss_per_100"]:
        return no(f"skip: a safe stop needs {stop:.1f}%, over the "
                  f"${rules['max_loss_per_100']:g} per $100 cap")
    reason = risk_pause_reason(ctx.get("equity", []), rules, now)
    if reason:
        return False, [reason], reason
    return True, ["all checks passed"], None


def main(argv=None):
    argv = argv or sys.argv[1:]
    if "--lock" in argv:
        with open(RULES_LOCK, "w") as f:
            f.write(rules_hash() + "  rules.json\n")
        print("rules.lock updated. Only do this after the NB2 gate + Matthew's GO.")
        return 0
    ok = rules_locked_ok()
    print("rules.json matches rules.lock" if ok else "rules.json does NOT match rules.lock")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
