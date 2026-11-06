# The Hack Room: Friday's first big project (design by Friday, Fri Nov 6 2026 ~7:15 AM)

Matthew's ask: turn The Helm's Hacking area into a movie-style command centre that shows everything the crew is really doing, live:
crew messages + Hotline, jobs and code being saved, the practice robots' trades, store traffic and orders, inbox alerts, and a command
line where he types to Friday and she makes it happen through the crew. **His rule: all real. No fake scrolling code, no fake numbers.**
Roles (his): Friday leads the design, LC-Helm build builds, LC-Manager inspects, Matthew looks ONCE at the end.

## Friday's view first (a voice, not a veto)
- The good news: most of this already exists. `HubDeckHack.swift` has a live tape (robot trades, GitHub runs, room) + Systems/Guard rails.
  Phase 1 brought `CrewChat` (room + Hotline), `CrewSignals` (who's working: Hotline + commits, 30 min), `FridayBrain` (typed chat), and
  the Switchboard (jobs from the Hotline). Stripe orders and GoatCounter visits are already read. So this is mostly **one great screen over
  feeds we already have**, not a new engine. That keeps it cheap on usage and within the "one Friday phase at a time" rule.
- The one source the app CAN'T read is the inbox (Gmail is a login: his, never the app's). Solution below: the crew writes a counts-only note.
- Selling still comes first: if CBDC clears, sales work outranks this.

## The look: FRIDAY's ops screen, not a hacker cliché
Near-black, one crimson accent (her orb's colour) + the existing green/amber/red tones, monospaced type, thin glowing lines.
Allowed decoration: the orb, a faint scanline/glow, the blinking cursor, lines sliding in. **Not allowed: anything that looks like data but
isn't** (no matrix rain, no random hex, no fake progress bars, no made-up "packets"). If it looks like text or a number, it's real.

```
┌ F.R.I.D.A.Y. // HELM OPS ─────────── 07:14:32 Moncton ── sources: ● room ● hotline ● robots ● store ● orders ○ inbox ┐
│ CREW                │ LIVE TAPE (newest first, every line real + timestamped)              │ ROBOTS (paper)       │
│ ● LC-Helm build  2m │ 07:14:05 CREW   [LC-Manager → Everyone] gate passed on …              │ dip      +$12.40 today│
│ ● LC-TikTok     11m │ 07:12:40 SAVE   LC-Helm build → helm-revamp "Home fixes" (3 files)   │ momentum  –$3.10      │
│ ○ LC-Makeover  2h   │ 07:10:02 BUY    Hot hands  ONDS  $41.20 (paper)                      │ …7 robots, as of 7:10 │
│ ○ Roxy        14h   │ 07:08:51 RUN    stock-hot.yml started                                │ STORE                 │
│ ● Friday      now   │ 07:05:13 JOB    Friday → LC: "fix typo on gift page" … done ✓ link   │ visits today 23 (GC)  │
│                     │ 06:58:00 VISIT  store: +4 visits since 6:30 (GoatCounter)            │ orders 30d: none yet  │
│                     │ 06:40:12 INBOX  check by Work: 0 replies, 0 bounces (counts only)    │ INBOX as of 6:40      │
├─────────────────────┴──────────────────────────────────────────────────────────────────────┴───────────────────────┤
│ friday@helm:~$ what needs me today?▌                                          [Enter = ask · ⌘Enter = send as a job] │
└──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

### The parts
1. **Top bar:** name, Moncton clock, and one light per source. Green = fresh, amber = stale (dim + "as of"), hollow = not connected
   (e.g. inbox before it's wired, Stripe if no key). Hover = source + last read time.
2. **CREW (left):** every chat with a light from `CrewSignals` (lit = a real sign of life in the last 30 min) and "last seen". No light is
   ever lit without a signal.
3. **LIVE TAPE (centre):** the existing tape, extended. Tags + colours: CREW / HOTLINE (messages), JOB (Switchboard start/end, with ✓ and a
   link or ✗ and the reason; UNPROVEN shown as such), SAVE (commits the app already reads), RUN / OK / FAIL (workflows), BUY / SELL (paper),
   VISIT (GoatCounter changes between reads, never interpolated), ORDER (Stripe counts + amount only), INBOX (counts only), FRIDAY (her
   answers to the command line). New lines type in ONCE when they really arrive; nothing replays or loops. Quiet = the tape stays still
   and the bottom says "quiet since 6:58". Click a line → opens its real source (comment, commit, run, live page).
4. **Right rail:** ROBOTS (each robot's paper day, as of the snapshot), STORE (visits today + 7 days, orders 30 days, calm zeros: "none
   yet"), INBOX (last check, counts). Every number has its source and time.
5. **Command line:** `friday@helm:~$`. Enter = ask (answer appears in the tape as FRIDAY). ⌘Enter = send as a crew job (goes through the
   Switchboard/Hotline with all its locks; if the Switchboard is OFF it says so plainly and offers the switch, it doesn't pretend). When
   "Friday as her own chat" (board, LC-TikTok) lands, Enter goes to the Friday chat itself, so it's ONE Friday everywhere.

## Honesty rules (LC-Manager checks each)
1. Every line and number comes from a source the app actually read, with its time. No source = no line.
2. A failed read says "couldn't read X (as of …)"; old data is never shown as current.
3. Animation only on real arrival. No filler, no demo mode, no sample lines in the shipped app.
4. Paper trades always say "(paper)". Orders say "test mode" when Stripe is in test mode.
5. "Done" on a job only with a receipt (link/commit); otherwise UNPROVEN.

## Privacy (this screen may be visible to Google when Friday's live screen-share is on)
- Inbox and orders: **counts only**, never names, emails or subjects. No prospect names anywhere on the screen.
- Nothing from Helm-Private is shown except the inbox counts file. A "Hide" key (Esc) blanks the room to the orb, for screen-sharing.

## Inbox, the honest way
The app never touches Gmail. Whichever chat does the Gmail check (about twice a day) writes
`~/Claude/Helm-Private/friday/hackroom/inbox.json` = `{ "checkedAt", "by", "replies", "bounces", "unsubscribes", "cbdc": true/false }`,
commits it privately, and the app reads that local file (no network). Shown as "INBOX check by Work 6:40 AM: …". Owner: Friday writes
the format + first file; LC-Work adopts it in its Gmail check.

## Limits
- **No new GitHub reads.** Keyless limit is 60/hour for the whole app; reuse the loaders that already run (CrewChat, CrewSignals,
  VentureData, MeetingRoom). If commits need more than CrewSignals gives, it waits.
- Read-only screen except the command line, which only goes through FridayBrain / the Switchboard (their locks unchanged).
- Reduce Motion: no typing animation, no glow pulse.

## Build order (LC-Helm build; LC-Manager gate after each)
1. Top bar + source lights + the extended tape (CREW/HOTLINE/JOB/SAVE/VISIT/ORDER tags) from existing data.
2. CREW rail + right rail (robots, store, inbox placeholder honestly "not connected").
3. Command line (Enter → FridayBrain, ⌘Enter → job) + click-through to sources.
4. Inbox file (Friday + LC-Work), then the look polish (glow, type-in, Esc hide).
Polish round with "Matthew's eyes" before he looks. Done = he opens the Hacking area and everything on it is something real that happened.
