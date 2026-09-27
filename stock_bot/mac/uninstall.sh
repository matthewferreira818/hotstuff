#!/bin/bash
# Turn the weekday Moomoo stock bot off on this Mac.
PLIST="$HOME/Library/LaunchAgents/com.findhotstuff.stockbot.plist"
launchctl unload "$PLIST" 2>/dev/null
rm -f "$PLIST"
echo "Stock bot turned off. (Nothing in Moomoo was changed.)"
