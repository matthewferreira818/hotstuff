#!/usr/bin/env python3
"""Packs the whole Game Companion app into ONE text file that can be dropped into a ChatGPT (GPT) Project.

    python3 tools/game_companion/make_gpt_bundle.py

It writes GPT-PROJECT-BUNDLE.md next to this script: a plain-words intro, a map of the files, then every source file
in full. Re-run it after the code changes and upload the new copy. It reads only files in this folder, so it can't
pick up anything private: the app's logins live in the Mac's Keychain and its memory lives outside this repo.
"""
import re
import subprocess
from datetime import date
from pathlib import Path

HERE = Path(__file__).parent

# (file, what it is). Order is the order they appear in the bundle.
FILES = [
    ("Companion.swift", "The app's entry point and the local (Ollama) conversation engine; the old UI kept for rollback."),
    ("Live.swift", "Friday's live voice and screen session with Google Gemini over a WebSocket, plus the Google key."),
    ("SecretFile.swift", "Saves each login or key as a private file (owner-only) on the Mac. No Mac frameworks; tested."),
    ("Keychain.swift", "Where the app's secrets are read and saved: private files, with a one-time copy out of the old Keychain."),
    ("Wiki.swift", "Free game-fact lookup (MetaBot, then the Minecraft wiki) that Friday calls as a tool."),
    ("Clips.swift", "Twitch clips: separate clip-account sign-in, the clip button and the 'clip that' voice command."),
    ("Conversation.swift", "Opt-in memory, stored on the Mac only, never in Git."),
    ("CompanionConversation.swift", "Hooks the memory and Friday's own questions into the local engine."),
    ("CompanionInterface.swift", "The main window: Friday's orb, captions, controls and the settings sheet."),
    ("FridayOrb.swift", "The look: noir palette, the animated orb with its aura and look picker, background, cards and buttons."),
    ("FridayCorner.swift", "The Siri-style popup in a screen corner while Friday is live and the window is out of sight."),
    ("StockData.swift", "Reads the stock bot's public practice snapshots. Read-only."),
    ("VentureData.swift", "Reads the store's public visitor counters, the ECS feed, GitHub automation status and the product list age."),
    ("StripeData.swift", "Reads store sales from Stripe with a read-only restricted key. GET requests only."),
    ("MeetingData.swift", "Reads the shared Meeting Room board (meeting-room/BOARD.md) from GitHub. Read-only."),
    ("MeetingRoom.swift", "The Meeting Room page: the board, the crew, and a box that makes a ready-to-paste note for Claude or GPT."),
    ("ClipMath.swift", "Picks the highlight out of a clip from how loud it is. Pure maths, tested."),
    ("ClipEditor.swift", "Cuts the highlight and makes a wide and a tall (9:16) version with Apple's video tools."),
    ("StreamData.swift", "Reads Twitch's answers (live status, channel, clips, followers) and explains its errors in plain words. Tested."),
    ("StreamManager.swift", "The Stream page: live status, title and category editor with presets, markers, clips and a go-live checklist."),
    ("FeedData.swift", "The Friday feed's data and plain-text format (no Mac frameworks). Tested."),
    ("FridayFeed.swift", "The Feed page and its store: what Matthew and Friday said, saved on this Mac only."),
    ("ChatData.swift", "The chat helper's rules and Twitch reply reading (no Mac frameworks). Tested."),
    ("ChatHelper.swift", "The chat helper: posts Matthew's saved links and reminders in his Twitch chat while he is live."),
    ("AudioRoute.swift", "Tells headphones from speakers (CoreAudio) so the mic can pause while Friday talks on speakers."),
    ("VodData.swift", "Clips from past streams (VODs): reading Twitch's answers, clock times, the clip plan and error words. No Mac frameworks; tested."),
    ("VodClips.swift", "Clips from past streams: the Stream page card, the clip-my-marked-moments button and Friday's voice tools for it."),
    ("WebData.swift", "Friday's browser tools: which sites she can search and which links she won't open. No Mac frameworks; tested."),
    ("VoiceOverData.swift", "Friday's voice-over on a clip: how much she can say, the claim check on her script, Google's answers, the speech file, the volume plan. No Mac frameworks; tested."),
    ("VoiceOver.swift", "The voice-over job (watch the clip, check the wiki, write, speak, mix) and its Stream page card."),
    ("AutopilotData.swift", "Clip autopilot rules: which viewer clips to take, live-clip caps, the hype detector and the TikTok caption. No Mac frameworks; tested."),
    ("ClipAutopilot.swift", "Clip autopilot: clips from markers, exciting live moments and viewers' best clips, with caps, a log and a TikTok caption for each."),
    ("HandsData.swift", "The rules and maths for Friday's hands and her all-screens view: where things land, what she may type, press and click, what needs an Allow. No Mac frameworks; tested."),
    ("ScreenSnap.swift", "One picture of every screen side by side, for Friday to see."),
    ("FridayHands.swift", "Friday's hands: her gliding cursor, scrolling, clicking, typing and keys, with an Allow box for anything that could send or buy. Off by default."),
    ("Hub.swift", "The hub: sidebar sections, Home, Stock, Store, ECS, Systems, Launchpad, Game and Accounts pages."),
    ("rebuild.sh", "Builds the app with swiftc (no Xcode), signs it and installs it."),
    ("make_cert.sh", "One-time: makes the self-signed signing certificate so permissions and Keychain trust stick."),
    ("checks/ReviewChecks.swift", "Small automated checks for the conversation code."),
    ("checks/DataChecks.swift", "Automated checks for the highlight cut, the board reader and the Stripe key rules."),
    ("README.md", "Running notes: what was built, what was tested, what is still unverified."),
    ("../../meeting-room/README.md", "The Meeting Room rules: how Claude, GPT, Friday and Matthew share one board."),
    ("../../meeting-room/BOARD.md", "The shared board right now: who is on what, open questions, decisions, known problems."),
]

