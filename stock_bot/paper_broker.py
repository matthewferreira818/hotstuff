#!/usr/bin/env python3
"""Our own practice brokerage: real live prices, fake money.

Built because Alpaca won't open accounts for Canadian tax residents, not
even practice ones. It speaks the same language as the Alpaca class in
stock_bot.py, so the bot and its rules don't change.

Honest-by-design:
  - Prices are real (Yahoo's free feed, about 1 minute fresh).
  - Every trade pays a fee and a little slippage (settings in
    watchlist.json, "paper_costs"), because real trades do. The defaults
    model a small account at a Canadian broker like Interactive Brokers
    Canada: a $1 minimum commission and ~0.1% worse fills. Check the
    broker's current price list before trusting them.
  - The account lives in stock_bot/paper/account.json, committed to the
    repo after every trade, so the record can't quietly change.

Usage:
  python stock_bot/paper_broker.py --status     # value vs SPY since start
  python stock_bot/paper_broker.py --selftest
"""

import datetime as dt
import json
import os
import subprocess
import sys
import time
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ACCOUNT = os.path.join(HERE, "paper", "account.json")
START_CASH = 1000.0
UA = {"User-Agent": "Mozilla/5.0"}


def _get(url):
    req = urllib.request.Request(url, headers=UA)
    for attempt in range(3):
        try:
            with urllib.request.urlopen(req, timeout=20) as r:
                return json.load(r)
        except Exception:
            if attempt == 2:
                raise RuntimeError("price feed unavailable") from None
            time.sleep(2 * (attempt + 1))


def new_account(spy_price, now):
    return {"started": now, "start_cash": START_CASH, "cash": START_CASH,
            "spy_at_start": spy_price, "positions": {}, "orders": []}


class PaperBroker:
    """Same methods the bot calls on Alpaca."""

    def __init__(self, costs=None, path=ACCOUNT, save_hook=None):
        costs = costs or {}
        self.fee = float(costs.get("fee_per_trade", 1.0))
        self.slip = float(costs.get("slippage_pct", 0.1)) / 100
        self.path = path
        self.save_hook = save_hook if save_hook is not None else git_save
        self._clock_cache = (0, None)
        self._last_prices = {}
        self.acct = self._load()

    # -------------------------------------------------------------- state

    def _load(self):
        if os.path.exists(self.path):
            with open(self.path) as f:
                return json.load(f)
        spy = self.latest_prices(["SPY"]).get("SPY")
        return new_account(spy, _now())

    def _save(self, message):
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        with open(self.path, "w") as f:
            json.dump(self.acct, f, indent=1)
        self.save_hook(self.path, message)

    def ready(self):
        return True

    # ----------------------------------------------------------- market

    def clock(self):
        """Open/closed from SPY's trading period (covers holidays and
        early closes). Cached for a minute."""
        at, cached = self._clock_cache
        if cached and time.time() - at < 60:
            return cached
        meta = _get("https://query1.finance.yahoo.com/v8/finance/chart/SPY"
                    "?range=1d&interval=1m")["chart"]["result"][0]["meta"]
        reg = meta["currentTradingPeriod"]["regular"]
        now = time.time()
        iso = lambda ts: dt.datetime.fromtimestamp(
            ts, dt.timezone.utc).isoformat()
        is_open = reg["start"] <= now < reg["end"]
        # After today's close the next open is unknown here; say "far off"
        # so the bot doesn't wait for it.
        next_open = reg["start"] if now < reg["start"] else now + 86400
        out = {"is_open": is_open, "next_open": iso(next_open),
               "next_close": iso(reg["end"])}
        self._clock_cache = (now, out)
        return out

    def latest_prices(self, symbols):
        q = urllib.parse.urlencode({"symbols": ",".join(symbols),
                                    "range": "1d", "interval": "1m"})
        data = _get(f"https://query1.finance.yahoo.com/v8/finance/spark?{q}")
        out = {}
        for sym, v in data.items():
            closes = [c for c in (v.get("close") or []) if c is not None]
            if closes:
                out[sym] = float(closes[-1])
        self._last_prices.update(out)
        return out

    def daily_closes(self, symbols, days=40):
        sys.path.insert(0, HERE)
        from screener import fetch
        out = {}
        for s in symbols:
            bars = fetch(s, "6mo")
            if bars:
                out[s] = [b["close"] for b in bars][-days:]
        return out

    # --------------------------------------------------------- account

    def positions(self):
        prices = self._last_prices
        out = {}
        for sym, p in self.acct["positions"].items():
            price = prices.get(sym) or p["avg_entry_price"]
            out[sym] = {"symbol": sym, "qty": p["qty"],
                        "avg_entry_price": p["avg_entry_price"],
                        "market_value": round(p["qty"] * price, 2)}
        return out

    def orders_today(self):
        # Same cut-off as the Alpaca path: 08:00 UTC today.
        cut = dt.datetime.now(dt.timezone.utc).replace(
            hour=8, minute=0, second=0, microsecond=0).isoformat()
        return [o for o in self.acct["orders"] if o["time"] >= cut]

    def buy(self, symbol, dollars):
        price = self._price(symbol) * (1 + self.slip)
        spend = dollars - self.fee
        if dollars > self.acct["cash"] + 1e-9:
            raise RuntimeError(f"not enough practice cash for {symbol}")
        if spend <= 0:
            raise RuntimeError("buy is smaller than the fee")
        qty = spend / price
        pos = self.acct["positions"].get(symbol)
        if pos:
            total = pos["qty"] + qty
            pos["avg_entry_price"] = round(
                (pos["qty"] * pos["avg_entry_price"] + dollars) / total, 4)
            pos["qty"] = total
        else:
            # The entry price includes the fee, so the bot's take-profit
            # and stop-loss measure what actually came out of pocket.
            self.acct["positions"][symbol] = {
                "qty": qty, "avg_entry_price": round(dollars / qty, 4)}
        self.acct["cash"] = round(self.acct["cash"] - dollars, 2)
        self._record(symbol, "buy", qty, price, dollars)
        self._save(f"Practice trade: buy {symbol}")
        return {"status": "filled"}

    def sell_all(self, symbol):
        pos = self.acct["positions"].get(symbol)
        if not pos:
            raise RuntimeError(f"no practice position in {symbol}")
        price = self._price(symbol) * (1 - self.slip)
        proceeds = pos["qty"] * price - self.fee
        self.acct["cash"] = round(self.acct["cash"] + proceeds, 2)
        del self.acct["positions"][symbol]
        self._record(symbol, "sell", pos["qty"], price, proceeds)
        self._save(f"Practice trade: sell {symbol}")
        return {"status": "filled"}

    def _price(self, symbol):
        p = self.latest_prices([symbol]).get(symbol)
        if not p:
            raise RuntimeError(f"no live price for {symbol}")
        return p

    def _record(self, symbol, side, qty, price, dollars):
        self.acct["orders"].append({
            "time": _now(), "symbol": symbol, "side": side,
            "status": "filled", "qty": round(qty, 6),
            "price": round(price, 4), "dollars": round(dollars, 2),
            "fee": self.fee})


