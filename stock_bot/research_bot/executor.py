#!/usr/bin/env python3
"""The paper executor: turns committed forecasts into PRACTICE trades, only
through the existing practice broker (paper_broker.py) and only when the
rule checker says yes. PRACTICE MONEY ONLY: there is no real-money path in
this file or anywhere in research_bot/ (no exchange, no real broker, no keys),
and it refuses to run on GitHub Actions.

One run:
  1. stop if a PAUSE file exists or rules.json doesn't match rules.lock;
  2. read the forecast ledger and its git history (append-only + timing proof);
  3. per market (stocks, crypto: separate practice accounts), get fresh prices
     with their timestamps, value the account, save an equity snapshot, and
     turn the auto-pause on if the day's loss or week's drawdown cap is hit;
  4. close positions whose forecast window has ended;
  5. open positions for 'up' forecasts that asked for a trade and whose window
     is open, sized at max_position_pct of the account.
Every order has a fixed id (<forecast id>:buy / :sell) written to orders.jsonl
BEFORE it is placed, so a crash or a retry can never place it twice; an order
left half-done stops that market until a human looks.

  python3 -m stock_bot.research_bot.executor --dry-run   # decide, place nothing
  python3 -m stock_bot.research_bot.executor             # place paper orders

Nothing schedules this yet (NB2's OK needed before any schedule).
"""

import datetime as dt
import json
import math
import os
import sys
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))

import checker  # noqa: E402
import scorer  # noqa: E402
import forecasts as ledger  # noqa: E402
from paper_broker import PaperBroker, new_account  # noqa: E402

ORDERS = os.path.join(HERE, "orders.jsonl")
RUN_LOCK = os.path.join(HERE, "RUN_LOCK")
STALE_LOCK_MIN = 30
EQUITY = os.path.join(HERE, "equity.jsonl")
PAPER_DIR = os.path.join(os.path.dirname(HERE), "paper")


class ResearchBroker(PaperBroker):
    """The practice broker, but it trades at the exact quote the checker
    approved (no second price fetch between 'yes' and the fill), never
    fetches anything itself, and never pings or pushes."""

    def __init__(self, costs, path, start_cash, quotes):
        self.quotes = quotes
        self.fee = float(costs.get("fee_min", costs.get("fee_per_trade", 1.0)))
        self.fee_per_share = float(costs.get("fee_per_share", 0.0))
        self.fee_pct = float(costs.get("fee_pct", 0.0)) / 100
        self.slip = float(costs.get("slippage_pct", 0.1)) / 100
        self.path = path
        self.save_hook = lambda *a: None
        self._clock_cache = (0, None)
        self._last_prices = {s: q["price"] for s, q in quotes.items()}
        if os.path.exists(path):
            self.acct = self._load()
        else:
            self.acct = new_account(None, ledger.iso(ledger.utcnow()))
            self.acct.update(start_cash=start_cash, cash=start_cash,
                             deposited=start_cash, spy_units=0.0)

    def latest_prices(self, symbols):
        return {s: self.quotes[s]["price"] for s in symbols if s in self.quotes}

    def sell_all(self, symbol):
        # Same as PaperBroker.sell_all minus the "made money" phone ping:
        # the research bot reports through the scorecard only.
        pos = self.acct["positions"].get(symbol)
        if not pos:
            raise RuntimeError(f"no practice position in {symbol}")
        price = self._price(symbol) * (1 - self.slip)
        fee = self.order_fee(pos["qty"], pos["qty"] * price)
        proceeds = pos["qty"] * price - fee
        self.acct["cash"] = round(self.acct["cash"] + proceeds, 2)
        del self.acct["positions"][symbol]
        self._record(symbol, "sell", pos["qty"], price, proceeds, fee)
        self._save(f"Research bot practice trade: sell {symbol}")
        return {"status": "filled",
                "profit": round(proceeds - pos["qty"] * pos["avg_entry_price"], 2)}

    def value(self):
        held = sum(p["qty"] * self.quotes[s]["price"]
                   for s, p in self.acct["positions"].items())
        return self.acct["cash"] + held


