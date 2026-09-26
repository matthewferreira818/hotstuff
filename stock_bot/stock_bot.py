#!/usr/bin/env python3
"""Stock bot: buys and sells the stocks Matthew lists in watchlist.json.

It is a rules bot, not a fortune teller. Each run it checks the price of
every listed stock against the rules he set (buy on a dip or under a price,
sell at a profit target, a stop-loss, or over a price) and acts through an
Alpaca brokerage account.

Safety rails, in order:
  - mode "paper" (the default) trades fake money on Alpaca's paper account.
  - mode "live" only PROPOSES trades to his phone unless live_auto_trade is
    true — he places them himself (Run workflow button, see README).
  - "paused": true, or a stock_bot/PAUSE file, stops everything.
  - Caps: max_total_invested, max_orders_per_day, max_position_dollars,
    and at most one buy per stock per day.
  - Only acts while the US market is open.

PRIVACY: this repo is public, so Actions logs are public. Never print
balances, positions, or trade details to stdout on CI — details go only to
the phone via ntfy (NTFY_TOPIC secret). Pass --local to print them when
running on your own machine.

Keys come from env vars only (GitHub secrets): ALPACA_KEY_ID /
ALPACA_SECRET_KEY for paper, ALPACA_LIVE_KEY_ID / ALPACA_LIVE_SECRET_KEY
for live. Stdlib only — no pip installs.

Usage:
  python stock_bot/stock_bot.py                 # normal run
  python stock_bot/stock_bot.py --local         # print details too
  python stock_bot/stock_bot.py --dry-run       # decide, don't place orders
  python stock_bot/stock_bot.py --order "BUY AAPL 100"   # one manual order
  python stock_bot/stock_bot.py --selftest      # offline logic check
"""

import datetime as dt
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
WATCHLIST = os.path.join(HERE, "watchlist.json")
PAUSE_FILE = os.path.join(HERE, "PAUSE")

PAPER_API = "https://paper-api.alpaca.markets"
LIVE_API = "https://api.alpaca.markets"
DATA_API = "https://data.alpaca.markets"

LOCAL = "--local" in sys.argv


def say(public, private=None):
    """Print a public-safe line; add private detail only with --local."""
    print(public if not (LOCAL and private) else f"{public} | {private}")


# ---------------------------------------------------------------- broker I/O

class Alpaca:
    def __init__(self, live):
        pre = "ALPACA_LIVE_" if live else "ALPACA_"
        self.key = os.environ.get(pre + "KEY_ID", "")
        self.secret = os.environ.get(pre + "SECRET_KEY", "")
        self.base = LIVE_API if live else PAPER_API

    def ready(self):
        return bool(self.key and self.secret)

    def _call(self, url, method="GET", body=None):
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(url, data=data, method=method, headers={
            "APCA-API-KEY-ID": self.key,
            "APCA-API-SECRET-KEY": self.secret,
            "Content-Type": "application/json",
        })
        try:
            with urllib.request.urlopen(req, timeout=30) as r:
                raw = r.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            # Error bodies can echo order details; keep them off public logs.
            detail = e.read().decode(errors="replace")[:300]
            raise RuntimeError(f"Alpaca HTTP {e.code} on {method} "
                               f"{urllib.parse.urlparse(url).path}"
                               + (f": {detail}" if LOCAL else "")) from None

    def trade(self, path, method="GET", body=None):
        return self._call(self.base + path, method, body)

    def data(self, path, params):
        return self._call(f"{DATA_API}{path}?{urllib.parse.urlencode(params)}")

    def clock(self):
        return self.trade("/v2/clock")

    def positions(self):
        return {p["symbol"]: p for p in self.trade("/v2/positions")}

    def orders_today(self):
        # 08:00 UTC = 3-4am New York: after any late order from yesterday,
        # before today's open. Runs only happen while the market is open.
        since = dt.datetime.now(dt.timezone.utc).replace(
            hour=8, minute=0, second=0, microsecond=0)
        return self.trade("/v2/orders?" + urllib.parse.urlencode({
            "status": "all", "limit": 500,
            "after": since.strftime("%Y-%m-%dT%H:%M:%SZ")}))

    def latest_prices(self, symbols):
        out = self.data("/v2/stocks/trades/latest",
                        {"symbols": ",".join(symbols), "feed": "iex"})
        return {s: float(t["p"]) for s, t in out.get("trades", {}).items()}

    def daily_closes(self, symbols, days=40):
        start = (dt.date.today() - dt.timedelta(days=days * 2)).isoformat()
        out = self.data("/v2/stocks/bars", {
            "symbols": ",".join(symbols), "timeframe": "1Day",
            "start": start, "limit": 10000, "feed": "iex"})
        return {s: [float(b["c"]) for b in bars][-days:]
                for s, bars in out.get("bars", {}).items()}

    def buy(self, symbol, dollars):
        return self.trade("/v2/orders", "POST", {
            "symbol": symbol, "notional": f"{dollars:.2f}", "side": "buy",
            "type": "market", "time_in_force": "day"})

    def sell_all(self, symbol):
        return self.trade(f"/v2/positions/{urllib.parse.quote(symbol)}",
                          "DELETE")


