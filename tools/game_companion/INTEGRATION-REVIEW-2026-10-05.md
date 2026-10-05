# Friday's integration packet: review (2026-10-05)

Packet base `0ab248f`. All six base-file hashes match current master, so
there's no drift. This lives on `claude/stock-buyer-ai-4ed40b`, not on
master, because nothing gets installed until Matthew says so.

## Accepted

- **New files, as sent:** `Conversation.swift`, `CompanionConversation.swift`,
  `CompanionInterface.swift`. Memory is opt-in and stays in
  `~/Library/Application Support/GameCompanion/` (mode 600, never in Git).
  Sharing memory with Google is a separate switch and resets to off on
  every launch.
- **Companion.swift hooks, as sent:** auto-comments are gated to local
  engine + Game view; one screen/notes/instructions policy for typed and
  spoken input; a cancel fence before network work; the old view is
  renamed `LegacyContentView` and kept for rollback.
- **Live.swift:** the proposed one-line `conversationInstructions()` hook.
- **rebuild.sh:** the three new files added to both the compile and copy lines.

## Engine fix added (the reconciliation the packet asked for)

`clearSession()` didn't stop late callbacks from a stopped session. Live.swift
now has a `session` counter, bumped on every start and stop:

- The microphone-permission callback only starts audio for the session that asked.
- A screenshot that finishes after Stop is dropped, and so is its error
  message (it used to overwrite "Live buddy is off").
- A wiki answer only goes to the connection that asked for it. A lookup
  that finishes after Stop, a restart, or a 10-minute reconnect is dropped,
  instead of reaching a newer session with a stale call ID.

The quota fallback (drop Search, switch on wiki, reconnect) was already on
master and is unchanged.

## Tests

- PASS: both patches apply cleanly to master; the packet's
  `patch --dry-run` result reproduced here.
- PASS: every engine property and method the new files use exists in
  Companion.swift and Live.swift.
- Friday's Mac compile log shows warnings only (deprecated audio APIs),
  no errors. **Not re-run with the engine fix.** There's no Swift
  compiler on Linux, so the Mac build below is the real test.
- Memory/privacy checks: `checks/ReviewChecks.swift` (run it as shown below).

## Notes, not blockers

- Switching between "On this Mac" and "Google Live" runs Stop all, which
  also un-shares the game window, so you have to choose it again.
  That's safe but a bit annoying.
- An automatic game comment can use up a due initiative question.
- In Conversation view, Google Live still says it's a "gaming buddy" first;
  the added scope line softens that.

## Matthew's steps before installing (on the Mac, in Terminal)

1. `cd ~/hotstuff && git fetch && git checkout claude/stock-buyer-ai-4ed40b`
2. Run the checks, which touch no Keychain, microphone or network:
   `cd tools/game_companion && xcrun swiftc -parse-as-library Conversation.swift checks/ReviewChecks.swift -o /tmp/rc && /tmp/rc`
   You should see a line starting `PASS:`.
3. Only when you're ready to install: `zsh tools/game_companion/rebuild.sh`.
   It backs up the old app as a zip first.
4. Live tests, in order: local voice → Google Live game view → a wiki
   lookup, then Stop mid-lookup → Conversation view → memory on/off/delete.
5. If it's good, tell Claude to merge it to master. To go back:
   `git checkout master`, then rebuild.
