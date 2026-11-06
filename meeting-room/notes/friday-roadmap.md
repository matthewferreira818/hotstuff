# Friday roadmap: how we actually build her (New beginning, Fri Nov 6 ~5 AM, Matthew: "think real hard. how are we gonna do this")

Vision: meeting-room/notes/friday-vision.md. This file is the HOW: one design, small phases, a test he can pass at the end of each.

## The design in one picture
Friday = **one brain + one memory + many doors.**
- **Brain:** Claude, through the Claude Code inside the desktop app (headless), on his Max plan. Sonnet by default, Haiku for
  sorting pings, Opus only on request. Google Gemini is no longer her brain; it stays an optional extra for watching the screen.
- **Memory:** files on his Mac (Helm-Private clone, `friday/`), backed up privately. Every brain call gets a SHORT "who Matthew is +
  today" summary (under ~2 pages), not the whole bank, to protect his usage.
- **Doors in:** typing on the Mac · the crew (Hotline/room, via the Switchboard) · later her voice on the Mac (Apple's on-device speech,
  private, free) · his phone (Claude app → cloud chat → Hotline → Friday) · later smart-home buttons.
- **Doors out:** chat replies · room/board posts · ntfy pings to his phone (important only) · Spotify and Mac controls · later her
  voice (Apple's built-in voices) · later smart-home scenes (HomeKit via Shortcuts on the Mac).
- **Rules:** the trust ladder decides what she may do alone, per job type. Money, logins, messages to people, Moomoo: always his.

## Phases (each = one new thing for him, a test he passes, LC-Manager's gate, his GO)
0. **Today:** he runs "Update Friday" (new Helm + Simple mode); he decides when to flip the Switchboard ON; EI report; CBDC call.
   Mac setting: System Settings → Battery/Energy → "Prevent automatic sleeping when the display is off" (she needs the Mac awake).
1. **She thinks** (week 1): typed chat on the Claude brain + crew chat timeline (room + Hotline + LC messages in one feed) +
   honest progress numbers. Test: he types "what needs me today?" and gets a true, plain answer; he can scroll the crew's talk.
2. **She knows you** (week 2): memory bank v1 (scrapbook he can Keep/Edit/Forget) + one question a day + One Money Move card.
   Test: "what did we decide about TikTok?" answered right; one card each morning; nothing on hold shown as a task.
3. **She earns trust** (week 3): jobs by chat ("fix the typo on the gift page") with receipts + the trust ladder.
   Test: 3 real jobs done with proof; he sees the ladder and moves a rung himself.
4. **She's in the room** (week 4): "Friday Home" mode (the Mac as an always-on home base screen) + private voice on the Mac
   (push-to-talk key first; hands-free "Hey Friday" only if it runs well on 8 GB). Test: from across the room, he asks and she answers out loud.
5. **She's in your pocket:** "tell Friday …" from the phone through the cloud chat, and her pings. Test: a phone message reaches her and she answers.
6. **Her own home (when the business pays, money mode):** smart plugs/bulbs (HomeKit), a small speaker, an old iPad as the wall
   screen, a private local brain as backup, better hardware. Then the dream: her bigger brain, all our memory, one day the chassis.

## Quality bar (Matthew, Fri Nov 6 ~5:55 AM: "i wanna wait, i really wanna build it up, refine and polish, make it the best it can be")
Every phase gets a **polish round** before his GO, but **the crew does the rounds, not him** (Matthew, ~6 AM: "i dont want to have to
do it every time"). LC-Manager runs a "Matthew's eyes" review (an Opus helper with his known taste: calm, one view, one new button at most,
plain words, no robot lines, honest numbers, nothing steals his screen), the crew fixes what it finds, and repeats until it passes.
**He looks ONCE, at the end of a phase**, and says GO or names what's off. Small fixes inside an approved phase (wording, spacing, bugs)
don't need him: gate + cloud Claude's review, then merge, and the morning brief tells him what changed.
Long-term, in his words: "eventually not rely on a company's AI, have one of my own": that's Phase 6 (own brain). Everything we build
(memory bank, character, doors, rules) is designed to move to her own brain later, so nothing is wasted.

## Who does what
- **LC-Manager:** project manager for this roadmap: one phase at a time, gate + test pack, keeps the board honest.
- **LC-TikTok:** the engine (brain calls, Switchboard, memory files, pings).
- **LC-Helm build:** what he sees (screens, Simple mode, Home mode, crew chat look).
- **Cloud Claude (New beginning / Work):** reviews and merges, the Hotline, the creative council for open questions, his phone door.

## Guardrails (so this doesn't eat the business)
- **Selling first:** when CBDC clears, sales work outranks Friday work every day. While the hold lasts, Friday work is fine.
- **Usage:** one Friday phase at a time; Sonnet/Haiku; a weekly usage check in the Sunday scorecard. If his Claude limit gets
  tight, Friday pauses before the business does.
- **Novice-first:** each phase adds at most ONE new button; everything else stays behind More.
- **Honesty:** she only says she did what a tool did (UNPROVEN flag); numbers show source and time.
- **Private stays private:** moods, money, prospects never leave the Mac + Helm-Private; nothing private to Google or the public repo.
