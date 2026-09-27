#!/bin/bash
# Started by launchd every weekday morning (see install.sh). Watches the
# market through Moomoo until the close, then exits. Needs the moomoo OpenD
# app open and logged in. Everything it prints goes to
# ~/Library/Logs/stockbot.log on this Mac only — never to GitHub.
cd "$(dirname "$0")/../.." || exit 1
echo "=== $(date) ==="
# The ntfy topic lives in ~/.stockbot-env, typed in by Matthew (never
# committed, never pasted into a chat).
if [ -f "$HOME/.stockbot-env" ]; then set -a; . "$HOME/.stockbot-env"; set +a; fi
git pull -q --ff-only || echo "Couldn't update the code; running the copy already here."
# caffeinate keeps the Mac awake while the bot runs (plugged in, lid open).
exec /usr/bin/caffeinate -i /usr/bin/python3 stock_bot/stock_bot.py --moomoo --local
