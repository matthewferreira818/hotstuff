# Game Companion: upgraded source

Matthew's local gaming companion is a Mac app that Codex built on his Mac. The
working copy lives in `~/Documents/Codex/2026-10-04/create-a-separate-free-local-ai/`.
This folder holds the upgraded `Companion.swift` so it can travel through git.

## What changed (2026-10-05)

1. **Bigger screenshots:** 1024 × 576 instead of 512 × 288, so menu and stat text can
   be read. Gemma 3 resizes every image to the same internal size, so this costs almost
   no extra model memory. JPEG quality went from 0.6 to 0.7.
2. **Game notes box:** a new field under "Local vision model". Whatever you type there
   goes in front of each question, capped at 400 characters, and is saved like the
   voice setting. It starts filled with the MCD2 soul build, so edit it any time.
   Notes are placed next to the question rather than in the system prompt. In the first
   test, the 4B model ignored notes in the system prompt and answered "Let me pull up
   your character sheet". The instructions now also tell it that it can't take actions,
   so it answers from the notes or says it can't tell.

3. **Fast mode** (2026-10-05, after the first live test): the old "Quicker follow-ups"
   button is now "Fast (AI stays loaded)". Picking it loads the AI right away and keeps
   it loaded for 10 minutes after each reply, with no 2-thread cap. Save memory still
   unloads after every reply, which is why every reply started slow. Matthew plays on a
   console and watches his Twitch on the Mac, so the Mac has room for it.
4. **Short / Detailed replies:** Detailed (the default) allows 2–4 sentences with
   specifics, up to 160 tokens. Short is the old one-liner. The context window is 2048
   for both, so switching never forces an AI reload.
5. **Voice list shows quality** (Premium / Enhanced / Basic). Download Premium voices in
   System Settings → Accessibility → Spoken Content → Manage Voices, then restart the app.
6. **Status shows "Taking a picture…" then "Thinking locally…"**, so it's clear which
   part is slow. The capture itself is fast; the AI is the slow part.

7. **Live buddy (2026-10-05):** a new first tab, in `Live.swift`. It streams the chosen window
   (one JPEG a second, 1024 × 576) and the mic (16 kHz PCM) to Google's Gemini Live API
   (`gemini-3.8-live`, free tier) over a WebSocket. It plays the spoken replies (24 kHz PCM)
   and shows both transcripts. Built from ai.google.dev/gemini-api/docs/live-api/get-started-websocket.
   - The key is pasted by Matthew into the app and stored in the macOS Keychain, never in files.
   - Context-window compression is on, because without it Google caps audio+video at 2 minutes.
   - Session resumption reconnects when Google ends the connection, about every 10 minutes.
   - The "I'm wearing headphones" box: when it's unticked, the mic pauses while the buddy talks
     so it can't hear itself.
   - Google Search grounding: a toggle, on by default, adds `tools: [{googleSearch: {}}]` so it
     looks up facts about new games instead of guessing. It runs on Google's side. Google's pricing
     page (2026-10-05) lists it as supported on the free tier for the 3.8 Live models.
     **In practice the free key was refused:** "You exceeded your current quota" with Search on,
     and it worked fine with Search off. So the toggle now defaults to off. If a session fails on
     quota while Search is on, the app turns Search off and reconnects by itself.
   - Privacy differs from the Local tab: frames and mic audio go to Google while it's on, and
     Google's free tier may use them to improve its products.

8. **Free game-fact lookup** (2026-10-05, `Wiki.swift`): replaces Google Search, which the free key
   refused ("exceeded your current quota"). The buddy gets a `lookup_game_wiki(query)` tool through
   Live API function calling. The app answers it by trying MetaBot first (exact tier numbers from the
   game files, by page name for enchantments, effects, weapons, talismans, artifacts and armor) and then
   the Minecraft wiki's "Dungeons II:" pages (bosses, mobs, quests). Only the name being looked up leaves
   the Mac. Search and Lookup can't both be on. Lookups take about 0.6-1.7 seconds. `Wiki.swift` was
   compiled and run on Linux against both live sites; gear, enchantments, effects, bosses and a miss all
   returned sensible text. NOT yet verified: that `gemini-3.8-live` accepts the tool declaration, since
   the Google docs page for it showed only the Python shape. If Google refuses it, the grey status
   line shows the reason; untick the lookup switch to run without it.
9. **Low usage mode** (default on): the free key has a daily allowance, so pictures go out about once a
   second only while Matthew is talking (the mic hears speech, or Google reports a transcript), plus one
   glance every 15 seconds when it's quiet. That's roughly 85% fewer pictures than Full. The pictures
   stay 1024 x 576 so on-screen text stays readable. Audio still streams the whole time. Which exact
   Google limit was hit (per minute or per day) is not known yet; aistudio.google.com/rate-limit shows it.
10. Typing a question while the buddy is off now says "Click Start live buddy first" instead of nothing.

11. **Twitch clips** (2026-10-05, `Clips.swift`): a Twitch account separate from the stream channel makes
   clips of the stream. Button "Clip the last 30 seconds", or say "clip that" to the live buddy (a tick box,
   off by default). Twitch's Create Clip grabs about the last 30 seconds of a channel that is live right now
   and posts it to Twitch immediately, so it only runs when Matthew clicks or asks, never on a timer, and
   not more than once every 30 seconds. The app then checks the clip really exists before saying so.
   Sharing a clip to X/TikTok/Facebook stays his click.
   - Sign-in is Twitch's Device Code flow: no secret in the app. The Client ID is public (settings);
     the login tokens go in the Keychain (`GameCompanion.TwitchTokens`).
   - **Setup, all his clicks:** (a) make the clip account at twitch.tv (turn on 2FA, needed for step b);
     (b) with that account, dev.twitch.tv/console → Register Your Application: name anything, OAuth
     Redirect URL `https://localhost` (the form rejects http; it is never opened, the sign-in uses a code), Category Application Integration, **Client Type: Public**; copy the
     Client ID; (c) in the app: type the stream channel name, paste the Client ID, click Sign in, approve
     on the Twitch page that opens while logged in as the clip account.
   - Honest limits: the clip is credited to the clip account but lives on his channel's clips page; the
     channel must be live and have clips enabled; clips are public on Twitch. NOT compiled yet (no Swift
     on the cloud machine); the first rebuild on the Mac is the check. Untested against live Twitch.

The Local tab keeps the same AI and the same privacy as before.
`Companion.swift` and `Live.swift` were syntax-checked with `swiftc -parse` on Linux but not compiled,
because the cloud machine has no Mac SDK; the new JSON message shapes were type-checked in a small
Foundation-only harness. `Wiki.swift` was fully compiled and run. The first rebuild on the Mac is the
full compile check.

## Install the upgrade

1. `cd ~/hotstuff && git pull`
2. Easiest: run `zsh ~/hotstuff/tools/game_companion/rebuild.sh`. It compiles first, keeps
   the old app as `outputs/GameCompanion-backup.zip`, swaps in the new program, and re-signs
   it with the app's existing identity.
   Or paste this into Codex, in the Game Companion chat:

   > Copy ~/hotstuff/tools/game_companion/Companion.swift over outputs/Companion.swift
   > in this project. Rebuild and re-sign GameCompanion.app exactly the way you built
   > it before, with the same app name, bundle ID, icon and signing, so macOS keeps its
   > permissions. Only build it: don't run the AI, capture the screen, or download anything.
   > If it fails to compile, show me the error.

