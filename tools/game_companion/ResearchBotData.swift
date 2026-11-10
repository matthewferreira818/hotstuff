import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The research bot's tab on the Stock bot page (job from NB2, 2026-11-10). PRACTICE MONEY ONLY.
// Reads the bot's own files on GitHub master (stock_bot/research_bot/, public repo) and shows them in plain words.
// Read defensively: LC-Research is still adding fields (phase 1b), so every field may be missing, null or new.
// READ-ONLY (NB2's call, 2026-11-10): nothing here writes anything. No order, no keys, no real-money switch, no pause/resume.
// A Pause button comes once the bot runs on a schedule, writing the file exactly where that runner looks.

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
 var ideaStatus: [String:(status: String,label: String?)] = [:]   // by_idea.<id>.replay_status / label (LC-Research 1b)
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
 var botPlain: String? = nil   // LC-Research's own `plain_reason` (from 1b on); older lines don't have it
 var idea: String = ""
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
 var replayStatus: String? = nil   // PASS / DEAD / untested (LC-Research 1b)
 var label: String? = nil
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
 // NB2: anything from an idea that failed the replay carries a plain warning. nil = nothing to say.
 static let deadDefault = "from an idea that failed the replay: data only, not a signal"
 func deadLabel(idea: String) -> String? {
  for m in markets { if let e = m.ideaStatus[idea], e.status.uppercased() == "DEAD" { return e.label ?? ResearchSnapshot.deadDefault } }
  return nil
 }
 func deadLabel(order o: ResearchOrder) -> String? {
  if o.replayStatus?.uppercased() == "DEAD" { return o.label ?? ResearchSnapshot.deadDefault }
  let fid = o.id.split(separator:":").first.map(String.init) ?? ""
  return forecasts.first { $0.id == fid }.flatMap { deadLabel(idea:$0.idea) }
 }
 // Honest empty state: nothing written yet in either market.
 var nothingYet: Bool { forecasts.isEmpty && noTrades.isEmpty && markets.allSatisfy { $0.forecasts == 0 && $0.noTradeDays == 0 } }
}

enum ResearchFetch { case ok(Data), missing, failed(String), cancelled }

enum ResearchBotData {
 static let base = "https://raw.githubusercontent.com/matthewferreira818/hotstuff/master/stock_bot/"

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
 // Where each evidence-bar key first appears after "<market>" … "evidence_bar" in the raw JSON text.
 static func keyPositions(_ raw: String,market: String,keys: [String]) -> [String:Int] {
  guard let m = raw.range(of:"\"\(market)\""), let eb = raw.range(of:"\"evidence_bar\"",range:m.upperBound..<raw.endIndex) else { return [:] }
  var out: [String:Int] = [:]
  for k in keys {
   let enc = (try? JSONSerialization.data(withJSONObject:[k])).map { String(decoding:$0,as:UTF8.self) }.map { String($0.dropFirst().dropLast()) } ?? "\"\(k)\""
   if let r = raw.range(of:enc,range:eb.upperBound..<raw.endIndex) { out[k] = raw.distance(from:raw.startIndex,to:r.lowerBound) }
  }
  return out
 }

