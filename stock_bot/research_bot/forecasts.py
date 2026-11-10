#!/usr/bin/env python3
"""The forecast ledger: an append-only diary of predictions, written BEFORE
the fact. PRACTICE MONEY ONLY.

Why it exists (money council, 2026-11-10): the only way to know whether a
forecaster (an AI chat, Grok, or a plain rule) has an edge is to write each
call down before its window opens, never touch it again, and let plain code
grade it afterwards. The git commit time of the line is the proof it came
first; a forecast whose first commit is after its window opened is marked
LATE by the scorer and never counts.

Three kinds of line live in forecasts.jsonl (one JSON object per line):
  idea      - every idea tried gets a line, even ones that never forecast.
  forecast  - asset, direction, probability, window, expected downside, why.
  no_trade  - "looked, nothing worth calling today". A normal outcome.

Rule-change proposals go to proposals.jsonl, never to rules.json.

Usage (run from the repo root):
  python3 -m stock_bot.research_bot.forecasts idea --market crypto \
      --text "BTC drifts up the day after a 5% drop"
  python3 -m stock_bot.research_bot.forecasts add --idea I-... \
      --asset BTC-USD --direction up --probability 0.55 \
      --opens 2026-11-11T14:00:00Z --resolves 2026-11-12T14:00:00Z \
      --downside 6 --reason "..." [--act]
  python3 -m stock_bot.research_bot.forecasts no-trade --market stock --reason "..."
  python3 -m stock_bot.research_bot.forecasts propose-rule --text "..."
  python3 -m stock_bot.research_bot.forecasts verify   # append-only + timing proof
Then commit and push forecasts.jsonl right away: the window must not open
before the commit exists.
"""

import argparse
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LEDGER = os.path.join(HERE, "forecasts.jsonl")
PROPOSALS = os.path.join(HERE, "proposals.jsonl")
RULES = os.path.join(HERE, "rules.json")

MARKETS = ("stock", "crypto")
MAX_REASON = 280
MIN_HORIZON = dt.timedelta(hours=1)
MAX_HORIZON = dt.timedelta(days=30)


class LedgerError(ValueError):
    pass


# ------------------------------------------------------------------ helpers

def utcnow():
    return dt.datetime.now(dt.timezone.utc)


def parse_time(s):
    """ISO time -> aware UTC datetime. 'Z' allowed. Naive times refused,
    because a forecast with an unclear time zone can't be graded."""
    if isinstance(s, dt.datetime):
        t = s
    else:
        t = dt.datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    if t.tzinfo is None:
        raise LedgerError(f"time needs a zone (use Z for UTC): {s}")
    return t.astimezone(dt.timezone.utc)


def iso(t):
    return parse_time(t).isoformat(timespec="seconds").replace("+00:00", "Z")


def market_of(asset):
    return "crypto" if asset.upper().endswith("-USD") else "stock"


def _make_id(prefix, fields, created):
    h = hashlib.sha256(json.dumps(fields, sort_keys=True).encode()).hexdigest()
    return f"{prefix}-{parse_time(created).strftime('%Y%m%d-%H%M%S')}-{h[:6]}"


def read_lines(path=LEDGER):
    if not os.path.exists(path):
        return []
    out = []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            if line.strip():
                try:
                    out.append(json.loads(line))
                except ValueError:
                    raise LedgerError(f"{os.path.basename(path)} line {n} is not JSON")
    return out


def _append(record, path):
    """The only writer. Opens in append mode: earlier lines are never
    rewritten by this code."""
    with open(path, "a") as f:
        f.write(json.dumps(record, sort_keys=True) + "\n")
    return record


# --------------------------------------------------------------- validators