3. If macOS asks for Screen Recording or Microphone permission again, allow it. A
   rebuilt app can look "new" to macOS.

## Make permissions survive rebuilds (one time)

Each ad hoc signature is different, so after every rebuild macOS forgets the Screen Recording
permission and asks for the Keychain password again. The fix is a self-signed code-signing
certificate, which `rebuild.sh` uses automatically when it exists:

1. Run `zsh ~/hotstuff/tools/game_companion/make_cert.sh`. Newer macOS replaced Keychain Access
   with the Passwords app, which can't make certificates, so the script does it with Apple's openssl
   and `security import`.
2. If the certificate exists but codesign won't use it, rebuild.sh falls back to ad hoc signing
   instead of leaving a broken app.
3. Rebuild. If macOS asks to let codesign use the key, enter the Mac password and choose Always Allow.
4. Redo the screen permission and the Keychain "Always Allow" one last time.

## What the buddy last saw (2026-10-05)

First live test: the buddy described a screenshot Matthew had taken earlier, not his screen. The app now
shows a small preview of the last picture it sent to Google ("What the buddy saw last", with a count), kept
in memory only and cleared on Stop. The instructions also tell the buddy the pictures are live captures,
not files from his storage. The cause of the stale picture is not known yet; the preview should show it.

**Steady mode (2026-10-05):** the old "Frequent" option is now "Steady", with a slider for the gap between pictures (1-5 seconds,
saved, default 2 as Matthew asked). It sends on a timer whether he talks or not. Google allows at most 1 picture per second.

## Item lookups are now required (2026-10-05)

The buddy described items wrongly (it only looked things up when it felt unsure, and Gemini does not know this
new game). The instructions now make `lookup_game_wiki` a rule for every weapon, armor piece, artifact, talisman,
enchantment or effect, and tell it to ask for the name when the on-screen text is too small to read. Also seen
in that test: Twitch was a small player inside a big Safari window, so the game was only about half the picture.
Tip: use Twitch's Theatre mode or a bigger window before choosing it.

## Noir look, with Friday as the orb (2026-10-05)

`FridayOrb.swift` holds the palette (near-black, one crimson accent), the orb, the dark glass cards and the background.
The main screen now has the crimson orb in the middle with the name "Friday" under it. The orb breathes when idle, ripples
outward while she listens or speaks, and swirls faster while she thinks. The state comes from the live engine
(`running`, `speakingUntil`, `lastVoice`) or the local one (`listening`, `busy`, `speaker.isSpeaking`). It respects the
macOS "Reduce motion" setting. Nothing about what is sent or saved changed. The buddy is also told its name is Friday.
SwiftUI can't be compiled on the Linux cloud machine, so the first Mac rebuild is the real check.

## Voice-first screen, like a voice assistant (2026-10-05)

The main window is now one calm screen: a big fluid crimson orb in the middle (light drifting inside a sphere that swells with
the sound of the mic and of her voice), the status and her words underneath, and five round buttons: choose window, keyboard,
the big start/stop (or talk, in local mode), settings, stop everything. The old tabbed screen, with every control, is the
"Settings & more" panel. While Google Live runs, a pill at the top says the window and mic are shared with Google.
Main button is never greyed out: with no key or window, the status line says what is missing. The blue focus ring is gone.
Panel and screen state live on `Companion` (`showPanel`, `showKeyboard`), not `@State`, which the command-line build can't expand.

## One combined build (2026-10-05)

Three lines of work had drifted apart: master (Twitch clips, `Clips.swift`), the integration branch (conversation and memory
files, session fencing) and this branch (preview, Steady mode, item-lookup rule, noir voice screen). This branch now holds all
three. Clips on the new screen: a scissors button next to Settings once signed in, and the clip settings inside Settings & more
(Google settings). `rebuild.sh` lists every source file once, in `SOURCES`, so a new file is added in one place only.

## The hub (2026-10-05)

The app is now a hub: a slim icon rail on the left (Home, Friday, Stock bot, Store, ECS, Game, Accounts, Settings), an
"Ask Friday" box on top, and a card dashboard on Home. Friday is one page of it and keeps listening while you browse; a LIVE
badge shows whenever she is. `Hub.swift` holds the shell and every page; `StockData.swift` reads the stock bot's public
practice snapshots (live.json on the stock-live and stock-live-momentum branches) and was compiled and run against the real
files. Read-only: nothing in the hub can place an order, post or spend. Store and ECS are placeholders for now; Accounts shows
what is connected. The old tabbed settings are still in the Settings panel (rail, bottom).

## Lighter look, full screen, Apple-style feel (2026-10-05)

