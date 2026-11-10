#!/usr/bin/env python3
"""The live forecaster: runs the plain-code ideas on the latest real prices
and writes FORWARD forecasts into the ledger. PRACTICE / RESEARCH ONLY.

It uses the exact functions the history replay tested (ideas.py), on bars
that have fully finished (a bar still in progress is dropped), and logs:
  - one forecast per (idea variant, asset) that makes a call, unless that
    variant already has an open forecast on that asset (no piling up);
  - one no_trade line per market when nothing at all was called.

Which variants run, on which assets, lives in forward.json (research config,
reviewed like code). Crypto runs any day, any hour. Stocks open at the next
New York market open and close at the open `horizon` trading days later.

  python3 -m stock_bot.research_bot.generate --dry-run
  python3 -m stock_bot.research_bot.generate --commit    # writes, commits, pushes

The window opens at least 15 minutes after writing, and --commit pushes at
once, so every forecast is in git before its window opens. Without --commit,
commit + push forecasts.jsonl yourself right away.
"""

import datetime as dt
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.dirname(HERE))

import forecasts as ledger  # noqa: E402
import ideas as idea_lib  # noqa: E402
import scorer  # noqa: E402

FORWARD = os.path.join(HERE, "forward.json")
AUTHOR = "generate.py"

try:
    from zoneinfo import ZoneInfo
    NY = ZoneInfo("America/New_York")
except Exception:  # pragma: no cover
    NY = None


class ForwardMissing(RuntimeError):
    pass


def load_forward(path=FORWARD):
    if not os.path.exists(path):
        raise ForwardMissing(f"{os.path.basename(path)} is missing: no idea variants to forecast. "
                             "Run replay.py and commit forward.json (see the spec).")
    with open(path) as f:
        fwd = json.load(f)
    if not fwd.get("variants"):
        raise ForwardMissing("forward.json has no variants: nothing to forecast")
    return fwd


def crypto_window(now, horizon_hours, lead_min):
    """Next whole hour at least lead_min away."""
    t = (now + dt.timedelta(minutes=lead_min)).replace(minute=0, second=0, microsecond=0)
    if t < now + dt.timedelta(minutes=lead_min):
        t += dt.timedelta(hours=1)
    return t, t + dt.timedelta(hours=horizon_hours)


def crypto_day_window(now, horizon_days, lead_min):
    """Daily crypto bars start at 00:00 UTC: the next midnight at least
    lead_min away, to the midnight horizon_days later."""
    t = (now + dt.timedelta(minutes=lead_min)).replace(hour=0, minute=0, second=0, microsecond=0)
    if t < now + dt.timedelta(minutes=lead_min):
        t += dt.timedelta(days=1)
    return t, t + dt.timedelta(days=horizon_days)


def _next_weekday_open(day):
    while day.weekday() >= 5:
        day += dt.timedelta(days=1)
    return dt.datetime(day.year, day.month, day.day, 9, 30, tzinfo=NY).astimezone(dt.timezone.utc)


def stock_window(now, horizon_days, lead_min):
    """Next NY 9:30 open at least lead_min away, to the open horizon_days
    trading days later (weekends skipped; a holiday rolls to the next bar)."""
    local = now.astimezone(NY)
    t = _next_weekday_open(local.date())
    if t < now + dt.timedelta(minutes=lead_min):
        t = _next_weekday_open(local.date() + dt.timedelta(days=1))
    end = t.astimezone(NY).date()
    for _ in range(horizon_days):
        end = _next_weekday_open(end + dt.timedelta(days=1)).astimezone(NY).date()
    return t, _next_weekday_open(end)


def finished(bars, interval, now, market="stock"):
    """Drop a bar that hasn't finished yet. A daily stock bar is stamped at the
    9:30 open and finishes at the 4:00 close (6.5 h later; 7 h for margin);
    a daily crypto bar runs a full 24 hours."""
    length = 3600 if interval == "1h" else (86400 if market == "crypto" else 7 * 3600)
    return [b for b in bars if b[0] + length <= now.timestamp()] if bars else []


def idea_id_for(lines, market, text, path, now):
    for l in lines:
        if l.get("kind") == "idea" and l.get("text") == text and l.get("market") == market:
            return l["id"], False
    return ledger.add_idea(market, text, AUTHOR, path, now=now)["id"], True


