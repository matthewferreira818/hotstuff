"""Robot Desk: one supervisor for the 7 PRACTICE-money stock robots.

Plan and hard lines: meeting-room/notes/robot-desk.md (Matthew, Nov 10:
"can we get all the bot under one supervisor? ... stock bots i mean").
Builder: LC-Stocks. Strategies stay with Grok.

What it does, every run (robot-desk.yml, about every 30 minutes):
  1. Health: for each robot, did it run today (Moncton date), is it running,
     did its last run fail, is its live snapshot stale, trades today.
  2. Scoreboard: each robot's practice account vs simply holding the
     benchmark it already tracks, after fees, since its own start.
  3. Shared limits: if a STOP rule trips, it CREATES stock_bot/PAUSE (the
     existing switch every robot already obeys) with the reason inside.
  4. Writes ONE file: stock_bot/live/desk.json (labelled "paper").

What it can never do (tests check these):
  - place, change or cancel an order; it doesn't import any broker code;
  - change a strategy, a watchlist, an account file or any setting;
  - start or stop a robot run (the Mac starter starts them);
  - delete or empty stock_bot/PAUSE. Only Matthew removes it.
  - touch real-money settings, keys or the real-money broker files.

Its only writes: stock_bot/live/desk.json, and (on a STOP rule, only if it
doesn't exist yet) stock_bot/PAUSE. Publishing desk.json to the
`stock-live-desk` branch is a normal (never forced) push of that one file.

Usage:
  python stock_bot/desk.py              build desk.json from live data, print the standup line
  python stock_bot/desk.py --publish    ...and push desk.json to the stock-live-desk branch
  python stock_bot/desk.py --no-pause   report STOP rules but never create PAUSE (dry run)
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
from zoneinfo import ZoneInfo

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.environ.get("GITHUB_REPOSITORY", "matthewferreira818/hotstuff")
PAUSE_FILE = os.path.join(HERE, "PAUSE")
DESK_FILE = os.path.join(HERE, "live", "desk.json")
DESK_BRANCH = "stock-live-desk"
DESK_PATH_IN_BRANCH = "stock_bot/live/desk.json"

MONCTON = ZoneInfo("America/Moncton")
NEW_YORK = ZoneInfo("America/New_York")

# The 7 practice robots. "workflow" = its GitHub workflow, "live" = the branch
# its live snapshot (live.json) goes to, "account" = its practice account file.
ROBOTS = [
    {"id": "stock-bot", "label": "Dip", "workflow": "stock-bot.yml",
     "live": "stock-live", "account": "paper/account.json", "crypto": False},
    {"id": "momentum", "label": "Momentum", "workflow": "stock-momentum.yml",
     "live": "stock-live-momentum", "account": "paper/account-momentum.json", "crypto": False},
    {"id": "hot", "label": "Hot hands", "workflow": "stock-hot.yml",
     "live": "stock-live-hot", "account": "paper/account-hot.json", "crypto": False},
    {"id": "moonshot", "label": "Moonshot", "workflow": "stock-moonshot.yml",
     "live": "stock-live-moonshot", "account": "paper/account-moonshot.json", "crypto": False},
    {"id": "moonshot-crypto", "label": "Moonshot crypto", "workflow": "stock-moonshot-crypto.yml",
     "live": "stock-live-moonshot-crypto", "account": "paper/account-moonshot-crypto.json", "crypto": True},
    {"id": "quality", "label": "Quality dip", "workflow": "stock-quality.yml",
     "live": "stock-live-quality", "account": "paper/account-quality.json", "crypto": False},
    {"id": "volatility", "label": "Volatility", "workflow": "stock-volatility.yml",
     "live": "stock-live-volatility", "account": "paper/account-volatility.json", "crypto": False},
]

# ---- Shared limits (practice). Changing one = NB2 gate + Matthew's GO. ----
STALE_AFTER = dt.timedelta(hours=2)   # snapshot older than this while it should be live
MAX_TRADES_PER_DAY = 40               # all 7 together; busiest day so far was about 20 (Nov 4)
FAILED_RUNS_IN_A_ROW = 3              # one robot's last 3 finished runs all failed
DESK_DAY_DROP_PCT = 5.0               # all 7 together down more than this since the day began
YOUNG_DAYS = 30                       # under this, "beats holding" is labelled too early to tell

# NYSE full closures and 1 PM early closes (exchange calendar, 2026-2027).
HOLIDAYS = {
    "2026-01-01", "2026-01-19", "2026-02-16", "2026-04-03", "2026-05-25", "2026-06-19",
    "2026-07-03", "2026-09-07", "2026-11-26", "2026-12-25",
    "2027-01-01", "2027-01-18", "2027-02-15", "2027-03-26", "2027-05-31", "2027-06-18",
    "2027-07-05", "2027-09-06", "2027-11-25", "2027-12-24",
}
EARLY_CLOSE = {"2026-11-27", "2026-12-24", "2027-11-26"}

ACTIVE = ("queued", "in_progress", "waiting", "pending", "requested")
FAILED = ("failure", "timed_out", "startup_failure")
IGNORED = ("cancelled", "skipped", "neutral", "stale")  # queue swaps, not robot failures


def parse_time(s):
    if not s:
        return None
    t = dt.datetime.fromisoformat(s.replace("Z", "+00:00"))
    return t if t.tzinfo else t.replace(tzinfo=dt.timezone.utc)


def moncton_day(t):
    return t.astimezone(MONCTON).strftime("%Y-%m-%d")


def stock_session(now):
    """(is_trading_day, open, close) for the New York stock day containing now."""
    ny = now.astimezone(NEW_YORK)
    day = ny.strftime("%Y-%m-%d")
    trading = ny.weekday() < 5 and day not in HOLIDAYS
    opens = ny.replace(hour=9, minute=30, second=0, microsecond=0)
    closes = ny.replace(hour=13 if day in EARLY_CLOSE else 16, minute=0, second=0, microsecond=0)
    return trading, opens, closes


def market_open(now, crypto):
    if crypto:
        return True
    trading, opens, closes = stock_session(now)
    return trading and opens <= now < closes


# ------------------------------- health ---------------------------------

def health(robot, now, runs, snapshot, account, paused):
    """One robot's health row. `runs` = its recent workflow runs (newest first
    or any order), `snapshot` = its live.json (or None), `account` = its
    practice account file (or None)."""
    today = moncton_day(now)
    runs = sorted(runs or [], key=lambda r: r.get("created_at") or "", reverse=True)
    todays = [r for r in runs if r.get("created_at") and moncton_day(parse_time(r["created_at"])) == today]
    ran_today = any(r.get("status") in ACTIVE or r.get("conclusion") == "success" for r in todays)
    running = any(r.get("status") == "in_progress" for r in runs)

    finished = [r for r in runs if r.get("status") == "completed" and r.get("conclusion") not in IGNORED]
    streak = 0
    for r in finished:
        if r.get("conclusion") in FAILED:
            streak += 1
        else:
            break
    last_failed = streak > 0

    updated = parse_time((snapshot or {}).get("updated"))
    age = (now - updated) if updated else None
    should_be_live = market_open(now, robot["crypto"])
    stale = should_be_live and (age is None or age > STALE_AFTER)

    trades = 0
    for o in (account or {}).get("orders", []):
        t = parse_time(o.get("time"))
        if t and moncton_day(t) == today:
            trades += 1

    trading_day = robot["crypto"] or stock_session(now)[0]
    _, opens, _ = stock_session(now)
    late = (not robot["crypto"]) and trading_day and now >= opens + dt.timedelta(minutes=30)

    if paused:
        state, why = "paused", "stock_bot/PAUSE is on: all 7 robots and the research bot stand still"
    elif last_failed:
        state, why = "failed", f"last {streak} finished run(s) failed"
    elif stale:
        state, why = "stale", ("no live snapshot" if age is None
                               else f"snapshot {int(age.total_seconds() // 60)} min old")
    elif running:
        state, why = "running", "running now"
    elif ran_today:
        state, why = "ok", "ran today"
    elif not trading_day:
        state, why = "closed", "market closed today"
    elif late or robot["crypto"]:
        state, why = "not started", "no run today yet"
    else:
        state, why = "waiting", "market not open yet"

    return {
        "state": state, "why": why, "ran_today": ran_today, "running": running,
        "last_run_failed": last_failed, "failed_in_a_row": streak, "stale": stale,
        "snapshot_age_min": int(age.total_seconds() // 60) if age is not None else None,
        "trades_today": trades,
    }


# ------------------------------ scoreboard -------------------------------

def score(robot, now, snapshot):
    """Practice account vs simply holding its benchmark, after fees (the
    account value already has every fee taken out), since its own start."""
    acct = (snapshot or {}).get("account") or {}
    value = acct.get("value")
    hold = acct.get("bench_value") if acct.get("bench_value") is not None else acct.get("spy_value")
    put_in = acct.get("start_cash")
    started = parse_time(acct.get("started"))
    days = (now - started).days if started else None
    row = {
        "benchmark": (snapshot or {}).get("benchmark") or "SPY",
        "value": value, "hold_value": hold, "put_in": put_in,
        "fees": acct.get("fees"), "trades_total": acct.get("trades"),
        "started": acct.get("started"), "days": days,
        "vs_hold": None, "vs_hold_pct": None, "beats_holding": None, "too_early": None,
    }
    if value is None or hold is None:
        return row
    row["vs_hold"] = round(value - hold, 2)
    row["vs_hold_pct"] = round((value - hold) / put_in * 100, 2) if put_in else None
    row["beats_holding"] = value > hold
    row["too_early"] = days is None or days < YOUNG_DAYS
    return row


# ------------------------------ STOP rules -------------------------------

def day_baseline(now, prev_desk, total):
    """The desk's total value when the Moncton day began: kept from the first
    run of the day (stored in desk.json), else today's first reading."""
    today = moncton_day(now)
    prev = (prev_desk or {}).get("day_open") or {}
    if prev.get("date") == today and prev.get("total") is not None:
        return prev
    return {"date": today, "total": total}


