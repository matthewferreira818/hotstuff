#!/usr/bin/env python3
"""Counts the stock council's votes by a fixed rule and logs the result.

The chair (Claude) only transcribes each seat's answer into a votes file;
this script makes the decision, so no one's favourite sneaks through.

THE RULE
  - Each pick adds its conviction (1-5); each veto subtracts its strength.
  - A stock needs picks from at least 2 different seats (independent
    agreement). One seat's darling doesn't make the list.
  - Any strength-5 veto blocks it outright.
  - Net score must be above 0.
  - Top 3 by score make the list (ties: the bigger steady swing wins).
    Zero picks is a valid result — "sit this week out".
  - Rules for each pick: Goalie's if Goalie gave them, else the average
    of the other seats' rules, else the screener's scaled rules; dollars
    default to $100 and never exceed the watchlist caps.

Votes file (JSON):
  {"date": "YYYY-MM-DD",
   "seats": {"Tally": {"picks":  [{"symbol": "X", "conviction": 4,
                                    "reason": "..."}],
                       "vetoes": [{"symbol": "Y", "strength": 3,
                                    "reason": "..."}],
                       "rules":  {"X": {"dip": 10, "take_profit": 12,
                                        "stop_loss": 12, "dollars": 100,
                                        "max_held": 200}},
                       "odds": 3, "worry": "..."}, ...}}

Usage:
  python stock_bot/council_vote.py votes.json        # tally + log
  python stock_bot/council_vote.py votes.json --dry  # tally only
  python stock_bot/council_vote.py --selftest
"""

import json
import os
import statistics
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCREEN = os.path.join(HERE, "screen", "latest.json")
WATCHLIST = os.path.join(HERE, "watchlist.json")
PICKS = os.path.join(HERE, "council", "picks.jsonl")
SESSIONS = os.path.join(HERE, "council", "SESSIONS.md")
MAX_PICKS = 3
MIN_BACKERS = 2


def tally(votes, screen, caps):
    stocks = {r["symbol"]: r for r in screen.get("stocks", [])}
    score, backers, vetoers, hard = {}, {}, {}, set()
    for seat, v in votes["seats"].items():
        for p in v.get("picks", []):
            s = p["symbol"].upper()
            score[s] = score.get(s, 0) + int(p["conviction"])
            backers.setdefault(s, []).append(seat)
        for x in v.get("vetoes", []):
            s = x["symbol"].upper()
            score[s] = score.get(s, 0) - int(x["strength"])
            vetoers.setdefault(s, []).append(f"{seat}({x['strength']})")
            if int(x["strength"]) >= 5:
                hard.add(s)

    rows = []
    for s in sorted(score, key=lambda s: (
            -score[s], -stocks.get(s, {}).get("steady_sigma", 0))):
        n = len(set(backers.get(s, [])))
        if s in hard:
            status = "blocked (strength-5 veto)"
        elif n == 0:
            status = "no seat picked it"
        elif n < MIN_BACKERS:
            status = "only 1 seat picked it"
        elif score[s] <= 0:
            status = "vetoes outweigh picks"
        elif s not in stocks:
            status = "not in today's screen (failed filters or no data)"
        else:
            status = "PASS"
        rows.append({"symbol": s, "score": score[s], "status": status,
                     "backers": backers.get(s, []),
                     "vetoers": vetoers.get(s, [])})
    passed = [r for r in rows if r["status"] == "PASS"]
    for r in passed[MAX_PICKS:]:
        r["status"] = f"passed, but only the top {MAX_PICKS} make the list"
    chosen = passed[:MAX_PICKS]

    for r in chosen:
        s = r["symbol"]
        goalie = votes["seats"].get("Goalie", {}).get("rules", {}).get(s)
        others = [v["rules"][s] for seat, v in votes["seats"].items()
                  if seat != "Goalie" and s in v.get("rules", {})]
        if goalie:
            rules, source = dict(goalie), "Goalie"
        elif others:
            rules = {k: round(statistics.mean(o[k] for o in others
                                              if k in o), 1)
                     for k in ("dip", "take_profit", "stop_loss")
                     if any(k in o for o in others)}
            source = "average of seats"
        else:
            rules, source = {}, "screener"
        scaled = stocks[s]["scaled_rules"]
        for k in ("dip", "take_profit", "stop_loss"):
            rules.setdefault(k, scaled[k])
        dollars = min(float(rules.get("dollars", 100)), caps["per_buy"])
        rules["dollars"] = dollars
        rules["max_held"] = min(float(rules.get("max_held", 2 * dollars)),
                                caps["max_held"])
        r["rules"], r["rules_from"] = rules, source
        r["price"] = stocks[s]["price"]
        r["steady_sigma"] = stocks[s]["steady_sigma"]
        r["sigma60"] = stocks[s]["sigma60"]
    return rows, chosen


def caps_from(watchlist):
    stocks = watchlist.get("stocks") or [{}]
    return {"per_buy": float(stocks[0].get("dollars_per_buy", 100)),
            "max_held": float(stocks[0].get("max_position_dollars", 300))}