def generate(now=None, bars_fn=None, path=ledger.LEDGER, forward=None, rules=None,
             dry_run=False):
    """Returns plain-English log lines. bars_fn(asset, interval) -> bars."""
    now = ledger.parse_time(now or ledger.utcnow())
    forward = forward or load_forward()
    rules = rules or ledger.load_rules()
    lead = rules.get("min_lead_minutes", 15) + 5
    lines = ledger.read_lines(path)
    log, called = [], {m: 0 for m in ledger.MARKETS}
    for v in forward["variants"]:
        market, name, hz, params = v["market"], v["idea"], v["horizon"], v["params"]
        interval = v.get("interval") or idea_lib.IDEAS[name].get("interval") or (
            "1h" if market == "crypto" else "1d")
        text = f"replay idea {name} h={hz} {json.dumps(params, sort_keys=True)}"
        if dry_run:
            iid = "I-dry-run"
        else:
            iid, new = idea_id_for(lines, market, text, path, now)
            if new:
                lines = ledger.read_lines(path)
        if market == "stock":
            opens, resolves = stock_window(now, hz, lead)
        elif interval == "1d":
            opens, resolves = crypto_day_window(now, hz, lead)
        else:
            opens, resolves = crypto_window(now, hz, lead)
        busy = {l["asset"] for l in lines if l.get("kind") == "forecast"
                and l.get("idea") == iid and ledger.parse_time(l["resolves_at"]) > now}
        for asset in v["assets"]:
            if asset in busy:
                continue
            bars = finished(bars_fn(asset, interval), interval, now, market)
            closes = [b[2] for b in bars]
            if len(closes) < 30:
                log.append(f"[{market}] {asset}: not enough recent bars, skipped")
                continue
            h = idea_lib.History(closes, len(closes) - 1)
            c = idea_lib.call(name, h, params)
            down = idea_lib.typical_move_pct(h, hz)
            if c is None or down is None:
                continue
            direction, prob = c
            fields = {"idea": iid, "asset": asset, "direction": direction,
                      "probability": prob, "opens_at": opens, "resolves_at": resolves,
                      "expected_downside_pct": round(down, 2), "act": direction == "up",
                      "author": AUTHOR,
                      "reason": f"{name} {json.dumps(params, sort_keys=True)}, horizon {hz} "
                                f"{'hours' if interval == '1h' else 'days'}: "
                                f"{idea_lib.IDEAS[name]['text']}"}
            called[market] += 1
            if dry_run:
                log.append(f"[{market}] would forecast {asset} {direction} {prob} ({name} h={hz})")
                continue
            try:
                ledger.add_forecast(fields, path, rules, now=now)
                log.append(f"[{market}] forecast {asset} {direction} {prob} ({name} h={hz})")
            except ledger.LedgerError as e:
                log.append(f"[{market}] {asset}: refused ({e})")
    for market in {v["market"] for v in forward["variants"]}:
        if not called[market] and not dry_run:
            ledger.add_no_trade(market, "generate.py: no idea made a call", AUTHOR, path, now=now)
            log.append(f"[{market}] no calls: logged a no-trade line")
    return log


def live_bars(asset, interval):
    now = ledger.utcnow()
    days = 40 if interval == "1h" else 500
    return scorer._yahoo(asset, now - dt.timedelta(days=days), now, interval)


def commit_and_push(path=ledger.LEDGER):
    repo = os.path.dirname(path)
    git = lambda *a: subprocess.run(["git", "-C", repo] + list(a), capture_output=True,
                                    text=True, timeout=120)
    git("add", path)
    if git("diff", "--cached", "--quiet").returncode == 0:
        return "nothing new to commit"
    git("commit", "-q", "-m", "Research bot: forward forecasts (generate.py)")
    # The Mac runner is a detached checkout of master: no branch name there.
    branch = git("branch", "--show-current").stdout.strip() or "master"
    for _ in range(3):
        git("pull", "-q", "--rebase", "origin", branch)
        if git("push", "-q", "origin", f"HEAD:{branch}").returncode == 0:
            return "committed and pushed"
    return "committed, PUSH FAILED: push it before the windows open"


def main(argv=None):
    import argparse
    ap = argparse.ArgumentParser(description="Log forward forecasts from the ideas in forward.json "
                                             "(practice / research only).")
    ap.add_argument("--dry-run", action="store_true", help="show what it would log; write nothing")
    ap.add_argument("--commit", action="store_true", help="commit + push the ledger right away")
    args = ap.parse_args(argv)  # --help prints and exits; unknown args exit with an error
    if os.environ.get("GITHUB_ACTIONS"):
        print("refused: not on GitHub Actions")
        return 1
    try:
        lines = generate(bars_fn=live_bars, dry_run=args.dry_run)
    except ForwardMissing as e:
        print(f"refused: {e}")
        return 2
    for line in lines:
        print(line)
    if args.commit and not args.dry_run:
        print(commit_and_push())
    return 0


if __name__ == "__main__":
    sys.exit(main())
