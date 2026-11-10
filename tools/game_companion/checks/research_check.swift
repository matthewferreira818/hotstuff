import Foundation
// Research bot tab (pixels/research-tab): defensive parsing, honest status, and the PAUSE push. Offline: fixtures + a throwaway git repo.
var fails = 0
func check(_ ok: Bool,_ what: String) { print(ok ? "PASS" : "FAIL",what); if !ok { fails += 1 } }
let root = URL(fileURLWithPath:CommandLine.arguments[1])          // repo root
func file(_ p: String) -> Data? { try? Data(contentsOf:root.appendingPathComponent("stock_bot/"+p)) }

// 1. Today's real (empty) files from the repo
let real = await ResearchBotData.load { p in file(p).map { .ok($0) } ?? .missing }
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
let failedPause = await ResearchBotData.load { p in p.hasSuffix("PAUSE") ? .failed("no connection") : (file(p).map { .ok($0) } ?? .missing) }
if case .unknown = failedPause.state { check(true,"a pause file that can't be read -> CAN'T TELL, not 'not paused'") } else { check(false,"a pause file that can't be read -> CAN'T TELL, not 'not paused'") }
let auto = await ResearchBotData.load { p in p == "research_bot/AUTO_PAUSE" ? .ok(Data("crypto: daily loss 3.1% (2026-11-12T15:00:00Z)\n".utf8)) : (file(p).map { .ok($0) } ?? .missing) }
check(auto.state == .autoPaused("crypto: daily loss 3.1% (2026-11-12T15:00:00Z)"),"AUTO_PAUSE -> AUTO-PAUSED with its reason")
let both = await ResearchBotData.load { p in p == "PAUSE" || p == "research_bot/AUTO_PAUSE" ? .ok(Data()) : (file(p).map { .ok($0) } ?? .missing) }
if case .paused(let why) = both.state { check(why.contains("all-robots"),"stock_bot/PAUSE counts as paused (and beats auto-pause)") } else { check(false,"stock_bot/PAUSE counts as paused") }

// 5. PAUSE push: only adds stock_bot/research_bot/PAUSE on the remote; the local folder (files, branch, index) is untouched
let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("rbcheck-\(UUID().uuidString)")
try! FileManager.default.createDirectory(at:tmp,withIntermediateDirectories:true)
func sh(_ dir: URL,_ args: [String]) -> ResearchBotData.GitResult { ResearchBotData.runGit(repo:dir)(["-c","user.name=t","-c","user.email=t@t"] + args,[:]) }
let bare = tmp.appendingPathComponent("r.git"), work = tmp.appendingPathComponent("work")
_ = ResearchBotData.runGit(repo:tmp)(["init","-q","--bare","-b","master",bare.path],[:])
_ = ResearchBotData.runGit(repo:tmp)(["clone","-q",bare.path,work.path],[:])
try! "x\n".write(to:work.appendingPathComponent("f.txt"),atomically:true,encoding:.utf8)
_ = sh(work,["add","f.txt"]); _ = sh(work,["commit","-qm","init"]); _ = sh(work,["push","-q","origin","HEAD:master"])
try! "half-done local edit\n".write(to:work.appendingPathComponent("f.txt"),atomically:true,encoding:.utf8)   // another chat's uncommitted work
let headBefore = sh(work,["rev-parse","HEAD"]).out
let git: ResearchBotData.GitRunner = { a,e in ResearchBotData.runGit(repo:work)(["-c","user.name=t","-c","user.email=t@t"] + a,e) }
check(ResearchBotData.pushPause(git:git) == nil,"pause push succeeds")
let remoteFiles = ResearchBotData.runGit(repo:bare)(["ls-tree","-r","--name-only","master"],[:]).out.split(separator:"\n").map(String.init)
check(remoteFiles.sorted() == ["f.txt","stock_bot/research_bot/PAUSE"],"remote master gained exactly the PAUSE file")
let noteText = ResearchBotData.runGit(repo:bare)(["show","master:stock_bot/research_bot/PAUSE"],[:]).out
check(noteText.contains("a person deletes this file"),"PAUSE note says how to undo it")
check(sh(work,["rev-parse","HEAD"]).out == headBefore && sh(work,["status","--porcelain"]).out == "M f.txt","local folder untouched (HEAD, files, index)")
check(!FileManager.default.fileExists(atPath:work.appendingPathComponent("stock_bot").path),"no PAUSE file written into the local folder (a later pull isn't blocked)")
let countBefore = ResearchBotData.runGit(repo:bare)(["rev-list","--count","master"],[:]).out
check(ResearchBotData.pushPause(git:git) == nil && ResearchBotData.runGit(repo:bare)(["rev-list","--count","master"],[:]).out == countBefore,"already paused -> no second commit")
check(sh(work,["for-each-ref","refs/helm"]).out.isEmpty,"temporary ref cleaned up")
let badGit: ResearchBotData.GitRunner = { a,e in ResearchBotData.runGit(repo:work)(a.first == "fetch" ? ["fetch","-q","/nonexistent/x.git","master"] : a,e) }
check(ResearchBotData.pushPause(git:badGit)?.contains("nothing was paused") == true,"no GitHub -> says plainly nothing was paused")
_ = try? FileManager.default.trashItem(at:tmp,resultingItemURL:nil)

// 6. The tab has no order button, keys, live switch or resume
let src = (try? String(contentsOf:root.appendingPathComponent("tools/game_companion/HubResearchBot.swift"),encoding:.utf8)) ?? ""
let dataSrc = (try? String(contentsOf:root.appendingPathComponent("tools/game_companion/ResearchBotData.swift"),encoding:.utf8)) ?? ""
let banned = ["Button(\"Buy","Button(\"Sell","Toggle(","SecureField","Keychain","moomoo","live_auto_trade","Resume","removeItem(at:URL(fileURLWithPath"]
check(!src.isEmpty && banned.allSatisfy { !src.contains($0) },"tab has no buy/sell button, toggle, key field, Moomoo or resume")
check(src.contains("PRACTICE MONEY ONLY") && src.contains("No guesses yet: no trade is a normal day"),"label + honest empty state present")
check(!dataSrc.isEmpty && !dataSrc.contains("--force") && !dataSrc.contains("\"-f\"") && !dataSrc.contains("\"+\\(commit"),"pause push never force-pushes")
print(fails == 0 ? "ALL PASS (research bot tab)" : "\(fails) FAILED (research bot tab)")
exit(fails == 0 ? 0 : 1)
