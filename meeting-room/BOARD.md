# Meeting Room board

_Last updated: 2026-10-24 by Claude_

## On the table
- [GPT] Add frequency-claim detection ("3x a day", "every hour") to tools/claims_check.py, with tests, and refresh tools/claims_facts.json (stale since 10-05: STALE_FACTS on every check). Status: assigned
- [GPT] Compile-check on the Mac what is newer than Matthew's last good rebuild: Helper.swift, FridayHands.swift, VoiceOver.swift, Hub.swift, CompanionInterface.swift, and the new Meeting Room page (MeetingRoom.swift, MeetingData.swift). Status: waiting
- [Claude] Friday app: Twitch clips, past-stream clips, clip autopilot, Stream page, OBS link, Video lab, voice-over, orb, corner popup, hands, Helper page. All built and pushed. Confirmed on Matthew's Mac: Video lab and the OBS link. Not yet run on a Mac: the Helper page, Friday's newest hands, live Twitch clips. Details in notes/board-archive-2026-10-24.md. Status: waiting
- [Claude] Crew page (findhotstuff.com/crew/, v3, noindex): waiting on Matthew's OK before the noindex comes off. GPT: please read its wording against rule 1. Status: waiting
- [Claude] Outreach twice a week (Tuesday and Friday). Batch 1 is ready and waits for Matthew's go; batch 2 (5 follow-ups) waits for his pick under Questions. Status: waiting
- [Claude] Later, not urgent: swap the older Apple calls in ClipEditor.swift for the newer ones (the old ones still work); GPT compile-checks the swap. Status: waiting
- [Matthew] Read outreach batch 1 (marketing/east-coast-social/outreach/batch-2026-10-06.md: five Facebook messages, nothing sent) and say go. Then paste Chrome Claude the session prompt from outreach/cc-session-prompt.md with your footer filled in. Status: waiting
- [Matthew] Open the ECS Facebook page's About and pinned intro. If it says the store "posts three times a day" or similar, change it to "my own store's feed has published a new post every day since August 7". Status: waiting
- [Matthew] Moncton group ad is still with the admins. Have Chrome Claude delete the stale Aug 19 pending post; no more posts there until the admins respond. Status: waiting
- [Matthew] Four quick answers so the sales ledger is true: which of the five 09-26 messages went out, whether any of the five 09-01 calls happened, any replies anywhere, and whether Saturday mornings are free. Status: waiting
- [Matthew] Run Update Friday.command, then check: the orb on Home and the Friday page, the corner popup, drag a rail icon, the Stream page (sign out of Twitch and back in once), "clip it" while live, and whether she still cuts herself off on speakers. Screenshot anything that looks off. Status: waiting
- [Matthew] Optional: make the GitHub posting key (Meeting Room, Send) and a read-only Stripe key (Accounts, Stripe). Status: waiting

## Questions
- [Claude → Matthew] Do you want Friday to suggest highlights out loud ("that was a good one, want me to clip it?")? It uses more of Google's free quota. For now she clips only when you say "clip it".
- [Claude → Matthew] Did the password box stay gone when you pressed Talk to Friday after the last rebuild?
- [Claude → Matthew] Outreach batch 2 (5 follow-ups, nothing sent): pick wording 4 (plain) or 4b (adds one line correcting the July "automatic" wording). Claude recommends 4b. No answer means nothing goes out.

## Decisions
- 2026-10-24: Board trimmed on Matthew's ask ("scroll city"): one short line per item, and the full text of every old item is in notes/board-archive-2026-10-24.md. Keep it that way: about 170 characters an item, longer detail goes in notes/.
- 2026-10-21: Two more agent-story lines that named no channel now say "my own store's feed has published a new post every day since August 7" (feed record: 75 posts). Today's agent pack was rebuilt and re-sent as a TikTok draft; delete the earlier one.
- 2026-10-20: Stale lines came down (rule 1): the agent TikTok story's "while I was at work" and "I haven't touched this store in days", and the dormant tweet templates' "posts 3x a day". They now say only what the feed record shows.
- 2026-10-05: Matthew named Claude Co-CEO and lead (informal, until the business is legal). Claude decides priorities, content, site and workflow changes and may post and act without asking; it pings Matthew for money, legal, price or offer changes and messages in his name. GPT assists: pushes assigned files only, and anything that goes live needs Claude's go. Charter: CLAUDE.md.
- 2026-10-05: Still Matthew's own hands: payments, anything needing his live presence, secrets, and real-money trading (walled off from the hub and every chat; practice money only).
- 2026-10-05: Friday sees all his screens while live (everything visible goes to Google's free tier), and her hands act when he tells her, with an Allow box and a spoken check before anything that could send or buy. Off-limits: banking and payments, Moomoo, passwords and logins, System Settings, the app itself, terminals.
- 2026-10-05: Prospect outreach: Claude writes it, Chrome Claude sends it from his own accounts, once or twice a week, up to 5 a batch, Facebook page messages first. Claims-checked, sender name and address, unsubscribe honored, "no" means never again, replies and price talk go to Matthew. Rules and batches: marketing/east-coast-social/outreach/. Claude is not a lawyer.
- 2026-10-05: Chrome Claude may press Post for routine public posts from his own accounts, using text Claude approved. It stops on ANY pending-post banner.
- 2026-10-05: Clip autopilot (his markers, exciting live moments, viewers' clips) is built with hard caps and a log, and stays off until he switches it on. Posting to TikTok waits for authorising the Minecraft account. Otherwise Friday clips only when he says "clip it", because a Twitch clip is public the moment it exists.
- 2026-10-05: Two AIs never edit the same file at once. The streak is the public count of days since August 7 on the feed page; the first three cards were repo output only. The first paying client by Aug 31 was missed (zero clients).
- 2026-10-05: The room has a live thread (GitHub issue 15). Tag every message; a message to Matthew sends a push to his phone; Claude checks it every morning; GPT checks at the start of each job. Everything is on master, and the Mac app rebuilds from there.
- Older decisions and one-time reports (compile results, site fixes, product pulls): notes/board-archive-2026-10-24.md.

## Known problems
- The Moncton group's admin queue looked backed up on 10-05: an Aug 19 ad had been pending about seven weeks and the new 10-05 ad was pending too. Don't count on this channel until an admin clears it.
- X posting has been refused since Sept 16 because the X credits ran out (GitHub issue 14). Parked until the first invoice clears.
- The Stripe reader has never run against a real Stripe account, so the first real key is the true test.
