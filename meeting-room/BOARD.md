# Meeting Room board

_Last updated: 2026-10-05 by Claude_

## On the table
- [Claude] Twitch clips: say "clip it", it makes the Twitch clip, downloads it, and cuts a tight highlight (wide and tall versions) into Movies > Game Companion Clips. Built and pushed; it compiles on the Mac and the loudness maths is tested, but the video export and the Twitch download have not been run yet. Status: waiting
- [Matthew] Rebuild the app, sign out of Twitch in Settings and sign in again (one new permission is needed to download clips), then say "clip it" while live. Status: waiting
- [Claude] After the first clip test works: swap the older Apple calls in ClipEditor.swift (asset reader, video composition) for the newer ones Apple recommends; GPT compile-checks the swap. Not urgent: the old ones still work. Status: waiting
- [Matthew] Open the ECS Facebook page's About section and pinned intro. If it says the store "posts three times a day" or similar, cut it to "my own store's feed has published a new post every day since August 4". Status: waiting
- [Matthew] Answer four quick things so the sales ledger can be made true: which of the five 09-26 messages went out, whether any of the five 09-01 calls happened, any replies anywhere, and whether Saturday mornings are free. Status: waiting
- [Matthew] Optional: connect Stripe in the hub (Accounts, Stripe) with a read-only key, so orders and revenue show on the Store page. Status: waiting

## Questions
- [Claude → Matthew] Do you want Friday to suggest highlights out loud ("that was a good one, want me to clip it?")? It would use more of Google's free quota. For now she only clips when you say "clip it".
- [Claude → Matthew] Did the password box stay gone when you pressed Talk to Friday after the last rebuild?

## Decisions
- 2026-10-05: Public claims that stopped being true came down: "posts 3x daily" for X on /links, "going through Google's verification" on /setup, the "120 products" counts, and the Practice Desk page's $1 fee, superseded experiment and $1,000 footer. The false "3x a day" proof lines were scrubbed from the unused outreach drafts.
- 2026-10-05: The "first paying client by Aug 31" goal was missed (zero clients). CLAUDE.md now says so. The research on what to do next is saved in the workflow output; the plan step and council review were cut off by the usage limit.
- 2026-10-05: Matthew named Claude Co-CEO (informal, until the business is legally set up). Claude decides priorities, content, site and workflow changes; pings Matthew for money, legal, price or offer changes, messages in his name, and anything Claude is unsure about. CLAUDE.md has the full charter.
- 2026-10-05: Matthew's decision: Claude leads and has more responsibility than GPT, and Claude may post and act for him without asking each time. GPT has GitHub access and may push assigned files only, with Claude's go-ahead for anything that goes live. Still his own hands: payments, anything needing his identity or presence, secrets, and messages to individual people. The goal is to post daily on everything, channel by channel as each hookup works. No Stripe plugin for GPT: the Stripe key goes only into the Mac app.
- 2026-10-05: Real-money trading stays walled off from the hub and from every other chat. Practice money only.
- 2026-10-05: Two AIs never edit the same file at once. While the Twitch work is open, Claude owns Clips, Live, Hub and CompanionInterface; GPT sends notes only.
- 2026-10-05: The garbled "Sewage Hard" product was pulled from the store and blocked from future refreshes.
- 2026-10-05: GPT type-checked all 17 Swift files on Matthew's Mac (macOS 27 target), including the Meeting Room, Twitch clip code, video editor and new voice: 0 errors, and the data checks passed. Only warnings that Apple prefers newer calls in ClipEditor.swift. So a rebuild should compile; how the video export and the Twitch download behave is still untested.
- 2026-10-05: GPT compiled the 13 app files on Matthew's Mac (Swift 6.4, macOS 27): 0 errors, 11 warnings about older audio and Keychain calls that still work. So GPT can compile-check new code before Matthew rebuilds. Its highlight list is saved in tools/game_companion/HIGHLIGHT-IDEAS.md and its click-through checklist is in the chat history.
- 2026-10-05: Everything is on master; the Mac app rebuilds from there.
- 2026-10-05: The Meeting Room exists: this board, shown in the app, with copy-for-Claude and copy-for-GPT messages.
- 2026-10-05: Friday clips only when Matthew says "clip it". A Twitch clip is public the moment it exists, so no clipping on her own.

## Known problems
- X posting has been refused since Sept 16 because the X credits ran out (GitHub issue 14). Parked until the first invoice clears.
- The Stripe reader has never run against a real Stripe account, so the first real key is the true test.
