import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The research bot's tab on the Stock bot page (job from NB2, 2026-11-10). PRACTICE MONEY ONLY.
// Reads the bot's own files on GitHub master (stock_bot/research_bot/, public repo) and shows them in plain words.
// Read defensively: LC-Research is still adding fields (phase 1b), so every field may be missing, null or new.
// The ONLY thing this file can change is adding the bot's PAUSE file. No order, no keys, no real-money switch:
// there is no code here that can place an order, and nothing here removes a pause (a person does that).

struct ResearchBrier {
 var forecaster: Double?
 var coinFlip: Double?
 var baseRate: Double?
 var tomorrow: Double?
}

struct ResearchMarket: Identifiable {
 var id: String { key }
 var key: String               // "stock" or "crypto"
 var title: String             // "Stocks" or "Crypto"
 var ideas = 0
 var forecasts = 0
 var graded = 0
 var open = 0
 var late = 0
 var noTradeDays = 0
 var hits = 0
 var hitRate: Double?
 var luckP: Double?
 var brier = ResearchBrier()
 var paperTrades = 0
 var tradeSize: Double?
 var paperPnl: Double?
 var cashPnl: Double?
 var holdPnl: Double?
 var benchmark = ""
 var median: Double?
 var worst: Double?
 var withoutBest: Double?
 var spanDays: Double?
 var bar: [(name: String,met: Bool)] = []
 var barMet: Int { bar.filter { $0.met }.count }
}

struct ResearchForecast: Identifiable {
 var id: String
 var asset: String
 var market: String
 var direction: String
 var probability: Double?
 var opens: Date?
 var resolves: Date?
 var reason: String
 var act: Bool
 var created: Date?
 var author: String
}

struct ResearchNoTrade: Identifiable {
 var id: String
 var market: String
 var reason: String
 var created: Date?
}

struct ResearchOrder: Identifiable {
 var id: String
 var side: String
 var asset: String
 var market: String
 var dollars: Double?
 var time: Date?
 var status: String           // "filled", "failed" or "half-done"
 var profit: Double?
 var error: String?
}

enum ResearchState: Equatable {
 case paused(String)          // a person's PAUSE file (this bot, or all robots)
 case autoPaused(String)      // the bot paused itself; a person reads why and deletes AUTO_PAUSE
 case on
 case unknown(String)         // couldn't read GitHub
}

struct ResearchSnapshot {
 var loaded: Date?
 var generated: Date?
 var markets: [ResearchMarket] = []
 var forecasts: [ResearchForecast] = []
 var noTrades: [ResearchNoTrade] = []
 var orders: [ResearchOrder] = []
 var ideaCount = 0
 var botPause: String?        // stock_bot/research_bot/PAUSE contents ("" if empty) or nil
 var allPause: String?        // stock_bot/PAUSE (every robot)
 var autoPause: String?
 var practiceOnly: Bool?
 var caps: String?
 var problems: [String] = []
 var pauseUnknown = false     // a pause file couldn't be checked: never shown as "not paused"
 var state: ResearchState {
  if let p = botPause { return .paused(p.isEmpty ? "The research bot's PAUSE file is there." : "The research bot's PAUSE file is there: \(p)") }
  if let p = allPause { return .paused(p.isEmpty ? "The all-robots PAUSE file (stock_bot/PAUSE) is there." : "The all-robots PAUSE file is there: \(p)") }
  if let a = autoPause { return .autoPaused(a.isEmpty ? "The bot paused itself (no reason written)." : a) }
  if pauseUnknown { return .unknown("Couldn't check the pause files on GitHub, so this can't say whether it's paused. Try Refresh.") }
  return .on
 }
 // Honest empty state: nothing written yet in either market.
 var nothingYet: Bool { forecasts.isEmpty && noTrades.isEmpty && markets.allSatisfy { $0.forecasts == 0 && $0.noTradeDays == 0 } }
}

enum ResearchFetch { case ok(Data), missing, failed(String) }