 static func parseScorecard(_ data: Data) -> (Date?,[ResearchMarket])? {
  let raw = String(decoding:data,as:UTF8.self)
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
   // The file's own order (JSONSerialization loses it, so find each key in the raw text), human checks last.
   let pos = keyPositions(raw,market:key,keys:Array(bar.keys))
   let order = bar.keys.sorted { a,b in
    let ha = a.contains("human check"), hb = b.contains("human check")
    if ha != hb { return !ha }
    let pa = pos[a] ?? Int.max, pb = pos[b] ?? Int.max
    return pa != pb ? pa < pb : a < b }
   for (id,v) in (m["by_idea"] as? [String:Any]) ?? [:] {
    guard let e = v as? [String:Any], let st = e["replay_status"] as? String, !st.isEmpty else { continue }
    r.ideaStatus[id] = (st,(e["label"] as? String).flatMap { $0.isEmpty ? nil : $0 })
   }
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
     reason:str(l["reason"]),act:(l["act"] as? Bool) ?? false,created:date(l["created"]),author:str(l["author"]),
     botPlain:(l["plain_reason"] as? String).map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : String($0.prefix(400)) },idea:str(l["idea"])))
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
   if let st = l["replay_status"] as? String, !st.isEmpty { o.replayStatus = st }
   if let lb = l["label"] as? String, !lb.isEmpty { o.label = lb }
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
 // nil = a read was cancelled (the view went away mid-load): keep what's on screen instead of storing a half-read snapshot.
 static func load(_ fetch: (String) async -> ResearchFetch) async -> ResearchSnapshot? {
  var s = ResearchSnapshot(loaded:Date())
  var cancelled = false
  func load(_ p: String) async -> ResearchFetch { let r = await fetch(p); if case .cancelled = r { cancelled = true }; return r }
  func text(_ d: Data) -> String { String(decoding:d,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines) }
  switch await load("research_bot/scorecard.json") {
  case .ok(let d): if let (g,m) = parseScorecard(d) { s.generated = g; s.markets = m } else { s.problems.append("The scorecard file couldn't be read.") }
  case .missing: s.problems.append("No scorecard file yet.")
  case .failed(let why): s.problems.append("Couldn't load the scorecard (\(why)).")
  case .cancelled: break
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
   case .cancelled: break
   }
  }
  return cancelled ? nil : s
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
  } catch {
   if Task.isCancelled || (error as? URLError)?.code == .cancelled || error is CancellationError { return .cancelled }
   return .failed("no connection")
  }
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

 // The research bot's reason, "momentum {"lookback": 20, "prob": 0.52}, horizon 1 trading days: Up if higher than N bars ago, else down",
 // in plain words. nil when it doesn't match that shape (the raw text is shown instead). The raw text always stays behind "details".
 // What to show as "why": the bot's own plain_reason first; else our reading of its rule (labelled as ours); else nil (raw shown).
 static func why(_ f: ResearchForecast) -> (text: String,ours: Bool)? {
  if let b = f.botPlain { return (b,false) }
  return plainReason(f).map { ($0,true) }
 }
 static func plainReason(_ f: ResearchForecast) -> String? {
  let r = f.reason
  guard let brace = r.firstIndex(of:"{"), let close = r[brace...].firstIndex(of:"}") else { return nil }
  let name = r[..<brace].trimmingCharacters(in:.whitespaces)
  guard !name.isEmpty, !name.contains(" ") else { return nil }
  let params = (try? JSONSerialization.jsonObject(with:Data(r[brace...close].utf8))) as? [String:Any] ?? [:]
  let rest = r[r.index(after:close)...]
  var n = 1, unit = "trading day", rule = ""
  if let h = rest.range(of:"horizon ") {
   let words = rest[h.upperBound...].split(separator:":",maxSplits:1)
   let hw = words.first.map { $0.split(separator:" ") } ?? []
   n = Int(hw.first ?? "") ?? 1
   let u = hw.dropFirst().joined(separator:" ")
   if !u.isEmpty { unit = u.hasSuffix("s") ? String(u.dropLast()) : u }
   rule = words.count > 1 ? words[1].trimmingCharacters(in:.whitespaces) : ""
  }
  let units = { (k: Int) in k == 1 ? unit : unit + "s" }
  let next = n == 1 ? "the next \(unit)" : "the next \(n) \(units(n))"
  let up = f.direction.lowercased() != "down"
  let L = num(params["lookback"]).map { Int($0) }
  switch name {
  case "momentum":
   guard let L else { break }
   return "Momentum (\(L)-\(unit.replacingOccurrences(of:"trading ",with:""))): \(f.asset) is \(up ? "higher" : "lower") than \(L) \(units(L)) ago, so it guesses \(up ? "up" : "down") for \(next)"
  case "reversal":
   guard let L, let d = num(params["drop_pct"]) else { break }
   return "Bounce-back (\(clean(d))% over \(L) \(units(L))): \(f.asset) \(up ? "fell" : "rose") more than \(clean(d))%, so it guesses \(up ? "a bounce up" : "a pullback down") for \(next)"
  default: break
  }
  let pretty = name.replacingOccurrences(of:"_",with:" ").prefix(1).uppercased() + name.replacingOccurrences(of:"_",with:" ").dropFirst()
  let ruleText = L.map { rule.replacingOccurrences(of:"N bars",with:"\($0) \(units($0))") } ?? rule
  return "\(pretty)\(ruleText.isEmpty ? "" : ": \(ruleText.prefix(1).lowercased() + ruleText.dropFirst())"). It guesses \(up ? "up" : "down") for \(next)"
 }

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
}
