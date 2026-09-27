#!/bin/bash
# One-time setup: start the Moomoo stock bot every weekday morning on this
# Mac, 10 minutes before the New York open (worked out from this Mac's own
# clock, so it's right on Atlantic time and stays right through the clock
# changes, which New Brunswick and New York make on the same days).
#   bash stock_bot/mac/install.sh      # turn on
#   bash stock_bot/mac/uninstall.sh    # turn off
set -e
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
LABEL="com.findhotstuff.stockbot"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
read -r H M < <(/usr/bin/python3 -c "
import datetime as d, zoneinfo as z
t = d.datetime.now(z.ZoneInfo('America/New_York')).replace(hour=9, minute=20).astimezone()
print(t.hour, t.minute)")
DAYS=""
for W in 1 2 3 4 5; do
  DAYS="$DAYS<dict><key>Weekday</key><integer>$W</integer><key>Hour</key><integer>$H</integer><key>Minute</key><integer>$M</integer></dict>"
done
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$REPO/stock_bot/mac/run.sh</string></array>
  <key>StartCalendarInterval</key><array>$DAYS</array>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/stockbot.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/stockbot.log</string>
</dict></plist>
PLIST
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
printf 'Done. The stock bot starts every weekday at %d:%02d on this Mac.\n' "$H" "$M"
echo "Its diary: ~/Library/Logs/stockbot.log"
