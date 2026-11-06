#!/bin/zsh
# Offline check of the crew working/idle/unknown logic and the events parsing. Run: zsh checks/run.sh
D=${0:A:h:h}; T=$(mktemp -d)
cp "$D/checks/crewstate_check.swift" "$T/main.swift"
xcrun swiftc -target arm64-apple-macos14.0 "$D"/{CrewSignals,CrewData,MeetingData,VentureData,StockData,GitHubRead}.swift "$T/main.swift" -o "$T/t" 2>&1 | grep error
"$T/t"
# GitHub rate-limit header parsing + plain message
cp "$D/checks/githubread_check.swift" "$T/main.swift"
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 "$D"/{GitHubRead,MeetingData,VentureData,StockData}.swift "$T/main.swift" -o "$T/g" 2>&1 | grep error
"$T/g"
# Phase 2 screens: composer tags, memory Keep/Edit/Forget, money move, DM thinking
cp "$D/checks/screensp2_check.swift" "$T/main.swift"
xcrun swiftc -target arm64-apple-macos14.0 "$D"/ScreensP2Data.swift "$T/main.swift" -o "$T/s" 2>&1 | grep error
"$T/s"
# Pixel crew station rules (who walks to whom, Friday's posts, labels, links)
cp "$D/checks/pixelcrew_check.swift" "$T/main.swift"
xcrun swiftc -target arm64-apple-macos14.0 "$D"/{PixelCrew,LiveSessions,CrewSignals,CrewData,MeetingData,VentureData,StockData,GitHubRead,HubTheme,FridayOrb}.swift "$T/main.swift" -o "$T/p" 2>&1 | grep error
"$T/p"
# Home button = Message Friday (opens the private DM panel), never starts Voice
python3 - "$D" <<'PY'
import sys,re
s=open(sys.argv[1]+"/HubSimple.swift").read()
i=s.index("var simpleHome"); body=s[i:s.index("var simpleNeedsCard")]
ok = "FridayMeModel.shared.open = true" in body and "\"Message Friday\"" in body and "mainAction()" not in body and "live.start" not in body and "Talk to Friday" not in body and "live buddy is off" not in body
print("PASS" if ok else "FAIL","Home button opens the DM panel, not Voice (no mainAction/live.start/'Talk to Friday' on Home)")
sys.exit(0 if ok else 1)
PY
# Usage ledger rules (measured fields only; unknown is never zero; no prices, no message text)
cp "$D/checks/usageledger_check.swift" "$T/main.swift"
xcrun swiftc -target arm64-apple-macos14.0 "$D"/{UsageLedger,HubTheme}.swift "$T/main.swift" -o "$T/u" 2>&1 | grep error
"$T/u"
# Engine checks (brain, Switchboard, pings/DMs), added 2026-11-06 after NB2's gate caught a stale test these didn't run
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 "$D"/{MeetingData,SwitchboardData,FridayBrainData}.swift "$D/checks/FridayBrainChecks.swift" -o "$T/fb" 2>&1 | grep error
"$T/fb" | grep -E "^FAIL|ALL|passed|failed" | tail -3
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 "$D/SwitchboardData.swift" "$D/checks/SwitchboardChecks.swift" -o "$T/sb" 2>&1 | grep error
"$T/sb" | grep -E "^FAIL|ALL|passed|failed" | tail -3
xcrun swiftc -parse-as-library -target arm64-apple-macos14.0 "$D"/{MeetingData,SwitchboardData,FridayBrainData,SwitchboardPingData}.swift "$D/checks/SwitchboardPingChecks.swift" -o "$T/pg" 2>&1 | grep error
"$T/pg" | grep -E "^FAIL|ALL|passed|failed" | tail -3
# Job cards: the Helm's reader (JobRules) and the crew's tool (tools/crew/job.py) agree
{ printf 'import Foundation\n'; awk '/^struct CrewJob/,/^}/' "$D/HubCommandJobs.swift"; awk '/^enum JobRules/,/^}/' "$D/HubCommandJobs.swift"; } > "$T/jobs.swift"
cp "$D/checks/jobs_check.swift" "$T/main.swift"
xcrun swiftc -target arm64-apple-macos14.0 "$T/jobs.swift" "$T/main.swift" -o "$T/jb" 2>&1 | grep error
"$T/jb"
J="$T/jobs-tool"; JP="$D/../crew/job.py"
JID=$(CREW_JOBS_DIR="$J" python3 "$JP" new LC-Test "check" --by Friday)
CREW_JOBS_DIR="$J" python3 "$JP" done "$JID" --by LC-Test 2>/dev/null && echo "FAIL job.py let 'done' through without proof" || echo "PASS job.py refuses 'done' without proof"
CREW_JOBS_DIR="$J" python3 "$JP" done "$JID" --by LC-Test --proof "x" >/dev/null && CREW_JOBS_DIR="$J" python3 "$JP" start "$JID" --by LC-Test 2>/dev/null && echo "FAIL job.py changed a finished job" || echo "PASS job.py won't touch a finished job"
JID2=$(CREW_JOBS_DIR="$J" python3 "$JP" new LC-Owner "owner check" --by Friday)
CREW_JOBS_DIR="$J" python3 "$JP" done "$JID2" --by LC-Other --proof x 2>/dev/null && echo "FAIL job.py let another chat finish someone else's job" || echo "PASS only the assigned chat can finish its job"
CREW_JOBS_DIR="$J" python3 "$JP" fail "$JID2" --by Friday --why "test" >/dev/null && echo "PASS whoever assigned it may fail it" || echo "FAIL the assigner couldn't fail its own job"
[ "$(stat -f %Lp "$J")" = "700" ] && echo "PASS jobs folder is private (700)" || echo "FAIL jobs folder is not 700"
# Self-healing handoffs (JobHeal rules); PingRules.backups is stubbed, the watcher itself is UI-side
{ printf 'import Foundation\n'; awk '/^struct CrewJob/,/^}/' "$D/HubCommandJobs.swift"; awk '/^enum JobRules/,/^}/' "$D/HubCommandJobs.swift"; awk '/^enum JobHeal/,/^}/' "$D/JobHealing.swift"; } > "$T/jh.swift"
printf 'enum PingRules { static func backups(for chat: String) -> [String] { chat == "Friday" ? ["LC-Manager"] : ["Friday"] } }\n' > "$T/jhstub.swift"
cp "$D/checks/jobheal_check.swift" "$T/main.swift"
xcrun swiftc -target arm64-apple-macos14.0 "$T/jhstub.swift" "$T/jh.swift" "$T/main.swift" -o "$T/jhx" 2>&1 | grep error
"$T/jhx"
