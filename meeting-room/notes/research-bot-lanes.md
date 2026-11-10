# Research bot: who does what (lanes), PRACTICE MONEY ONLY

_Set 2026-11-10 ~9:30 AM by Friday (backup manager). Matthew: "make sure no one conflicts, lets get everyone on this so it gets done faster."_
_Spec: meeting-room/notes/research-bot.md. Real money stays OFF (council NO-GO; re-vote ~Dec 1)._

**Update Tue Nov 10 ~7 PM (Matthew: all stock bots under one new chat; Roxy keeps sales):** **LC-Stocks** (Local Claude) now owns the whole
stock-bot side: the engine lane LC-Research had (LC-Research is parked), coordination of this file's lanes, the 7 practice robots and the Robot Desk.
Roxy's review in Helm-Private `research-bot/ideas-list.md` is LC-Stocks' checklist. Grok still writes forecasts; NB2 still gates and merges.

**One owner per lane, one owner per file.** If your work needs a file in someone else's lane, message that owner; don't edit it.

| Who | Lane | Owns (only these) | Status |
|---|---|---|---|
| **LC-Stocks** (was LC-Research, parked 11-10) | The bot engine (history replay, walk-forward, guess-maker, per-bet stop, run lock, Mac schedule), plus coordinating every lane here | `stock_bot/research_bot/*` code + tests (1b merged; new work on `stocks/*` branches) | 🔨 next: lock idea 2's no-look-ahead in a test, pre-register grids, count every setting tried |
| LC-Pixels | The Helm "Research bot" tab (scorecard, guesses, practice orders, status, Pause only) | `tools/game_companion/` research-tab files, branch `pixels/research-tab` | ✅ merged ce1a7e4; design partner now LC-Stocks (was Roxy) |
| NB2 | Gate + merge both branches; council synthesis | merges to master | 🔨 |
| ~~LC-Manager~~ (parked 11-10) | Quality gate moved to NB2 | — | parked |
| **LC-Trends (new)** | **Market connections check, look-only:** which free price feeds we can rely on (Yahoo now, CoinGecko free tier as backup: limits, delays, terms), and which crypto exchanges legally serve New Brunswick with an official key that can be set to trade-only / no withdrawals (fees, rules). No sign-ups, no logins, no keys. | Helm-Private `research-bot/connections.md` | ✅ done (e8295f3, Friday checked; backup-feed call now LC-Stocks'; LC-Trends parked 11-10) |
| **Roxy (new)** | **Idea list:** 10 testable ideas for stocks and crypto, each with what would prove it wrong, the data it needs, and why it might survive fees. Draft only: she does NOT write to the ledger. Loose deadline: she is also LC-Pixels' design partner on the Stock bot revamp. | Helm-Private `research-bot/ideas-list.md` ("Roxy's notes" section is hers) | ✅ first 10 written by Friday as backup (0049362; the Switchboard handed it over unanswered). Roxy reviewed it 11-10 (Roxy's notes); she is on sales now, so new ideas come through LC-Stocks |

**Replay result, Nov 10 (LC-Research, claude/research-bot-1b @ 96ab6dc, Friday checked the table):** ideas 1-8 → 0 of 16 new variants passed (0 of 32 tried in all). Closest: crypto squeeze 5d, crypto crossover and stock crossover each beat holding by a little on 62-207 trades, but failed the typical-trade, blow-through and most-windows checks. 9-10 parked. Feeds: Yahoo stays for now (its terms flagged to NB2, since that affects all 7 robots); CoinGecko is a later option and needs Matthew's key.
| Grok (from Nov 11) | Turns ideas into forecasts in the ledger (via `forecasts.py`, committed before the window opens) | `forecasts.jsonl` entries | Nov 11 |
| Friday | Supervisor: keeps this lanes file true, checks each finished lane against the spec, reads the scorecard, PAUSE/STOP only, calls out "lucky week" pressure | this file | 🔨 |

## Ground rules for every lane
- Only `forecasts.py` writes the ledger, and only LC-Stocks (tests) or Grok (real forecasts) run it. Nobody hand-edits `forecasts.jsonl`.
- **Ideas count only after the history replay**, and EVERY idea tried goes into the "ideas tried" count, winners and losers alike (the council's multiple-testing rule). Nothing goes live in `forward.json` without NB2's gate.
- **Hand-offs:** ideas (Roxy's list, Friday's, Grok's) → LC-Stocks turns each into a plain past-prices-only function in `stock_bot/research_bot/ideas.py` and replays it. LC-Trends' feed findings → LC-Stocks decides whether to wire in a backup feed (its code).
- Nobody edits `rules.json` / `rules.lock`. Rule changes go in as proposals: NB2 gates them and Matthew says GO.
- No exchange or broker accounts, no keys, no live switches. Matthew alone does those, and only after the evidence bar in the spec.
- Anything private (accounts, balances, EI/tax) goes to Helm-Private `research-bot/` only, never this public repo.
- When you finish: commit + push, update your board line, and post one tagged line in issue 15.
