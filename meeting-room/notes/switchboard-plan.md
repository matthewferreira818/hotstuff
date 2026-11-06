# Friday the Switchboard + the Hotline (started 2026-11-06, ~2:30 AM Moncton)

Matthew's ask: "lets made this shit perfect" — cloud Claude and the Local Claude (LC) chats should
talk to each other without him copying and pasting. Friday (The Helm, on his Mac) becomes the switchboard.

## Why this is needed (tested 2026-11-06)
- Cloud Claude cannot see the Mac: Remote Control folders show `not_available` for cloud chats.
- LC's ListAgents only lists the LC chats on the Mac; no cloud chat shows up (LC-Manager checked).
- Issue 15 works both ways but nobody gets woken: up to 2 hours of lag.

## The two pieces
1. **Hotline (LC/Friday → cloud Claude, instant).** A never-merged pull request named "📞 Hotline".
   Cloud Claude (chat "New beginning") is subscribed to it: every comment wakes that chat within seconds.
   To reach cloud Claude fast: comment on the Hotline PR, tag `**[Local Claude (LC-xxx) → Claude]**`
   or `**[Friday → Claude]**`, one short message, and also mirror it to issue 15. Rare, only when it matters.
2. **Switchboard (cloud Claude → LC, within minutes).** Inside The Helm, Friday checks issue 15 and the
   Hotline every few minutes. When she sees a message tagged exactly `[Claude → Local Claude]` (or
   `[Claude (<name>) → Local Claude ...]`), she starts a Local Claude job on the Mac with that message
   as the job, and posts "[Friday] started job: <first line>" to issue 15; when it ends, the result line.

## Safety locks (non-negotiable, LC-Manager's quality gate checks every one)
- Only comments authored by the owner account AND carrying a `[Claude` sender tag count. Everything else is ignored.
- The job runs with LC's normal settings and deny list (no secrets, no ~/.ssh, no moomoo, no rm -rf,
  no force-push, no ~/hotstuff build folder). Friday never widens permissions; no permission laundering.
- One job at a time, at most 3 started per hour, at most 12 per day (usage). A job longer than 30 minutes is stopped.
- An on/off switch on the Friday page, OFF by default until Matthew's GO; a visible log of every job.
- Never acts on money, logins, payments, sending to a person, or Moomoo: those stay Matthew's.
- Every job's start and end mirrored to issue 15 (no PII; the repo is public).

## How Friday starts a job (to verify on the Mac first)
- Check whether the Claude Code command-line tool is installed (`claude --version`), as part of the desktop
  app or separately. If it is, the job is a headless run in `~/Claude/hotstuff`
  (e.g. `claude -p "<job>"` with the same settings file). If not, LC-Manager reports what's needed; nothing gets installed without saying so.

## Who does what
- **LC-Manager**: owns the plan, checks the safety locks, runs the quality gate, reports to the room.
- **Builder: LC-TikTok** (idle, its job is done): builds the Switchboard in its own git worktree
  `~/Claude/hotstuff-switchboard`, branch `switchboard` off `helm-revamp`, NEW files only where possible
  (SwitchboardData.swift, HubSwitchboard.swift) plus the smallest wiring, so it doesn't collide with LC-Helm build.
- **LC-Helm build**: keeps finishing the revamp; doesn't touch the switchboard files.
- **Cloud Claude (New beginning)**: owns the Hotline, reviews and merges the switchboard branch after the gate and Matthew's GO.

## Done means
One harmless round trip, proven: cloud Claude posts `[Claude → Local Claude] test: reply "pong" on the Hotline`,
Friday starts an LC job, the LC comments "pong" on the Hotline, cloud Claude wakes and answers. Screenshots + links.

## Model per job (Matthew, 2026-11-06)
Each switchboard job runs on the right brain: Haiku for quick checks, Sonnet (default) for normal work,
Opus only for hard design/bugs/safety reviews. Cloud Claude may name the model in the message, e.g.
`[Claude → Local Claude] (model: opus) ...`; with no model named, Sonnet. Friday shows the model in her job log.
