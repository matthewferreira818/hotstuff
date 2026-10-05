# Prospect outreach — how it runs (decided by Matthew, 2026-10-05)

Matthew lifted the old "he sends every message to individual people" rule for prospect outreach (CLAUDE.md, rule 3).
**Channel: Facebook page messages.** Claude prepares, Chrome Claude (C.C) sends from Matthew's own account.
Twice a week at most (Tuesday and Friday), up to 5 messages a batch. This is a public repo: **Matthew's home address is never
written here.** The footer's address is pasted into C.C's session by Matthew (see `cc-session-prompt.md`).

## Who does what
- **Claude (scheduled routine, Tuesday and Friday around noon):** reads the room thread for C.C's sent log, replies, and any
  "no thanks"; updates `prospects.md`; picks up to 5 prospects; writes `batch-YYYY-MM-DD.md` with the messages filled in
  (except the last-post month and the footer); runs `tools/claims_check.py` on each; pings Matthew that the batch is ready. If
  the last batch has no sent log yet, no new batch is made; Claude just reminds him.
- **Matthew:** starts a C.C session when a batch is ready (paste the prompt, paste the footer). First batch only: he reads it
  and says go. After that, no per-batch approval, but the morning brief lists what went out.
- **C.C:** opens the batch, checks each page's last post, sends only to pages that are truly quiet, skips active ones, and posts a
  sent log in the room thread (issue 15) tagged `**[C.C → Claude]**`.

## Rules (anti-spam law, honesty, good manners)
Canada's anti-spam law (CASL) covers messages that sell a service, including Facebook messages. Claude is not a lawyer, and
Matthew will have a business advisor check this as we go. Until then:
1. **Every message** says who it is from (Matthew Ferreira, East Coast Social), has the mailing address and phone, a website,
   and a plain way to stop: "reply no thanks and I won't message you again".
2. **Only to a business's own published page**, only about their business (their social media). No personal profiles.
3. **A "no", "stop", "unsubscribe", or a clear annoyed reply = never contact that business again.** Honored the same day, and
   marked 🚫 in `prospects.md`.
4. **Two touches at most per business:** a first message, and one follow-up at least three weeks later. Then they rest.
5. **Keep a record:** the ledger notes the date, the page, and why we thought it was a fit.
6. **Only true claims.** Free setup, free sample week, $79 a month, no contract, and "my own store's feed has published a new
   post every day since August 7" (never "my page"; link findhotstuff.com/automation). No invented reviews, no fake urgency,
   no misleading first line. Never claim a quiet page is quiet unless C.C just saw the last post date.
7. **Small and personal:** at most 5 a batch, each with the business's real name. Facebook can flag accounts that send many
   similar messages, so if Facebook shows any warning, checkpoint or "message limit" notice, C.C stops and tells Matthew.
8. **Replies outrank new outreach.** Any reply, or any talk of price or the offer, goes to Matthew straight away.
9. Messages to clients or officials are not covered by this and still go through Matthew.
