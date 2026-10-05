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
     Redirect URL `http://localhost`, Category Application Integration, **Client Type: Public**; copy the
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

