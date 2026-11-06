#!/usr/bin/env python3
"""Haiku vs Sonnet room-sorting test (Matthew, 2026-11-06: "get the crew to run the haiku test").

Question: is Haiku good enough to sort room messages for Friday and the Switchboard, so the light brain does the
light work and his Max plan lasts longer? One run = 20 public room messages x 2 models = 40 small calls.

Safety (same locks as Friday's brain in FridayBrainData.swift): no tools, no MCP, dontAsk + no prompts, hooks off,
no transcript on disk, run from an empty folder (no CLAUDE.md). Only public room text goes in. Nothing is installed,
no key, no cost shown (his Max plan is not billed per call). The answer key was written before any model ran.

Run on the Mac, from the main checkout:
  python3 tools/crew/haiku-test/run_test.py --limit 2     # smoke test first (4 calls)
  python3 tools/crew/haiku-test/run_test.py               # the real test (40 calls)
Results land in tools/crew/haiku-test/results/ (public-safe: model answers about public messages, seconds, tokens).
"""
import argparse, json, os, re, statistics, subprocess, sys, tempfile, time
from datetime import datetime
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = ["haiku", "sonnet"]
NO_HOOKS = '{"disableAllHooks": true}'
TIMEOUT = 120
WORD_CAP = 25   # NB2, 2026-11-06 (set 2): summaries over 25 words are counted and shown. The prompt itself stays v2 ("at most 20 words").

SYSTEM = (
    "You sort messages from a team chat room. Reply with ONLY one JSON object and no other text:\n"
    '{"asks_action": true or false, "who": "<name>", "summary": "<one line, at most 20 words>"}\n'
    "asks_action: true only if the message asks a specific person or group to do something.\n"
    "who: the ONE name that must act, as written in the message (for example LC-Manager, Friday, Roxy, Matthew, "
    'Everyone). Use "none" when asks_action is false. A name after "cc" is only copied, not asked. '
    'A message that says "no action needed" asks nothing. A status report asks nothing.\n'
    "summary: what the message says, using only facts that are in it.\n"
    # v2 (2026-11-06, after run 1736: Haiku's m12 named the wrong person, m13 blurred who did what; LC-Manager's wording)
    "Who must act is the name after the arrow, or the name written as \"Name:\" right before a request, that is asked to do "
    "something. Never name anyone who is not asked. In the summary, keep who did what exactly as the message says: "
    "never move an action or a request from one person to another."
)

KNOWN = ["matthew", "roxy", "friday", "lcmanager", "lcwork", "lctiktok", "lcpixels", "lctrends",
         "nb2", "newbeginning", "grok", "everyone"]
EVERYONE_WORDS = ["everyone", "crew", "team"]


def find_claude():
    """Newest bundled Claude Code in the desktop app, the same lookup as SwitchboardRules.findClaude."""
    root = Path.home() / "Library/Application Support/Claude/claude-code"
    def ver(name):
        parts = name.split(".")
        return [int(p) for p in parts] if len(parts) >= 2 and all(p.isdigit() for p in parts) else None
    try:
        versions = sorted((n for n in os.listdir(root) if ver(n)), key=ver, reverse=True)
    except OSError:
        return None
    for v in versions:
        for h in sorted(os.listdir(root / v)):
            exe = root / v / h / "claude.app/Contents/MacOS/claude"
            if os.access(exe, os.X_OK):
                return str(exe)
    return None


def args_for(claude, model, text):
    return [claude, "-p", text, "--model", model, "--tools", "", "--strict-mcp-config",
            "--permission-mode", "dontAsk", "--permission-prompts", "none", "--output-format", "json",
            "--system-prompt", SYSTEM, "--settings", NO_HOOKS, "--no-session-persistence"]


def norm(s):
    return re.sub(r"[^a-z0-9]", "", str(s).lower().replace("local claude", ""))


def who_ok(answer, accepted):
    s = norm(answer)
    if accepted == ["none"]:
        return s in ("", "none", "noone", "nobody", "na", "null")
    acc = set(accepted) | (set(EVERYONE_WORDS) if "everyone" in accepted else set())
    hit = any(a in s for a in acc)
    wrong = any(k in s for k in KNOWN if k not in acc)
    return hit and not wrong


