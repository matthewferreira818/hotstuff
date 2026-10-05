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
