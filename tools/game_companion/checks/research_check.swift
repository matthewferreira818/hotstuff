import Foundation
// Research bot tab (pixels/research-tab): defensive parsing, honest status, and the PAUSE push. Offline: fixtures + a throwaway git repo.
var fails = 0
func check(_ ok: Bool,_ what: String) { print(ok ? "PASS" : "FAIL",what); if !ok { fails += 1 } }
let root = URL(fileURLWithPath:CommandLine.arguments[1])          // repo root
func file(_ p: String) -> Data? { try? Data(contentsOf:root.appendingPathComponent("stock_bot/"+p)) }

// 1. Today's real (empty) files from the repo
let real = (await ResearchBotData.load { p in file(p).map { .ok($0) } ?? .missing })!
check(real.markets.map(\.key) == ["stock","crypto"],"real scorecard: stocks and crypto, separate, stocks first")
check(real.nothingYet,"real files: honest empty state (no guesses yet)")
check(real.state == .on,"real files: no PAUSE / AUTO_PAUSE -> not paused")
check(real.practiceOnly == true && (real.caps ?? "").contains("10%"),"rules.json read: practice only + plain caps line")
check(real.markets.first?.bar.count == 12 && real.markets.first?.barMet == 0,"evidence bar: 12 items, 0 met, human checks last")
check(real.markets.first?.bar.last?.name.contains("human check") == true,"evidence bar: human checks listed last")
check(ResearchBotData.guessVerdict(real.markets[0]) == "No guesses yet.","verdict says no guesses yet")

// 2. Phase 1b may add fields, nulls and new markets: nothing breaks
let future = """
{"generated":"2026-11-20T12:00:00Z","schema":2,"markets":{"crypto":{"forecasts":"4","graded":3,"hits":2,"hit_rate":0.6667,"brier":{"forecaster":0.21,"coin_flip":0.25,"base_rate":null,"tomorrow_equals_today":0.3,"new_baseline":0.2},
"paper_trades":2,"paper_pnl":-3.5,"cash_pnl":0,"hold_pnl":12.25,"benchmark":"BTC-USD","evidence_bar":{"brand new check":true,"100+ graded forecasts":false},"permutation_p":0.4},
"stock":{"forecasts":null},"fx":{"forecasts":1}}}
"""
let parsed = ResearchBotData.parseScorecard(Data(future.utf8))
check(parsed?.1.map(\.key) == ["stock","crypto","fx"],"new market kept, after stocks and crypto")
let c = parsed?.1[1]
check(c?.forecasts == 4 && c?.brier.baseRate == nil && c?.holdPnl == 12.25,"string number, null and new fields tolerated")
check(c?.bar.first?.name == "100+ graded forecasts" && c?.bar.count == 2,"known bar items first, new ones kept")
check(ResearchBotData.moneyVerdict(c!).contains("behind just holding BTC-USD"),"money verdict is honest when behind holding")
check(ResearchBotData.guessVerdict(c!).contains("too few to tell skill from luck"),"small samples are called luck-prone")
check(ResearchBotData.parseScorecard(Data("not json".utf8)) == nil,"broken scorecard -> nil, not a crash")

