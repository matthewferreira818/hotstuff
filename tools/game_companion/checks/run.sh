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
# Pixel crew station rules (who walks to whom, Friday's posts, labels, links)
cp "$D/checks/pixelcrew_check.swift" "$T/main.swift"
xcrun swiftc -target arm64-apple-macos14.0 "$D"/{PixelCrew,LiveSessions,CrewSignals,CrewData,MeetingData,VentureData,StockData,GitHubRead,HubTheme,FridayOrb}.swift "$T/main.swift" -o "$T/p" 2>&1 | grep error
"$T/p"
