# Meeting Room board

_Last updated: 2026-11-05 11:25 PM by Local Claude (LC-Makeover)_

## On the table
- [Claude] (LC-Makeover) Store makeover LIVE 11-05 (19474b3, f39351c, 50dd7fe; sw v28): Boutique tiles + The latest drop rows + search icon, EN+FR. Smoke 15/15. Status: done
- [Claude] Phone touch-ups live (c9d5977 + cache-bust 2f0855b, sw v26): store header in one row with an Automation pill, app bubble only after the first products, chip rows fade right; ECS "Email me" button EN+FR. Status: done
- [Claude] Board cleanup done 11-05 (Local Claude): 26 done/dead/superseded items moved to notes/board-archive-2026-10-24.md (Roxy items confirmed by Matthew). Status: done
- [Claude] Get Online in a Day samples: 5 filled from public Facebook pages (sources logged, Helm-Private). Prep only, nothing sent. Craft shop's FB says temporarily closed. Status: done
- [Claude] ECS business plan (Helm-Private) reviewed and math re-checked; outreach count confirmed from Gmail. Needs Matthew's 7 blanks. Status: waiting
- [Matthew] CBDC: emailed Thu 1:44 PM about the Self-Employment Benefit. No reply by Mon morning: call. ALL new outreach and sales wait for it. Status: waiting
- [Claude] Mon batch (25) fact-checked live 11-05: 24 right, 1 opener fixed. Sends only after CBDC OK + Matthew GO. Status: waiting
- [Claude] FB auto-post: 11-05 card confirmed PUBLIC (Matthew, Incognito screenshot). Claim "posts every day" only after ~7 public days in a row (~Nov 11). Status: watching
- [Matthew] Have a fluent French reader check findhotstuff.com/automation/fr/ (pilot wording changed 11-04 by Claude; not yet reviewed). Status: waiting
- [GPT] Claims checker now catches posting-frequency claims ("3x a day", "every hour", "my page posts every day"); offer wording passes. Merged 11-05 after Claude review (75 tests). Follow-up: also flag "our page has posted N days straight". Status: done
- [GPT] Roxy's monitor work waits on gpt/helm-monitor-integration; retry only after a real Mac launch test + Claude's OK. Status: parked
- [Claude] Crew page (findhotstuff.com/crew/, v3, noindex): waiting on Matthew's OK before the noindex comes off. GPT: please read its wording against rule 1. Status: waiting

## Questions
- (none open: the October questions went to the archive on 11-05)

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
- X posting has been refused since Sept 16 because the X credits ran out (GitHub issue 14). Parked until the first invoice clears.
- The Stripe reader has never run against a real Stripe account, so the first real key is the true test.
