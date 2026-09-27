# Moomoo setup — the bot on your Mac

One time, about 20 minutes. After that the bot starts itself every
weekday morning. **It starts on Moomoo's paper account: fake money, real
order system.** Real money needs three more switches, all yours (bottom).

Why the Mac: Moomoo's official bot connection goes through a program
called **OpenD**, which you log into yourself, so your password never
touches our code. The bot talks to OpenD on the same Mac. And a real
account's numbers never go near GitHub, where everything is public.

## 1. OpenD (Moomoo's bot connection)

1. Download **moomoo OpenD** for Mac: https://www.moomoo.com/download/OpenAPI
2. Open it and log in with your Moomoo account. You type your password
   into OpenD, never into a chat.
3. The first time, OpenD may show a link to Moomoo's API agreement or
   questionnaire. Open it, read it, agree (your click), then quit OpenD and
   open it again.
4. Leave OpenD open.

## 2. The Mac's tools (Python and git)

Open **Terminal** (Spotlight: type Terminal) and paste:

    xcode-select --install

Click **Install** in the box that pops up. If it says they're already
installed, that's fine. Then paste these two lines, one at a time:

    python3 -m pip install --user --upgrade pip
    python3 -m pip install --user moomoo-api

## 3. The bot

    git clone https://github.com/matthewferreira818/hotstuff.git ~/hotstuff

## 4. Test the connection (trades nothing)

    cd ~/hotstuff && python3 stock_bot/moomoo_broker.py --check

The last line should be **All good — nothing was traded.** If it says it
can't reach OpenD, check OpenD is open and logged in. Tell Claude the last
line (not your account numbers).

## 5. Phone alerts

Type this, replacing `your-topic` with the topic your ntfy app already
uses. Type it yourself; don't send the topic to anyone, Claude included.

    echo 'NTFY_TOPIC=your-topic' > ~/.stockbot-env

## 6. Start it every weekday

    bash ~/hotstuff/stock_bot/mac/install.sh

It says what time it will start (10:20 on Atlantic time: 10 minutes
before New York opens).

## Every day after that

- Mac **plugged in, lid open**, OpenD **open and logged in**. That's all.
- The bot starts itself, watches until the close (5pm our time), and texts
  you every trade. If OpenD is closed or logged out, it texts "not
  connected" instead.
- Its diary: `tail -20 ~/Library/Logs/stockbot.log`
- Turn it off: `bash ~/hotstuff/stock_bot/mac/uninstall.sh`

## Good to know

- **Same stocks and rules as the practice account** (watchlist.json), and
  the same $1,000 bankroll (`bankroll_usd` in moomoo.json), even though
  Moomoo's paper account starts with more.
- **Whole shares only** — Moomoo's bot connection takes no fractions. With
  ~$100 bets, a stock over ~$100 a share can't be bought, and the bot
  skips it. The practice account on GitHub buys fractions, so the two
  will differ; that difference is part of what we're testing.
- **It only touches stocks it bought.** Anything you buy by hand in the
  same account (a fund, say) is invisible to it and never sold.
- Orders are limit orders 0.5% through the price, never market orders.

## Real money — not yet, and never by accident

Three switches, all yours, all needed:

1. `"env": "real"` in stock_bot/moomoo.json
2. `"live_auto_trade": true` — without it, real mode only texts you ideas
   and you place them in the Moomoo app yourself
3. Click **Unlock** in OpenD (your trade password) — Moomoo's own lock,
   which no code can open

The standing plan (CLAUDE.md) keeps the Moomoo money as cash until a
strategy passes the six checks in .claude/skills/stock-council/SKILL.md.
Today none has. With Moomoo's fees, the dip rules lost $3,456 in the
tests; momentum made $2,416 against SPY's $2,118, with bigger swings, which
doesn't pass.
