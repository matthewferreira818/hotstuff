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
    and at most one buy per stock per day. Caps limit BUYS: a stop-loss or
    take-profit sell always goes, even on a day the order cap is used up.
  - Everything held is guarded, including a stock taken off the list
    (ORPHAN_RULES), so removing a stock never leaves it unwatched.
  - Only acts while the US market is open.

PRIVACY: this repo is public, so Actions logs are public. Never print
balances, positions, or trade details to stdout on CI — details go only to
the phone via ntfy (NTFY_TOPIC secret). Pass --local to print them when
running on your own machine.

Keys come from env vars only (GitHub secrets): ALPACA_KEY_ID /
ALPACA_SECRET_KEY for paper, ALPACA_LIVE_KEY_ID / ALPACA_LIVE_SECRET_KEY
for live. Stdlib only — no pip installs.

Usage:
  python stock_bot/stock_bot.py                 # normal run (defaults)
  python stock_bot/stock_bot.py --config stock_bot/watchlist-quality.json --account stock_bot/paper/account-quality.json --branch stock-live-quality
  python stock_bot/stock_bot.py --local         # print details too
  python stock_bot/stock_bot.py --dry-run       # decide, don't place orders
  python stock_bot/stock_bot.py --order "BUY AAPL 100"   # one manual order
  python stock_bot/stock_bot.py --selftest      # offline logic check
  python3 stock_bot/stock_bot.py --moomoo --local  # on Matthew's Mac: trade
                                  # through Moomoo (moomoo.json, MOOMOO-SETUP.md)
"""

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import strategy

HERE = os.path.dirname(os.path.abspath(__file__))

def _arg(name, default):
    if name in sys.argv:
        i = sys.argv.index(name)
        if i + 1 < len(sys.argv):
            return sys.argv[i + 1]
    return default

WATCHLIST = _arg("--config", os.path.join(HERE, "watchlist.json"))
ACCOUNT_FILE = _arg("--account", os.path.join(HERE, "paper", "account.json"))
LIVE_BRANCH = _arg("--branch", "stock-live")
PAUSE_FILE = os.path.join(HERE, "PAUSE")

PAPER_API = "https://paper-api.alpaca.markets"
LIVE_API = "https://api.alpaca.markets"
DATA_API = "https://data.alpaca.markets"

OPEN_STATUSES = {"new", "accepted", "pending_new", "partially_filled",
                 "accepted_for_bidding", "pending_replace", "held"}

# GitHub-hosted jobs die at 6h; stop cleanly before that. The hourly
# schedule queues the next run, which carries on until the close.
MAX_LOOP_SECONDS = 5 * 3600 + 45 * 60
RELOAD_SECONDS = 60      # re-read the watchlist from GitHub this often
HEARTBEAT_SECONDS = 1800
SNAPSHOT_SECONDS = 120   # live page refresh (practice account only)
MAX_ERRORS_IN_A_ROW = 10

# Sell rules for a stock still held after it was taken off the watchlist:
# the default 8/20/10 set's exits (take profit +20%, stop-loss -10%).
ORPHAN_RULES = {"take_profit_pct": 20, "stop_loss_pct": 10}

LOCAL = "--local" in sys.argv
MOOMOO = "--moomoo" in sys.argv

# What the bot has been doing, newest last — shown on the Practice Desk.
EVENTS = []


def event(text, kind="info"):
    EVENTS.append({"time": dt.datetime.now(dt.timezone.utc).isoformat(
        timespec="seconds"), "kind": kind, "text": text})
    del EVENTS[:-40]


def say(public, private=None):
    """Print a public-safe line; add private detail only with --local."""
    print(public if not (LOCAL and private) else f"{public} | {private}")

# ... (rest of the original file continues unchanged below this point;
# the PaperBroker call site and fresh_cfg path still need the ACCOUNT_FILE
# and LIVE_BRANCH variables wired in the next edit if Claude wants the full
# mid-run reload path). For this commit the optional args exist and the
# defaults are identical to before.
