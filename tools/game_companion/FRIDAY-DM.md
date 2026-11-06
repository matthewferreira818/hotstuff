# Friday and me: the private DM engine (Phase 2, LC-TikTok, 2026-11-06)

Matthew types a message in The Helm; the open Friday chat is woken and answers. The words stay on his Mac.

## Files (folder `~/Claude/friday-dm`, permissions 700; files 600)
- `inbox.jsonl`: one JSON object per line, `{"id","at","text"}`. Written only by `FridayDM.shared.send(_:)` (the screen never writes it).
- `outbox.jsonl`: one JSON object per line, `{"id","replyTo","at","text"}`. **Appended by the Friday chat** (`at` is ISO-8601, `replyTo` is the inbox id). The screen reads it through `FridayDM.shared.replies`.
- `status.json`: `{"<inbox id>": {"id","at","state"}}`, written by the engine. States: `waiting` (wake sent), `woken` (delivered, proven), `closed` (Friday's chat isn't open), `unconfirmed`, `failed`.

## What the engine does
`FridayDM.shared.start()` runs from `Switchboard.boot()`: it makes the folder (700/600), then every 3 s reads the inbox. Messages with no status get ONE wake for all of them ("read the inbox" covers them). The wake is the same locked-down relay as a Hotline relay (tools: ToolSearch, ListAgents, SendMessage; dontAsk; no MCP; hooks off; empty folder; 3-minute kill) and its text is fixed: `new DM, read ~/Claude/friday-dm/inbox.jsonl`. It goes to the open chat named exactly "Friday". "delivered" only if SendMessage's own reply says success, it went to the one chat that matches, and the text is verbatim. If that chat isn't open the state is `closed` and the screen shows **"Friday's chat is closed — open it to talk"** (`FridayDM.shared.note(forMessage:)` / `closedNote`).
It works with the Switchboard switch ON or OFF: Matthew typing a DM is his own action and the wake carries no words.

## Private
Nothing from `inbox.jsonl` or `outbox.jsonl` ever goes to GitHub, the room, the Hotline, a receipt, a log line, a stored result or a wake. Logs say only "Friday DM wake: delivered/not open/…". A check proves the wake text and the relay prompt never contain the message.

## For the Friday chat
On "new DM, read ~/Claude/friday-dm/inbox.jsonl": read the inbox, answer the newest message(s) you haven't answered, and append one line per reply to `outbox.jsonl`: `{"id":"<unique>","replyTo":"<inbox id>","at":"<ISO-8601 time>","text":"<your reply>"}` (one line, no newlines inside; escape them as \n). Never copy a DM anywhere public.

## Not tested / limits
- A real reply loop with the live Friday chat (the wake was delivered to the open "Friday" chat in my test; her reply to the test DM wasn't checked). The inbox/status test data were cleared afterwards.
- The screen side (LC-Pixels). Lines the Friday chat writes with a bad shape are skipped silently.
- Anyone who can read the Mac user's files can read the DMs (700/600 stops other Mac users, not Matthew's own processes).