def as_bool(v):
    if isinstance(v, bool):
        return v
    if isinstance(v, str) and v.strip().lower() in ("true", "yes"):
        return True
    if isinstance(v, str) and v.strip().lower() in ("false", "no"):
        return False
    return None


def parse_answer(text):
    m = re.search(r"\{.*\}", text or "", re.S)
    if not m:
        return None
    try:
        obj = json.loads(m.group(0))
    except ValueError:
        return None
    return obj if isinstance(obj, dict) else None


def run_one(claude, model, msg, workdir):
    start = time.monotonic()
    rec = {"id": msg["id"], "model": model}
    try:
        p = subprocess.run(args_for(claude, model, msg["text"]), cwd=workdir, capture_output=True,
                           text=True, timeout=TIMEOUT)
        rec["seconds"] = round(time.monotonic() - start, 1)
        rec["exit"] = p.returncode
        outer = json.loads(p.stdout) if p.stdout.strip().startswith("{") else None
    except subprocess.TimeoutExpired:
        rec.update(seconds=TIMEOUT, exit="timeout")
        outer = None
    except (OSError, ValueError) as e:
        rec.update(seconds=round(time.monotonic() - start, 1), exit=f"error: {type(e).__name__}")
        outer = None
    if outer is None:
        rec["engine_ok"] = False
        return rec
    rec["engine_ok"] = not outer.get("is_error", False)
    rec["raw"] = outer.get("result", "")
    u = outer.get("usage")
    if isinstance(u, dict) and "output_tokens" in u:
        rec["tokens"] = {k: u.get(k) for k in ("input_tokens", "cache_read_input_tokens",
                                               "cache_creation_input_tokens", "output_tokens")}
    else:
        rec["tokens"] = "not reported"
    mu = outer.get("modelUsage")
    rec["model_used"] = sorted(mu.keys()) if isinstance(mu, dict) and mu else "not reported"
    rec["answer"] = parse_answer(rec["raw"])
    return rec


def score(recs, key):
    out = {}
    for model in MODELS:
        rs = [r for r in recs if r["model"] == model]
        a_ok = w_ok = valid = 0
        for r in rs:
            k = key[r["id"]]
            ans = r.get("answer")
            if not ans:
                continue
            valid += 1
            if as_bool(ans.get("asks_action")) == k["asks_action"]:
                a_ok += 1
            if who_ok(ans.get("who", ""), k["who"]):
                w_ok += 1
        secs = [r["seconds"] for r in rs if isinstance(r.get("seconds"), (int, float))]
        tok = [r["tokens"] for r in rs if isinstance(r.get("tokens"), dict)]
        def tsum(f):
            return sum((t.get(f) or 0) for t in tok)
        used = sorted({m for r in rs if isinstance(r.get("model_used"), list) for m in r["model_used"]})
        words = [len(str((r.get("answer") or {}).get("summary", "")).split()) for r in rs if r.get("answer")]
        out[model] = {"calls": len(rs), "valid_json": valid, "asks_ok": a_ok, "who_ok": w_ok, "points": a_ok + w_ok,
                      "median_s": round(statistics.median(secs), 1) if secs else None,
                      "tokens_reported_for": len(tok),
                      "input_tokens": tsum("input_tokens") + tsum("cache_read_input_tokens") + tsum("cache_creation_input_tokens"),
                      "output_tokens": tsum("output_tokens"), "model_used": used or "not reported",
                      "over_cap": sum(1 for w in words if w > WORD_CAP), "max_words": max(words) if words else 0}
    return out


def verdict(s, n):
    h, so = s["haiku"], s["sonnet"]
    if h["calls"] < n or so["calls"] < n:
        return "INCOMPLETE: not every call ran. No decision from a partial run."
    need = 0.95 * so["points"]
    passes = h["points"] >= need and h["valid_json"] >= n - 1
    line = (f"Haiku {h['points']}/{2*n} vs Sonnet {so['points']}/{2*n} (Haiku needs >= {need:.1f}); "
            f"valid JSON Haiku {h['valid_json']}/{n}.")
    if passes:
        return line + (" Score test PASSED. Final step: LC-Manager reads the Haiku summaries below; "
                       "if none invents a fact, Haiku takes the sorting jobs.")
    return line + " Score test FAILED: sorting stays on Sonnet."


