# Stock bot

You give it the stocks. It watches their prices every 30 minutes while the
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

- `max_total_invested` caps the total amount it holds across all stocks.
- `max_orders_per_day` caps how many orders it places per day.
- It buys each stock at most once a day.
- `"paused": true` stops all trading. So does adding a file named
  `stock_bot/PAUSE`.

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

## Privacy

This repo is public, so its Actions logs are public too. The bot never
writes your balances or trades to the log, only lines like "Placed 1
order(s)". The details go to your phone only.
