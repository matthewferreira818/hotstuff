#!/bin/zsh
# Offline check of the crew working/idle/unknown logic and the events parsing. Run: zsh checks/run.sh
D=${0:A:h:h}; T=$(mktemp -d)
cp "$D/checks/crewstate_check.swift" "$T/main.swift"
xcrun swiftc -target arm64-apple-macos14.0 "$D"/{CrewSignals,CrewData,MeetingData,VentureData,StockData}.swift "$T/main.swift" -o "$T/t" 2>&1 | grep error
"$T/t"