// 3. Ledger + orders
let ledger = """
{"kind":"idea","id":"I-1","market":"crypto","text":"x"}
{"kind":"forecast","id":"F-1","asset":"BTC-USD","market":"crypto","direction":"up","probability":0.55,"opens_at":"2026-11-12T14:00:00Z","resolves_at":"2026-11-13T14:00:00Z","reason":"Test reason","act":true,"created":"2026-11-12T13:00:00Z"}
garbage line
{"kind":"forecast","id":"F-2","asset":"SPY","market":"stock","direction":"down","created":"2026-11-14T13:00:00Z"}
{"kind":"no_trade","id":"N-1","market":"stock","reason":"quiet day","created":"2026-11-13T12:00:00Z"}
"""
let l = ResearchBotData.parseLedger(Data(ledger.utf8))
check(l.forecasts.map(\.id) == ["F-2","F-1"] && l.ideas == 1 && l.noTrades.count == 1,"ledger: newest first, garbage line skipped")
let orders = """
{"id":"F-1:buy","side":"buy","asset":"BTC-USD","market":"crypto","dollars":100,"status":"intent","time":"2026-11-12T14:05:00Z"}
{"id":"F-1:buy","side":"buy","asset":"BTC-USD","market":"crypto","dollars":100,"status":"filled","time":"2026-11-12T14:05:00Z"}
{"id":"F-1:sell","side":"sell","asset":"BTC-USD","market":"crypto","status":"intent","time":"2026-11-13T14:05:00Z"}
{"id":"F-1:sell","side":"sell","asset":"BTC-USD","market":"crypto","status":"filled","profit":-1.25,"time":"2026-11-13T14:05:00Z"}
{"id":"F-3:buy","side":"buy","asset":"ETH-USD","market":"crypto","dollars":100,"status":"intent","time":"2026-11-14T14:05:00Z"}
"""
let o = ResearchBotData.parseOrders(Data(orders.utf8))
check(o.count == 3 && o[0].id == "F-3:buy" && o[0].status == "half-done","orders: one row per id; intent-only shows HALF-DONE")
check(o.first { $0.id == "F-1:sell" }?.profit == -1.25,"orders: sell keeps its profit")

// 4. Status is never falsely "not paused"
let failedPause = (await ResearchBotData.load { p in p.hasSuffix("PAUSE") ? .failed("no connection") : (file(p).map { .ok($0) } ?? .missing) })!
if case .unknown = failedPause.state { check(true,"a pause file that can't be read -> CAN'T TELL, not 'not paused'") } else { check(false,"a pause file that can't be read -> CAN'T TELL, not 'not paused'") }
let auto = (await ResearchBotData.load { p in p == "research_bot/AUTO_PAUSE" ? .ok(Data("crypto: daily loss 3.1% (2026-11-12T15:00:00Z)\n".utf8)) : (file(p).map { .ok($0) } ?? .missing) })!
check(auto.state == .autoPaused("crypto: daily loss 3.1% (2026-11-12T15:00:00Z)"),"AUTO_PAUSE -> AUTO-PAUSED with its reason")
let both = (await ResearchBotData.load { p in p == "PAUSE" || p == "research_bot/AUTO_PAUSE" ? .ok(Data()) : (file(p).map { .ok($0) } ?? .missing) })!
if case .paused(let why) = both.state { check(why.contains("all-robots"),"stock_bot/PAUSE counts as paused (and beats auto-pause)") } else { check(false,"stock_bot/PAUSE counts as paused") }

// 6. The tab has no order button, keys, live switch or resume
let src = (try? String(contentsOf:root.appendingPathComponent("tools/game_companion/HubResearchBot.swift"),encoding:.utf8)) ?? ""
let dataSrc = (try? String(contentsOf:root.appendingPathComponent("tools/game_companion/ResearchBotData.swift"),encoding:.utf8)) ?? ""
let banned = ["Button(\"Buy","Button(\"Sell","Toggle(","SecureField","Keychain","moomoo","live_auto_trade","Resume","removeItem(at:URL(fileURLWithPath"]
check(!src.isEmpty && banned.allSatisfy { !src.contains($0) },"tab has no buy/sell button, toggle, key field, Moomoo or resume")
check(src.contains("PRACTICE MONEY ONLY") && src.contains("No guesses yet: no trade is a normal day"),"label + honest empty state present")
let writes = ["Process(","/usr/bin/git",".write(to","write(toFile","createFile","removeItem","URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15)\n   req.httpMethod"]
check(!dataSrc.isEmpty && writes.allSatisfy { !dataSrc.contains($0) && !src.contains($0) },"research tab is read-only: no git, no process, no file writes")
check(src.contains("How to pause") && src.contains("off for now") && !src.contains("coming when the bot runs on a schedule"),"How to pause box + Pause spot off (bot runs hourly now)")
// 7. NB2's v2 catch: a cancelled read (view rebuilt mid-load) is thrown away, never shown as "no connection"
let cancelled = await ResearchBotData.load { p in p.hasSuffix("PAUSE") ? .cancelled : (file(p).map { .ok($0) } ?? .missing) }
check(cancelled == nil,"a cancelled load returns nil (the old snapshot stays on screen)")
let area = (try? String(contentsOf:root.appendingPathComponent("tools/game_companion/HubStockArea.swift"),encoding:.utf8)) ?? ""
check(area.contains("@ObservedObject var research = ResearchBotModel.shared") && src.contains("@ObservedObject var model = ResearchBotModel.shared"),"Research notes and the Research bot tab read the same model (one source)")
check(src.contains("await Task {") && src.contains("if let fresh { snap = fresh }"),"the model loads in an unstructured task and keeps the old snapshot on nil")