def report(votes, rows, chosen):
    date = votes["date"]
    lines = [f"## {date} — stock council", ""]
    odds = {seat: v.get("odds") for seat, v in votes["seats"].items()}
    lines.append("Seats' odds the picks make money on paper this month: " +
                 " · ".join(f"{k} {v}/5" for k, v in odds.items()))
    lines += ["", "| Stock | Score | Picked by | Vetoed by | Result |",
              "|---|---|---|---|---|"]
    for r in rows:
        lines.append(f"| {r['symbol']} | {r['score']:+} | "
                     f"{', '.join(r['backers']) or '—'} | "
                     f"{', '.join(r['vetoers']) or '—'} | {r['status']} |")
    lines.append("")
    if chosen:
        lines.append("**The council's list:**")
        for r in chosen:
            ru = r["rules"]
            lines.append(
                f"- **{r['symbol']}** at ${r['price']} — dip {ru['dip']}% / "
                f"take-profit {ru['take_profit']}% / stop {ru['stop_loss']}% "
                f"/ ${ru['dollars']:.0f} a buy / max ${ru['max_held']:.0f} "
                f"held (rules from {r['rules_from']})")
    else:
        lines.append("**The council's list: none — sit this one out.**")
    lines += ["", "Worries: " + " | ".join(
        f"{k}: {v['worry']}" for k, v in votes["seats"].items()
        if v.get("worry")), "", "Matthew's decision: pending", ""]
    return "\n".join(lines)


def log(votes, chosen, text):
    os.makedirs(os.path.dirname(PICKS), exist_ok=True)
    with open(PICKS, "a") as f:
        for r in chosen:
            f.write(json.dumps({
                "date": votes["date"], "symbol": r["symbol"],
                "price": r["price"], "steady_sigma": r["steady_sigma"],
                "sigma60": r["sigma60"], "score": r["score"],
                "backers": r["backers"], "rules": r["rules"]}) + "\n")
    head = "# Stock council sessions (newest first)\n\n"
    old = ""
    if os.path.exists(SESSIONS):
        with open(SESSIONS) as f:
            old = f.read().replace(head, "", 1)
    with open(SESSIONS, "w") as f:
        f.write(head + text + "\n" + old)


def selftest():
    screen = {"stocks": [
        {"symbol": s, "price": 10.0, "steady_sigma": sg, "sigma60": sg,
         "scaled_rules": {"dip": 9, "take_profit": 11, "stop_loss": 11}}
        for s, sg in [("AAA", 5), ("BBB", 4), ("CCC", 6), ("DDD", 3),
                      ("EEE", 2)]]}
    votes = {"date": "2026-01-01", "seats": {
        "Tally": {"picks": [{"symbol": "AAA", "conviction": 4},
                            {"symbol": "BBB", "conviction": 3},
                            {"symbol": "DDD", "conviction": 2}],
                  "rules": {"AAA": {"dip": 12, "take_profit": 14,
                                    "stop_loss": 10}}},
        "Scoop": {"picks": [{"symbol": "AAA", "conviction": 3},
                            {"symbol": "CCC", "conviction": 5},
                            {"symbol": "DDD", "conviction": 2}]},
        "Rebound": {"picks": [{"symbol": "BBB", "conviction": 2},
                              {"symbol": "EEE", "conviction": 5}],
                    "vetoes": [{"symbol": "DDD", "strength": 4}]},
        "Goalie": {"picks": [{"symbol": "BBB", "conviction": 3}],
                   "vetoes": [{"symbol": "CCC", "strength": 5}],
                   "rules": {"BBB": {"dip": 8, "take_profit": 10,
                                     "stop_loss": 9, "dollars": 500,
                                     "max_held": 900}}},
        "The Bear": {"picks": [],
                     "vetoes": [{"symbol": "AAA", "strength": 2}]},
    }}
    rows, chosen = tally(votes, screen, {"per_buy": 100, "max_held": 300})
    status = {r["symbol"]: r["status"] for r in rows}
    assert [r["symbol"] for r in chosen] == ["BBB", "AAA"], chosen
    assert status["CCC"].startswith("blocked"), status  # hard veto
    assert status["EEE"].startswith("only 1"), status   # one fan only
    assert status["DDD"] == "vetoes outweigh picks", status  # 2+2-4 = 0
    b = next(r for r in chosen if r["symbol"] == "BBB")["rules"]
    assert b["dollars"] == 100 and b["max_held"] == 300, b  # caps win
    a = next(r for r in chosen if r["symbol"] == "AAA")
    assert a["rules_from"] == "average of seats" and a["rules"]["dip"] == 12
    assert "Matthew's decision: pending" in report(votes, rows, chosen)
    print("selftest OK")


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        selftest()
        sys.exit(0)
    with open(sys.argv[1]) as f:
        votes = json.load(f)
    with open(SCREEN) as f:
        screen = json.load(f)
    with open(WATCHLIST) as f:
        caps = caps_from(json.load(f))
    rows, chosen = tally(votes, screen, caps)
    text = report(votes, rows, chosen)
    print(text)
    if "--dry" not in sys.argv:
        log(votes, chosen, text)
        print(f"Logged to {os.path.relpath(SESSIONS)} and "
              f"{os.path.relpath(PICKS)}")
