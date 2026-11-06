---
name: creative-council
description: Convene Matthew's creative council: four idea seats (Spark, Hustler, Neighbour, Designer) each bring 5 ideas on a question, the Skeptic checks the finalists, and the Right Hand (you) scores them and picks the best 3. Use when Matthew says /creative-council, "ask the creative council", "brainstorm with the council", or wants fresh ideas on something. Separate from the decision /council.
argument-hint: <what we want ideas for>
---

# The Creative Council (Matthew, 2026-11-06: "comes up with ideas for what we ask them to and decided which are best")

The decision council (/council) judges a choice. This one CREATES options, then picks. Matthew decides.

## 1. Frame the ask
One sentence: what we want ideas for, plus 2-4 bullets of context (real numbers, holds like "outreach waits on CBDC",
deadline, budget $0). Check `.claude/council/CREATIVE.md` for past sessions on the same topic.

## 2. Ideas: four seats in parallel (one message)
Agent types `creative-spark`, `creative-hustler`, `creative-neighbor`, `creative-designer` (Sonnet). Same brief to each,
no hints about the others. 4 × 5 = up to 20 ideas.

## 3. Shortlist, then one Skeptic pass
Merge duplicates. Score every idea 1-5 on: **Money** (does it help us earn?), **Honest** (rule 1: true today, no fake
anything; a fail here = out), **Easy** (Matthew-hours and $; novice-friendly), **Fast** (results within 2 weeks), **Fun**
(will he actually do it?). Money and Honest count double. Take the top 5 to ONE `skeptic` call: "Find the hidden risk in each."
Drop or fix what it breaks.

## 4. Verdict (short, phone-friendly, plain words)
- **The best 3**, each: name, one sentence, first step, why it won (scores).
- **Honourable mentions** (2-3 names).
- **Cut for honesty or risk** (one line each, if any).
- Ask Matthew to pick; nothing gets built or posted until he does (rule 3 still applies to anything public).

## 5. Log
Append to `.claude/council/CREATIVE.md`: date (Moncton), the ask, best 3, mentions, cuts, Matthew's pick when he makes it.
Commit and push. Cost: about 5 Sonnet agents per session; don't run more than one session at a time.
