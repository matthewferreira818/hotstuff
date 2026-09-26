"""Snapshot of the practice account for Matthew's live page.

The page (stock_bot/live/index.html, served at findhotstuff.com/stock_bot/
live/) can't fetch prices itself, so the bot publishes this JSON every
couple of minutes during market hours. It goes to its own branch,
`stock-live`, as a single replaced commit: no history pile-up, and no
GitHub Pages rebuild on every update. The page reads it from
raw.githubusercontent.com.

Practice account only. A real-money account's balances must never be
published to a public repo.
"""

import datetime as dt
import json
import os
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BRANCH = "stock-live"


def build(broker, cfg, closes, market_open):
    symbols = [s["symbol"].upper() for s in cfg.get("stocks", [])]
    prices = broker.latest_prices(symbols + ["SPY"])
    acct = broker.acct
    positions = broker.positions()
    traded = {o["symbol"] for o in broker.orders_today()}
    held = sum(p["market_value"] for p in positions.values())
    value = acct["cash"] + held
    start = acct["start_cash"]
    spy_value = (start * prices["SPY"] / acct["spy_at_start"]
                 if prices.get("SPY") and acct.get("spy_at_start") else None)

    stocks = []
    for s in cfg.get("stocks", []):
        sym = s["symbol"].upper()
        price = prices.get(sym)
        row = {"symbol": sym, "price": price,
               "rules": {"dip": s.get("buy_dip_pct"),
                         "buy_below": s.get("buy_below") or None,
                         "take_profit": s.get("take_profit_pct"),
                         "stop_loss": s.get("stop_loss_pct"),
                         "dollars": s.get("dollars_per_buy")}}
        hist = closes.get(sym) or []
        if price and hist:
            high = max(hist[-20:])
            row["high20"] = round(high, 2)
            row["off_high_pct"] = round((price - high) / high * 100, 2)
        pos = positions.get(sym)
        if pos and price:
            entry = float(pos["avg_entry_price"])
            row.update(held=True, qty=round(float(pos["qty"]), 6),
                       entry=round(entry, 2), value=pos["market_value"],
                       change_pct=round((price - entry) / entry * 100, 2))
        else:
            row["held"] = False
        row["traded_today"] = sym in traded
        stocks.append(row)

    return {
        "updated": dt.datetime.now(dt.timezone.utc).isoformat(
            timespec="seconds"),
        "market_open": market_open,
        "account": {
            "started": acct["started"], "start_cash": start,
            "cash": round(acct["cash"], 2), "held": round(held, 2),
            "value": round(value, 2),
            "spy_value": round(spy_value, 2) if spy_value else None,
            "trades": len(acct["orders"]),
            "fees": round(sum(o.get("fee", 0) for o in acct["orders"]), 2),
        },
        "spy_price": prices.get("SPY"),
        "stocks": stocks,
        "orders": list(reversed(acct["orders"]))[:20],
        "picked_by": cfg.get("_stocks_from", ""),
    }


def publish(snapshot):
    """Replace the stock-live branch with one commit holding live.json."""
    git = ["git", "-C", HERE]
    env = dict(os.environ, GIT_AUTHOR_NAME="stock-bot",
               GIT_AUTHOR_EMAIL="stock-bot@users.noreply.github.com",
               GIT_COMMITTER_NAME="stock-bot",
               GIT_COMMITTER_EMAIL="stock-bot@users.noreply.github.com")
    run = lambda *a, inp=None: subprocess.run(
        git + list(a), input=inp, capture_output=True, text=True,
        timeout=60, env=env)
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(snapshot, f, separators=(",", ":"))
    try:
        blob = run("hash-object", "-w", f.name).stdout.strip()
        tree = run("mktree", inp=f"100644 blob {blob}\tlive.json\n"
                   ).stdout.strip()
        commit = run("commit-tree", tree, "-m", "live snapshot"
                     ).stdout.strip()
        ok = commit and run("push", "-q", "-f", "origin",
                            f"{commit}:refs/heads/{BRANCH}").returncode == 0
    finally:
        os.unlink(f.name)
    if not ok:
        print("Live page update failed (will retry).")
    return bool(ok)
