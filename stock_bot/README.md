# Stock bot

You give it the stocks. It watches their prices every 10 seconds while the
US market is open and buys or sells by the rules you set. Anything it does
gets pushed to your phone (the same ntfy alerts the store uses).

**What it is, honestly:** a rules bot. It does what you tell it (for
example, "buy $100 of Apple when it's 8% under its recent high, sell when
I'm up 20% or down 10%"). It doesn't predict the market, and no tool can
promise a profit. It can lose money, so start on paper.

## Setup: nothing to do

The bot trades a **practice account we built ourselves**
(`stock_bot/paper_broker.py`), because Alpaca won't open accounts for
Canadian tax residents, not even practice ones.

- **Real live prices** from Yahoo's free feed, about 1 minute fresh.
- **Fake money**: it starts with $1,000.
- **Real-world costs on every trade** (`paper_costs` in watchlist.json):
  Moomoo Canada's US-stock pricing, US$1.99 minimum per order (more above
  ~200 shares), plus fills 0.1% worse than the quote. A $100 buy-and-sell
  costs about $4, so a stock has to rise ~4% just to break even. The
  practice account is in US dollars.
- **Bets sized from the account** (`sizing`): each buy is 10% of the
  whole account (cash + stocks), never under $100 (smaller and the fees
  eat it), never over 20% in one stock, never more than the cash on hand.
  As deposits grow the account, the bets grow and the fees matter less.
- **Payday deposits** (`practice_deposits`): mirrors Matthew adding
  $100 CAD per paycheque, converted to US dollars at the day's rate. The
  "same money in SPY" comparison buys SPY with each deposit too, so it
  stays fair. Set `first` to the next payday to switch it on.
- **A public record**: the account lives in `stock_bot/paper/account.json`
  and is saved to GitHub after every trade, so nobody can quietly fix
  the numbers later.

How it's doing, compared with putting the same $1,000 in SPY:
`python stock_bot/paper_broker.py --status` (or just ask Claude).

Manual orders (below) only apply to a real broker. The practice account
trades by the rules alone.

## Your list: `stock_bot/watchlist.json`

| Setting | Meaning |
|---|---|
| `symbol` | Ticker, e.g. `AAPL`. US-listed stocks and ETFs only. |
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

Don't rush this. The council's standing rule has six conditions (20+
graded picks, beating SPY after costs, the typical pick winning, no
blow-through losses, winning unseen walk-forward windows, the Practice
Desk ahead of SPY). They're listed in `.claude/skills/stock-council/SKILL.md`.

## Research

`python stock_bot/backtest.py --why` explains, trade by trade, why the
rules beat or trail just holding. `--walk-forward` tunes the rules on 6
months and tests them on the next 3 they never saw. Reports go to
`stock_bot/research/`. The live bot and the backtests share one rulebook
(`strategy.py`), so what's tested is what trades.

Alpaca's real-money accounts aren't open to Canadians. **Moomoo Canada**
is the chosen route: its OpenAPI lets a bot trade US stocks and ETFs from
a Moomoo CA account, at no extra cost. It needs moomoo's OpenD program
logged in during market hours, and it has a practice mode to test in
first. Matthew applied on 2026-09-27; approval takes up to 3 business
days. The fallback is **Interactive Brokers Canada**: it allows automated
trading and TFSAs. Its connection needs an IBKR program logged in during market
hours, which means a computer left on or a small rented server. When
the time comes, Claude builds that connection.

The Alpaca code stays in place for anyone who can use it
(`"broker": "alpaca"`, keys as GitHub secrets, `"mode": "live"`).
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
- The practice account's prices come from Yahoo's free feed, about a
  minute behind. (With Alpaca it would be the IEX feed.)
- GitHub's terms say Actions are for building and publishing software. A
  bot that runs all day stretches that, and GitHub could throttle or
  flag it. If that happens, we move it to a free Cloudflare Worker that
  checks once a minute.

## Privacy

This repo is public, so its Actions logs are public too. The bot never
writes your balances or trades to the log, only lines like "Placed 1
order(s)". The details go to your phone only.
