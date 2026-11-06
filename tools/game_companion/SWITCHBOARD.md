# Friday's Switchboard (branch `switchboard`, built 2026-11-06 by LC-TikTok for LC-Manager)

Cloud Claude posts a tagged comment; Friday (The Helm, on Matthew's Mac) starts ONE headless Local Claude job for it.
Plan: `meeting-room/notes/switchboard-plan.md`. **Nothing is on master. The switch is OFF by default.**

## What it is
- `SwitchboardData.swift`: every rule and limit, no UI, no network (tested offline).
- `HubSwitchboard.swift`: the runner + the panel (switch, log) at the bottom of the Friday page. Test-copy-only hooks at the end.
- `checks/SwitchboardChecks.swift`: the dry run (54 checks). `switchboard-proof/`: its output + screenshots.
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
   replaced by "(result kept in the Friday log)". Refusals of tagged comments are mirrored too. Uses the Meeting Room's GitHub key.
7. **Hard block** (`SwitchboardRules.blockReason`, before anything starts): whole-word match for money/payments, logins/passwords/keys,
   sending to a person, Moomoo (list in the file). Over-blocking is deliberate. Refusals are logged and mirrored.

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
- Real GitHub fetch with the key (`since=` query, 100-comment page limit), real posting of mirror lines to issue 15, rate limits.
- Whether `--permission-mode dontAsk` + `--permission-prompts none` really denies everything outside Matthew's allow list with this settings
  file (read from `--help` text only; LC-Manager's pong run is the first proof). Note his allow list is short, so most jobs will fail with denials.
- Restart-while-ON resuming; the "Stop job" button; the confirm alert's look; narrow/compact layout; accessibility/VoiceOver pass.
- A seen-ID is saved when a comment is handled, so a crash mid-job loses that job rather than re-running it (intended).
- The real Helm (`local.mattyb.gamecompanion`) was not launched or modified. The test copy is `local.mattyb.helmswitchboard`.
- One unexplained log line: in an earlier launch of the test copy the log shows "Switchboard ON" then "OFF" 13 s later that I didn't trigger
  (no job could run: no key). Possibly a stray click while I was setting up screenshots; not reproduced.
