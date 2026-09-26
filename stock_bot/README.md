# Stock bot

You give it the stocks. It watches their prices every 10 seconds while the
US market is open and buys or sells by the rules you set. Anything it does
gets pushed to your phone (the same ntfy alerts the store uses).

**What it is, honestly:** a rules bot. It does what you tell it (for
example, "buy $100 of Apple when it's 8% under its recent high, sell when
I'm up 20% or down 10%"). It doesn't predict the market, and no tool can
promise a profit. It can lose money, so start on paper.

## Setup (about 10 minutes, $0)

1. Sign up at **alpaca.markets**. A paper (fake-money) account comes with
   every signup.
2. In the Alpaca dashboard (Paper side), click **API Keys → Generate**.
3. Open GitHub → this repo → Settings → Secrets and variables → Actions,
   then paste in two secrets yourself:
   - `ALPACA_KEY_ID`
   - `ALPACA_SECRET_KEY`

   (Never paste them in chat. `NTFY_TOPIC` is already there.)
4. Done. The bot starts on the next market-hours run. To test it right
   away, go to Actions → **Stock bot** → Run workflow and tick "dry run".

## Your list: `stock_bot/watchlist.json`

| Setting | Meaning |
|---|---|
| `symbol` | Ticker, e.g. `AAPL`. US-listed stocks and ETFs only (Alpaca doesn't trade the TSX). |
| `buy_below` | Buy when the price is at or under this. `0` = off. |
| `buy_dip_pct` | Buy when it's this % under its 20-day high. `0` = off. |
| `dollars_per_buy` | How much each buy spends (fractional shares are fine). |
| `max_position_dollars` | It never holds more than this in one stock. |
| `take_profit_pct` | Sell it all when you're up this %. |
| `stop_loss_pct` | Sell it all when you're down this %. |
| `sell_above` | Sell it all at or over this price. `0` = off. |

Across the whole list:

- `check_every_seconds` sets how often it looks (default `10`, lowest `5`).
  Set it to `0` to check once an hour instead.
- `max_total_invested` caps the total amount it holds across all stocks.
- `max_orders_per_day` caps how many orders it places per day.
- It trades each stock at most once a day each way, so it won't sell on a
  stop-loss and then buy the same stock back seconds later.
- `"paused": true` stops all trading within about a minute, even
  mid-day. So does adding a file named `stock_bot/PAUSE`. For an
  instant stop, go to Actions → the running **Stock bot** run → Cancel.

## Manual orders

Actions → **Stock bot** → Run workflow → type into `order`:
`BUY AAPL 100` spends $100 on Apple. `SELL AAPL` sells your whole Apple
position.

## Going live with real money

Don't rush this. Run it on paper for a few weeks first.

1. Open and fund a live Alpaca account. Check at signup that they accept
   Canadian residents; availability changes.
2. Add `ALPACA_LIVE_KEY_ID` and `ALPACA_LIVE_SECRET_KEY` as secrets.
3. In watchlist.json, set `"mode": "live"`.

In live mode the bot starts in **you-decide mode**
(`"live_auto_trade": false`). It sends each trade idea to your phone and
places nothing. You place a trade with the Run workflow button. Set
`live_auto_trade` to `true` only if you want it to trade real money on
its own.

## How the 10-second checks work

One GitHub Actions run starts near the 9:30 open and keeps looking every
10 seconds until the 4pm close. A run can only last 6 hours, so a second
run queued behind it finishes the day. In the Actions tab you'll see one
long run per day plus some "cancelled" queued runs. That's normal.
Changes to watchlist.json take effect within about a minute.

Honest limits:
- 10 seconds is fast for a person but slow for Wall Street. Pro firms
  trade in millionths of a second. This bot is for sticking to your
  rules, not for out-racing anyone.
- The free price feed comes from one exchange (IEX). It's real-time, but
  for thinly traded stocks it can lag the full market a little.
- GitHub's terms say Actions are for building and publishing software. A
  bot that runs all day stretches that, and GitHub could throttle or
  flag it. If that happens, we move it to a free Cloudflare Worker that
  checks once a minute.

## Privacy

This repo is public, so its Actions logs are public too. The bot never
writes your balances or trades to the log, only lines like "Placed 1
order(s)". The details go to your phone only.
