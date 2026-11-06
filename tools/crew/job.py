#!/usr/bin/env python3
"""Crew job cards: one small, honest record of a handed-off job (Matthew's goal, 2026-11-06: "give Friday a job and watch the crew do it").

Delegation demo #1 showed a woken chat can lose the job text. So a job lives in a FILE, not only in a message:
  ~/Claude/crew-jobs/jobs.jsonl  (this Mac only, folder 700, one event per line, never in git)
Stages: assigned -> got it (ack) -> started -> done (with proof) | failed (with reason). Friday can resend an assigned job that got no "got it".
The Helm's Command Core > Crew Station reads the same file and shows each job's stages with their real times.

Usage (any crew chat on this Mac; --by is who you are, e.g. LC-Pixels):
  job.py new <to> "<short title>" --by Friday         -> prints the job id (J-...)
  job.py ack <id> --by <you>                           "got it"
  job.py start <id> --by <you>
  job.py done <id> --by <you> --proof "<commit/link/screenshot path>"
  job.py fail <id> --by <you> --why "<plain reason>"
  job.py resend <id> --by Friday
  job.py show <id>        job.py list [--all]
Titles are work labels (max 140 chars, one line). Never put private chat text, secrets or personal details in a job.
"""
import json, os, sys, time, datetime, argparse

ROOT = os.path.expanduser(os.environ.get("CREW_JOBS_DIR", "~/Claude/crew-jobs"))
FILE = os.path.join(ROOT, "jobs.jsonl")
ORDER = ["assigned", "ack", "started", "done"]
MAXT, MAXP = 140, 300


def now_iso():
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def events():
    if not os.path.exists(FILE):
        return []
    out = []
    with open(FILE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                out.append(json.loads(line))
            except ValueError:
                continue  # a broken line never breaks the rest
    return out


def fold(evs):
    """Every job's current state, built only from recorded events."""
    jobs = {}
    for e in evs:
        jid, kind = e.get("id"), e.get("event")
        if not jid or not kind:
            continue
        if kind == "assigned":
            jobs[jid] = {"id": jid, "to": e.get("to", ""), "by": e.get("by", ""), "title": e.get("title", ""), "assigned": e.get("at"),
                         "ack": None, "started": None, "done": None, "failed": None, "proof": None, "why": None, "resends": 0,
                         "ack_implied": False, "started_implied": False}
            continue
        j = jobs.get(jid)
        if not j:
            continue
        if kind == "resend":
            j["resends"] += 1
            j["resent"] = e.get("at")
        elif kind == "handoff":   # written by The Helm when it hands an unanswered job to the backup
            if not j.get("handed_at"):
                j["handed_at"], j["handed_to"] = e.get("at"), e.get("to")
        elif kind in ("ack", "started", "done", "failed") and not j.get(kind):
            j[kind] = e.get("at")
            # A later stage proves the earlier ones happened (started means it got the job), but their TIME was never recorded:
            # mark them implied, with no time, rather than borrowing this event's time (rule 1, NB2's gate).
            if kind in ("started", "done") and not j["ack"]:
                j["ack_implied"] = True
            if kind == "done" and not j["started"]:
                j["started_implied"] = True
            if kind == "done":
                j["proof"] = e.get("proof")
            if kind == "failed":
                j["why"] = e.get("why")
    return jobs


def stage(j):
    if j["failed"]:
        return "failed"
    if j["done"]:
        return "done"
    if j["started"] or j["started_implied"]:
        return "started"
    if j["ack"] or j["ack_implied"]:
        return "ack"
    return "assigned"


def append(e):
    os.makedirs(ROOT, mode=0o700, exist_ok=True)
    os.chmod(ROOT, 0o700)
    new = not os.path.exists(FILE)
    with open(FILE, "a", encoding="utf-8") as f:
        f.write(json.dumps(e, ensure_ascii=False) + "\n")
    if new:
        os.chmod(FILE, 0o600)


def one_line(s, cap):
    s = " ".join(str(s).split())
    return s[:cap]


def fail(msg):
    print("job: " + msg, file=sys.stderr)
    sys.exit(2)


def main(argv):
    p = argparse.ArgumentParser(prog="job.py")
    p.add_argument("cmd")
    p.add_argument("args", nargs="*")
    p.add_argument("--by", default="")
    p.add_argument("--proof", default="")
    p.add_argument("--why", default="")
    p.add_argument("--all", action="store_true")
    a = p.parse_args(argv)
    jobs = fold(events())

    if a.cmd == "new":
        if len(a.args) != 2:
            fail('usage: job.py new <to> "<title>" --by <you>')
        to, title = one_line(a.args[0], 40), one_line(a.args[1], MAXT)
        if not to or not title:
            fail("a job needs a crew member and a title")
        if not a.by:
            fail("say who is assigning it: --by <you>")
        jid = "J-" + time.strftime("%m%d-%H%M%S")
        while jid in jobs:
            jid += "x"
        append({"id": jid, "event": "assigned", "at": now_iso(), "to": to, "by": one_line(a.by, 40), "title": title})
        print(jid)
        return

    if a.cmd in ("ack", "start", "done", "fail", "resend"):
        if len(a.args) != 1:
            fail(f"usage: job.py {a.cmd} <id> --by <you>")
        jid = a.args[0]
        j = jobs.get(jid)
        if not j:
            fail(f"no job {jid}")
        if not a.by:
            fail("say who you are: --by <you>")
        st = stage(j)
        if st in ("done", "failed"):
            fail(f"{jid} is already {st}")
        kind = {"start": "started", "fail": "failed"}.get(a.cmd, a.cmd)
        who, owner, boss = a.by.strip().lower(), j["to"].strip().lower(), j["by"].strip().lower()
        # Only the crew member it was given to moves its job. Whoever assigned it may also fail it or resend it.
        if kind in ("ack", "started", "done") and who != owner:
            fail(f"{jid} belongs to {j['to']}; only {j['to']} can mark it {kind}")
        if kind in ("failed", "resend") and who not in (owner, boss):
            fail(f"only {j['to']} or {j['by']} can {a.cmd} {jid}")
        e = {"id": jid, "event": kind, "at": now_iso(), "by": one_line(a.by, 40)}
        if kind == "resend":
            if st != "assigned":
                fail(f"{jid} already got a 'got it'; no resend needed")
        elif kind == "done":
            if not a.proof.strip():
                fail("done needs proof: --proof \"<commit, link or screenshot path>\"")
            e["proof"] = one_line(a.proof, MAXP)
        elif kind == "failed":
            if not a.why.strip():
                fail("fail needs a reason: --why \"...\"")
            e["why"] = one_line(a.why, MAXP)
        append(e)
        print(f"{jid}: {kind}")
        return

    if a.cmd == "show":
        if len(a.args) != 1 or a.args[0] not in jobs:
            fail("usage: job.py show <id>")
        print(json.dumps(jobs[a.args[0]], indent=1, ensure_ascii=False))
        return

    if a.cmd == "list":
        rows = sorted(jobs.values(), key=lambda j: j["assigned"] or "", reverse=True)
        for j in rows:
            st = stage(j)
            if not a.all and st in ("done", "failed"):
                continue
            print(f'{j["id"]}  {st:8}  -> {j["to"]:12}  {j["title"]}')
        return

    fail("unknown command (new, ack, start, done, fail, resend, show, list)")


if __name__ == "__main__":
    main(sys.argv[1:])
