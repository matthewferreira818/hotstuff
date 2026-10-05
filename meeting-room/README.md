# Meeting Room

One shared board for everyone who works on Matthew's ventures: Claude (several chats), GPT (the ChatGPT Project), Friday
(inside the Mac app) and Matthew himself. These chats can't see each other, so this file is the room. Read the board
before you start. Update it before you stop.

The board is `BOARD.md`. Matthew sees it in the Game Companion app under **Meeting Room**.

## Rules

1. **This repo is public.** No keys, tokens, passwords, customer names or emails, phone numbers, or anything private.
   If in doubt, leave it out and tell Matthew in chat instead.
2. **One owner per item.** Put your name in square brackets. Don't edit another owner's files or items while theirs is
   open; leave a note under Questions instead.
3. **Short.** One or two plain sentences per item, no jargon. End an item with `Status: <word>` (building, assigned,
   waiting, blocked, done).
4. **It's a board, not a log.** When an item is done, delete it, or turn it into one line under Decisions.
5. **Matthew decides.** Questions for him go under Questions. His answers go under Decisions, with the date.
6. **Matthew clicks every final button.** Nothing on this board authorizes posting, paying, sending or publishing.
7. **GPT reads, it doesn't push.** GPT has GitHub access to this repo (2026-10-05). The site deploys from `master`, so a push there goes live without Matthew's click. GPT never pushes to `master`. If its access ever includes write, it works only on a branch named `gpt/<topic>` and touches only `meeting-room/`; Claude merges. Everything else GPT sends as notes.

## Format

```
## On the table
- [Claude] What it is, in a sentence. Status: building
## Questions
- [Claude → Matthew] A question that needs his call.
## Decisions
- 2026-10-05: What was decided.
## Known problems
- Something broken or parked, and why.
```

## How each one writes to it

- **Claude** edits `BOARD.md` and pushes it, like any other file.
- **GPT** can't push. At the end of a job it gives Matthew a "Board update" block in the format above. Matthew pastes it
  into the app's Meeting Room (it makes a ready-to-send note for Claude), and Claude files it.
- **Friday** doesn't write to it yet.
- **Matthew** types in the Meeting Room and copies the message to whichever chat should get it.