def stop_rules(rows, total, baseline):
    """Plain-code STOP checks. Returns a list of reasons (empty = all fine).
    Unknown data never trips a rule: a missing number skips the check."""
    reasons = []
    trades = sum(r["health"]["trades_today"] for r in rows)
    if trades > MAX_TRADES_PER_DAY:
        reasons.append(f"{trades} practice trades today across all robots (limit {MAX_TRADES_PER_DAY})")
    for r in rows:
        if r["health"]["failed_in_a_row"] >= FAILED_RUNS_IN_A_ROW:
            reasons.append(f"{r['label']}: last {r['health']['failed_in_a_row']} runs failed "
                           f"(limit {FAILED_RUNS_IN_A_ROW} in a row)")
    if total is not None and baseline.get("total"):
        drop = (baseline["total"] - total) / baseline["total"] * 100
        if drop > DESK_DAY_DROP_PCT:
            reasons.append(f"all robots together down {drop:.1f}% today "
                           f"(${baseline['total']:.2f} -> ${total:.2f}; limit {DESK_DAY_DROP_PCT}%)")
    return reasons


def create_pause(path, reasons, now):
    """CREATE stock_bot/PAUSE with the reasons. Never overwrites, never
    deletes: if the file already exists, nothing happens. Returns True only
    if this call created it."""
    if os.path.exists(path):
        return False
    text = ("Paused by the Robot Desk (practice money), "
            f"{now.astimezone(MONCTON).strftime('%a %b %d %Y %I:%M %p')} Moncton.\n"
            "Why:\n" + "".join(f"- {r}\n" for r in reasons) +
            "All 7 practice robots AND the research bot stand still while this file exists.\nThe Desk never removes it: "
            "Matthew deletes it after reading why.\n")
    try:
        with open(path, "x") as f:  # "x" = create only; fails if it appeared meanwhile
            f.write(text)
    except FileExistsError:
        return False
    return True