Background is now a soft charcoal-and-plum gradient with slow drifting crimson and violet glows (`NoirBackground`), so the edges are
no longer black; it holds still when macOS "Reduce motion" is on. The window is resizable with a hidden title bar, so the green
button gives full screen, and Friday's orb and column scale with the window. Interactions: frosted-glass cards and sidebar
(`.ultraThinMaterial`), a selection highlight that slides between sidebar icons (`matchedGeometryEffect`), spring page changes,
cards that lift under the pointer, springy button presses, a soft trackpad tap when changing page, and shortcuts: Cmd+1 to Cmd+7
for the pages and Cmd+, for Settings. Hover state lives on `HubModel` (not `@State`, which the command-line build can't expand).

## Fewer password boxes (2026-10-05)

The Keychain password box came back at every launch and after every rebuild. Causes: the app read the secret itself just to
see whether it was saved (once for the Google key, once for Twitch), and rebuilt apps are not trusted by older Keychain items.
`Keychain.swift` now (1) answers "is it saved?" from the item's label only, (2) reads the secret only when needed, once per run,
and (3) saves items with "allow all applications" access, re-saving old items after their next successful read. The tradeoff:
other software running as the same user could read the key without a prompt, which is fine for a free API key and not for a
bank password. If macOS refuses the open access, it falls back to a normal save. The Security calls used are deprecated by
Apple but still present; they could not be run on the Linux cloud machine, so the first Mac run is the real test.

## Store, ECS and Systems pages (2026-10-05)

Real data, free, read-only, no logins. `VentureData.swift` was compiled and run against the live sources.
- **Store**: unique visitors today, 7 days and 30 days from GoatCounter's public counters (`TOTAL.json`), plus the `ref-<tag>`
  channel counters the traffic report already uses. Day precision. Orders and revenue need Stripe, which is not connected.
- **ECS**: the site's own feed files (`automation/feed/stats.json` and `index.json`). The streak claims "in a row" only when
  every day from the first post to the last has a post and the last post is today or yesterday (the honesty rule in CLAUDE.md);
  otherwise it shows the plain count. It offers the safe wording to copy, and the three newest cards.
- **Systems**: GitHub's public workflow runs for the repo (one request, anonymous, 60 per hour allowed), latest run of each
  automation, failures flagged red and shown as a banner on Home. First run showed "Refresh trending products" failing.
Refresh is every 9+ minutes in the background, or on demand. Accounts page lists these as read-only public sources.

## Launchpad (2026-10-05)

A "master folder": one page of one-click links (Porkbun, Cloudflare, GitHub, Stripe, CJ Dropshipping, Moomoo, GoatCounter, Twitch,
X, TikTok, Facebook, Pinterest, Google Business, the live store and ECS pages) that open in Matthew's browser, where he is already
logged in. No logins pass through the app. It also holds "Your agents": buttons that open the Claude chats where the stock,
website and build work lives (the app can only open them; chats can't see each other). Home gets a plain-words "Today at a glance"
card made from the data already on screen (no AI, no quota). The sidebar now scrolls on short windows, since it has nine pages.
The Porkbun link goes to its domain-management page; if Porkbun has moved that page it may land on a login screen instead.


## Stripe sales and the catalog check (2026-10-05)

- **Stripe (Accounts page, then Store)**: Matthew creates a *restricted* Stripe key with only Charges set to Read and pastes it
  into the app, which saves it in the Mac's Keychain (service `stripe-readonly`). `StripeData.swift` only sends GET requests and
  refuses a full secret key (`sk_`) or publishable key on purpose, so the app can never move money or change anything. It reads
  the last 30 days of charges and keeps counts and amounts only: no names, emails or card details are read in. Fully refunded
  orders aren't counted. The Store page then shows orders and revenue for today, 7 days and 30 days, and the latest three orders.
  The charge-list parser was compiled and run on Linux against Stripe's documented response shape, not against a real Stripe
  account, so the first real key is the true test. Wrong key, missing permission and no internet each show a plain message.
- **Catalog freshness (Store, Systems, Home banner)**: reads findhotstuff.com/products.json (count and categories) and GitHub's
  public commit list for the date of the last "Refresh: trending products" commit. More than 5 days old raises the Home banner.
  This is the check that would have caught Sept 4 to Oct 5, when CJ switched its API access off and the refresh failed 30 runs
  in a row without anyone noticing. Run live on 2026-10-05: 199 products, 18 categories, refreshed that morning.
- Accounts page now also lists CJ Dropshipping (read-only freshness) and the Stripe connect form. The Stripe key is the third login.

## Build fix (2026-10-05)

`Keychain.swift` shipped with a compile error (`SecACLCopyContents` needs a real place to put the application list, not `nil`).
It could not be compiled on the Linux cloud machine, so it was only found on the Mac. Every rebuild after the Keychain commit
therefore failed before installing, and the old app stayed in place without anyone noticing. Fixed. `rebuild.sh` now hides the
warnings and, if the compile fails, prints "BUILD FAILED. The app was NOT updated" with just the errors to paste.

## Open alerts, and a more honest Systems page (2026-10-05)

A green run only means the job didn't crash. The "Product spotlight 3x daily (X + Instagram)" job has shown green while X has
refused every post since Sept 16 (credits depleted; the job opens a GitHub issue and carries on). The hub said "all 9 look fine".
Now `VentureData.fetchAlerts()` reads GitHub's public open-issues list (pull requests filtered out): the Systems page has an
"Alerts your automations raised" card, the pill says "ALL 9 RAN WITHOUT ERRORS" plus "1 OPEN ALERT", and Home's briefing lists
them. Open alerts do not trigger the Home warning banner, so a known, parked item doesn't nag; failing runs and a stale catalog
still do. Tested live: it found issue #14. Also: the sidebar is tighter so more of the nine pages fit without scrolling
(Accounts is also Command-9), and Launchpad tiles are wider so names like "CJ Dropshipping" no longer break mid-word.

## Meeting Room (2026-10-05)

A tenth hub page (Command-0). Claude's chats, the GPT Project and Friday can't see each other, so the room is a shared board:
`meeting-room/BOARD.md` in the public repo (rules in `meeting-room/README.md`). `MeetingData.swift` (Foundation-only, tested
against the real file) reads it through GitHub's contents API and splits it into sections and items (`- [Owner] text. Status: x`).
The page shows the crew (Claude, GPT, Friday), the board, and a message box: pick To Claude, To GPT or Note for the board, type,
and Copy puts a ready-to-paste message on the clipboard (the GPT version includes the whole board, since GPT can't read the repo).
The app only reads the board. Claude edits it and pushes; GPT hands Matthew a "Board update" block to paste. Home's briefing
shows how many things are on the table. Nothing private belongs on it: the repo is public. The Command-number shortcut code
was changed so a tenth page can't crash it.

## Twitch clips: "clip it", download, cut the highlight (2026-10-05)

Say "clip it" (or "clip that" / "clip this"). Two things listen for it, and they join into one clip: Friday's `clip_that` tool
(she can also give the clip a short title, only from what she saw; if Twitch's AutoMod rejects a title it clips without one) and a
backup that watches the transcript of Matthew's own words, in case she skips the tool call. A clip goes public on his Twitch
channel the moment it is made, so it only ever happens when he asks. Friday never clips on her own.
- **Twitch**: `POST /clips` with `duration` (Twitch allows 5 to 60 seconds; we ask for 30 to 55 depending on the highlight length
  setting) and an optional title. Then `GET /clips/downloads` (verified against Twitch's reference page, 2026-10-05) for a
  short-lived download link. That needs the `channel:manage:clips` or `editor:manage:clips` permission, which sign-ins made
  before today don't have: the app says "sign out and sign in again". A clip account that isn't the broadcaster must be an
  Editor on the channel (Creator Dashboard, Roles), or Twitch answers 403.
- **Cut** (`ClipEditor.swift`, `ClipMath.swift`): measures how loud the clip is every quarter second, keeps the loudest stretch
  (default 25 s, choices 15/25/40) with a beat of run-up and aftermath, and drops the quiet before and after. With no readable
  sound it keeps the most recent stretch, because the clip is made right after the moment. The loudness maths is tested
  (`checks/DataChecks.swift`). It is a loudness guess, not understanding: a quiet clutch moment can lose to a loud noise.
- **Output**: `~/Movies/Game Companion Clips/<date> - <title>/` holds `original.mp4`, `highlight-wide.mp4` and `highlight-tall.mp4`
  (1080x1920: the game fitted across the middle over a blurred, zoomed copy of itself, for TikTok, Reels and Shorts). Matthew
  posts them himself. Free, and nothing to install: it uses Apple's own video tools.
- **Not yet run on the Mac**: the AVFoundation code was written against Apple's current docs (checked: `export(to:as:)`, the
  asset reader, the Core Image composition; the last two are marked deprecated but still present, so they warn) but never
  compiled or run. Captions are not done: they would need speech recognition.

## Friday's voice (2026-10-05)

Friday was using Google's "Puck", a male-sounding voice. She now defaults to "Aoede" (breezy). The first run of this version
switches the saved choice once; after that, whatever Matthew picks is kept. Settings, Live voice lists the female-sounding
voices first with Google's own style words (Aoede breezy, Zephyr bright, Leda youthful, Laomedeia upbeat, Sulafat warm, and so
on), then the male-sounding ones. Google doesn't label voices by gender (its docs give only the style word), so "female-sounding"
is how people describe them; try two or three. The voice can only be changed while Friday is asleep. Local mode's voice is a
separate macOS voice and was not changed.

## Meeting Room messages (2026-10-05)

The Meeting Room page now has a live message thread: GitHub issue 15 on the repo, locked so only the owner's account can post.
`MeetingData.swift` reads it with no key (comments from the owner's account only; each message is tagged **[From → To]**, and
the Claude footer is dropped) and shows the newest 12. To post from the app, Matthew pastes a fine-grained GitHub key limited to
**Issues: Read and write on the hotstuff repo only** into the Meeting Room page or Accounts; it goes in the Keychain. Classic keys
are refused because they can't be limited to one repo. That key can't touch code or the site. A message tagged `→ Matthew]`
triggers `.github/workflows/room-ping.yml`, which sends a push to his phone through the same ntfy secret the other alerts use.
The tag parser, trust filter, page-number reader and key rules are in `checks/DataChecks.swift` and pass. The page itself and
the posting call have not been compiled or run on the Mac.

## Refresh everything (2026-10-05)

A **Refresh** button sits in the top bar of every page (Command-R). It reloads the stock snapshots, store and ECS numbers,
automations, sales and the Meeting Room together, spins while it works, and shows "Updated 2 minutes ago". The Meeting Room's
Messages card has its own Refresh too. A page left open also refreshes itself once a minute (stocks, Meeting Room, or the
store/ECS/Systems numbers), and the Meeting Room uses the saved GitHub key for its reads when there is one, because GitHub allows
far more reads with a key than without (60 an hour). Without a key the Meeting Room refreshes about every five minutes.

## New orb, corner popup, movable tabs and the Stream page (2026-10-05)

**The orb** (`FridayOrb.swift`) was rewritten: a soft glow behind it that matches its colour and pulses with the voice, a
glassy sphere with drifting colour inside and a bright core, and little sparks in orbit while she talks. It reacts to both
her voice and Matthew's, in live mode and local mode. Under it, a small glass bar switches the look (red orb, emoji faces,
robot, fire); it fades back until the pointer is over the orb. The choice is saved on the Mac. The Home page's orb hides the bar.

**The corner popup** (`FridayCorner.swift`) is a small Siri-style card in a corner of the screen while Friday is live. It shows the
orb (reacting to voice), what she is hearing or saying, and a close button. It appears whenever the app's window is out of sight:
minimized, hidden, or another app (the game) in front. It floats over full-screen apps, can be dragged, and a click brings the
app forward. Settings, Live voice has an on/off switch and a choice of corner. It starts nothing and sends nothing; it only shows
what the live session already knows. Compiles and parses; not seen on the Mac yet.

**Movable tabs**: drag any icon on the left rail to a new spot, or right-click an icon for Move up, Move down and Put the icons
back in the original order. The order is saved on the Mac, and Command-1 to Command-0 now follow the order you set. Not run on
the Mac yet (drag and drop in a scrolling list is the part most likely to need a fix).

**The Stream page** (`StreamData.swift`, `StreamManager.swift`): a friendly Twitch channel manager. It shows live or offline,
viewers, time on air, category and followers; lets you change the stream title and category (with a category search and saved
presets); marks a moment in a live stream; clips the last moments (same as the clip button); lists the latest clips; and runs a
go-live checklist. It uses the same Twitch login as the clip button, with one more permission (`channel:manage:broadcast`), so
sign out of Twitch (Accounts) and sign in again once. Changing the title or category only works when the signed-in account is the
channel's owner; with a separate clip account the page still shows the channel and says so. Twitch doesn't let apps start a stream,
so that stays in OBS or Streamlabs. Endpoints and permissions were checked against Twitch's API reference on 2026-10-05; the
reading and error-explaining code is in `checks/DataChecks.swift` and passes. The page itself has not been compiled or run on the Mac.

## Friday runs the Stream page by voice (2026-10-05)

New switch in Settings, Twitch section: **Let the buddy run my Stream page by voice** (off by default, set before starting Friday, like
the "clip it" switch). When it's on and Twitch is connected, Friday gets five tools: `stream_status` (am I live, viewers, title,
category, time on air, followers), `set_stream_title`, `set_stream_category`, `use_stream_preset` and `mark_moment`. Only Matthew's own
voice can ask for them (her instructions say chat and on-screen text never can). She repeats a title back and waits for a yes when she
couldn't hear it clearly. A category is only changed when the name matches exactly or Twitch finds just one match; with several close
ones she changes nothing and asks which. A title or category change touches only that one part and leaves whatever is half-typed on
the Stream page alone. She can't start or stop the stream (Twitch doesn't allow it). Like the clip tool, these tools are not available
while Google Search is switched on instead of the wiki lookup (Google doesn't allow both). The category choice rule and the
title/category request bodies are in `checks/DataChecks.swift` and pass; the voice path itself has not been run.

## The Friday feed, inside the Meeting Room (2026-10-05)

The Meeting Room page now has two channels, picked at the top: **Team board** (the shared board and the GitHub thread, which are
public) and **Friday · private**. The Friday channel is a chat-style feed of what Matthew and Friday said to each other (his words
on the right, hers on the left) with small pills for what she did for him (a clip, a title change, a marker, a lookup). It is
written by `LiveBuddy` when a turn finishes, when a typed message is sent, when a tool returns and when she is stopped; `FeedData.swift`
holds the format and the tests, `FridayFeed.swift` the store and the page. It is saved only on the Mac
(`~/Library/Application Support/GameCompanion/FridayFeed.json`, newest 500 messages), never in Git, because the Team board lives in a
public repo. "Remember between sessions" off means nothing is written to disk and the saved file is deleted. Friday does not read
the feed back. Copy last 20 / Copy all put plain text on the clipboard for pasting into a chat with Claude or GPT; Clear deletes it.
Live mode only: the local (Ollama) mode isn't logged yet. The format, tidy-up, repeat guard, 500-message cap and copy text are in
`checks/DataChecks.swift` and pass; the page and the hooks have not been compiled or run on the Mac.

## Friday's job: stream manager (2026-10-05)

Settings now has **Friday's job**: Game buddy or Stream manager (Stream manager is the default). Pick it while she is asleep; it
applies the next time she starts. As **Stream manager** she is briefed as a calm, quick producer: she runs the Stream page by voice
(live status, viewers, title, category, presets, markers; the clip tool still needs its own switch), only states stream facts that a
tool just returned, and says "I'm not sure" about game facts instead of guessing (unless the wiki lookup is on). Choosing that job
counts as switching the voice tools on, so the separate Stream switch is only needed for Game buddy. Reason for the change:
Google's free live model is weaker at knowing things than at relaying what a tool returns, and Twitch's own answers are the
reliable part. It does not make the model smarter; the model name is still in Settings ("Live model"). She still speaks only when
Matthew talks to her.

## Chat helper: posts Matthew's links and reminders in his Twitch chat (2026-10-05)

A card on the Stream page (`ChatHelper.swift`, rules in `ChatData.swift`). It posts Matthew's own saved messages (starter set: his
store link, a "use your Prime sub" reminder, a Follow reminder, and East Coast Social switched off) in his chat while he is live,
from whichever Twitch account is signed in. Each message has its own on/off switch, text, and a wait (10 to 180 minutes); "Post now"
sends one right away. **Off every time the app opens**; Start or Friday ("turn on the chat helper") turns it on. Rules built in:
only while a Twitch check from the last 3 minutes says he is live; the first post waits 5 minutes after Start; at least 5 minutes
between any two posts and at most 6 an hour; a message starting with `/` or `.` is refused (could be read as a chat command); 500
characters max; two failures in a row switch it off. Friday can post a saved message by name (`post_chat_message`) or switch the helper
(`chat_helper`), never free text. It writes "Posted in chat: …" to the Friday feed. Needs the `user:write:chat` permission, so sign out
of Twitch (Accounts) and in again once. Twitch's Send Chat Message call was checked in its API reference on 2026-10-05. The rules and
the reply reading are in `checks/DataChecks.swift` and pass; the posting itself has not been run on the Mac. The Prime starter
message says Prime members get one free channel sub a month; Twitch's own pages could not be re-read from this build machine, so
Matthew should check that wording against what Twitch offers today. NOT built yet: answering viewers' commands like `!store` (needs
reading chat), and deleting spam or banning (needs the moderator permissions and a clear rule about who gets timed out).

