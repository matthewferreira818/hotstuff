#!/usr/bin/env python3
"""The bot's connection to Matthew's Moomoo Canada account.

Why Moomoo: Alpaca won't open accounts for Canadians, and Questrade's API
won't let its customers place trades. Moomoo's OpenAPI is built for it:
the bot talks to moomoo's OpenD program, which Matthew logs into on his
own Mac — so his password never touches this code.

Runs ON THE MAC only (python3 stock_bot/stock_bot.py --moomoo), never on
GitHub Actions: OpenD lives on the Mac, and a real account's numbers must
never reach the public repo or its logs. Setup: stock_bot/MOOMOO-SETUP.md.
Settings: stock_bot/moomoo.json.

Safety, in order:
  - "env": "simulate" (the default) trades Moomoo's own paper account.
  - "env": "real" with live_auto_trade false only texts ideas to his phone.
  - A real order also needs Matthew to click Unlock in OpenD — a lock on
    Moomoo's side that no code here can open.
  - bankroll_usd caps what the bot may ever have in play.
  - The bot only manages stocks IT bought (a ledger in ~/.stockbot/). A
    fund Matthew buys by hand in the same account is never touched.
  - Whole shares only (the API takes no fractions); a bet smaller than one
    share is skipped, never rounded up.
  - Limit orders 0.5% through the quote, never market orders, so a thin
    moment can't fill far from the price the rules saw.

Prices, the market clock and 20-day history come from the same free feed
as the practice account (inherited from PaperBroker), so the rules see the
same numbers in both places.

  python3 stock_bot/moomoo_broker.py --check      # connect, report, trade nothing
  python3 stock_bot/moomoo_broker.py --selftest   # offline, no moomoo needed
"""

import datetime as dt
import json
import math
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from paper_broker import PaperBroker  # noqa: E402  (price feed + clock)

CONFIG = os.path.join(HERE, "moomoo.json")
LEDGER_DIR = os.path.expanduser("~/.stockbot")
PAD = 0.005          # limit price this far through the quote
CACHE_SECONDS = 8    # one fresh account read per 10-second check
REMARK = "stockbot"  # tags our orders, so the daily cap counts only ours
OPEN = {"UNSUBMITTED", "WAITING_SUBMIT", "SUBMITTING", "SUBMITTED",
        "FILLED_PART"}
DEAD = {"SUBMIT_FAILED", "FAILED", "DISABLED", "DELETED", "TIMEOUT"}


def load_config(path=CONFIG):
    with open(path) as f:
        return json.load(f)


def rows(data):
    """moomoo returns pandas DataFrames; the self-test returns lists."""
    return data.to_dict("records") if hasattr(data, "to_dict") else list(data)


def limit_price(price, side):
    """0.5% through the quote, rounded away from it (a buy limit rounds up,
    a sell limit down) to the ticks Moomoo takes: cents from $1, else
    hundredths of a cent."""
    p = price * (1 + PAD) if side == "BUY" else price * (1 - PAD)
    tick = 100 if p >= 1 else 10000
    step = math.ceil if side == "BUY" else math.floor
    return step(round(p * tick, 6)) / tick


def ny_today():
    try:
        from zoneinfo import ZoneInfo
        return dt.datetime.now(ZoneInfo("America/New_York")).date().isoformat()
    except Exception:  # no tz database: EDT is right for most of the year
        return (dt.datetime.now(dt.timezone.utc)
                - dt.timedelta(hours=4)).date().isoformat()


