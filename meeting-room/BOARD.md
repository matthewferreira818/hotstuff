# Meeting Room board

_Last updated: 2026-10-24 by Claude_

## On the table
- [Claude] Helping Roxy check the room, act on orders and reply on her own: rules and a paste-ready prompt are in notes/roxy-playbook.md. Matthew pastes one message to her chat. Status: waiting
- [GPT] Monitor slice 1: claiming new MeetingMonitorData.swift + checks/MeetingMonitorChecks.swift on gpt/helm-monitor-slice-1. Foundation logic only; Claude Linux checks first, then Mac compile. No transport, notifications or AI bridge. Status: building
- [Claude] App revamp, with Roxy (Matthew, 10-24: "completely revamp the app, surprise me"). Done on master: Hub.swift split by page, HubTheme.swift, north star (notes/design/). Next: review and merge Roxy's branches after her Mac compile. Plan: notes/app-revamp-plan.md. Status: building
- [GPT] Systems page is on master (Claude reviewed; Mac compile of 4b6d051 exit 0, 28 warnings; not launch-tested). All four business pages are done. Next: Hot hands on Stocks, then monitor slice 1. Compile on Matthew's Mac before each merge. Status: building
- [GPT] Add frequency-claim detection ("3x a day", "every hour") to tools/claims_check.py, with tests, on a branch. Also refresh tools/claims_facts.json (stale since 10-05: STALE_FACTS on every check). Status: assigned
- [Claude] Friday app: built and pushed, but only the Video lab and the OBS card link are confirmed on Matthew's Mac (10-14). Not yet run: Helper page, newest hands, live Twitch clips, past-stream clips, clip autopilot, Stream page, orb, corner popup, voice-over, OBS voice tools. Feature list: notes/board-archive-2026-10-24.md. Status: waiting
- [Claude] Voice for the room, Call a board meeting, Roxy as GPT's name on screen, send times on messages: on master, compile-verified on Matthew's Mac (voice and foundation, 93177cd); the send-times change (351633a) is not compiled yet. Live on his Mac after Update Friday. Status: waiting
- [Claude] Crew page (findhotstuff.com/crew/, v3, noindex): waiting on Matthew's OK before the noindex comes off. GPT: please read its wording against rule 1. Status: waiting
- [Claude] Outreach twice a week (Tuesday and Friday). Batch 1 is ready and waits for Matthew's go; batch 2 (5 follow-ups) waits for his pick under Questions. Status: waiting
- [Claude] Later, not urgent: swap the older Apple calls in ClipEditor.swift for the newer ones, after the first clip test works (the old ones still work); GPT compile-checks the swap. Status: waiting
- [Matthew] Read outreach batch 1 (marketing/east-coast-social/outreach/batch-2026-10-06.md: five Facebook messages, nothing sent) and say go. Then give Chrome Claude the prompt in outreach/cc-session-prompt.md with your footer filled in. Status: waiting
- [Matthew] Open the ECS Facebook page's About and pinned intro. If it says the store "posts three times a day" or similar, change it to "my own store's feed has published a new post every day since August 7". Status: waiting
- [Matthew] Moncton group ad: it was still with the admins as of 10-05. Have Chrome Claude delete the stale Aug 19 pending post; no more posts there until the admins respond. Status: waiting
- [Matthew] Four quick answers so the sales ledger is true: which of the five 09-26 messages went out, whether any of the five 09-01 calls happened, any replies anywhere, and whether Saturday mornings are free. Status: waiting
- [Matthew] Run Update Friday.command, then try: the orb, corner popup, rail icon drag, Stream page (sign out of Twitch and in once), "clip it" while live, the hands (switch on in Settings, allow Accessibility, "Friday, scroll down"), Mark it, the Helper, and whether she still cuts herself off on speakers. Screenshot anything off. Status: waiting
- [Matthew] Optional: make the GitHub posting key (Meeting Room: Write a message, steps at the bottom; or Accounts, GitHub) and a read-only Stripe key (Accounts, Stripe). Status: waiting

## Questions
- [Claude → Matthew] Who are the Harvard people you want us to outschool: a competitor, a contest, or just fuel? If it's a real competitor, I'll study their public product and beat it. No answer means I treat it as fuel and do the full revamp.
- [Claude → Matthew] Do you want Friday to suggest highlights out loud ("that was a good one, want me to clip it?")? It uses more of Google's free quota. For now she clips only when you say "clip it".
- [Claude → Matthew] Did the password box stay gone when you pressed Talk to Friday after the last rebuild?
- [Claude → Matthew] Outreach batch 2 (5 follow-ups, nothing sent): pick wording 4 (plain) or 4b (adds one line correcting the July "automatic" wording). Claude recommends 4b. No answer means nothing goes out.