def report(recs, s, n, msgs, stamp, keyname="answer-key.json"):
    L = [f"# Haiku vs Sonnet room-sorting test, {stamp}", "",
         f"{n} public room messages x 2 models. Answer key written before any run ({keyname}). "
         "No tools, no transcript, hooks off. Tokens are what the engine reported; no cost is shown "
         "(his Max plan isn't billed per call).", "",
         "| | Haiku | Sonnet |", "|---|---|---|"]
    rows = [("Asks-for-action right", "asks_ok"), ("Who-must-act right", "who_ok"), ("Points (of %d)" % (2 * n), "points"),
            ("Valid JSON answers", "valid_json"), ("Median seconds per call", "median_s"),
            ("Calls with tokens reported", "tokens_reported_for"), ("Input tokens (incl. cache)", "input_tokens"),
            ("Output tokens", "output_tokens"), (f"Summaries over {WORD_CAP} words", "over_cap"), ("Longest summary (words)", "max_words"),
            ("Model the engine reported", "model_used")]
    for label, f in rows:
        L.append(f"| {label} | {s['haiku'][f]} | {s['sonnet'][f]} |")
    L += ["", "**Verdict:** " + verdict(s, n), "",
          "## Summaries for LC-Manager's check (does any invent a fact not in the message?)", ""]
    by = {(r["id"], r["model"]): r for r in recs}
    for m in msgs:
        L.append(f"- **{m['id']}** ([source]({m['source']}))")
        for model in MODELS:
            ans = (by.get((m["id"], model)) or {}).get("answer") or {}
            L.append(f"  - {model}: {str(ans.get('summary', '(no answer)')).replace(chr(10), ' ')}")
    return "\n".join(L) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--limit", type=int, default=0, help="only the first N messages (smoke test)")
    ap.add_argument("--claude", help="path to claude (default: the desktop app's bundled copy)")
    ap.add_argument("--set", type=int, default=1, help="message set: 1 = messages.json, 2 = messages-2.json (new messages, key committed first)")
    a = ap.parse_args()
    claude = a.claude or find_claude()
    if not claude:
        sys.exit("No bundled Claude Code found under ~/Library/Application Support/Claude/claude-code. Nothing ran.")
    sfx = "" if a.set == 1 else f"-{a.set}"
    msgs = json.load(open(HERE / f"messages{sfx}.json"))
    if a.limit:
        msgs = msgs[: a.limit]
    key = json.load(open(HERE / f"answer-key{sfx}.json"))["answers"]
    n = len(msgs)
    print(f"{n} messages x {len(MODELS)} models = {n * len(MODELS)} calls, using {claude}")
    recs = []
    with tempfile.TemporaryDirectory(prefix="haiku-test-") as empty:
        for m in msgs:
            for model in MODELS:   # interleaved so neither model gets the quieter minutes
                r = run_one(claude, model, m, empty)
                recs.append(r)
                print(f"  {m['id']} {model:6s} {r.get('seconds')}s exit={r.get('exit')} "
                      f"json={'yes' if r.get('answer') else 'NO'}")
    s = score(recs, key)
    stamp = datetime.now().strftime("%Y-%m-%d-%H%M")
    tag = f"{stamp}{f'-set{a.set}' if a.set != 1 else ''}{'-smoke' if a.limit else ''}"
    outdir = HERE / "results"
    outdir.mkdir(exist_ok=True)
    with open(outdir / f"{tag}.jsonl", "w") as f:
        for r in recs:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    md = report(recs, s, n, msgs, stamp, f"answer-key{sfx}.json")
    (outdir / f"{tag}.md").write_text(md)
    print("\n" + md)
    print(f"Saved: results/{tag}.md and results/{tag}.jsonl")


if __name__ == "__main__":
    main()
