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
xcrun swiftc -target arm64-apple-macos14.0 "$D"/{PixelCrew,CrewSignals,CrewData,MeetingData,VentureData,StockData,GitHubRead,HubTheme,FridayOrb}.swift "$T/main.swift" -o "$T/p" 2>&1 | grep error
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
# Offline brain rules (local-only address, limit detection, reply parsing, ledger shape)
{ printf 'import Foundation\n'; awk '/^enum LocalBrainRules/,/^}/' "$D/FridayLocalBrain.swift"; } > "$T/lbr.swift"
printf 'import Foundation\nenum FridayBrainLimits { static let questionCap = 1500 }\n' > "$T/lbstub.swift"
cp "$D/checks/localbrain_check.swift" "$T/main.swift"
xcrun swiftc -target arm64-apple-macos14.0 "$T/lbstub.swift" "$T/lbr.swift" "$T/main.swift" -o "$T/lb" 2>&1 | grep error
"$T/lb"