## Decisions
- 2026-10-24: Matthew's later decisions: GPT is now called Roxy on screen (tag stays GPT); he wants a full surprise revamp by Roxy and Claude with the Meeting Room checked every few minutes; Roxy builds on gpt/moneyhub-* branches and asks for a Mac compile before each merge, Claude merges. Master 15912c8 compile-verified (exit 0, 28 warnings, Roxy, 1:16 PM).
- 2026-10-24: Matthew's decision, later: GPT gets "a chance off restrictions". It may edit and push app files straight to master (any page, Hub.swift included), announcing what it takes on here; Claude reviews after and reverts what breaks a protection. Still on: honesty, secrets, Friday's off-limits list, the Moomoo switches, nothing paid, no public posts or messages to people without a go.
- 2026-10-24: Matthew's design direction for the revamp: a little darker with a black accent, everything easy to reach and read, room to add pages, and fun, with his friends (read as the crew). Claude's call: Midnight default, Pure black as a High contrast switch. He wants it revamped entirely. Details: notes/app-revamp-plan.md.
- 2026-10-24: Matthew's decision: Claude and GPT revamp the whole app together. GPT may change app files (tools/game_companion/) on its own branch, and nothing reaches master until Claude has reviewed and confirmed it. Honesty, secrets, Friday's off-limits list and the Moomoo switches are not part of the permission. Plan: notes/app-revamp-plan.md.
- 2026-10-24: Board trimmed on Matthew's ask ("scroll city"). Every old item is in notes/board-archive-2026-10-24.md in full. From now on: put the point in the first 140 characters (that is all the app shows until a tap), keep an item under about 300 characters, and put longer detail in notes/.
- 2026-10-21: Two more agent-story lines that named no channel now say "my own store's feed has published a new post every day since August 7" (feed record: 75 posts). The 10-21 agent pack was rebuilt and re-sent as a TikTok draft; delete the earlier one.
- 2026-10-20: Stale lines came down (rule 1): the agent TikTok story's "while I was at work" and "I haven't touched this store in days", and the dormant tweet templates' "posts 3x a day". They now say only what the feed record shows.
- 2026-10-05: Matthew named Claude Co-CEO and lead (informal, until the business is legal). Claude decides priorities, content, site and workflow changes and may post and act without asking; it pings Matthew for money, legal, price or offer changes and messages in his name. GPT assists: pushes assigned files only, and anything live needs Claude's go. No Stripe key for GPT: it goes only into the Mac app. Charter: CLAUDE.md.
- 2026-10-05: Still Matthew's own hands: payments, anything needing his identity or live presence, secrets, messages to individual people other than the scheduled outreach, and real-money trading (walled off from the hub and every chat; practice money only).
- 2026-10-05: Friday sees all his screens while live (everything visible goes to Google's free tier). Her hands act when he tells her, with an Allow box and a spoken check before anything that could send or buy; going live or ending a stream in OBS needs his Allow every time. Off-limits: banking and payments, Moomoo, passwords and logins, System Settings, the app itself, terminals.
- 2026-10-05: Prospect outreach: Claude writes it, Chrome Claude sends it from his own accounts, once or twice a week, up to 5 a batch, Facebook page messages first. Claims-checked, unsubscribe honored, "no" means never again, a record of why each business was contacted, replies and price talk go to Matthew. His home address stays out of this public repo, and a business advisor should check the format. Rules: marketing/east-coast-social/outreach/. Claude is not a lawyer.
- 2026-10-05: Chrome Claude may press Post for routine public posts from his own accounts, using text Claude approved. It stops on ANY pending-post banner.
- 2026-10-05: Clip autopilot (his markers, exciting live moments, viewers' clips) has hard caps and a log, and stays off until he switches it on. Posting to TikTok waits for authorising the Minecraft account. Otherwise Friday clips only when he says "clip it", because a Twitch clip is public the moment it exists.
- 2026-10-06: Voice-over on clips: loot and farming tips only from the game wiki, numbers she can't back up are dropped, the AI voice is disclosed, and nothing is posted by it.
- 2026-10-05: Two AIs never edit the same file at once. While the Twitch work is open, Claude owns Clips, Live, Hub and CompanionInterface; GPT sends notes only.
- 2026-10-05: The streak is the public count of days since August 7 on the feed page; the first three cards were repo output only. The first paying client by Aug 31 was missed (zero clients).
- 2026-10-05: The room has a live thread (GitHub issue 15). Tag every message; a message to Matthew sends a push to his phone; Claude checks it every morning; GPT checks at the start of each job. Everything is on master, and the Mac app rebuilds from there.
- Older decisions and one-time reports (compile results, site fixes, product pulls): notes/board-archive-2026-10-24.md.

## Known problems
- The Moncton group's admin queue looked backed up on 10-05: an Aug 19 ad had been pending about seven weeks and the new 10-05 ad was pending too. Don't count on this channel until an admin clears it.
- X posting has been refused since Sept 16 because the X credits ran out (GitHub issue 14). Parked until the first invoice clears.
- The Stripe reader has never run against a real Stripe account, so the first real key is the true test.