class MoomooBroker(PaperBroker):
    """Same methods stock_bot.py calls on every broker."""

    whole_shares = True

    def __init__(self, conf=None, ctx=None, ledger_path=None):
        self._clock_cache, self._last_prices = (0, None), {}
        self.conf = conf or load_config()
        self.real = self.conf.get("env") == "real"
        self.env = "REAL" if self.real else "SIMULATE"
        self._ctx, self._acc_id, self._cache = ctx, None, {}
        self.ledger_path = ledger_path or os.path.join(
            LEDGER_DIR, f"moomoo-ledger-{self.env.lower()}.json")
        self.not_ready_help = ("Can't reach Moomoo. Is OpenD open and logged "
                               "in? See stock_bot/MOOMOO-SETUP.md.")
        self.manual_hint = ("If you agree, place it yourself in the Moomoo "
                            "app — whole shares, limit order.")

    # ------------------------------------------------------------ plumbing

    def ctx(self):
        if self._ctx is None:
            import moomoo  # pip install moomoo-api (on the Mac only)
            self._ctx = moomoo.OpenSecTradeContext(
                filter_trdmarket=moomoo.TrdMarket.US,
                host=self.conf.get("host", "127.0.0.1"),
                port=int(self.conf.get("port", 11111)),
                security_firm=getattr(moomoo.SecurityFirm,
                                      self.conf.get("security_firm", "FUTUCA")))
        return self._ctx

    def _call(self, name, **kw):
        ret, data = getattr(self.ctx(), name)(**kw)
        if ret != 0:  # moomoo.RET_OK
            raise RuntimeError(f"Moomoo {name} failed: {data}")
        return data

    def _cached(self, key, fetch):
        at, val = self._cache.get(key, (0, None))
        if time.monotonic() - at < CACHE_SECONDS:
            return val
        val = fetch()
        self._cache[key] = (time.monotonic(), val)
        return val

    def acc_id(self):
        """The US account for this env: the paper one, or the real one."""
        if self._acc_id is None:
            accts = [a for a in rows(self._call("get_acc_list"))
                     if str(a.get("trd_env")) == self.env
                     and str(a.get("acc_status", "ACTIVE")) != "DISABLED"]
            us = [a for a in accts if "US" in [str(m) for m in
                                              (a.get("trdmarket_auth") or [])]]
            accts = us or accts
            if not self.real:
                stock = [a for a in accts if str(a.get("sim_acc_type"))
                         in ("STOCK", "STOCK_AND_OPTION")]
                accts = stock or accts
            if not accts:
                raise RuntimeError(f"no {self.env.lower()} US account in OpenD")
            self._acc_id = int(accts[0]["acc_id"])
        return self._acc_id

    def _q(self, name, **kw):
        return rows(self._call(name, trd_env=self.env, acc_id=self.acc_id(),
                               **kw))

    # -------------------------------------------------------------- ledger

    def _ledger(self):
        try:
            with open(self.ledger_path) as f:
                return json.load(f)
        except (OSError, ValueError):
            return {"held": {}}

    def _save_ledger(self, led):
        os.makedirs(os.path.dirname(self.ledger_path), exist_ok=True)
        with open(self.ledger_path, "w") as f:
            json.dump(led, f, indent=1)

    # ------------------------------------------------------------- account

    def ready(self):
        try:
            self.acc_id()
            return True
        except Exception as e:  # OpenD closed, logged out, not installed
            print(f"Moomoo not ready: {type(e).__name__}: {e}")
            return False

    def _positions_all(self):
        return self._cached("pos", lambda: {
            r["code"].split(".", 1)[-1]: r
            for r in self._q("position_list_query") if float(r["qty"]) > 0})

    def positions(self):
        """Only what the bot bought — never a fund bought by hand."""
        mine = self._ledger()["held"]
        return {sym: {"symbol": sym, "qty": float(r["qty"]),
                      "can_sell_qty": float(r.get("can_sell_qty", r["qty"])),
                      "avg_entry_price": float(r.get("average_cost")
                                               or r["cost_price"]),
                      "market_value": float(r["market_val"])}
                for sym, r in self._positions_all().items() if sym in mine}

    def cash(self):
        """US cash the bot may use: what's there, capped by the bankroll
        minus what it already has in play."""
        info = self._cached("acc", lambda: self._q(
            "accinfo_query", currency="USD")[0])
        usd = info.get("us_cash")
        usd = float(usd if usd not in (None, "N/A") else info["cash"])
        in_play = sum(p["market_value"] for p in self.positions().values())
        room = float(self.conf.get("bankroll_usd", 1000)) - in_play
        return round(max(0.0, min(usd, room)), 2)

    def orders_today(self):
        """Today's orders placed by the bot (New York date), in the shape
        decide() expects. Failed orders don't count against the cap."""
        today = ny_today()
        out = []
        for r in self._cached("orders", lambda: self._q("order_list_query")):
            status = str(r["order_status"])
            if (r.get("remark") != REMARK or status in DEAD
                    or not str(r["create_time"]).startswith(today)):
                continue
            out.append({"symbol": r["code"].split(".", 1)[-1],
                        "side": str(r["trd_side"]).lower(),
                        "status": "new" if status in OPEN else status.lower(),
                        "time": str(r["create_time"])})
        return out

    # -------------------------------------------------------------- orders

    def _place(self, symbol, side, qty, price):
        data = self._call(
            "place_order", price=price, qty=qty, code=f"US.{symbol}",
            trd_side=side, order_type="NORMAL", trd_env=self.env,
            acc_id=self.acc_id(), remark=REMARK, time_in_force="DAY")
        self._cache.clear()  # the account just changed
        return data

    def buy(self, symbol, dollars):
        price = limit_price(self._price(symbol), "BUY")
        qty = math.floor(dollars / price)
        if qty < 1:
            raise RuntimeError(f"one share costs ${price:,.2f}, more than "
                               f"the ${dollars:,.2f} bet")
        self._place(symbol, "BUY", qty, price)
        led = self._ledger()
        led["held"][symbol] = {"since": dt.datetime.now(
            dt.timezone.utc).isoformat(timespec="seconds")}
        self._save_ledger(led)
        return {"status": "submitted", "qty": qty, "limit": price}

    def sell_all(self, symbol):
        if symbol not in self._ledger()["held"]:
            raise RuntimeError(f"{symbol} wasn't bought by the bot — "
                               "not touching it")
        pos = self.positions().get(symbol)
        if not pos or pos["can_sell_qty"] < 1:
            raise RuntimeError(f"no sellable {symbol} shares right now")
        price = limit_price(self._price(symbol), "SELL")
        self._place(symbol, "SELL", int(pos["can_sell_qty"]), price)
        led = self._ledger()
        led["held"].pop(symbol, None)
        self._save_ledger(led)
        return {"status": "submitted", "qty": int(pos["can_sell_qty"]),
                "limit": price}


