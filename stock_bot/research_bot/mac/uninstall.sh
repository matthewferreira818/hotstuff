#!/bin/bash
# Turns the research bot's hourly cycle off. The runner folder and all
# records stay (use the Trash for the folder if you want it gone).
PLIST="$HOME/Library/LaunchAgents/com.findhotstuff.researchbot.plist"
launchctl unload "$PLIST" 2>/dev/null || true
[ -e "$PLIST" ] && mv "$PLIST" "$HOME/.Trash/"
echo "Research bot schedule is off."