def validate_forecast(r, ideas, rules, now=None):
    """Raises LedgerError on anything that would make the forecast ungradeable
    or unfair. Returns the cleaned record."""
    now = parse_time(now or utcnow())
    need = ("idea", "asset", "direction", "probability", "opens_at",
            "resolves_at", "expected_downside_pct", "reason")
    missing = [k for k in need if r.get(k) in (None, "")]
    if missing:
        raise LedgerError(f"missing: {', '.join(missing)}")
    if r["idea"] not in ideas:
        raise LedgerError(f"unknown idea {r['idea']}: log the idea first, "
                          "so every idea tried is counted")
    asset = str(r["asset"]).upper().strip()
    market = market_of(asset)
    if market not in rules["markets"]:
        raise LedgerError(f"market {market} is not in rules.json")
    if r["direction"] not in ("up", "down"):
        raise LedgerError("direction must be up or down")
    p = float(r["probability"])
    if not 0.5 < p <= 0.99:
        raise LedgerError("probability is the chance the direction is right: "
                          "above 0.5 and at most 0.99 (0.5 = no call; log no-trade)")
    opens, resolves = parse_time(r["opens_at"]), parse_time(r["resolves_at"])
    lead = dt.timedelta(minutes=rules.get("min_lead_minutes", 15))
    if opens < now + lead:
        raise LedgerError(f"window opens too soon: needs {lead} to commit + push first")
    if not MIN_HORIZON <= resolves - opens <= MAX_HORIZON:
        raise LedgerError("window must be 1 hour to 30 days long")
    down = float(r["expected_downside_pct"])
    if not 0 <= down <= 100:
        raise LedgerError("expected_downside_pct is a % from 0 to 100")
    act = bool(r.get("act", False))
    if act and r["direction"] != "up":
        raise LedgerError("phase 1 is long-only: only 'up' forecasts can ask "
                          "for a paper trade (no shorting)")
    reason = str(r["reason"]).strip()
    if len(reason) > MAX_REASON:
        raise LedgerError(f"reason is over {MAX_REASON} characters")
    plain = str(r.get("plain_reason") or "").strip()
    if len(plain) > MAX_REASON:
        raise LedgerError(f"plain_reason is over {MAX_REASON} characters")
    return {"kind": "forecast", "idea": r["idea"], "asset": asset,
            "market": market, "direction": r["direction"],
            "probability": round(p, 4), "opens_at": iso(opens),
            "resolves_at": iso(resolves), "expected_downside_pct": round(down, 2),
            "act": act, "reason": reason, **({"plain_reason": plain} if plain else {}),
            "author": str(r.get("author") or "unknown")[:40],
            "created": iso(now)}


# ------------------------------------------------------------------ writers

def load_rules(path=RULES):
    with open(path) as f:
        return json.load(f)


def add_idea(market, text, author, path=LEDGER, now=None):
    if market not in MARKETS and market != "both":
        raise LedgerError("market must be stock, crypto or both")
    text = text.strip()
    if not text or len(text) > MAX_REASON:
        raise LedgerError(f"idea text must be 1-{MAX_REASON} characters")
    created = iso(now or utcnow())
    rec = {"kind": "idea", "market": market, "text": text,
           "author": author[:40], "created": created}
    rec["id"] = _make_id("I", rec, created)
    return _append(rec, path)


def add_forecast(fields, path=LEDGER, rules=None, now=None):
    rules = rules or load_rules()
    lines = read_lines(path)
    ideas = {l["id"] for l in lines if l.get("kind") == "idea"}
    rec = validate_forecast(fields, ideas, rules, now)
    rec["id"] = _make_id("F", rec, rec["created"])
    if rec["id"] in {l.get("id") for l in lines}:
        raise LedgerError("this exact forecast is already logged")
    return _append(rec, path)


def add_no_trade(market, reason, author, path=LEDGER, now=None):
    if market not in MARKETS:
        raise LedgerError("market must be stock or crypto")
    created = iso(now or utcnow())
    rec = {"kind": "no_trade", "market": market,
           "reason": reason.strip()[:MAX_REASON], "author": author[:40],
           "created": created}
    rec["id"] = _make_id("N", rec, created)
    return _append(rec, path)


def propose_rule(text, author, path=PROPOSALS, now=None):
    """The AI's only way to change a rule: a proposal, read by a human."""
    created = iso(now or utcnow())
    rec = {"kind": "rule_proposal", "text": text.strip()[:1000],
           "author": author[:40], "created": created, "status": "proposed"}
    rec["id"] = _make_id("P", rec, created)
    return _append(rec, path)