# ---------------------------------------------------------------- check

def check():
    """Connect and report. Trades nothing. Prints to Matthew's own
    terminal, so account numbers are fine here (never run it on GitHub)."""
    b = MoomooBroker()
    print(f"Settings: env={b.env.lower()}, live_auto_trade="
          f"{bool(b.conf.get('live_auto_trade'))}, bankroll "
          f"US${b.conf.get('bankroll_usd')}")
    try:
        accts = rows(b._call("get_acc_list"))
    except Exception as e:
        print(f"Can't reach OpenD: {e}\n{b.not_ready_help}")
        return 1
    print(f"OpenD answered: {len(accts)} account(s).")
    for a in accts:
        print(f"  {a.get('trd_env')}  {a.get('acc_type')}  "
              f"sim={a.get('sim_acc_type')}  markets={a.get('trdmarket_auth')}"
              f"  {a.get('acc_status')}")
    try:
        print(f"Using the {b.env.lower()} US account. Cash the bot may use: "
              f"US${b.cash():,.2f}. Bot-held stocks: "
              f"{list(b.positions()) or 'none'}.")
    except Exception as e:
        print(f"Found OpenD but not a usable account: {e}")
        return 1
    print("All good — nothing was traded.")
    return 0


# -------------------------------------------------------------- selftest

