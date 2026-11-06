# Haiku test: can the light brain sort the room?

Matthew, 2026-11-06: "get the crew to run the haiku test". Kit by Claude (New beginning).

**The question:** can Haiku (the quick, light brain in his Max plan) sort room messages for Friday and the
Switchboard as well as Sonnet? If it can, the light jobs move to Haiku and his plan goes further. No install,
no key, no extra cost. (The local gemma3:4b brain stays parked; Matthew's call, and it squeezes the 8 GB Mac.)

**The test:** 20 public room messages from issue 15, each sent to Haiku and to Sonnet (40 small calls). Each
model answers: does it ask someone to act, who must act, and a one-line summary. `answer-key.json` was written
before any model ran, so neither model grades itself.

**Safety:** the same locks as Friday's brain: no tools, no MCP, nothing that asks, hooks off, no transcript on
disk (`--no-session-persistence`), run from an empty folder. Only public room text goes in.

## Run it (on the Mac, main checkout, pull master first)

```
python3 tools/crew/haiku-test/run_test.py --limit 2   # smoke test, 4 calls
python3 tools/crew/haiku-test/run_test.py             # the real test, 40 calls
```

It finds the desktop app's bundled Claude Code by itself (the same lookup the Switchboard uses).
Results: `results/<date-time>.md` (table + verdict + summaries) and `.jsonl` (every call). Both are public-safe.
Commit them as the job's proof.

## The pass rule (fixed before the run)

Haiku passes if **all three** hold:
1. its points (asks-for-action + who-must-act, out of 40) are at least 95% of Sonnet's,
2. at least 19 of 20 answers are valid JSON,
3. LC-Manager reads Haiku's 20 summaries and none invents a fact that isn't in the message.

Pass: Switchboard sorting and Friday's light sorting jobs move to Haiku (a separate change, with Matthew's GO).
Fail: they stay on Sonnet, and we say so plainly.