# ------------------------------------------------------------ decision logic

def decide(cfg, prices, closes, positions, orders_today):
    """Pure function: returns a list of (side, symbol, dollars, reason).

    Sells are listed before buys so freed-up cash counts. Every cap is
    enforced here, so the self-test covers them.
    """
    actions = []
    invested = sum(float(p.get("market_value", 0)) for p in positions.values())
    bought_today = {o["symbol"] for o in orders_today if o.get("side") == "buy"}
    orders_left = int(cfg.get("max_orders_per_day", 4)) - len(orders_today)

    for s in cfg.get("stocks", []):
        sym = s["symbol"].upper()
        price = prices.get(sym)
        pos = positions.get(sym)
        if price is None or not pos:
            continue
        entry = float(pos["avg_entry_price"])
        change = (price - entry) / entry * 100
        reason = None
        if s.get("sell_above") and price >= s["sell_above"]:
            reason = f"price {price:.2f} >= sell_above {s['sell_above']}"
        elif s.get("take_profit_pct") and change >= s["take_profit_pct"]:
            reason = f"up {change:.1f}% (target {s['take_profit_pct']}%)"
        elif s.get("stop_loss_pct") and change <= -s["stop_loss_pct"]:
            reason = f"down {change:.1f}% (stop-loss {s['stop_loss_pct']}%)"
        if reason and orders_left > 0:
            actions.append(("SELL", sym, float(pos["market_value"]), reason))
            invested -= float(pos["market_value"])
            orders_left -= 1

    sold = {a[1] for a in actions}
    for s in cfg.get("stocks", []):
        sym = s["symbol"].upper()
        price = prices.get(sym)
        if price is None or sym in sold or sym in bought_today:
            continue
        reason = None
        if s.get("buy_below") and price <= s["buy_below"]:
            reason = f"price {price:.2f} <= buy_below {s['buy_below']}"
        elif s.get("buy_dip_pct") and closes.get(sym):
            high = max(closes[sym][-20:])
            dip = (high - price) / high * 100
            if dip >= s["buy_dip_pct"]:
                reason = f"{dip:.1f}% under its 20-day high {high:.2f}"
        if not reason:
            continue
        held = float(positions.get(sym, {}).get("market_value", 0))
        dollars = min(float(s.get("dollars_per_buy", 0)),
                      float(s.get("max_position_dollars", 0)) - held,
                      float(cfg.get("max_total_invested", 0)) - invested)
        if dollars < 1 or orders_left <= 0:
            continue
        actions.append(("BUY", sym, round(dollars, 2), reason))
        invested += dollars
        orders_left -= 1
    return actions


# ------------------------------------------------------------------- alerts

def notify(title, body, priority="default"):
    topic = os.environ.get("NTFY_TOPIC", "")
    if not topic or os.environ.get("QUIET"):
        return
    req = urllib.request.Request(
        f"https://ntfy.sh/{topic}", data=body.encode(), method="POST",
        headers={"Title": title, "Tags": "chart_with_upwards_trend",
                 "Priority": priority})
    try:
        urllib.request.urlopen(req, timeout=20).read()
    except Exception as e:  # an alert failing must not hide a trade
        print(f"ntfy push failed: {type(e).__name__}")


# --------------------------------------------------------------------- main

def load_cfg():
    with open(WATCHLIST) as f:
        return json.load(f)


def manual_order(broker, text):
    """'BUY AAPL 100' (dollars) or 'SELL AAPL' (whole position)."""
    parts = text.upper().split()
    if len(parts) >= 2 and parts[0] == "SELL":
        broker.sell_all(parts[1])
        return f"SELL {parts[1]} (whole position)"
    if len(parts) == 3 and parts[0] == "BUY":
        dollars = float(parts[2].lstrip("$"))
        if not 1 <= dollars <= 5000:
            raise SystemExit("Manual buy must be between $1 and $5000.")
        broker.buy(parts[1], dollars)
        return f"BUY {parts[1]} ${dollars:.2f}"
    raise SystemExit('Order must look like "BUY AAPL 100" or "SELL AAPL".')


