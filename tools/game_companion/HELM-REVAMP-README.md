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
