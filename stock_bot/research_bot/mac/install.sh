#!/bin/bash
# PROPOSAL ONLY: do not run until NB2 has said OK (CLAUDE.md: no new schedules
# without the Co-CEO's OK). Turns on the research bot's hourly practice cycle
# on this Mac: every hour at :25 (so the next whole hour, when crypto windows
# open, is 35 minutes away). A Mac asleep at :25 runs it once on waking.
#   bash stock_bot/research_bot/mac/install.sh     # turn on
#   bash stock_bot/research_bot/mac/uninstall.sh   # turn off
# Stop trading without uninstalling: add stock_bot/research_bot/PAUSE and push.
set -e
REPO="$(cd "$(dirname "$0")/../../.." && pwd)"
RUN="$HOME/Claude/research-bot-runner"
LABEL="com.findhotstuff.researchbot"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
if [ ! -d "$RUN" ]; then
  git -C "$REPO" fetch -q origin master
  git -C "$REPO" worktree add -q --detach "$RUN" origin/master
fi
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key><array><string>/bin/bash</string><string>$RUN/stock_bot/research_bot/mac/cycle.sh</string></array>
  <key>EnvironmentVariables</key><dict><key>RESEARCH_BOT_DIR</key><string>$RUN</string></dict>
  <key>StartCalendarInterval</key><array><dict><key>Minute</key><integer>25</integer></dict></array>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/researchbot.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/researchbot.log</string>
</dict></plist>
PLIST
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
echo "Done. The research bot (practice only) runs every hour at :25. Diary: ~/Library/Logs/researchbot.log"
