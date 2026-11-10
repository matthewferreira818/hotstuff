# Helm Simple-mode navigation reorg (LC-Pixels, Mon Nov 9 2026; job J-1108-141525)
Spec: .claude/council/DECISIONS.md, 2026-11-08 (Matthew: "Yes, that layout"). Branch `pixels/nav-reorg`. Advanced mode is untouched.

## What changed (Simple mode only)
- **Five tabs, Cmd-1..5:** Home · Friday · Business · Messages · Crew. Each tab is a family of pages. It lights up on any of them, and a slim strip under the top bar switches between them.
  - Friday: Chat and Voice · Helper · What Friday remembers (the memory button is now always visible on Friday's tab)
  - Business: East Coast Social (opens first) · Store
  - Crew: Jobs (opens first, new small page with the Jobs card) · Crew Station · Daily jobs · Practice robots. A red dot shows on Crew when a crew job failed in the last 24 hours.
- **More, in 3 labelled groups:** Safety (Safety checks, Real or fake?, Accounts, Learn to stay safe) · Tools (Shortcuts, Council) · Fun (Game, Streaming). The tour, Settings and Advanced mode stay at the bottom.
- **One home per page:** every page is in exactly one tab family or More group. Command Core has no home in Simple mode; it lives in Advanced mode. Safety checks, Real or fake? and Learn to stay safe no longer show the Command Core tab bar in Simple mode.
- **One-time "things moved" note** across the top, with a Got it button. It never comes back after that (UserDefaults `hub.navMoved1Seen`).
- **The Home "Needs you" card** was already there. It's unchanged.
- **Deep links and Friday's jumps:** no page was removed or renamed in code, so every `hubSelect(...)` still lands on the same page. In Simple mode it now also shows that page's family strip.

## Calls made (flagged for the gate)
1. **Practice stocks / Practice robots:** the spec lists "Practice robots" under Crew and "Practice stocks" under Tools, but they're the same page. To keep one home, it lives under Crew as "Practice robots". It's a one-line move (`simpleFamilies` / `simpleMoreGroups` in HubSimple.swift) if the gate prefers Tools.
2. **Jobs first:** a new `jobs` page (added at the END of the HubSection enum, so saved numbers keep their meaning). It's the first chip under Crew and reuses CoreJobsCard (up to 20 jobs).

## Files
HubSimple.swift (tabs, families, More groups, strip, Jobs page, red dot, moved note) · HubDeck.swift (Simple mode uses the new strip instead of the Command Core bar) · Hub.swift (`jobs` case) · HubShell.swift (route) · HubCommandJobs.swift (`limit`, `failedRecently`).

## Tested
- Full-app typecheck: 0 errors.
- checks/run.sh: 154 PASS. 1 FAIL ("Roxy herself is away until Nov 9") is a date check that turns false on Nov 9, not this change.
- Optimised build of the test binary: OK.

## NOT done yet (blocked)
- **Before/after screenshots and the 10-second find test (Guard, ECS, Memory) on a test copy.** On Nov 9 at 9:35 PM, background control of the test copy was declined, and `screencapture -l` couldn't capture its window (no screen-recording permission in this session). Both need Matthew's OK for screen access, or the gate runs them.
- Click counts from the code, not timed:

  | Find | Before | After |
  |---|---|---|
  | Guard | More → "Safety checks" (item 7 of a flat 15) | More → Safety → "Safety checks" (item 1 of 4) |
  | ECS | More → "East Coast Social" (item 2 of 15) | **Business** tab (1 click, Cmd-3) |
  | Memory | More → "What Friday remembers" (item 4 of 15) | **Friday** tab → "What Friday remembers" chip |

## Rollback
Not merged. If it is merged and needs undoing, `git revert <merge commit>` brings back the 4 tabs and the flat 15-item More list. Saved settings are safe: the new `jobs` case is last in the enum, so a page number saved by the new build (`hub.testStart`) just falls back to Home in the old build. The `hub.navMoved1Seen` flag is harmless if left behind.
