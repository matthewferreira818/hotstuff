# The Helm revamp (Signal Deck + Simple mode), branch helm-revamp

NOT on master. Goes to master only after Matthew's GO and LC-Manager's gate.

## What it is
- **Simple mode (default):** Home = orb + one Talk button + 3 cards (Needs you, Today, Your businesses). Four tabs (Home, Friday, Store, Messages), a More menu with a one-line "what this is" for every other page, a skippable first-run tour (More > Show me around), "?" help bubbles. Plain words, bigger buttons.
- **Advanced mode:** More > "Advanced mode" brings back the full Signal Deck (top tabs, green hacking area, Friday dock, Crew station, live tape). Switch back from Advanced's More menu.
- Per-chat Local Claude names in the Meeting Room (filter + "To <chat>" picker).
- Files: HubSimple.swift, HubDeck*.swift, HubCrew.swift, CrewData.swift (new); Hub.swift, HubShell.swift, HubTheme.swift, HubHome.swift, MeetingData.swift, MeetingRoom.swift, FridayOrb.swift, VentureData.swift, rebuild.sh (edited). Friday's off-limits list, Allow box, hands rules, Moomoo walls and secrets handling are untouched.

## ROLLBACK (get the old Helm back)
1. The old app is saved by every rebuild as `outputs/GameCompanion-backup.zip` next to The Helm.app (rebuild.sh makes it before installing). Unzip it over The Helm.app to restore the previous build.
2. Or rebuild from master: `git checkout master && git pull`, then run `Update Friday.command` (it only builds master).
3. Nothing in the revamp changes saved data (memory, keys, settings). The new settings keys are `hub.simple` and `hub.tourSeen`; deleting them only resets the mode/tour.
4. If merged and it must be undone: `git revert -m 1 <merge commit>` on master.

## Not tested (honest list)
- Live "talk to Friday" (mic + screen share to Google): Matthew's test, not run.
- Real VoiceOver run; High-contrast switch on the new pages; 200% text size.
- Composer "To <LC chat>" picker (compiled, not seen); the More dropdown menu itself (menus can't be screenshotted; its pages were opened directly).
- Away + alarm crew pictures were checked with a labelled test switch (`crew.testStates`) and a unit run, not with real away/failing data.
- Test builds use `-Onone` in a separate test app (own app ID); the final release build with `-O` via rebuild.sh has not been run by me.

## Friday Phase 1 pieces 2+3 (branch friday-phase1-crew)
- **Crew chat** (Messages > Crew chat; new file CrewChat.swift, last in rebuild.sh SOURCES): the room (issue 15) + Hotline (PR 35), read-only, newest at the bottom, one switch "Show technical lines". A failed read shows an empty list and "Couldn't load the room (as of <time>)".
- **Honest numbers** on Simple Home: "as of <time>, from <source>" under every number; failed read = "unknown (couldn't reach <source>)", never the last good value. Orders come only from Stripe's read-only key; without it: "Orders: not tracked yet".
- **ROLLBACK:** same as above (old build zip, or rebuild master). These pieces add no saved data. To drop just this work: `git revert` the merge, or rebuild from `friday-phase1`/master without CrewChat.swift (remove it from SOURCES and the `meeting.tab == 6` lines in MeetingRoom.swift).
- **Test-only switches** (never set in the real app): `test.failChat`, `test.failStore`, `hub.testStart`, `hub.testHour`.
- **Not tested:** noise-switch behaviour on every message shape (only a sample of real lines); Stripe orders path with a real key (no key on this Mac, so "not tracked yet" is what shows); long-run refresh over hours; VoiceOver on the new views; real app (-O build).

## Phase 1 polish round
- Messages (Simple mode) opens on the crew chat only: header "Your crew's messages.", ONE Filter button (everyone / one chat / other views), Refresh, the chat, the "Show technical lines" switch. Friday's Switchboard lines show only when the switch is ON.
- Crew strip: CrewSignals.token is set from the Helm's saved GitHub access (MeetingHub.refresh); no new key, no new Keychain entry. Keyless it stays at one read per 6 min.
- Plain words: "Meeting Room" and "snapshots" wording removed from Home.
- ROLLBACK: same as above; or revert the polish commit(s) on friday-phase1-crew.
- Not tested: the Filter menu items (menus can't be screenshotted), the token path with a real saved key on the crew strip (this Mac's test copy read the room without error but the strip's 3-min cadence was not timed), -O release build.