// 8. reasons in plain words (raw kept behind "details")
func fc(_ asset: String,_ dir: String,_ reason: String) -> ResearchForecast {
 ResearchForecast(id:"x",asset:asset,market:"stock",direction:dir,probability:0.52,opens:nil,resolves:nil,reason:reason,act:false,created:nil,author:"")
}
let mom = "momentum {\"lookback\": 20, \"prob\": 0.52}, horizon 1 trading days: Up if higher than N bars ago, else down"
check(ResearchBotData.plainReason(fc("SPY","down",mom)) == "Momentum (20-day): SPY is lower than 20 trading days ago, so it guesses down for the next trading day","momentum reason in plain words (NB2's wording)")
let rev = "reversal {\"drop_pct\": 8, \"lookback\": 5, \"prob\": 0.56}, horizon 4 hours: Bounce after a big drop, pullback after a big rise"
check(ResearchBotData.plainReason(fc("BTC-USD","up",rev)) == "Bounce-back (8% over 5 hours): BTC-USD fell more than 8%, so it guesses a bounce up for the next 4 hours","reversal reason in plain words")
let other = "calm_momentum {\"lookback\": 20}, horizon 1 trading days: Up if higher than N bars ago, sitting out wild stretches"
check(ResearchBotData.plainReason(fc("QQQ","up",other)) == "Calm momentum: up if higher than 20 trading days ago, sitting out wild stretches. It guesses up for the next trading day","unknown idea: generic plain words")
var withBot = fc("SPY","down",mom); withBot.botPlain = "SPY is 3.3% lower than 20 trading days ago, so this rule bets it falls."
check(ResearchBotData.why(withBot)?.text == withBot.botPlain && ResearchBotData.why(withBot)?.ours == false,"LC-Research's own plain_reason wins over our reading")
check(ResearchBotData.why(fc("SPY","down",mom))?.ours == true,"older lines without plain_reason: our reading, marked as ours")
let pl = ResearchBotData.parseLedger(Data(#"{"kind":"forecast","id":"F","asset":"SPY","direction":"down","reason":"x","plain_reason":"  Plain words.  "}"#.utf8))
check(pl.forecasts.first?.botPlain == "Plain words.","plain_reason is read from the ledger")
check(ResearchBotData.plainReason(fc("SPY","up","Earnings next week look strong")) == nil,"free-text reason -> nil (shown as written)")
check(src.contains("Technical details") && src.contains("Technical reason only"),"the raw reason stays one click away, labelled Technical reason only (Roxy)")
check(src.contains("PAUSE REQUESTED") && src.contains("not confirmed"),"pause shown as requested, not confirmed (Roxy)")

print(fails == 0 ? "ALL PASS (research bot tab)" : "\(fails) FAILED (research bot tab)")
exit(fails == 0 ? 0 : 1)