def run():
    cfg = load_cfg()
    live = cfg.get("mode") == "live"
    label = "LIVE" if live else "paper"
    broker = Alpaca(live)
    if not broker.ready():
        print(f"No Alpaca {label} keys set — nothing to do. See README.")
        return 0

    if "--order" in sys.argv:
        done = manual_order(broker, sys.argv[sys.argv.index("--order") + 1])
        say("Manual order sent.", done)
        notify(f"Stock bot ({label}): order sent", done, "high")
        return 0

    if cfg.get("paused") or os.path.exists(PAUSE_FILE):
        print("Paused — no trades.")
        return 0
    if not broker.clock().get("is_open"):
        print("Market closed — no trades.")
        return 0

    symbols = sorted({s["symbol"].upper() for s in cfg.get("stocks", [])})
    if not symbols:
        print("Watchlist is empty.")
        return 0
    prices = broker.latest_prices(symbols)
    closes = broker.daily_closes(symbols)
    positions = broker.positions()
    orders = broker.orders_today()
    actions = decide(cfg, prices, closes, positions, orders)
    if not actions:
        print(f"Checked {len(symbols)} stocks — no trades this run.")
        return 0

    lines = [f"{side} {sym} ${amt:,.2f} — {why}"
             for side, sym, amt, why in actions]
    propose_only = "--dry-run" in sys.argv or (
        live and not cfg.get("live_auto_trade"))
    if propose_only:
        say(f"{len(actions)} trade idea(s) sent to phone, none placed.",
            "; ".join(lines))
        notify(f"Stock bot ({label}): {len(actions)} idea(s) — you decide",
               "\n".join(lines) + "\n\nTo place one: Actions → Stock bot → "
               "Run workflow → order, e.g. BUY AAPL 100", "high")
        return 0

    done, failed = [], []
    for (side, sym, amt, why), line in zip(actions, lines):
        try:
            broker.sell_all(sym) if side == "SELL" else broker.buy(sym, amt)
            done.append(line)
        except RuntimeError as e:
            failed.append(f"{line} — FAILED: {e}")
    say(f"Placed {len(done)} order(s), {len(failed)} failed.",
        "; ".join(done + failed))
    notify(f"Stock bot ({label}): {len(done)} order(s) placed",
           "\n".join(done + failed), "high" if failed else "default")
    return 1 if failed else 0


def selftest():
    cfg = {"max_total_invested": 250, "max_orders_per_day": 3, "stocks": [
        {"symbol": "AAA", "buy_dip_pct": 5, "dollars_per_buy": 100,
         "max_position_dollars": 150, "take_profit_pct": 20,
         "stop_loss_pct": 10},
        {"symbol": "BBB", "buy_below": 50, "dollars_per_buy": 100,
         "max_position_dollars": 300},
        {"symbol": "CCC", "buy_below": 10, "dollars_per_buy": 100,
         "max_position_dollars": 300, "stop_loss_pct": 10},
    ]}
    closes = {"AAA": [100] * 20}
    # AAA 6% under its high, holds $80 -> buy capped to $70 by position cap.
    # BBB under buy_below -> buy capped by max_total_invested.
    # CCC down 20% from entry -> stop-loss sell, and no re-buy same run.
    pos = {"AAA": {"avg_entry_price": "94", "market_value": "80"},
           "CCC": {"avg_entry_price": "10", "market_value": "40"}}
    acts = decide(cfg, {"AAA": 94, "BBB": 40, "CCC": 8}, closes, pos, [])
    got = [(a[0], a[1], a[2]) for a in acts]
    want = [("SELL", "CCC", 40.0), ("BUY", "AAA", 70.0), ("BUY", "BBB", 100.0)]
    assert got == want, got
    # Already bought AAA today -> skip it; daily order cap of 3 with 2 used.
    acts = decide(cfg, {"AAA": 94, "BBB": 40, "CCC": 8}, closes, pos,
                  [{"symbol": "AAA", "side": "buy"}, {"symbol": "X"}])
    assert [(a[0], a[1]) for a in acts] == [("SELL", "CCC")], acts
    # Take-profit.
    acts = decide(cfg, {"AAA": 120}, closes,
                  {"AAA": {"avg_entry_price": "100", "market_value": "120"}},
                  [])
    assert acts[0][:2] == ("SELL", "AAA"), acts
    # Real watchlist parses and has sane caps.
    real = load_cfg()
    assert real["mode"] in ("paper", "live"), real["mode"]
    for s in real["stocks"]:
        assert s["symbol"] and s["dollars_per_buy"] > 0, s
    print("selftest OK")
    return 0


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