class FakeOpenD:
    """Stands in for moomoo's OpenSecTradeContext: same method names and
    column names as the moomoo API docs; fills limit orders instantly."""

    def __init__(self, cash=1_000_000.0):
        self.cash, self.pos, self.orders = cash, {}, []

    def get_acc_list(self):
        return 0, [
            {"acc_id": 1, "trd_env": "REAL", "acc_type": "CASH",
             "trdmarket_auth": ["US", "CA"], "acc_status": "ACTIVE",
             "sim_acc_type": "N/A"},
            {"acc_id": 2, "trd_env": "SIMULATE", "acc_type": "MARGIN",
             "trdmarket_auth": ["US"], "acc_status": "ACTIVE",
             "sim_acc_type": "STOCK_AND_OPTION"}]

    def accinfo_query(self, trd_env, acc_id, currency=None):
        return 0, [{"us_cash": self.cash, "cash": self.cash}]

    def position_list_query(self, trd_env, acc_id):
        return 0, [{"code": f"US.{s}", "qty": q, "can_sell_qty": q,
                    "cost_price": c, "average_cost": c, "market_val": q * c}
                   for s, (q, c) in self.pos.items()]

    def order_list_query(self, trd_env, acc_id):
        return 0, list(self.orders)

    def place_order(self, price, qty, code, trd_side, order_type, trd_env,
                    acc_id, remark, time_in_force):
        assert order_type == "NORMAL" and qty == int(qty) and qty >= 1
        sym = code.split(".", 1)[1]
        if trd_side == "BUY":
            self.cash -= qty * price
            q, c = self.pos.get(sym, (0, 0))
            self.pos[sym] = (q + qty, (q * c + qty * price) / (q + qty))
        else:
            self.cash += qty * price
            q, c = self.pos[sym]
            self.pos[sym] = (q - qty, c)
            if self.pos[sym][0] == 0:
                del self.pos[sym]
        self.orders.append({"code": code, "trd_side": trd_side, "qty": qty,
                            "order_status": "FILLED_ALL", "remark": remark,
                            "create_time": ny_today() + " 10:00:00.000"})
        return 0, [{"order_id": str(len(self.orders))}]


def selftest():
    import tempfile
    tmp = tempfile.mkdtemp()
    conf = {"env": "simulate", "bankroll_usd": 1000}
    fake = FakeOpenD()
    b = MoomooBroker(conf, ctx=fake,
                     ledger_path=os.path.join(tmp, "ledger.json"))
    prices = {"HOOD": 41.0, "CRWD": 450.0, "VFV": 150.0}
    b.latest_prices = lambda syms: {s: prices[s] for s in syms if s in prices}

    # Picks the US paper account, not the real one.
    assert b.acc_id() == 2
    # A $1,000,000 paper account still looks like a $1,000 bankroll.
    assert b.cash() == 1000.0, b.cash()
    # Whole shares at a limit 0.5% over the quote: $100 at $41.21 = 2 shares.
    r = b.buy("HOOD", 100)
    assert r["qty"] == 2 and r["limit"] == 41.21, r
    assert list(b.positions()) == ["HOOD"]
    assert b.orders_today()[0]["symbol"] == "HOOD"
    # Bankroll counts what's in play: 1000 - 2 x 41.21.
    assert abs(b.cash() - (1000 - 2 * 41.21)) < 0.01, b.cash()
    # One share costs more than the bet -> refused, not rounded up.
    try:
        b.buy("CRWD", 100)
        raise AssertionError("bought a fraction")
    except RuntimeError as e:
        assert "more than" in str(e)
    # A fund Matthew bought by hand is invisible to the bot and can't be sold.
    fake.pos["VFV"] = (5, 140.0)
    b._cache.clear()
    assert list(b.positions()) == ["HOOD"]
    try:
        b.sell_all("VFV")
        raise AssertionError("sold a hand-bought fund")
    except RuntimeError as e:
        assert "wasn't bought by the bot" in str(e)
    # Selling the bot's own stock: whole position, limit 0.5% under.
    r = b.sell_all("HOOD")
    assert r["qty"] == 2 and r["limit"] == 40.79, r
    assert list(b.positions()) == [] and "VFV" in fake.pos
    # Orders not tagged as ours don't count toward the daily cap.
    fake.orders.append({"code": "US.VFV", "trd_side": "BUY", "qty": 5,
                        "order_status": "FILLED_ALL", "remark": "",
                        "create_time": ny_today() + " 11:00:00"})
    b._cache.clear()
    assert [o["symbol"] for o in b.orders_today()] == ["HOOD", "HOOD"]
    # Real env picks the real account.
    real = MoomooBroker({"env": "real"}, ctx=FakeOpenD(),
                        ledger_path=os.path.join(tmp, "l2.json"))
    assert real.acc_id() == 1 and real.real
    print("selftest OK")
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(check())
