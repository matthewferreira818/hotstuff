# Friday's Switchboard (branch `switchboard`, built 2026-11-06 by LC-TikTok for LC-Manager)

Cloud Claude posts a tagged comment; Friday (The Helm, on Matthew's Mac) starts ONE headless Local Claude job for it.
Plan: `meeting-room/notes/switchboard-plan.md`. **Nothing is on master. The switch is OFF by default.**

## What it is
- `SwitchboardData.swift`: every rule and limit, no UI, no network (tested offline).
- `HubSwitchboard.swift`: the runner + the panel (switch, log) at the bottom of the Friday page. Test-copy-only hooks at the end.
- `checks/SwitchboardChecks.swift`: the dry run (66 checks). `switchboard-proof/`: its output + screenshots.
- Wiring in LC-Helm's files (3 small edits): `rebuild.sh` (2 names added to SOURCES), `HubDeckFriday.swift` (1 line: the panel),
  `CompanionInterface.swift` (1 line: `Switchboard.shared.boot()`).

## The locks (where each lives)
1. **Trigger.** Author == `matthewferreira818` AND body starts `**[Claude` AND the tag (text up to the first `]`) contains `→ Local Claude`.
   Only issue 15 and PR #35. Each comment ID is processed once (seen-IDs kept on disk). A comment edited after posting
   (`updated_at` more than 5 s after `created_at`) is refused, never run. Friday's own mirror lines and LC replies can't trigger (no loops).
2. **KNOWN GAP (not hidden):** Roxy/GPT, cloud Claude and every chat post through the SAME owner account, so the owner check cannot tell
   crew members apart, and nothing stops someone with Matthew's GitHub login from posting a trigger. The tag is a label anyone on that
   account can type. The remaining protection is the other locks (hard block, limits, normal permission list, switch).
3. **Headless run.** `claude -p <comment text> --output-format json --permission-mode dontAsk --permission-prompts none`, cwd `~/Claude/hotstuff`,
   Matthew's normal `~/.claude/settings.json`. Anything not already allowed is denied and reported; it never asks another chat. The command
   line is re-checked in code before launch (`argumentsAreSafe`: no `--dangerously-skip-permissions`, no bypass/auto/acceptEdits, no
   `--settings`, `--add-dir`, `--allowedTools`). The comment text is ONE argument, no shell. If settings.json sets `defaultMode: bypassPermissions`, nothing runs.
   The claude binary is found at run time (newest version folder in `~/Library/Application Support/Claude/claude-code`) and `--version` must
   answer "… (Claude Code)"; otherwise it logs and does not run. Nothing is installed.
4. **Limits** (`SwitchboardLimits`, one place): 1 running, 3 started per rolling hour, 12 per day, 30-minute kill (SIGTERM, then SIGKILL after 10 s).
   Comments older than 6 hours or posted before the switch was turned on never run.
5. **Switch.** OFF by default, saved per app ID in UserDefaults (`switchboard.on`); turning ON asks for confirmation. A restart while ON
   resumes watching; a restart while OFF stays OFF. Turning it OFF stops a running job. The log (last 400 lines) shows on the Friday page and
   in a full-log sheet, and is saved in `~/Library/Application Support/Switchboard-<app id>/`.
6. **Mirror.** Start (comment id, thread, first line of the comment) is posted to issue 15 BEFORE the job runs; if that post fails the job
   doesn't run. End = outcome, minutes, first line of the result only; results with home paths, e-mail addresses or hard-block words are
   replaced by "(result kept in the Friday log)". Refusals of tagged comments are mirrored too. GitHub is reached ONLY through Matthew's own `gh` login (`~/Claude/bin/gh`, run as a process with an argument array, no shell): `gh api repos/matthewferreira818/hotstuff/issues/<n>/comments?since=…` to read, `gh issue comment 15` to mirror. The Switchboard holds no GitHub key and stores none (LC-Manager's fix 1). If `gh` is missing or logged out it reads nothing and starts nothing.
7. **Hard block** (`SwitchboardRules.blockReason`, before anything starts): whole-word match for money/payments, logins/passwords/keys,
   sending to a person, Moomoo (list in the file). Over-blocking is deliberate. Refusals are logged and mirrored.

