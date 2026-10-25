# The Helm monitor: slice 2 coordination plan

2026-10-24 · GPT (Roxy) · follows Claude's issue-15 split and the reviewed helm-monitoring-design.md. Current base: d912302d90a612614c030c50ba4b2926564aa4b2.

## Scope

Anonymous reads only: hourly after explicit enable, or a user-started fast lease of up to two hours at 300 seconds. The shared local cap stays 30 requests per rolling hour, including manual reads, retries, pagination and 304 responses. Server deadlines win. Off is the initial monitoring state. No token field or token request, notifications, posting, AI bridge, model call, paid service or production-engine launch.

Matthew resumed this integration on October 25 and selected hourly chat checks. Those checks can continue this authorized operation, then return to read-only checks between operations. The app monitor and chat routine remain separate.

## Ownership and first review piece

GPT owns new MeetingMonitor.swift and its offline checks. Claude owns any MeetingData.swift read seam. First deliver the coordinator, private persistence and fake-transport checks as a dormant component; do not change the live room refresh paths yet. Claude runs the offline checks on Linux, then GPT compiles the exact candidate on Matthew's Mac before Claude reviews/merges.

After that review, claim and edit MeetingRoom.swift, CompanionInterface.swift and HubHelpers.swift one at a time for one coherent integration candidate. Register the new sources in rebuild.sh and make_gpt_bundle.py. Do not activate a second poller alongside the old timers: all room read entry points must switch together through the coordinator. Existing explicit posting and Friday's permissions stay unchanged.

## Read seam requested from Claude

Provide monitor-only request/parsing types without a dependency on the coordinator, preserving existing display/posting functions. GPT will own the URLSession lifetime, cancellation, GET-only dispatch, strict endpoint guard and request reservation. The seam should supply:

- Board payload plus stable source digest; comments with ID, createdAt, updatedAt, stable body digest and transient RoomMessage payload.
- Exact cache identity and ETag, complete-page status, validated server Date and Link continuation, and normalized rate/reset/retry/poll hints.
- Conditional requests only for an identical endpoint/query/representation with a usable memory snapshot. After restart, a missing snapshot requires a full response.

Allow only HTTPS api.github.com resources for this repository's BOARD.md and issue 15 comments. Generate/validate expected page, per_page and fixed since query values; do not accept arbitrary Link URLs. Reject redirects. Never attach Authorization, cookies, a saved posting credential, an HTTP body or a write method. Invalid payloads must still retain server delay metadata. No response body or raw headers enter persisted state or audit events.

## Coordinator and persistence

One cancellable scheduler and serialized request path use the existing slice-1 policies. Reserve and persist every attempt before dispatch; retain the reservation if cancelled. Check generation and Stop after every suspension, and discard late results. Persist a complete candidate before adopting cursor/unread changes. Preserve per-source successful-check timestamps and partial cached data; attempted refresh is not success. Cold sync establishes a silent baseline, with at most three pages per scheduler turn.

Store settings, budgets, per-source policy state, revision cursor/batch metadata, unread identifiers and the last 200 audit events atomically in one new private file under the app's Application Support area. The directory is owner-only, and the file is owner read/write. Keep payloads and cache validators only in memory. Events contain fixed event kinds, IDs/hashes, timestamps and numeric status/timing values; never bodies, excerpts, secrets, headers, private paths or raw errors. A storage failure pauses automatic work, preserves the last committed cursor and displays an honest fixed error. No rotation/viewer in this slice.

## Decision before routing integration

Off must stop all automatic room reads. Proposed manual behavior: an explicit Refresh may perform one budgeted read while remaining Off; it never enables a timer, and Stop cancels/discards that request by generation too. Existing automatic startup/timer callers cannot use that manual path. Claude should confirm this, or choose that Refresh is disabled until the user enables monitoring. Resolve this before changing live refresh routes; do not silently reinterpret force:true as user intent.

## Acceptance gates

Offline checks cover anonymous-only requests and redirect/path rejection; single-flight refreshes; shared limits/backoff and pagination; persistence before dispatch/adoption; interrupted writes; last-200 retention without payloads; quiet-room freshness; lease expiry; Stop during a delayed response; restart after Stop; and partial failures. The integration candidate also needs compact/keyboard UI checks and a complete Mac compile. No install or production launch is a build test. Actual installed-app smoke checks remain a later, explicit step.

## Integration candidate (October 25)

Based on master 31fe8e9, including Claude’s Friday upgrade. MeetingHub owns one coordinator and observes transient snapshots. The compact scrollable card offers Hourly, Fast for 2 hours, Finish task, Stop, unread count/Mark read, and separate one-request board/messages refresh buttons. It shows each source’s last successful check, missing session payload, pagination and backoff/error state. Storage failures pause reads with a fixed message.

Routing lives in HubShell.swift (not HubHelpers.swift). Startup resumes only a saved enabled mode; the old page/global room timers are removed. Friday’s existing automatic `refresh(minGap:)` caller is kept compatible through MeetingHub but only resumes the same scheduler, never overrides Off/cadence. Explicit inbox and post-followup reads use one budgeted comments request. Existing posting permissions are unchanged. Missing session history is described honestly; full history remains on GitHub.

The coordinator publishes payloads only after persistence succeeds, bounds the observation buffer to one latest snapshot, and uses an ephemeral URLSession per request, invalidated on completion. No session/delegate retention cycle remains. Monitor sources and offline checks are registered in the build/bundle lists. No production engine is installed or launched by validation.

## Integration validation and handoff

- Review PR #26, branch `gpt/helm-monitor-integration`.
- Exact Swift/build candidate: `8929272bcd065351682d3c584a1b593b40e147cf`, based on master `31fe8e9261349d4303348e2e6a399ef8eec80a92`.
- Full optimized 57-source compile on Matthew’s Mac: **exit 0, errors 0, warnings 28** (existing Apple deprecations), macOS 27.2, Apple Swift 6.4. Build-only output; no install or production launch.
- Offline coordinator, core policy and read-seam binaries: **compile 0, run 0** each. New observation checks cover payload publication after persistence, explicit one-source manual reads, missing payload after restart, Stop/late responses and storage failure.
- Mac-only isolated MeetingHub/card fixture: **compile 0, run 0**. Checks startup and Friday’s automatic caller under Off, one-source manual reads, Fast/Finish/Stop, restart and unread clearing. Command-period is dispatched through the fixture window and verified to stop the monitor. Off, Fast and paused card renders inspected at 344-point width; controls wrap vertically and content remains scrollable. This fixture contains no production engines and stubs credential access.
- Presentation snapshots carry a monotonic revision so a delayed observer cannot overwrite a newer action result. A timing regression surfaced in the fixture and was fixed before the compiled candidate.
- Build-script shell syntax, Python syntax and diff whitespace checks pass. Source registration retains the script executable mode and FridayData.
- Linux rerun/review and merge belong to Claude. Installed-app smoke testing (actual network, sleep/resume and whole-window navigation) remains unverified; the isolated card check is not a production launch.

Reproduce on Linux from `tools/game_companion`: compile/run the commands in `checks/MeetingMonitorCoordinatorChecks.swift`, `checks/MeetingMonitorChecks.swift` and `checks/MeetingReadSeamChecks.swift`. On Mac: `python3 checks/run_monitor_integration_checks.py /tmp/helm-monitor-integration-checks`. Do not use rebuild.sh as a compile-only test: it installs the app.
