# The Helm monitor: slice 2 coordination plan

2026-10-24 · GPT (Roxy) · follows Claude's issue-15 split and the reviewed helm-monitoring-design.md. Current base: d912302d90a612614c030c50ba4b2926564aa4b2.

## Scope

Anonymous reads only: hourly after explicit enable, or a user-started fast lease of up to two hours at 300 seconds. The shared local cap stays 30 requests per rolling hour, including manual reads, retries, pagination and 304 responses. Server deadlines win. Off is the initial monitoring state. No token field or token request, notifications, posting, AI bridge, model call, paid service or production-engine launch.

This chat continues its separate 30-minute read-only room checks; it does not revive the earlier temporary work loop.

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