enum ResearchBotData {
 static let base = "https://raw.githubusercontent.com/matthewferreira818/hotstuff/master/stock_bot/"
 static let pausePath = "stock_bot/research_bot/PAUSE"
 static let barOrder = ["100+ graded forecasts","60+ days of forward forecasting","a down market happened during it",
  "Brier beats all three baselines","not likely luck (p < 0.05)","paper P&L after costs beats cash",
  "paper P&L after costs beats buy-and-hold","typical trade wins (median > 0)","still ahead without the best trade"]

 // MARK: small readers (every one tolerates missing/null/wrong-type)
 static func num(_ v: Any?) -> Double? {
  if v is NSNull { return nil }
  if let n = v as? NSNumber { return n.doubleValue }
  if let s = v as? String { return Double(s) }
  return nil
 }
 static func int(_ v: Any?) -> Int { Int(num(v) ?? 0) }
 static func str(_ v: Any?) -> String { (v as? String) ?? "" }
 static func date(_ v: Any?) -> Date? {
  guard let s = v as? String, !s.isEmpty else { return nil }
  let f = ISO8601DateFormatter()
  if let d = f.date(from:s) { return d }
  f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
  return f.date(from:s)
 }
 static func jsonLines(_ data: Data) -> [[String:Any]] {
  String(decoding:data,as:UTF8.self).split(whereSeparator:\.isNewline).compactMap {
   (try? JSONSerialization.jsonObject(with:Data($0.utf8))) as? [String:Any]
  }
 }