# -------------------------------------------------- git proof (append-only)

def _git(repo, *args):
    return subprocess.run(["git", "-C", repo] + list(args), capture_output=True,
                          text=True, timeout=60)


def history(path=LEDGER):
    """[(commit, unix_time, text)] oldest first for every commit that touched
    the file. Uses the AUTHOR time, which survives a rebase. A squash merge
    would still erase the history: merge this file with a merge commit."""
    path = os.path.realpath(path)
    repo = os.path.dirname(path)
    top = _git(repo, "rev-parse", "--show-toplevel").stdout.strip()
    if not top:
        return []
    rel = os.path.relpath(path, os.path.realpath(top))
    log = _git(top, "log", "--reverse", "--format=%H %at", "--", rel).stdout.split()
    out = []
    for sha, ts in zip(log[0::2], log[1::2]):
        shown = _git(top, "show", f"{sha}:{rel}")
        out.append((sha, int(ts), shown.stdout if shown.returncode == 0 else ""))
    return out


def verify(path=LEDGER):
    """Checks the file was only ever appended to, in git and on disk.
    Returns (ok, problems, first_seen) where first_seen maps a line id to
    the unix time of the first commit that contained it."""
    problems, first_seen, prev = [], {}, ""
    for sha, ts, text in history(path):
        if not text.startswith(prev):
            problems.append(f"commit {sha[:8]} changed or removed earlier lines")
        for line in text.splitlines():
            if line.strip():
                try:
                    lid = json.loads(line).get("id")
                except ValueError:
                    problems.append(f"commit {sha[:8]} has a line that is not JSON")
                    continue
                first_seen.setdefault(lid, ts)
        prev = text
    if os.path.exists(path):
        with open(path) as f:
            disk = f.read()
        if not disk.startswith(prev):
            problems.append("the file on disk changed already-committed lines")
    return (not problems), problems, first_seen


# --------------------------------------------------------------------- CLI

def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    a = sub.add_parser("idea")
    a.add_argument("--market", required=True)
    a.add_argument("--text", required=True)
    a.add_argument("--author", default="unknown")
    f = sub.add_parser("add")
    for k in ("idea", "asset", "direction", "opens", "resolves", "reason"):
        f.add_argument(f"--{k}", required=True)
    f.add_argument("--probability", type=float, required=True)
    f.add_argument("--downside", type=float, required=True)
    f.add_argument("--act", action="store_true",
                   help="ask the paper executor to trade it (up only)")
    f.add_argument("--author", default="unknown")
    n = sub.add_parser("no-trade")
    n.add_argument("--market", required=True)
    n.add_argument("--reason", required=True)
    n.add_argument("--author", default="unknown")
    p = sub.add_parser("propose-rule")
    p.add_argument("--text", required=True)
    p.add_argument("--author", default="unknown")
    sub.add_parser("verify")
    args = ap.parse_args(argv)
    try:
        if args.cmd == "idea":
            rec = add_idea(args.market, args.text, args.author)
        elif args.cmd == "add":
            rec = add_forecast({
                "idea": args.idea, "asset": args.asset,
                "direction": args.direction, "probability": args.probability,
                "opens_at": args.opens, "resolves_at": args.resolves,
                "expected_downside_pct": args.downside, "reason": args.reason,
                "act": args.act, "author": args.author})
        elif args.cmd == "no-trade":
            rec = add_no_trade(args.market, args.reason, args.author)
        elif args.cmd == "propose-rule":
            rec = propose_rule(args.text, args.author)
        else:
            ok, problems, seen = verify()
            print("append-only: OK" if ok else "append-only: BROKEN")
            for pr in problems:
                print(" -", pr)
            print(f"{len(seen)} committed line(s)")
            return 0 if ok else 1
    except LedgerError as e:
        print(f"refused: {e}")
        return 2
    print(json.dumps(rec, indent=1))
    print("Now commit + push forecasts.jsonl before the window opens.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