def _now():
    return dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds")


def git_save(path, message):
    """Commit the account after a trade so the record survives. Only on
    GitHub Actions; locally the file is just written."""
    if not os.environ.get("GITHUB_ACTIONS"):
        return
    git = ["git", "-C", HERE]
    run = lambda *a: subprocess.run(git + list(a), capture_output=True,
                                    timeout=60)
    run("config", "user.name", "stock-bot")
    run("config", "user.email", "stock-bot@users.noreply.github.com")
    run("add", path)
    run("commit", "-q", "-m", message)
    branch = os.environ.get("GITHUB_REF_NAME", "master")
    for _ in range(4):
        run("pull", "-q", "--rebase", "origin", branch)
        if run("push", "-q", "origin", f"HEAD:{branch}").returncode == 0:
            return
        time.sleep(5)
    print("Could not push the practice account (will retry next trade).")


def status():
    if not os.path.exists(ACCOUNT):
        print("No practice account yet — it opens on the first trading run.")
        return
    b = PaperBroker(save_hook=lambda *a: None)
    syms = list(b.acct["positions"]) + ["SPY"]
    prices = b.latest_prices(syms)
    held = sum(p["market_value"] for p in b.positions().values())
    value = b.acct["cash"] + held
    start = b.acct["start_cash"]
    spy = start * prices["SPY"] / b.acct["spy_at_start"]
    fees = sum(o["fee"] for o in b.acct["orders"])
    print(f"Practice account since {b.acct['started'][:10]}: "
          f"${value:,.2f} ({value / start * 100 - 100:+.1f}%)")
    print(f"Same ${start:,.0f} in SPY: ${spy:,.2f} "
          f"({spy / start * 100 - 100:+.1f}%)")
    print(f"Cash ${b.acct['cash']:,.2f} · held ${held:,.2f} · "
          f"{len(b.acct['orders'])} trades · ${fees:,.2f} in fees")


def selftest():
    import tempfile
    path = os.path.join(tempfile.mkdtemp(), "acct.json")
    b = PaperBroker.__new__(PaperBroker)
    b.fee, b.slip, b.path = 1.0, 0.001, path
    b.save_hook = lambda *a: None
    b._clock_cache, b._last_prices = (0, None), {}
    b.acct = new_account(500.0, _now())
    price = {"X": 100.0}
    b.latest_prices = lambda syms: {s: price[s] for s in syms if s in price}
    b.buy("X", 100)
    assert b.acct["cash"] == 900.0
    pos = b.acct["positions"]["X"]
    assert abs(pos["qty"] - 99 / 100.1) < 1e-9, pos
    # Entry counts the fee: flat price already shows a small loss.
    assert pos["avg_entry_price"] > 100.1
    price["X"] = 120.0
    b._last_prices = {"X": 120.0}
    mv = b.positions()["X"]["market_value"]
    assert abs(mv - pos["qty"] * 120) < 0.01
    b.sell_all("X")
    # 99/100.1 shares * 119.88 - $1 fee
    assert abs(b.acct["cash"] - (900 + 99 / 100.1 * 119.88 - 1)) < 0.01
    assert [o["side"] for o in b.orders_today()] == ["buy", "sell"]
    try:
        b.buy("X", 5000)
        raise AssertionError("overspent")
    except RuntimeError:
        pass
    print("selftest OK")


if __name__ == "__main__":
    selftest() if "--selftest" in sys.argv else status()