def yahoo_quote(asset, lookback_min=15):
    """Latest 1-minute price WITH its time, plus the price ~lookback_min
    earlier (for the big-jump halt). None on any failure: fail closed."""
    q = urllib.parse.urlencode({"range": "1d", "interval": "1m"})
    url = (f"https://query1.finance.yahoo.com/v8/finance/chart/"
           f"{urllib.parse.quote(asset)}?{q}")
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=20) as r:
            res = json.load(r)["chart"]["result"][0]
        pts = [(t, c) for t, c in zip(res["timestamp"],
                                      res["indicators"]["quote"][0]["close"])
               if c is not None]
        t, c = pts[-1]
        ago = [c0 for t0, c0 in pts if t0 <= t - lookback_min * 60]
        return {"price": float(c),
                "time": dt.datetime.fromtimestamp(t, dt.timezone.utc),
                "price_ago": float(ago[-1]) if ago else None}
    except Exception:
        return None


def yahoo_daily_range(asset, days=20):
    """Typical (median) daily high-low range in %, over the last `days`
    finished days. None on any failure: no range = no stop = no buy."""
    try:
        from screener import fetch
        bars = fetch(asset, "3mo")[-days - 1:-1]
        rng = sorted((b["high"] - b["low"]) / b["close"] * 100 for b in bars if b["close"])
        return rng[len(rng) // 2] if len(rng) >= days // 2 else None
    except Exception:
        return None


class RunLock:
    """Only one executor at a time. The lock file is made atomically; a
    lock older than STALE_LOCK_MIN minutes (a crashed run) is taken over and
    said so. Half-done orders are caught separately by the order log."""

    def __init__(self, path=RUN_LOCK, now=None):
        self.path, self.now, self.note, self.held = path, now, None, False

    def __enter__(self):
        now = self.now or ledger.utcnow()
        for _ in range(2):
            try:
                fd = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                with os.fdopen(fd, "w") as f:
                    f.write(f"{os.getpid()} {ledger.iso(now)}\n")
                self.held = True
                return self
            except FileExistsError:
                try:
                    with open(self.path) as f:
                        started = ledger.parse_time(f.read().split()[1])
                except (OSError, IndexError, ValueError):
                    started = now
                if now - started < dt.timedelta(minutes=STALE_LOCK_MIN):
                    return self
                self.note = f"took over a stale run lock from {ledger.iso(started)}"
                os.replace(self.path, self.path + ".stale")
        return self

    def __exit__(self, *exc):
        if self.held and os.path.exists(self.path):
            os.remove(self.path)
        return False


def read_jsonl(path):
    return ledger.read_lines(path)


def append_jsonl(path, rec):
    with open(path, "a") as f:
        f.write(json.dumps(rec, sort_keys=True, default=str) + "\n")


def run(now=None, quote_fn=yahoo_quote, dry_run=False, lines=None, first_seen=None,
        rules=None, rules_ok=None, manual_pause=None, paper_dir=PAPER_DIR,
        orders_path=ORDERS, equity_path=EQUITY, auto_pause_path=checker.AUTO_PAUSE,
        range_fn=yahoo_daily_range, lock_path=RUN_LOCK):
    """Returns a list of plain-English log lines. Everything it touches can be
    passed in, so tests run offline in a temp folder."""
    if os.environ.get("GITHUB_ACTIONS"):
        return ["refused: the research bot never runs on GitHub Actions"]
    with RunLock(lock_path, now=ledger.parse_time(now) if now else None) as lock:
        if not lock.held:
            return ["another executor run is in progress: nothing done"]
        log = _run(now, quote_fn, dry_run, lines, first_seen, rules, rules_ok,
                   manual_pause, paper_dir, orders_path, equity_path,
                   auto_pause_path, range_fn)
        return ([lock.note] if lock.note else []) + log


def _run(now, quote_fn, dry_run, lines, first_seen, rules, rules_ok, manual_pause,
         paper_dir, orders_path, equity_path, auto_pause_path, range_fn):
    now = ledger.parse_time(now or ledger.utcnow())
    rules = rules or ledger.load_rules()
    rules_ok = checker.rules_locked_ok() if rules_ok is None else rules_ok
    manual_pause = checker.manual_pause_on() if manual_pause is None else manual_pause
    log = []
    if manual_pause:
        return ["PAUSE file present: nothing done"]
    if not rules_ok or rules.get("practice_only") is not True:
        return ["rules.json doesn't match rules.lock (or isn't practice_only): nothing done"]
    if lines is None or first_seen is None:
        ok, problems, first_seen = ledger.verify()
        if not ok:
            return ["forecast file was edited, not appended: nothing done"] + problems
        lines = ledger.read_lines()
    by_id = {l["id"]: l for l in lines if l.get("kind") == "forecast"}
    idea_text = {l["id"]: l.get("text", "") for l in lines if l.get("kind") == "idea"}
    replay = scorer.replay_log()
    orders = read_jsonl(orders_path)
    seen = {o["id"] for o in orders}
    unfinished = {o["id"] for o in orders if o["status"] == "intent"} - {
        o["id"] for o in orders if o["status"] in ("filled", "failed")}
    new_today = sum(1 for o in orders if o["status"] == "intent" and o["side"] == "buy"
                    and ledger.parse_time(o["time"]) >= checker.day_start(now))
    auto_pause = None
    if os.path.exists(auto_pause_path):
        with open(auto_pause_path) as f:
            auto_pause = f.read().strip() or "auto-pause on"

    for market, m in rules["markets"].items():
        path = os.path.join(paper_dir, m["account_file"])
        if any(by_id.get(i.split(":")[0], {}).get("market") == market for i in unfinished):
            log.append(f"[{market}] an order was left half-done ({sorted(unfinished)}): "
                       "market stopped until a human checks the account")
            continue
        acct_held = []
        if os.path.exists(path):
            with open(path) as f:
                acct_held = list(json.load(f).get("positions", {}))
        due_buys = [f for f in by_id.values() if f["market"] == market and f.get("act")
                    and ledger.parse_time(f["opens_at"]) <= now
                    < ledger.parse_time(f["resolves_at"]) and f"{f['id']}:buy" not in seen]
        assets = sorted(set(acct_held) | {f["asset"] for f in due_buys})
        if not assets:
            log.append(f"[{market}] nothing to do (no trade is a normal outcome)")
            continue
        quotes = {a: quote_fn(a) for a in assets}
        missing = [a for a in acct_held if not quotes.get(a)]
        if missing:
            log.append(f"[{market}] no price for held {missing}: can't value the account, halt")
            continue
        broker = ResearchBroker(m["costs"], path, rules["start_cash"],
                                {a: q for a, q in quotes.items() if q})
        value = broker.value()
        append_jsonl(equity_path, {"time": ledger.iso(now), "market": market,
                                   "value": round(value, 2)})
        equity = [(ledger.parse_time(e["time"]), e["value"])
                  for e in read_jsonl(equity_path) if e["market"] == market]
        reason = checker.risk_pause_reason(equity, rules, now)
        if reason and not auto_pause:
            auto_pause = f"{market}: {reason} ({ledger.iso(now)})"
            if not dry_run:
                with open(auto_pause_path, "w") as f:
                    f.write(auto_pause + "\n")
            log.append(f"[{market}] AUTO-PAUSE: {reason}")

        # Which forecast opened each held position, and its stop (our order log).
        opener = {o["asset"]: o for o in orders
                  if o["status"] == "filled" and o["side"] == "buy"}
        planned, stop_hit = [], set()
        for asset in acct_held:
            o = opener.get(asset) or {}
            fid = o.get("forecast_id")
            f = by_id.get(fid)
            entry = broker.acct["positions"][asset]["avg_entry_price"]
            stop = o.get("stop_pct")
            if stop and quotes[asset]["price"] <= entry * (1 - stop / 100):
                stop_hit.add(asset)
                planned.append({"id": f"{fid}:stop", "side": "sell", "asset": asset,
                                "market": market, "forecast_id": fid})
            elif f and now >= ledger.parse_time(f["resolves_at"]):
                planned.append({"id": f"{fid}:sell", "side": "sell", "asset": asset,
                                "market": market, "forecast_id": fid})
        ranges = {}
        for f in sorted(due_buys, key=lambda f: f["opens_at"]):
            rng = ranges.setdefault(f["asset"], range_fn(f["asset"]))
            stop = round(rules["stop_daily_ranges"] * rng, 2) if rng else None
            planned.append({"id": f"{f['id']}:buy", "side": "buy", "asset": f["asset"],
                            "market": market, "forecast_id": f["id"],
                            "stop_pct": stop})

        for o in planned:
            f = by_id.get(o["forecast_id"])
            if o["side"] == "buy":
                # Size each buy from the account as it is NOW: an earlier fill this
                # run shrank it by fee + slippage. Round down so it never tops the cap.
                o["dollars"] = math.floor(broker.value() * rules["max_position_pct"]) / 100
            seen_at = first_seen.get(o["forecast_id"])
            ctx = {"rules": rules, "rules_ok": rules_ok, "manual_pause": manual_pause,
                   "auto_pause": auto_pause, "now": now, "forecast": f,
                   "committed_before_open": bool(
                       f and seen_at is not None
                       and seen_at < ledger.parse_time(f["opens_at"]).timestamp()),
                   "quote": quotes.get(o["asset"]),
                   "account": {"value": broker.value(), "cash": broker.cash(),
                               "positions": broker.acct["positions"]},
                   "equity": equity, "seen_ids": seen, "new_orders_today": new_today,
                   "daily_range_pct": ranges.get(o["asset"]),
                   "stop_hit": o["side"] == "sell" and o["asset"] in stop_hit}
            ok, why, pause = checker.check_order(o, ctx)
            if pause and not auto_pause:
                auto_pause = f"{market}: {pause} ({ledger.iso(now)})"
                if not dry_run:
                    with open(auto_pause_path, "w") as fh:
                        fh.write(auto_pause + "\n")
            if not ok:
                log.append(f"[{market}] NO {o['side']} {o['asset']}: {'; '.join(why)}")
                continue
            if dry_run:
                log.append(f"[{market}] would {o['side']} {o['asset']} (dry run)")
                continue
            base = dict(o, time=ledger.iso(now), practice=True)
            if f:  # say plainly where the idea stands, so nobody reads a practice trade as a signal
                status = scorer.replay_status(market, idea_text.get(f.get("idea"), ""), replay)
                base["replay_status"] = status
                if status == "DEAD":
                    base["label"] = scorer.FAILED_LABEL
            append_jsonl(orders_path, dict(base, status="intent"))
            seen.add(o["id"])
            try:
                if o["side"] == "buy":
                    broker.buy(o["asset"], o["dollars"])
                    new_today += 1
                    res = {}
                else:
                    res = broker.sell_all(o["asset"])
                append_jsonl(orders_path, dict(base, status="filled",
                                               profit=res.get("profit")))
                log.append(f"[{market}] practice {o['side']} {o['asset']} filled"
                           + (" (idea FAILED the replay: data only)" if base.get("label") else ""))
            except Exception as e:
                append_jsonl(orders_path, dict(base, status="failed",
                                               error=type(e).__name__))
                log.append(f"[{market}] practice {o['side']} {o['asset']} failed: {e}")
    return log


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description="Paper executor (practice money only).")
    ap.add_argument("--dry-run", action="store_true", help="decide, place nothing")
    args = ap.parse_args(argv)
    for line in run(dry_run=args.dry_run):
        print(line)
    return 0


if __name__ == "__main__":
    sys.exit(main())