## Friday hearing herself on speakers (2026-10-05)

Matthew's report: the mic was "really sensitive": on speakers Friday heard her own voice, cut herself off and wrote her own words
into what she "heard". Cause: the old "I'm wearing headphones" box defaulted to ticked, which keeps the mic open while she talks.
Fix: Settings now has **Sound output: Auto / Headphones / Speakers** (default Auto). `AudioRoute.swift` asks CoreAudio what the Mac
is playing through (built-in output with the headphone jack in use, or Bluetooth, counts as headphones; everything else, including
HDMI/monitor speakers, AirPlay and USB, counts as speakers; when it can't tell it says speakers). On speakers the mic is not sent
to Google while she is talking, plus 0.6 seconds after her estimated last sample (the speaker and room keep sounding a little
after). Cost: on speakers you can't interrupt her by voice. If it still happens, choose Speakers by hand. Auto re-checks every 3
seconds. NOT done: echo cancellation with Apple's voice processing, which would let you interrupt on speakers; it can also lower the
game's own volume and couldn't be tried from here. Parsed only; not run on the Mac.

## Friday's hands: her own cursor and scrolling (2026-10-05)

Settings: **Let Friday scroll and point in the window she's watching** (`FridayHands.swift`). Off every time the app opens. When on
and she is live, she has two voice tools: `scroll_page` (up, down, top or bottom; small, medium or large) and `point_at` (x and y
from 0 to 1000 across the picture she sees, plus a short label): a crimson pointer with a glow glides across the screen from where
your real pointer is, shows her label, and fades after a few seconds. **She cannot click, type or press keys.** Safety rules in the
code: only the window or display Matthew chose to share; the scroll goes through only if that window is the front-most window at its
middle (so it can't land on another app); if you moved the mouse in the last 1.5 seconds or a button is down she leaves the page
alone; at most one action every 0.4 seconds and 30 a minute; pointing never moves the real mouse and needs no permission. Scrolling
briefly moves the real pointer to the middle of the window and puts it back, and needs macOS's Accessibility permission (the app
asks; Settings has an Open Settings button). Parsed only; not run on the Mac. NOT built: clicking. If wanted later it should ask
Matthew's OK on screen for each click.

## Friday and the Meeting Room (2026-10-05)

Two more voice tools: `tell_the_team` (passes a short message, in Matthew's words, to Claude, GPT or everyone as
`**[Friday → Claude]** (from Matthew, by voice) ...`) and `team_messages` (reads the newest messages tagged for Friday or
everyone). It needs the GitHub posting key in Accounts (the same one the Meeting Room box uses). The thread is public, so her
instructions say never to pass on keys, passwords, addresses, phone numbers or private details; the app adds nothing of its own; at
most 6 a hour; she is told not to promise an instant reply, because Claude and GPT read the room at their next check (Claude's daily
routine, or when Matthew opens a chat). This is a relay, not a live link. Not run on the Mac.

## Keys now live in private files, not the Keychain (2026-10-05)

Matthew's report: macOS kept asking for the Mac password at launch (screenshot: "Game Companion wants to access key
GameCompanion.GitHubIssuesToken"), and "Always Allow" didn't stick. Cause: the old file-based Keychain ties permission to the
exact build of the app, which changes at every rebuild, and a self-made certificate can't make that stable. Fix: the Google key,
the Twitch login, the GitHub posting key and the Stripe read-only key are now saved as private files in
`~/Library/Application Support/GameCompanion/secrets` (folder 700, files 600; `SecretFile.swift`, tested), and `Keychain.swift` reads
and writes those. On the first launch after this change, each old Keychain item is copied into a file once and then deleted
(`Keychain.migrateLegacy`); that is the last password box macOS can show. What this changes, honestly: the Keychain encrypts each
secret and a private file does not (FileVault still encrypts the disk), and other software running as the same user could read
either one, since the previous "allow all applications" setting already allowed that. Nothing is in the repo, the settings or
chat. CLAUDE.md was updated to match. To go back to the Keychain, ask Claude. The file read/write rules are in
`checks/DataChecks.swift` and pass; the migration has not been run on the Mac.

## A calmer look, in the style of a voice assistant (2026-10-05)

Matthew asked for a more mellow crimson and "that type of UI" (a voice-assistant screen, like ChatGPT's voice mode). Changes:
the crimson is softer and dustier everywhere (`Noir` in `FridayOrb.swift`: rosewood instead of neon red); the background is darker
and quieter; the Friday page is bigger orb, a small centred "LIVE" line, softer captions, and fewer, calmer round buttons (the
settings gear was removed from the stage; Settings stays on the left rail, Command-comma); the filled button is a soft crimson
gradient. The orb, the corner popup and Friday's cursor pick up the new colours automatically. Not seen on the Mac yet.

## Orb: dimmer light, breathing and a wobbling edge (2026-10-05)

After the first look at the calmer palette ("a little bright", "motion like GPT", "react to voice"): the white core, highlight, streaks
and drifting lights are about half as bright, and the body is a softer rose. The orb now breathes in every state (even asleep) and
its outline slowly wobbles like a voice assistant's orb (`FridayBlob` in `FridayOrb.swift`): barely while asleep, more when idle,
and swelling with the sound level while she listens (your voice) or speaks (hers), faster while she thinks. The light inside drifts
even when asleep. Reduce Motion still freezes it. It can only react to a voice while Friday is live, because that is the only time
the mic is open. Not seen on the Mac yet.

## Fluid orb motion (2026-10-05)

Matthew: the change from listening to hearing something was abrupt; make it fluid, keep it the orb. The cause: every state set the
drift speed, brightness and wobble in one jump, and speeds were multiplied by the clock, so a change of speed made the picture leap.
Fix (`OrbDynamics` in `FridayOrb.swift`): each of those values now eases toward its goal over a second or so; speeds are added up
frame by frame instead of multiplied by the clock; ripples and sparks fade in and out instead of popping; and the sound level
behaves like a meter (fast to rise with the voice, slow to fall). The main orb and the Home orb now draw at 60 frames a second.
The look picker under the orb now stays hidden until the pointer is over the orb, so the screen is just the orb. The easing rules
were checked on their own (no jumps, meter rises and falls). Not seen on the Mac yet.

## Friday sees every screen, and her hands do more (2026-10-05)

Matthew's choices, made after being told the trade-offs: **Friday sees all screens, all the time while live**, and **her hands act when
he tells her**, with an Allow box only for anything that could send or buy.

- **All screens** (`ScreenSnap.swift`, layout maths in `HandsData.swift`, tested): one picture of every screen side by side, laid
  out the way they sit on the desk, up to 1600 x 900, sent where the window picture used to go. Settings, Friday sees: All my screens
  (default) or Just the window I pick (the old way). What this means, plainly: everything visible on every screen goes to Google while
  she is live, including private windows and banking tabs, and Google's free tier may use it to improve its products. The picture is
  bigger than before, so it uses more of the free allowance. The Live bar says "LIVE · ALL SCREENS + MIC SHARED WITH GOOGLE".
- **Hands** (`FridayHands.swift`): scroll, point, **click, type and press keys**, off at every launch, only while live. Her cursor
  now glides along a curved path with an ease in and out, a fading trail and a click ripple, slow enough to watch (0.7 to 1.4
  seconds). Needs Accessibility permission (the app asks). She is told to say out loud what she is about to do and wait for his yes
  before anything that could send or buy. **The Allow box** (top of the screen, never steals the keyboard; no answer in 25 seconds is
  a Deny) appears for: pressing Return or Enter (or typing a line break), clicking a button whose label or her own description says
  Send, Post, Submit, Pay, Order, Buy and the like (the label is read from macOS accessibility data, never stored), and anything done
  in a window titled like a checkout, cart, payment or order page. **Always refused**: banking and payment pages, Moomoo and other
  trading apps, password and login pages and password fields, System Settings, this app, terminals; text that looks like a card
  number; quit, force-quit and Trash shortcuts. The lists match the app name, window title and button label, so they can miss a
  page that doesn't say what it is; the Allow box is the hard backstop. Parsed and the rules tested; the hands themselves,
  the box and the all-screens picture have not been run on the Mac.

## One Friday, no job setting (2026-10-05)

Matthew: "she doesn't need a Job, she can do both, no setting." The Friday's job picker (Game buddy / Stream manager) and the separate
"run my Stream page by voice" switch are gone. There is one Friday: a friendly gaming buddy and also the stream manager. Her Twitch
voice tools (am I live, title, category, presets, markers) are available whenever Twitch is connected, and still act only on his
voice; "clip it" by voice keeps its own switch. Her instructions say to state stream facts only when a tool just returned them.

## Clips from past streams (VODs) (2026-10-05)

Matthew asked for clips made from his past Twitch streams, for the Minecraft side of the channel and growth and for more than that.
Twitch has a "Create Clip From VOD" call (checked in its API reference), so the Stream page has a new card, **Clip from my past
streams** (`VodClips.swift`, rules and tests in `VodData.swift`): Load my streams lists the last twelve (title, how long ago, length,
views); **Clip my marked moments** reads the markers he dropped during that stream (the Mark it button, or "Friday, mark that") and
makes one clip per marker, ending 8 seconds after it, at most 8 a run; or type the time the clip should end at (1:12:30, 45m), pick
15, 30, 45 or 60 seconds, give it a title and press Make clip. After each clip the existing pipeline downloads it and cuts the highlight
into Movies > Game Companion Clips. Friday has two voice tools when the clip switch is on: `clip_past_moment` ("clip last night's
stream at one hour twelve") and `clip_marked_moments`. A clip is public on Twitch the moment it exists, so these only run when he taps
or asks. Needs the account to be the channel's owner or an Editor; uses the permissions the clip sign-in already has (sign out and in
once if clipping was set up earlier). Twitch deletes old streams after a while (it varies), and a stream needs "store past broadcasts"
switched on in Twitch. The clock reading, clip plan, marker reading and error words are in `checks/DataChecks.swift` and pass; the
card and the calls have not been run on the Mac or against a real Twitch account.

## Clip autopilot (2026-10-05)

Matthew asked for Friday to clip his streams and post the clips without being asked: "all 3" sources, to the Minecraft TikTok, dubbed.
Built so far (`ClipAutopilot.swift`, rules and tests in `AutopilotData.swift`; a card on the Stream page, **off until he switches it
on**, runs only while the app is open): (1) after a stream ends (three clean "offline" checks, then 90 seconds for the stream's
recording to appear) every moment he marked becomes a clip, up to 8; (2) while he streams and Friday is running, a jump in the
loudness of his own voice (held 0.8 s, well above his normal level) makes a live clip, at most 3 a stream and 5 minutes apart;
(3) every 6 hours the 2 best recent viewer clips (at least 3 views, last 7 days, not already handled) are downloaded and cut. Every
action is in the card's log and the Friday feed. After EVERY finished clip, whoever asked for it, `tiktok-caption.txt` is saved next to
it (the clip's title and hashtags for the game, no claims). Clips are public on Twitch the moment they exist.

NOT built yet, and why: **posting to TikTok.** TikTok does not let an unreviewed app publish publicly; at most it takes a draft into the
account's TikTok inbox (how the HotsTuff store account's drafts already work), and the existing hookup is the store account, not the
Minecraft one, so the Minecraft account has to be authorised with our TikTok developer app first (a test user while the app is unreviewed)
and the app needs its keys, which Matthew pastes himself. **Dubbing**: a short voice-over line (his clip's title in a Mac voice, mixed
over the start with the game sound turned down) is doable with Apple's speech and video tools and is the next step; translating his own
speech into another language is not possible with what is built.

## Review fixes (2026-10-06)

An overnight review of the newest builds found 26 real problems (none stopped the app from building). All are fixed, with new tests in
`checks/DataChecks.swift`. The ones that matter most are about Friday's hands:
- A click or scroll lands on whatever window is on TOP at that spot, of any kind (menus, pop-ups, her own Allow box). The rules are now
  checked against that window, and her own windows are never clicked, so she can't press her own Allow button.
- Nothing else runs while an Allow box is open, and only one hands action runs at a time.
- Everything is checked AGAIN after the cursor glide and after any wait for Allow (same window, not a blocked app, not a password box,
  hands still on, still live). Typing re-checks before every ten characters and stops if the window changed.
- Scrolling follows the same off-limits list as clicking and typing, and the "Matthew is using the mouse" check runs again after the glide.
- The hands now need macOS's Accessibility permission (the password-box and button-name checks read it). If macOS won't let her look, a
  password box counts as "there".
- Word lists: "Payment", "Sending", "Posting", "Orders", "Allow" now ask for his Allow; "RBC"/"BMO" match as the last word of a title;
  security prompts (SecurityAgent, loginwindow) are off-limits; a card number anywhere inside the text she's asked to type is refused.
Also fixed: in Google Search mode she is told she has no other tools; click/point refuse a missing x or y; the cursor glides correctly across
screens; the key migration only marks itself done when every old item was copied; the orb never freezes if the clock steps back; the Start
buttons and privacy captions now say "all your screens" when that's the mode (and don't need a chosen window); the round X button also turns
Clip autopilot off; the Meeting Room's Friday card and her inbox are accurate. Still true: these rules are a safety net, not a guarantee;
the Allow box is the hard stop for send and buy. None of it has been run on the Mac yet.

## Friday's voice-over (2026-10-06)

Matthew: "like a voice over of the clip, like in the clip she explains what's going on, how to get loot, best ways to farm." Built as a
card on the Stream page, **Friday's voice-over** (`VoiceOver.swift`; the rules, prompts and tests are in `VoiceOverData.swift`).
How it works, step by step:
1. She **watches** the clip: a small copy (picture and sound, under 14 MB) goes to Google's Gemini with his free key, which says what happens
   and names the items, enemies and areas it can clearly read or hear (at most 3).
2. She **looks those names up** on the game wiki (the same MetaBot and Minecraft wiki lookup she uses live).
3. She **writes** a short script from only those two sources (about 2.3 words a second, so about 53 words for a 25-second clip). Anything about
   loot or farming may only come from the wiki pages. Every sentence with a number (digits or spelled-out, such as "twenty percent") that
   the sources don't contain is dropped.
4. Gemini's voice maker **speaks** it in the voice she uses live; if it runs too long for the clip, fewer sentences and once more.
5. The speech is **mixed over the clip** from 0.8 seconds in, with the game's sound (and his voice in the clip) turned down to 22% while she
   talks. He gets `highlight-tall-voiceover.mp4` and `highlight-wide-voiceover.mp4` next to the plain ones, plus `voiceover-script.txt`
   (the words, what she looked at, which wiki pages, and that the voice is an AI) and `voiceover.wav`.
Switch it on and every cut clip gets one (off by default); or press **Add a voice-over to my latest clip**; or tell Friday ("narrate that clip",
optionally "...and cover how to farm it"), which runs in the background and lands in the clips folder and the Friday feed. The TikTok caption
saved by the autopilot adds "Voice-over by Friday, my AI companion (AI voice)." whenever a voice-over version exists. **Nothing is posted.**
Honest limits: it has NOT been run on the Mac or with a real key. The Google endpoint and model names (`gemini-3.8-flash`,
`gemini-3.8-flash-tts`, the `interactions` call) come from Google's docs as of today and may need a tweak; the free plan may not include the voice
maker (if so she says so and saves the words as `voiceover-draft.txt`; there is no Mac-voice fallback yet). English only. She can be wrong about
what she saw, so listen before posting. It does not translate his own speech. Part of the clip's sound (his voice, the game) is lowered, not
removed, while she talks. A small copy of the clip goes to Google (public Twitch footage, but still sent).

### One-click update (2026-10-06)

After this one, you don't need to type the update command: double-click **Update Game Companion.command** (in this folder, in Finder). It runs
`git pull` and then `rebuild.sh`, and waits for a key press so you can read the result. If it says BUILD FAILED, the old app is still
installed; copy the error and send it to Claude. (The first time, get the file with the usual `cd ~/hotstuff && git pull`.)

## Smaller window, and Friday can use the web (2026-10-06)

Matthew: the window takes up too much of the screen, and "I asked her to search TikTok, Twitter and YouTube for references and she said she
can't. I want her to be able to do anything I ask, especially something that easy."
- **Window:** it can now be shrunk to 440 x 400 (it was stuck at 960 x 660) and opens at 900 x 640. Under 720 points wide the app goes
  compact: a slim icon rail without labels, a one-line top bar (no blurb, the Refresh button is just its icon, no avatar), no orb on the Home
  card, and the fixed-width pickers and boxes are allowed to shrink. A window you resized before keeps its old size until you drag it.
- **The web:** she had no way to open a page, so she said she couldn't. New voice tools in `Live.swift` (rules and tests in `WebData.swift`):
  `search_site` (YouTube, TikTok, X/Twitter, Google, Reddit, Pinterest, Facebook, Twitch or the Minecraft wiki plus search words) and
  `open_link` (an https address). They open the page in his own browser and she reads what is on the screen (she sees every screen while
  live), scrolls with her hands and clicks a result if asked. No key, no cost, and no need for the hands switch to just open a page; scrolling
  and clicking still need it. Safety: https only (http is upgraded), never a bare number address, this Mac or the home network, a link with a
  password in it, or a page whose address looks like a bank, payment, password or login page; 8 pages a minute; only his voice can ask.
  Honest limits: she only sees the pages through the pictures she is sent (every few seconds), she cannot hear a video, and she cannot
  open private pages. She is told never to invent results. The Google Search switch in Settings is a separate thing and still doesn't
  work on the free key (first live test 2026-10-05: quota).
- Not run on the Mac yet. Rules and tests pass here (`checks/DataChecks.swift`); the layout changes are untested.
- **Fix (same day):** on the Friday page the round buttons (start and stop live, keyboard, clip, stop everything) were pushed off the bottom of a
  short window. They are now pinned at the bottom and always shown (smaller in a small window, 40 and 56 points instead of 54 and 80), and the
  orb and what she says scroll above them if there's no room. The "LIVE · ALL SCREENS + MIC SHARED WITH GOOGLE" note wraps instead of overflowing.

- **Twitch setup gotcha (2026-10-06):** dev.twitch.tv/console has an **Applications** tab and an **Extensions** tab. The Client ID must come from
  **Register Your Application** (Applications), not from Create Extension (which starts a viewer-panel/overlay project). Matthew's first try made an
  Extension; the app still said "signed in" with its ID, so it may work, but if the Stream page shows a Twitch error, make a real Application and swap the ID.
- **"Couldn't find the channel" fix (2026-10-06):** that message was shown for ANY refusal from Twitch, not only a wrong name (for example a login that
  doesn't match the Client ID after the ID was swapped). Now the Stream page says what Twitch really answered, reads the name from whatever was
  typed or pasted (`TheyCallMe`, `@TheyCallMe`, `twitch.tv/TheyCallMe` or a whole link), and if no channel has that name it uses the account you
  signed in with and says so. Tests are in `checks/DataChecks.swift`.

## Scrolling, screens and hands, round two (2026-10-06)

Matthew: she has trouble with all the screens ("I still need to select the one she can operate on") and can't scroll pages.
- **Scrolling:** with no spot given she used "the front window", and right after he talks to her the front window is Friday herself (so the
  scroll hit her own app or was refused). Now she scrolls the top-most window that isn't hers, and her tool is told to ALWAYS give the middle
  of the page (x and y across the picture of all screens), so she scrolls exactly that page on any screen. If something floats over the
  middle of a window she tries other spots in it before giving up.
- **Hands switch:** it was off at every launch and buried in Settings, so she often had no hands without him knowing. It is now remembered, and
  there is a hand button on the Friday page (filled = on). If macOS hasn't given the app Accessibility permission, a line on the Friday page says
  so and opens the right Settings page. (After every rebuild macOS may forget Accessibility and Screen Recording for the app: switch Game
  Companion off and on in Privacy & Security.)
- **Screens:** in the default all-screens mode there is nothing to choose, so the choose-window button is hidden (it only shows in "Just the window
  I pick" mode). If she can't capture the screens the status line now says to re-grant Screen & System Audio Recording.
- **VODs:** Twitch only saves every stream to the channel while "Store past broadcasts" is on in Twitch's own settings; the app can't switch it. The Stream
  page checklist now has a button that opens that Twitch page.

## Hands with fewer false alarms, and a smarter-brain option (2026-10-06)

Matthew: the hand button is there but "it isn't working very well with all the restrictions", and "can we upgrade her model too?"
- **What I loosened** (the real safety stays: Allow box for send and buy, banking, Moomoo, password and login pages, System Settings, terminals, her own app, card numbers):
  - Money-app brand names (Moomoo, Wealthsimple, Questrade, Interactive Brokers) block anywhere. Softer words (bank, sign in, password) now only block when
    they're in an app's name or a SHORT page title (a real login or bank page has a short title); long article titles that mention a bank, or a wiki page called
    "Terminal Velocity", are fine. Terminals, System Settings and her own app match on the app's name only. Web links use the strict version.
  - "Needs Allow" no longer fires on ordinary clicks: Accept, Share, Apply, Upload, Allow, Approve and Remove are gone from the list (Send, Post, Pay, Buy, Order, Confirm,
    Subscribe, Delete, Reply, Book, Register, Install and similar stay). Checkout-page detection is narrower ("Order of the Stick" and "Bag of Holding" don't trigger it).
  - Return in a web browser's single-line box (address bar, search box) is harmless and no longer needs Allow; Return anywhere else still does.
  - She no longer refuses when you touch the mouse or when two actions come close together: she waits up to 3 seconds for the mouse to be still, and
    pauses 0.3 seconds between actions. The per-minute cap went from 30 to 60, and she can type 600 characters at a time (was 300).
  - Whatever she did or refused, in her words, now shows as a small "Hands: ..." line on the Friday page, so a refusal is never a mystery.
- **Her brain:** she was already on Google's newest everyday live model, `gemini-3.8-live`. Settings now has a switch: **Standard** (that one) or **Thinks harder**
  (`gemini-3.8-live-extended-thinking`, thinking depth "low"): more background reasoning, slower, may use the free allowance sooner. It handles tool calls only in
  Google's "async" way and reports end-of-turn differently, so it is new and untried here; switch back to Standard if it errors.

## Her crimson cursor stays visible (2026-10-06)

Matthew: "make sure we can see the crimson cursor when she is looking around". It used to show for 1.6 to 3.5 seconds when she acted and then vanish, so
while she looked around (scroll, read, scroll) it flickered off, and you never saw it while she was just watching.
- While Friday is live, her cursor now stays on screen the whole time: resting a bit softer (62%) between jobs where she last was (or low on the right
  of the main screen), full strength while she moves. It pulses a ring each time a picture of your screens is sent to her (at most once every 5 seconds).
  It puts itself away when the live session ends. Switch: Settings, "Keep her crimson cursor on screen while she's live" (on by default).
- It's bigger and glows more (26 x 41 points), and the overlay sits at the screen-saver window level so it shows above full-screen windows and
  borderless-window games. The Allow box was raised the same way, so it can't hide behind a full-screen game. A game in true exclusive full screen can
  still cover both; if that happens, use borderless or windowed mode.
- Not run on the Mac yet.

## "I can't control your browser" (2026-10-06 night)

Matthew asked her to scroll a Safari page and she answered that she can't control the browser or scroll, she can only see: the scroll tool never ran, so her tools
either weren't there or she didn't trust them. Two things were wrong in the design. Google Search mode used to switch ALL her other tools off (hands, web, clips,
stream, team) and the app told her so, and nothing on screen said which mode she was in. And her instructions never told her not to claim limits from memory.
- Google Search now works together with her tools (Google's Live docs, updated 2026-09-15, allow it), and the wiki and Search switches no longer cancel each other. If
  Search won't start for any reason before the connection is ready, the app drops it, keeps her tools, and says so in the status line.
- Her instructions now say: never say you can't do something your tools cover; call the tool and repeat what it returned or why it refused.
- Settings shows "Tools she has this session: ..." (the real list sent to Google when the session started), so what she says can be checked against what she has.
  If hands and web tools are missing from that list, tell Claude.
- The tools list is also shown on the Friday page itself while she is live (small grey "Tools on: ..." under her words), not only in Settings.

## Listening, fresh pictures, links and videos (2026-10-07)

Matthew: "she has trouble listening to me the first time", "she can't analyze videos", "she can't search links", and "she sees more of my screen than I can: when I ask her to scroll she
says she can see things I can't see yet".
- **Listening.** Three real causes. (1) Google's voice detector clips the first syllable unless it keeps some sound from before speech starts: the setup now asks for 300 ms of
  padding, high start sensitivity, and 700 ms of quiet before deciding he's finished (`realtimeInputConfig.automaticActivityDetection`; if Google refuses the fields the app
  drops them and reconnects with defaults). (2) On speakers the mic stream pauses while she talks, and Google's docs say to send an `audioStreamEnd` after a pause of over a
  second so nothing stale is left; the app never did, so the first sentence after she spoke could be mangled. It does now, and the mute after she stops talking is 0.35 s instead of 0.6.
  (3) Every ~10 minutes Google ends the connection and the app reconnects; anything he said in that gap was lost. The last 3 seconds of his voice are now kept and sent the moment she is back.
  Headphones still help most: on speakers she can't hear him while she talks (that is the echo guard).
- **Fresh pictures.** In Low usage she only looks every 15 seconds when he's quiet, so after she scrolled she was describing the screen from before. Now a fresh picture is sent 0.8 and 2.2
  seconds after any hands action, and 3 and 6 seconds after opening a page, and she is told to describe only the NEWEST picture. She also sees every screen, including ones he isn't looking at.
  The small "Friday sees this" preview now shows in a small window too, so you can compare.
- **Links and videos.** New tool `read_link` (rules and tests in `WebData.swift`, the call in `VoiceOver.swift`): a public YouTube address is watched by Google's video reader; any other public page
  is read by Google's "url_context" tool; "latest clip" watches the newest saved clip (as in the voice-over). She reads a YouTube address from the browser's address bar if he doesn't say it.
  It can't open TikTok, X, Instagram or Twitch videos, pages behind a login or paywall, or private videos, and she is told to say so and describe only what is on screen. Long videos use a lot of
  the free allowance. Not run on the Mac yet.

### Why `read_link` can't open TikTok, X or Twitch videos, and the answer: `watch_screen` (2026-10-07)

Matthew: "if I'm already logged in it should be okay, no?" Two different things. **Opening** a page (`open_link`, `search_site`) happens in HIS browser, where he is logged in, so
logged-in pages open fine and she reads them off the screen (the app only refuses addresses that look like a login, bank or payment page). **Reading** a page (`read_link`) is done by
Google's servers, not his Mac: they aren't logged in as him, can't use his cookies, and Google's video reader only takes YouTube addresses or uploaded files, not TikTok, X or Twitch pages.
- New tool `watch_screen` (seconds 5 to 40, default 15, and a question): once the video is playing, a picture of every screen is taken each second and sent to Google's reader in order
  (about 1280 x 720 each, under 14 MB in total). It works on anything he can see, logged in or not. Pictures only, **no sound**, and one picture a second misses fast action. Needs the
  Screen Recording permission. Not run on the Mac yet.

- **Build notes (2026-10-07):** the "Game notes and build context" box in Settings (on the Game view) now takes up to 2000 characters (it silently cut at 400) and grows to show what you paste, so a whole
  12-slot build with its enchantments fits. Friday reads it as true facts about his game and can coach him through it. (She still can't equip anything: she has no way to press a console's buttons.)
