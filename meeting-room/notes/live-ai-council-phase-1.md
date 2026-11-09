# Live AI Council: Phase 1 implementation plan

Written 2026-11-04 by GPT (Roxy) after Matthew said to begin. **Planning only.** Nothing in this branch changes or runs the Mac app.

## Objective and ownership

Matthew wants Roxy (OpenAI), Claude (Anthropic), and Grok (xAI) to **talk to one another in real time** inside his existing Game Companion / The Helm Meeting Room. He can enter at any point, see which model said what, pause/stop the discussion, and approve any external action. Claude owns Meeting Room / voice code under the app revamp agreement. GPT provides this independent design for Claude to review; no edit to owned app files without coordination.

## Existing system to preserve

- `tools/game_companion/MeetingRoom.swift`, `MeetingData.swift` and `ThreadData.swift` show the public board and GitHub issue #15. The thread is asynchronous, not a live model session.
- `MeetingVoice.swift` reads existing text aloud with local macOS voices. It is **not** a two-way live AI call.
- Keep existing six tabs, message routing, Guard rules, Friday's hands/off-limits, Keychain, and Update Friday flow working.
- **Do not** put private conversation transcripts, credentials, personal/customer data or API payloads into public GitHub issue #15 or the public repository.

## Phase 1A: offline, no-account prototype (first milestone)

1. Design a **separate Council session** view behind a clear `Start council` action, not as an automatic listener to issue #15.
2. Create local meeting records: `session_id`, sequence, speaker (Matthew/Roxy/Claude/Grok), recipient/round, UTC timestamp, message body, state (`queued/streaming/done/failed/stopped`). Store privately on Matthew's Mac, or hold in memory for the first prototype. No automatic public sync.
3. Use clearly marked **test providers** initially to validate the UX and orchestration without pretending generated fixtures are real model replies.
4. Single moderated turn queue: start with Matthew's prompt; every response receives the prior session transcript. Suggested bounded sequence: Roxy proposal → Claude critique → Grok alternative → Roxy synthesis; optionally one more round if Matthew asks. The models must address actual preceding arguments, not merely give three independent answers.
5. UI: speaker labels and streamed output, text input, `Start`, `Interrupt`, `Stop`; waiting/error/paused states; copy/export local transcript. Ensure no double-send, no ghost replies after Stop, and no claims of a connected model when none is connected.
6. Bound everything: default maximum 6 assistant turns per session; no automatic restart; per-model output caps; timeout; queue depth limit; maximum context size. The hard `Stop` cancels ongoing streaming requests and pending turns. User input interrupts the queue and becomes next priority.

## Phase 1B: connect real model adapters (only after explicit owner approval)

- One interchangeable adapter per provider: OpenAI, Anthropic, xAI; use the provider's official API and streaming mechanism. Keep provider configuration separate from UI and transcript storage.
- Credentials in existing macOS Keychain / locally protected configuration only, never hard-coded, committed, included in issue comments, or printed in logs. Matthew enters credentials himself.
- ChatGPT/Claude/Grok consumer subscriptions **do not automatically supply** the API billing or keys. **No sign-up, billing, purchase, usage charges, or credential changes** in this phase without Matthew's approval.
- Prefer minimal input per model: council messages and selected facts only. Exclude saved secrets, client leads, banking details, and screen captures by default. Each model receives the same relevant context plus its own role instructions.
- Implement a hard spending/usage guard before making real requests, with visible current usage and automatic halt on cap. Never silently fall back to a paid model.
- Network operations restricted to model responses. Tools that post, send, publish, trade, spend, sign, log in, or control the Mac are **disabled** in Phase 1. Keep existing Friday approval gates untouched.
- Show honest statuses (connected / not configured / error) for each provider. Fewer than three configured providers = identify missing seat; do not simulate it as live.

## Phase 2: voice after real text works

- Reuse local AVSpeechSynthesizer output for distinct spoken voices where appropriate. Handle one speaking at a time and user interruptions.
- Microphone capture and speech-to-text require explicit enable/permission, and the UI must disclose where any audio is sent. Do not claim simultaneous full-duplex voice until verified.

## Acceptance tests

- Three distinct adapters can each receive the transcript and answer **one another's actual messages** with independent speaker attribution.
- The full round displays as a streamed conversation; Matthew can send a message between any two turns.
- Stop prevents another token or provider turn from being initiated; retries are explicit, bounded, and idempotent.
- No public issue posts, emails, social posts, orders, trades, or file changes from the council.
- Model unavailable/billing unconfigured: clearly labelled unavailable, never faked.
- Existing Meeting Room + Friday still launch and work as before; `rebuild.sh` includes any new Swift sources and passes a real Mac compile before merge.

## Proposed next step

Claude: review this spec, identify the smallest file-level integration on a separate branch that **does not alter** public issue #15, and choose Phase 1A file ownership. GPT can prepare data model / test notes if delegated. Neither model should merge any council-related UI to master without the normal compile, honesty, secrets, and approval checks.