# ------------------------------ the desk --------------------------------

def build(now, runs_by_robot, snapshots, accounts, prev_desk, paused):
    rows = []
    for rb in ROBOTS:
        rows.append({
            "id": rb["id"], "label": rb["label"], "crypto": rb["crypto"],
            "health": health(rb, now, runs_by_robot.get(rb["id"]), snapshots.get(rb["id"]),
                             accounts.get(rb["id"]), paused),
            "score": score(rb, now, snapshots.get(rb["id"])),
        })
    values = [r["score"]["value"] for r in rows]
    total = round(sum(values), 2) if all(v is not None for v in values) else None
    baseline = day_baseline(now, prev_desk, total)
    reasons = stop_rules(rows, total, baseline)
    ran = sum(1 for r in rows if r["health"]["ran_today"] or r["health"]["running"])
    beat = [r for r in rows if r["score"]["beats_holding"]]
    desk = {
        "paper": True,
        "note": "PRACTICE MONEY ONLY. Numbers are the practice accounts, not real money.",
        "as_of": now.astimezone(dt.timezone.utc).isoformat(timespec="seconds"),
        "as_of_moncton": now.astimezone(MONCTON).strftime("%a %b %d %I:%M %p"),
        "paused": paused,
        "pause_covers": "stock_bot/PAUSE stops all 7 robots and the research bot",
        "robots": rows,
        "desk": {
            "robots": len(rows), "ran_today": ran,
            "failed": sum(1 for r in rows if r["health"]["last_run_failed"]),
            "stale": sum(1 for r in rows if r["health"]["stale"]),
            "beat_holding": len(beat),
            "beat_holding_but_too_early": sum(1 for r in beat if r["score"]["too_early"]),
            "trades_today": sum(r["health"]["trades_today"] for r in rows),
            "total_value": total,
        },
        "day_open": baseline,
        "limits": {"max_trades_per_day": MAX_TRADES_PER_DAY,
                   "failed_runs_in_a_row": FAILED_RUNS_IN_A_ROW,
                   "desk_day_drop_pct": DESK_DAY_DROP_PCT,
                   "stale_after_min": int(STALE_AFTER.total_seconds() // 60)},
        "stop_reasons": reasons,
    }
    desk["line"] = standup_line(desk)
    return desk


def standup_line(desk):
    d = desk["desk"]
    early = f" ({d['beat_holding_but_too_early']} under {YOUNG_DAYS} days old)" if d["beat_holding_but_too_early"] else ""
    bits = [f"{d['ran_today']}/{d['robots']} ran today", f"{d['beat_holding']} beat holding{early}"]
    if d["failed"]:
        bits.append(f"{d['failed']} failed")
    if d["stale"]:
        bits.append(f"{d['stale']} stale")
    bits.append("paused: " + ("YES" if desk["paused"] else "no"))
    if desk["stop_reasons"]:
        bits.append("STOP: " + "; ".join(desk["stop_reasons"]))
    return "Robot Desk (paper): " + ", ".join(bits)


# ------------------------ reading (read-only) ----------------------------

def _gh():
    return os.environ.get("GH_BIN") or "gh"


def fetch_runs(workflow):
    try:
        out = subprocess.run([_gh(), "api", f"repos/{REPO}/actions/workflows/{workflow}/runs?per_page=20"],
                             capture_output=True, text=True, timeout=60)
        return json.loads(out.stdout).get("workflow_runs", []) if out.returncode == 0 else None
    except (subprocess.SubprocessError, OSError, ValueError):
        return None


def read_branch_file(branch, path):
    git = ["git", "-C", HERE]
    try:
        f = subprocess.run(git + ["fetch", "-q", "--depth=1", "origin", branch],
                           capture_output=True, timeout=60)
        if f.returncode != 0:
            return None
        out = subprocess.run(git + ["show", f"FETCH_HEAD:{path}"], capture_output=True, text=True, timeout=30)
        return json.loads(out.stdout) if out.returncode == 0 else None
    except (subprocess.SubprocessError, OSError, ValueError):
        return None


def read_account(rel):
    try:
        with open(os.path.join(HERE, rel)) as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def publish(desk, branch=DESK_BRANCH):
    """Add desk.json as a new commit on `branch` (normal push, never forced).
    If the push is refused (someone else moved it), this run just skips."""
    git = ["git", "-C", HERE]
    env = dict(os.environ, GIT_AUTHOR_NAME="robot-desk", GIT_AUTHOR_EMAIL="robot-desk@users.noreply.github.com",
               GIT_COMMITTER_NAME="robot-desk", GIT_COMMITTER_EMAIL="robot-desk@users.noreply.github.com")
    run = lambda *a, inp=None: subprocess.run(git + list(a), input=inp, capture_output=True,
                                              text=True, timeout=60, env=env)
    parent = run("fetch", "-q", "--depth=1", "origin", branch).returncode == 0 and \
        run("rev-parse", "FETCH_HEAD").stdout.strip()
    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(desk, f, indent=1)
    try:
        blob = run("hash-object", "-w", f.name).stdout.strip()
        live = run("mktree", inp=f"100644 blob {blob}\tdesk.json\n").stdout.strip()
        sb = run("mktree", inp=f"040000 tree {live}\tlive\n").stdout.strip()
        root = run("mktree", inp=f"040000 tree {sb}\tstock_bot\n").stdout.strip()
        args = ["commit-tree", root, "-m", "Robot Desk snapshot (paper)"] + (["-p", parent] if parent else [])
        commit = run(*args).stdout.strip()
        ok = bool(commit) and run("push", "-q", "origin", f"{commit}:refs/heads/{branch}").returncode == 0
    finally:
        os.unlink(f.name)  # our own temp file, nothing else
    print("desk.json published" if ok else "desk.json publish skipped (will retry next run)")
    return ok


def main(argv=None):
    ap = argparse.ArgumentParser(description="Robot Desk (practice money only)")
    ap.add_argument("--publish", action="store_true", help="push desk.json to the stock-live-desk branch")
    ap.add_argument("--no-pause", action="store_true", help="report STOP rules but never create PAUSE")
    args = ap.parse_args(argv)

    now = dt.datetime.now(dt.timezone.utc)
    runs = {rb["id"]: fetch_runs(rb["workflow"]) for rb in ROBOTS}
    snaps = {rb["id"]: read_branch_file(rb["live"], "live.json") for rb in ROBOTS}
    accts = {rb["id"]: read_account(rb["account"]) for rb in ROBOTS}
    prev = read_branch_file(DESK_BRANCH, DESK_PATH_IN_BRANCH)
    paused = os.path.exists(PAUSE_FILE)

    desk = build(now, runs, snaps, accts, prev, paused)
    if desk["stop_reasons"] and not args.no_pause:
        if create_pause(PAUSE_FILE, desk["stop_reasons"], now):
            desk["paused"] = True
            desk["paused_by_desk"] = True
            desk["line"] = standup_line(desk)

    os.makedirs(os.path.dirname(DESK_FILE), exist_ok=True)
    with open(DESK_FILE, "w") as f:
        json.dump(desk, f, indent=1)
    print(desk["line"])
    if args.publish:
        publish(desk)
    return 0


if __name__ == "__main__":
    sys.exit(main())