 // MARK: scorecard.json
 static func parseScorecard(_ data: Data) -> (Date?,[ResearchMarket])? {
  guard let root = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return nil }
  let mk = root["markets"] as? [String:Any] ?? [:]
  var out: [ResearchMarket] = []
  // Stocks first, then crypto, then anything new LC-Research adds later.
  let keys = ["stock","crypto"].filter { mk[$0] != nil } + mk.keys.filter { $0 != "stock" && $0 != "crypto" }.sorted()
  for key in keys {
   guard let m = mk[key] as? [String:Any] else { continue }
   var r = ResearchMarket(key:key,title:key == "stock" ? "Stocks" : key == "crypto" ? "Crypto" : key.capitalized)
   r.ideas = int(m["ideas_tried"]); r.forecasts = int(m["forecasts"]); r.graded = int(m["graded"])
   r.open = int(m["open"]); r.late = int(m["late_not_counted"]); r.noTradeDays = int(m["no_trade_days"])
   r.hits = int(m["hits"]); r.hitRate = num(m["hit_rate"]); r.luckP = num(m["luck_p_value"])
   let b = m["brier"] as? [String:Any] ?? [:]
   r.brier = ResearchBrier(forecaster:num(b["forecaster"]),coinFlip:num(b["coin_flip"]),baseRate:num(b["base_rate"]),tomorrow:num(b["tomorrow_equals_today"]))
   r.paperTrades = int(m["paper_trades"]); r.tradeSize = num(m["trade_size"]); r.paperPnl = num(m["paper_pnl"])
   r.cashPnl = num(m["cash_pnl"]); r.holdPnl = num(m["hold_pnl"]); r.benchmark = str(m["benchmark"])
   r.median = num(m["median_trade"]); r.worst = num(m["worst_trade"]); r.withoutBest = num(m["pnl_without_best"])
   r.spanDays = num(m["span_days"])
   let bar = m["evidence_bar"] as? [String:Any] ?? [:]
   let order = barOrder.filter { bar[$0] != nil } + bar.keys.filter { !barOrder.contains($0) }.sorted { a,b in
    a.contains("human check") == b.contains("human check") ? a < b : !a.contains("human check") }
   r.bar = order.map { ($0,(bar[$0] as? Bool) ?? ((bar[$0] as? NSNumber)?.boolValue ?? false)) }
   out.append(r)
  }
  return (date(root["generated"]),out)
 }

 // MARK: forecasts.jsonl (ideas, forecasts, no-trade days)
 static func parseLedger(_ data: Data) -> (forecasts:[ResearchForecast],noTrades:[ResearchNoTrade],ideas:Int) {
  var f: [ResearchForecast] = [], n: [ResearchNoTrade] = [], ideas = 0
  for (i,l) in jsonLines(data).enumerated() {
   switch str(l["kind"]) {
   case "idea": ideas += 1
   case "no_trade":
    n.append(ResearchNoTrade(id:str(l["id"]).isEmpty ? "nt\(i)" : str(l["id"]),market:str(l["market"]),reason:str(l["reason"]),created:date(l["created"])))
   case "forecast":
    f.append(ResearchForecast(id:str(l["id"]).isEmpty ? "f\(i)" : str(l["id"]),asset:str(l["asset"]),market:str(l["market"]),
     direction:str(l["direction"]),probability:num(l["probability"]),opens:date(l["opens_at"]),resolves:date(l["resolves_at"]),
     reason:str(l["reason"]),act:(l["act"] as? Bool) ?? false,created:date(l["created"]),author:str(l["author"])))
   default: break
   }
  }
  let newest: (Date?,Date?) -> Bool = { ($0 ?? .distantPast) > ($1 ?? .distantPast) }
  return (f.sorted { newest($0.created,$1.created) },n.sorted { newest($0.created,$1.created) },ideas)
 }

 // MARK: orders.jsonl: one row per order id, its final word (filled / failed), or "half-done" if only the intent was logged.
 static func parseOrders(_ data: Data) -> [ResearchOrder] {
  var byId: [String:ResearchOrder] = [:], first: [String:Int] = [:]
  for (i,l) in jsonLines(data).enumerated() {
   let id = str(l["id"]); guard !id.isEmpty else { continue }
   let status = str(l["status"])
   var o = byId[id] ?? ResearchOrder(id:id,side:str(l["side"]),asset:str(l["asset"]),market:str(l["market"]),dollars:num(l["dollars"]),
    time:date(l["time"]),status:"half-done",profit:nil,error:nil)
   if first[id] == nil { first[id] = i }
   if status == "filled" || status == "failed" {
    o.status = status; o.profit = num(l["profit"]); o.error = l["error"] as? String
    if let t = date(l["time"]) { o.time = t }
   }
   byId[id] = o
  }
  return byId.values.sorted { ($0.time ?? .distantPast,first[$0.id] ?? 0) > ($1.time ?? .distantPast,first[$1.id] ?? 0) }
 }

 // MARK: rules.json -> one plain line of caps, and whether it still says practice only.
 static func parseRules(_ data: Data) -> (Bool?,String?) {
  guard let r = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return (nil,nil) }
  var parts: [String] = []
  if let v = num(r["max_position_pct"]) { parts.append("at most \(clean(v))% of the account per trade") }
  if let v = num(r["max_open_positions"]) { parts.append("at most \(clean(v)) open at once") }
  if let v = num(r["max_new_orders_per_day"]) { parts.append("at most \(clean(v)) new a day") }
  if let d = num(r["daily_loss_cap_pct"]), let w = num(r["weekly_drawdown_cap_pct"]) {
   parts.append("it pauses itself after a \(clean(d))% loss in a day or a \(clean(w))% drop in a week")
  }
  return ((r["practice_only"] as? Bool),parts.isEmpty ? nil : parts.joined(separator:", ").prefix(1).uppercased() + parts.joined(separator:", ").dropFirst() + ".")
 }

 // MARK: one load of everything. `load` gets a path under stock_bot/ (tests pass fixtures).
 static func load(_ load: (String) async -> ResearchFetch) async -> ResearchSnapshot {
  var s = ResearchSnapshot(loaded:Date())
  func text(_ d: Data) -> String { String(decoding:d,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines) }
  switch await load("research_bot/scorecard.json") {
  case .ok(let d): if let (g,m) = parseScorecard(d) { s.generated = g; s.markets = m } else { s.problems.append("The scorecard file couldn't be read.") }
  case .missing: s.problems.append("No scorecard file yet.")
  case .failed(let why): s.problems.append("Couldn't load the scorecard (\(why)).")
  }
  if case .ok(let d) = await load("research_bot/forecasts.jsonl") { (s.forecasts,s.noTrades,s.ideaCount) = parseLedger(d) }
  if case .ok(let d) = await load("research_bot/orders.jsonl") { s.orders = parseOrders(d) }
  if case .ok(let d) = await load("research_bot/rules.json") { (s.practiceOnly,s.caps) = parseRules(d) }
  // Pause files: a failed read is NOT "not paused", so say we couldn't tell.
  for (path,keyPath) in [("research_bot/PAUSE",\ResearchSnapshot.botPause),("PAUSE",\ResearchSnapshot.allPause),("research_bot/AUTO_PAUSE",\ResearchSnapshot.autoPause)] {
   switch await load(path) {
   case .ok(let d): s[keyPath:keyPath] = String(text(d).prefix(300))
   case .missing: break
   case .failed(let why): s.problems.append("Couldn't check \(path) (\(why))."); s.pauseUnknown = true
   }
  }
  return s
 }

 static func fetchGitHub(_ path: String) async -> ResearchFetch {
  guard let url = URL(string:base + path + "?nc=\(Int(Date().timeIntervalSince1970))") else { return .failed("bad address") }
  var req = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15)
  req.setValue("TheHelm",forHTTPHeaderField:"User-Agent")
  do {
   let (data,resp) = try await URLSession.shared.data(for:req)
   let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
   if code == 200 { return .ok(data) }
   if code == 404 { return .missing }
   return .failed("GitHub said \(code)")
  } catch { return .failed("no connection") }
 }

 // MARK: plain words
 static func clean(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format:"%.1f",v) }
 static func money(_ v: Double?) -> String {
  guard let v else { return "-" }
  let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.currencySymbol = "$"; f.maximumFractionDigits = 2; f.minimumFractionDigits = 2
  return f.string(from:NSNumber(value:v)) ?? String(format:"$%.2f",v)
 }
 static func signed(_ v: Double?) -> String {
  guard let v else { return "-" }
  return (v > 0 ? "+" : v < 0 ? "-" : "") + money(abs(v))
 }
 static func brier(_ v: Double?) -> String { v.map { String(format:"%.3f",$0) } ?? "-" }

 // One sentence on the guesses. Small samples are said out loud.
 static func guessVerdict(_ m: ResearchMarket) -> String {
  if m.graded == 0 { return m.forecasts == 0 ? "No guesses yet." : "\(m.forecasts) guess\(m.forecasts == 1 ? "" : "es") written, none graded yet (their windows haven't closed)." }
  let small = m.graded < 30 ? " Only \(m.graded) graded: that's too few to tell skill from luck." : ""
  guard let f = m.brier.forecaster else { return "\(m.graded) graded." + small }
  let base = [m.brier.coinFlip,m.brier.baseRate,m.brier.tomorrow].compactMap { $0 }
  if base.isEmpty { return "\(m.graded) graded." + small }
  if base.allSatisfy({ f < $0 }) { return "Beating all \(base.count) simple guesses so far." + small }
  if f >= (m.brier.coinFlip ?? 0.25) { return "Not beating a coin flip yet." + small }
  return "Beating a coin flip, but not every simple guess yet." + small
 }

 static func moneyVerdict(_ m: ResearchMarket) -> String {
  if m.paperTrades == 0 { return "No practice trades yet." }
  let pnl = m.paperPnl ?? 0
  var s = "\(m.paperTrades) practice trade\(m.paperTrades == 1 ? "" : "s"), \(signed(pnl)) after fees. "
  s += pnl > (m.cashPnl ?? 0) ? "Ahead of doing nothing" : "Not ahead of doing nothing"
  if let h = m.holdPnl { s += pnl > h ? ", and ahead of just holding \(m.benchmark.isEmpty ? "the benchmark" : m.benchmark)." : ", and behind just holding \(m.benchmark.isEmpty ? "the benchmark" : m.benchmark)." } else { s += "." }
  return s
 }

 // MARK: PAUSE. Adds ONE file (stock_bot/research_bot/PAUSE) to GitHub master as its own commit, built with git's plumbing so
 // the shared ~/Claude/hotstuff folder (its files, branch and index) is never touched: other chats may be working in it.
 // Never force-pushes; if master moved meanwhile, it rebuilds on the new master once more. It cannot remove a pause.
 struct GitResult { var code: Int32; var out: String }
 typealias GitRunner = ([String],[String:String]) -> GitResult

 static func runGit(repo: URL) -> GitRunner {
  { args,env in
   let p = Process(); p.executableURL = URL(fileURLWithPath:"/usr/bin/git")
   p.arguments = ["-C",repo.path] + args
   var e = ProcessInfo.processInfo.environment; e["GIT_TERMINAL_PROMPT"] = "0"
   for (k,v) in env { e[k] = v }
   p.environment = e
   let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
   do { try p.run() } catch { return GitResult(code:-1,out:"git didn't start") }
   let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
   return GitResult(code:p.terminationStatus,out:String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines))
  }
 }

 static func pauseNote(_ now: Date) -> String {
  "Paused from The Helm (Stock bot page, Research bot tab) at \(ISO8601DateFormatter().string(from:now)).\n" +
  "Nothing runs while this file is here. To let the research bot run again, a person deletes this file (the Helm has no start button on purpose).\n"
 }

 // Returns nil on success, or a plain-words reason it didn't happen.
 static func pushPause(git: GitRunner,remote: String = "origin",branch: String = "master",now: Date = Date(),tmp: URL = FileManager.default.temporaryDirectory) -> String? {
  let ref = "refs/helm/research-pause-base"
  defer { _ = git(["update-ref","-d",ref],[:]) }
  for attempt in 0..<2 {
   guard git(["fetch","-q",remote,"+refs/heads/\(branch):\(ref)"],[:]).code == 0 else { return "Couldn't reach GitHub, so nothing was paused. Try again in a minute." }
   if git(["cat-file","-e","\(ref):\(pausePath)"],[:]).code == 0 { return nil }     // already paused on GitHub
   let note = tmp.appendingPathComponent("helm-research-pause-\(UUID().uuidString).txt")
   let index = tmp.appendingPathComponent("helm-research-index-\(UUID().uuidString)")
   defer { try? FileManager.default.removeItem(at:note); try? FileManager.default.removeItem(at:index) }
   guard (try? pauseNote(now).write(to:note,atomically:true,encoding:.utf8)) != nil else { return "Couldn't write the note. Nothing was paused." }
   let env = ["GIT_INDEX_FILE":index.path]
   let blob = git(["hash-object","-w",note.path],[:])
   guard blob.code == 0, git(["read-tree",ref],env).code == 0,
         git(["update-index","--add","--cacheinfo","100644,\(blob.out),\(pausePath)"],env).code == 0 else { return "git couldn't build the pause. Nothing was paused." }
   let tree = git(["write-tree"],env)
   guard tree.code == 0 else { return "git couldn't build the pause. Nothing was paused." }
   let commit = git(["commit-tree",tree.out,"-p",ref,"-m","Research bot: PAUSE from The Helm (Research bot tab)\n\nAdds stock_bot/research_bot/PAUSE only. Nothing runs while it is there; a person deletes it to resume."],[:])
   guard commit.code == 0 else { return "git couldn't make the commit (\(commit.out.prefix(80))). Nothing was paused." }
   if git(["push","-q",remote,"\(commit.out):refs/heads/\(branch)"],[:]).code == 0 { return nil }
   if attempt == 1 { return "GitHub didn't take the pause (someone pushed at the same moment, or the login needs a look). Nothing was paused; try again." }
  }
  return "Nothing was paused."
 }
}