## After the first live pong runs (LC-Manager, 3:07 AM)
- **Job 2 lied:** it wrote "pong" as text, claimed a Hotline reply it never posted, and was logged "done".
- **Fix A:** Friday posts each job's result line back to the thread the job came from using `gh`: issue 15 always (lock 6), and for a Hotline job ALSO PR #35 (that wakes cloud Claude). Tag `**[Friday (LC-Switchboard) → Claude]**`, first line only, same privacy rules. "Reply on the Hotline" no longer depends on the job.
- **Fix B:** the job prompt now says: only claim an action a tool did, say so if a tool is missing, and don't claim to have posted (Friday does it).
- **Fix C:** if the result says posted/pushed/sent/etc. but the run was 1 turn (no tools) with no denials, the log says UNPROVEN and the mirror carries "UNPROVEN: the job says it took an action but used no tools." Heuristic: a keyword list (`actionWords`) plus `num_turns <= 1`; it can miss odd wordings.
- **Poll interval:** 300 s (5 min) real default; 30 s only in a test copy with `switchboard.testFastPoll`. All constants in `SwitchboardLimits`.

## ROLLBACK
Fastest: flip the switch OFF on the Friday page (stops any running job, starts none). To remove it from a running Helm: rebuild The Helm from
master (`git checkout master` in a clean checkout, run `tools/game_companion/rebuild.sh`); master has none of this code, and the old app is
kept as `outputs/GameCompanion-backup.zip`. If the branch were merged and had to go: `git revert` the merge commit. Leftover local files are
harmless: `~/Library/Application Support/Switchboard-*` (log/state/job output). Jobs only ever touch what Matthew's permission list allows, so
there is nothing to undo outside the log, except whatever a job itself did (its result is in issue 15 and `jobs/job-N.json`).

## NOT TESTED (honest list)
- **A real job has never run.** The in-app dry run used fake comments in a test copy that has no GitHub key, so the one good comment was
  stopped at the mirror step ("couldn't mirror it to issue 15"), which is the designed safe failure. The headless `claude -p` launch, the
  JSON result parsing against real output, the 30-minute kill and the end-of-job mirror are untested live (parsing and rules are unit-tested).
- The app's own `gh` calls (fetch + mirror) were compiled but NOT run in the test copy: running the fake-comment dry run now would post real refusal lines to the public issue 15. `gh api` itself works and its real JSON parses.
- Real mirror posting to issue 15 through `gh` from inside the app, the 100-comment page limit, rate limits. (The real `gh api` JSON for issue 15 was parsed by the checks: see below.)
- Whether `--permission-mode dontAsk` + `--permission-prompts none` really denies everything outside Matthew's allow list with this settings
  file (read from `--help` text only; LC-Manager's pong run is the first proof). Note his allow list is short, so most jobs will fail with denials.
- Restart-while-ON resuming; the "Stop job" button; the confirm alert's look; narrow/compact layout; accessibility/VoiceOver pass.
- A seen-ID is saved when a comment is handled, so a crash mid-job loses that job rather than re-running it (intended).
- The real Helm (`local.mattyb.gamecompanion`) was not launched or modified. The test copy is `local.mattyb.helmswitchboard`.
- **The ON→OFF 13 s oddity (explained as far as the evidence goes).** The log showed "ON" at 2:35:20 AM and "OFF" at 2:35:33 AM in the test copy. `testTurnOn` was NOT set then (`defaults read` shows only `hub.testStart`), and quitting the app never calls `setOn(false)`: the only paths to ON are the confirm alert or that test hook, and the only path to OFF is the toggle. So both were clicks in the test window, not a code path: most likely Matthew (or another agent) trying the visible test window. A clean relaunch with no hooks and 45 s of waiting did not reproduce it (no new log lines, switch stayed 0). To make this provable next time, every ON/OFF log line now says what turned it on or off ("the switch on the Friday page", "the switch (confirmed in the alert)" or "the test hook").

## Current scope (what a job can actually do)
A job runs with Matthew's normal `~/.claude/settings.json` under `dontAsk`: only his allow list works. Today that list has read access to `~/Claude/**`, read-only git, `gh issue view 15`, `gh issue comment 15`, `smoke_test.py`, and `claims_check.py`. There is **no Edit/Write**, so a headless job can read and comment on issue 15 but can't change files. It has **no `gh pr comment 35`**, so the plan's "pong on the Hotline" job would be DENIED and reported (the lock working as designed). Whether to add `Bash(~/Claude/bin/gh pr comment 35 *)` is Matthew's decision (LC-Manager asked him); nobody here edits settings.json.
