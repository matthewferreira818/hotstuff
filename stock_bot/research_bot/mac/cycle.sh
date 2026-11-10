#!/bin/bash
# One research-bot cycle. PRACTICE MONEY ONLY. Plain Python: uses no Claude usage.
# PROPOSAL (2026-11-10, LC-Research): nothing runs this until NB2 says OK and
# someone runs install.sh. Runs in its OWN folder (a detached worktree of
# master), never in ~/Claude/hotstuff where the chats work.
#   1. pull master  2. log forward forecasts and push them (before any window opens)
#   3. paper executor (stops, closes, new buys under the caps)  4. scorecard
#   5. commit + push the order log, equity, practice accounts, scorecard
set -u
RUN="${RESEARCH_BOT_DIR:-$HOME/Claude/research-bot-runner}"
cd "$RUN" 2>/dev/null || { echo "$(date) no runner folder at $RUN"; exit 1; }
if [ "$(pwd -P)" = "$(cd "$HOME/Claude/hotstuff" 2>/dev/null && pwd -P)" ]; then
  echo "$(date) refusing to run in the chats' main folder"; exit 1
fi
echo "=== $(date) research bot cycle"
git pull -q --rebase origin master || { echo "pull failed: cycle skipped"; exit 1; }
python3 -m stock_bot.research_bot.generate --commit
python3 -m stock_bot.research_bot.executor
python3 -m stock_bot.research_bot.scorer
for f in stock_bot/research_bot/orders.jsonl stock_bot/research_bot/equity.jsonl \
         stock_bot/research_bot/AUTO_PAUSE stock_bot/research_bot/scorecard.md \
         stock_bot/research_bot/scorecard.json stock_bot/paper/account-research-stocks.json \
         stock_bot/paper/account-research-crypto.json; do
  [ -e "$f" ] && git add -- "$f"
done
if ! git diff --cached --quiet; then
  git commit -q -m "Research bot: practice cycle (orders, equity, scorecard)"
  for i in 1 2 3; do
    git pull -q --rebase origin master && git push -q origin HEAD:master && break
    sleep 10
  done
fi
echo "=== done"
