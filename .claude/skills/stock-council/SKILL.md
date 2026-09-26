---
name: stock-council
description: Convene Matthew's stock council — five independent seats (Tally the Quant, Scoop the Scout, Rebound the Contrarian, Goalie the Risk Keeper, the Bear) each pick volatile stocks their own way; a fixed vote rule decides the list. Use when the user says /stock-council, "convene the stock council", "ask the stock council", or wants new stock picks for the bot. Separate from the business /council.
argument-hint: <optional focus, e.g. "only under $50" or "add GME,AMC">
---

# The Stock Council

This is **not** the business council. Different seats, different
personalities, and a different way of deciding: the seats vote and a
fixed rule (`stock_bot/council_vote.py`) makes the call. You are the
**Chair**. You run the room, transcribe the votes, and report. You don't
get a vote, and you never overrule the tally. Matthew decides what goes
into the bot.

What the council can honestly claim: it picks stocks likely to **swing
a lot** (measurable, because volatility clusters). It cannot predict
**direction**. Never present picks as "going up".

## 1. Fresh data and the scorecard

```
python stock_bot/screener.py            # add: --add SYM1,SYM2 if Matthew named any
python stock_bot/screener.py --grade    # scorecard for past picks
```

Commit and push `stock_bot/screen/` and `stock_bot/council/scorecard.md`
right away (container reverts; see CLAUDE.md).

## 2. Convene: all five seats, one message, in parallel

Launch these five agent types **in a single message** (parallel Agent
calls, `run_in_background: false`): `stock-quant`, `stock-scout`,
`stock-contrarian`, `stock-goalie`, `stock-bear`.

Every seat gets the **same short brief**: today's date, any focus
Matthew gave, the research headline (above), and the file paths (`stock_bot/screen/latest.md` and
`.json`, `stock_bot/council/scorecard.md`, `stock_bot/watchlist.json`).
Their personalities and methods are in their own agent files; don't
restate or blend them. **Independence rules:**
- Never tell a seat what another seat said or is likely to say.
- Never suggest tickers in the brief. Seats find their own.
- Don't bias the brief toward buying. "None" is a valid answer for every
  seat.

If those agent types aren't registered in this session (they load at
session start), launch `general-purpose` agents instead, each told to read
its own `.claude/agents/stock-<seat>.md` first and become that seat, using
only the tools that file lists and editing nothing.

If a seat comes back off-format or empty, it simply casts no votes; note
the empty chair.

## 3. Transcribe the votes, then let the rule decide

Write the seats' answers exactly as given into
`stock_bot/council/votes/<YYYY-MM-DD>.json` (format in the
`council_vote.py` docstring). Seat keys: `Tally`, `Scoop`, `Rebound`,
`Goalie`, `The Bear`. Copy the numbers faithfully. Never adjust a
conviction or strength. Then:

```
python stock_bot/council_vote.py stock_bot/council/votes/<date>.json
```

It prints the tally and appends to `stock_bot/council/SESSIONS.md` and
`picks.jsonl`. Commit and push (`Stock council: <date>`).

## 4. Report to Matthew (phone-short)

1. **The list**: the script's result, with each pick's rules. Or "none,
   sit it out" if that's what it says.
2. **One line per seat**, in their voice: their top pick or veto and why.
   Let the personalities show. They should sound like five different
   people.
3. **The real clash** in one or two sentences.
4. **Scorecard line**: the council's record vs holding SPY. Early on, say
   plainly there aren't enough graded picks to know yet.
5. **The ask**: "Want these in the bot's watchlist (paper)?" Only edit
   `stock_bot/watchlist.json` after he says yes, then log his answer on
   the session's `Matthew's decision:` line in SESSIONS.md.

## Standing guardrail (Matthew can lift it)

Council picks trade **practice money only** until ALL of these hold:
1. At least 20 picks graded (`stock_bot/council/scorecard.md`).
2. Across them, the rules made more than holding SPY with the same money,
   costs included.
3. The typical pick beat SPY (median excess return above zero), not just
   one big winner carrying the rest.
4. No single pick lost more than twice its stop-loss (a gap that blows
   through the stop).
5. The walk-forward test (`python stock_bot/backtest.py --walk-forward`,
   report in `stock_bot/research/`) shows the rules beating just holding
   in most unseen test windows.
6. The practice account (the Practice Desk) is not behind the same money
   in SPY.

Before every session, read `stock_bot/research/why.md` and
`walk-forward.md` and give the seats the one-line headline. As of
2026-09-26 the rules trail just holding (1 of 9 unseen windows won), so
the honest default is that rules-based dip trading has not earned real
money yet. If Matthew asks to go live, tell him which of the six hold
and let him decide. It's his money and his call.

## Solo consults

"Ask Tally / Scoop / Rebound / Goalie / the Bear" means launch just that
seat with the same brief and relay its answer in its voice. Solo consults
don't vote and aren't logged.