INTRO = """# Game Companion: everything in one file (for a ChatGPT Project)

Generated {today} from commit {commit}. Re-generate with `python3 tools/game_companion/make_gpt_bundle.py`.
Source of truth: https://github.com/matthewferreira818/hotstuff (folder `tools/game_companion/`, branch `master`).

## What this is

A free Mac app, built with SwiftUI and compiled with the command-line `swiftc` (no Xcode). It has two jobs:

1. **Friday**: a voice-and-screen game buddy. Matthew talks to her while he plays; she can see the game window and answers
   by voice. The live mode uses Google's free Gemini Live API. There is also a local mode (Ollama) and a free game-fact lookup.
2. **The hub**: a "master folder" for Matthew's ventures, shown as sections: stock bot (practice money), the store, East
   Coast Social (ECS), automations, a Launchpad of one-click links, the game side, and Accounts (the logins).

## Who you are helping

Matthew Ferreira is a founder, not a programmer. Use plain words and short messages, lead with what happened, and give exact
numbers and honest bad news. Never use jargon without explaining it.

## Rules that must not be broken

- **Secrets never go in chat or in files.** API keys live in the Mac Keychain. Matthew pastes them into the app himself. Do not
  ask him to paste a key to you.
- **Matthew clicks every final button** (Send, Post, Publish, Pay, Submit). The app prepares; it never submits for him.
- **Real-money trading is walled off.** The hub only reads the practice snapshots. Never wire the Moomoo real-money path into it.
- **App memory stays on his Mac**, in `~/Library/Application Support/GameCompanion/`, never in this public repo.
- **No paid services** until his first invoice clears. Everything here must run free.
- **Honesty in anything public.** Do not invent numbers or claims. Streaks count the site's feed, not any social page.
- Read-only by default: the Stripe reader sends GET requests only and refuses a full secret key.
- **Use the Meeting Room.** The last two files in this bundle are the shared board and its rules. Read the board before you
  start. When you finish a job, end with a "Board update" block in the board's format (`## heading`, then `- [GPT] ... Status: x`
  lines) for Matthew to hand to Claude. Never put keys or private details on it: the repo is public. Don't change a file the
  board says Claude owns while that item is open; send notes instead.

## Build facts that will trip you up

- Build and install: `cd ~/hotstuff && git pull && zsh tools/game_companion/rebuild.sh`. The script lists its source files in
  one `SOURCES=(...)` line; a new Swift file must be added there.
- **`@State` (and other SwiftUI macros) can't be used.** The Mac has no SwiftUIMacros plugin without Xcode. UI state lives on
  `ObservableObject` classes instead (`Companion`, `HubModel`, `VentureHub`, `SalesHub`...). `@StateObject`, `@Environment` and
  `@Namespace` are fine.
- The app is signed with a self-signed certificate (`make_cert.sh`, run once) so Screen Recording permission and Keychain
  trust survive rebuilds.
- Files that only use Foundation (`StockData.swift`, `VentureData.swift`, `StripeData.swift`, `Wiki.swift`) can be compiled and
  tested on Linux. SwiftUI files can only be compiled on his Mac.
- Matthew's Claude chats can't see each other, and neither can this project's chat. Hand changes back as **whole replacement
  files** (or a clear diff) so they can be applied and rebuilt.

## Not yet proven on a real Mac

The newest hub pages, the Stripe reader (never run against a real Stripe account), the Keychain "allow all applications" save,
and Gemini Live tool calls. `README.md` below lists what was tested and what wasn't.

## Files in this bundle

{filemap}

---
"""


def fence_for(text: str) -> str:
    longest = max((len(m.group(0)) for m in re.finditer(r"`+", text)), default=0)
    return "`" * max(3, longest + 1)


def language(name: str) -> str:
    return {"swift": "swift", "sh": "bash", "md": "markdown", "py": "python"}.get(name.rsplit(".", 1)[-1], "")


def main() -> None:
    try:
        commit = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=HERE, capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        commit = "unknown"
    present = [(name, note) for name, note in FILES if (HERE / name).exists()]
    def shown(name: str) -> str:
        return name.replace("../../", "")

    filemap = "\n".join(f"- `{shown(name)}`: {note}" for name, note in present)
    parts = [INTRO.format(today=date.today().isoformat(), commit=commit, filemap=filemap)]
    for name, _ in present:
        text = (HERE / name).read_text(encoding="utf-8")
        fence = fence_for(text)
        parts.append(f"\n## FILE: {shown(name)}\n\n{fence}{language(name)}\n{text.rstrip()}\n{fence}\n")
    out = HERE / "GPT-PROJECT-BUNDLE.md"
    out.write_text("".join(parts), encoding="utf-8")
    size = out.stat().st_size
    print(f"Wrote {out} ({size / 1024:.0f} KB, {len(present)} files, about {size // 4:,} tokens)")


if __name__ == "__main__":
    main()
