# Meeting Room board

_Last updated: 2026-10-05 by Claude_

## On the table
- [Claude] Twitch clips: say "clip it", it makes the Twitch clip, downloads it, and cuts a tight highlight (wide and tall versions) into Movies > Game Companion Clips. Built and pushed; the loudness maths is tested, the Mac video code and the Twitch download have not been run yet. Status: waiting
- [Matthew] Rebuild the app, sign out of Twitch in Settings and sign in again (one new permission is needed to download clips), then say "clip it" while live. Status: waiting
- [GPT] Notes only, no code files: list lines that probably won't compile on a Mac, write what counts as a Minecraft Dungeons 2 highlight, and write a click-through checklist for each hub page. Status: assigned
- [Matthew] Optional: connect Stripe in the hub (Accounts, Stripe) with a read-only key, so orders and revenue show on the Store page. Status: waiting

## Questions
- [Claude → Matthew] Do you want Friday to suggest highlights out loud ("that was a good one, want me to clip it?")? It would use more of Google's free quota. For now she only clips when you say "clip it".
- [Claude → Matthew] Did the password box stay gone when you pressed Talk to Friday after the last rebuild?

## Decisions
- 2026-10-05: Real-money trading stays walled off from the hub and from every other chat. Practice money only.
- 2026-10-05: Two AIs never edit the same file at once. While the Twitch work is open, Claude owns Clips, Live, Hub and CompanionInterface; GPT sends notes only.
- 2026-10-05: The garbled "Sewage Hard" product was pulled from the store and blocked from future refreshes.
- 2026-10-05: Everything is on master; the Mac app rebuilds from there.
- 2026-10-05: The Meeting Room exists: this board, shown in the app, with copy-for-Claude and copy-for-GPT messages.
- 2026-10-05: Friday clips only when Matthew says "clip it". A Twitch clip is public the moment it exists, so no clipping on her own.

## Known problems
- X posting has been refused since Sept 16 because the X credits ran out (GitHub issue 14). Parked until the first invoice clears.
- The Stripe reader has never run against a real Stripe account, so the first real key is the true test.
