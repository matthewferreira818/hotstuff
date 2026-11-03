# Friday the guard: plan and split (2026-11-02)

Matthew, after a weekend of real attacks (hacked emergency-alert apps in Russia and Ukraine, hacked supermarket fridges in seven
European countries) and this year's reports of AI models reaching past their test limits: "a guard ... with the capabilities and
personality of Friday", "all 9, we gotta take it up a few notches", "imagine it could happen any day now", "a lot more modern",
"then we can test minor hacks on our own devices". Defensive only: she watches, warns, blocks and helps him report. Never attacks.
Unlock is a plain button (his choice: "itll only be me"); Friday has no unlock tool and her hands are off in lockdown.

## Claude's half: the engine (branch `claude/guard`, done, tested on Linux)

- `GuardData.swift` (Foundation, tested in DataChecks): `GuardPolicy` (what lockdown blocks: hands, links, screen reading, posting,
  clips, stream and OBS changes), `GuardCheckKind` (FileVault, firewall, Gatekeeper, SIP, automatic updates: fixed commands, plain
  verdicts and fixes), `GuardStartup` (launch agents/daemons, flags new names), `GuardNetwork` (apps with live internet connections
  via lsof, flags new ones), `GuardSweep` (9 account pages to check), `GuardKeys` (the keys The Helm holds), `GuardShield`,
  `GuardEvent`/`GuardLog`, `FakeCheck` (offline red flags for scams and fake alerts, plus a prompt for a model's second opinion).
- `Guard.swift`: `GuardHub.shared` (ObservableObject): `locked`, `offline`, `results`, `network`, `log`, `checking`,
  `lastChecked`, `shield`, `fakeText`, `fakeReport`; `lock(_:)`, `unlock()`, `setOffline(_:)`, `runChecks()`, `isSaved(_:)`,
  `forget(_:)`, `checkFake()`, `note(_:_:)`, `clearLog()`. Log in Application Support/GameCompanion/GuardLog.json (0600, newest 500).
- Wired in: Live.swift (blocked tools refuse in lockdown, no screen pictures while locked, `lockdown_now` voice tool, offline mode
  keeps her Google session off, she's told the moment lockdown changes), Helper.swift (off in lockdown; no Google brain offline),
  MeetingRoom.swift (no room reads offline). Registered in rebuild.sh and the bundle.

## Roxy's half: the screens (new file `HubGuard.swift`, plus the sidebar)

A modern security look, NOT retro terminal: midnight glass cards, one bright accent (cyan for safe, crimson for warnings), SF Pro
for words and SF Mono only for data (names, numbers, times), big clear status, 44 pt buttons, text at least 4.5:1. Use
`@ObservedObject var guardHub = GuardHub.shared`.

1. Sidebar: a new **Guard** group with three pages (add cases to `HubSection` in Hub.swift: titles, icons, colours, blurbs).
2. **Guard** page: a large shield (verdict + `shield.line`, last checked time), a big **Lockdown** button (crimson; when locked it
   becomes **Unlock**, which only Matthew presses), an **Offline mode** switch with the line "Stops Friday's Google session, room
   reads and the Helper's Google brain. To cut the Mac off completely, also turn off Wi-Fi.", **Run checks** (shows `results`
   as cards with verdict, detail and fix), **Apps using the internet** (`network`, new ones highlighted), **Account sweep**
   (`GuardSweep.items` as rows with an Open button, disabled while locked since links are off), **Keys** (`GuardKeys.all` with
   Saved / Not saved and a Forget button that asks "Are you sure?"), and the **Alert log** (newest first, with Clear).
3. **Real or Fake?** page: a paste box, Check (calls `checkFake()`), the verdict big, the red flags as a list, the advice line.
   Phase 2 (later): a "second opinion" button sending `FakeCheck.prompt` to the local Ollama brain.
4. **Lab** page (phase 1): lessons as cards in order (passwords and 2FA, phishing, how the internet works, Linux basics, Python
   basics) each with a short plain explanation; a **Practice** list (picoCTF https://picoctf.org, OverTheWire Bandit
   https://overthewire.org/wargames/bandit/, TryHackMe https://tryhackme.com, Get Cyber Safe https://www.getcybersafe.gc.ca) with
   a done tick saved in UserDefaults; the rule shown at the top: "Practise only on your own devices or on sites built for practice."
   Phase 2 (later): the code scratchpad.
5. Register `HubGuard` in rebuild.sh SOURCES and make_gpt_bundle.py.

Then the Mac compile of the exact hash (the branch includes Claude's half), exit code and hash in the room. Claude reviews and merges.
Rules unchanged: honesty, secrets, Friday's off-limits list and Allow box, Moomoo, nothing paid, no posts without a go.
