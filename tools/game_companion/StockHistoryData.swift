import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Stock bot area revamp (LC-Pixels, 2026-11-10; Roxy's concept, NB2's brief). READ-ONLY, practice money only.
// - Each robot's paper account file on master (stock_bot/paper/account*.json: every filled order, start cash, benchmark units, deposits).
// - Public Yahoo prices (the same chart endpoint the bots use), cached in memory and on disk; offline shows the last cached prices, marked.
// - The account-value line is REBUILT from the robot's own recorded orders plus public prices (snapshots are replaced each run, so no
//   recorded value history exists). Replaying the orders lands within a few cents of the recorded cash on all 7 accounts (checked 2026-11-10).
// Nothing here writes anything except the price cache, and nothing can place an order.

struct PricePoint: Equatable { var t: Date; var v: Double }

struct PaperOrder: Identifiable, Equatable {
 var id: String { "\(t.timeIntervalSince1970)-\(symbol)-\(side)-\(qty)" }
 var t: Date
 var symbol: String
 var side: String          // "buy" / "sell"
 var qty: Double
 var price: Double
 var fee: Double
 var realized: Double?     // sells: after fees, average-cost basis (filled in by realizedPnL)
 var cash: Double { side == "buy" ? -(qty * price + fee) : qty * price - fee }
}

struct PaperAccount {
 var started: Date?
 var startCash = 1000.0
 var spyAtStart: Double?
 var spyUnits: Double?
 var benchUnits: Double?
 var deposits: [(t: Date,usd: Double)] = []
 var orders: [PaperOrder] = []
 var cash = 0.0
 var fees: Double { orders.reduce(0) { $0 + $1.fee } }
}

struct StockRobotInfo: Identifiable {
 var id: Int
 var short: String          // fleet list name
 var group: String          // "Stocks" / "Crypto"
 var name: String           // header name
 var branch: String
 var account: String
 var watchlist: String
 var icon: String
 var crypto: Bool { group == "Crypto" }
}

enum ChartRange: String, CaseIterable, Identifiable {
 case day = "1D", week = "1W", month = "1M", year = "1Y", all = "ALL"
 var id: String { rawValue }
 // How far down from the recent high counts as a dip worth shading, per range.
 var dipPct: Double { switch self { case .day: return 1.5; case .week: return 3; case .month: return 5; case .year, .all: return 10 } }
 var ttl: TimeInterval { switch self { case .day: return 300; case .week: return 900; case .month: return 1800; case .year, .all: return 6 * 3600 } }
}

enum StockHistory {
 static let raw = "https://raw.githubusercontent.com/matthewferreira818/hotstuff/master/stock_bot/"
 static let robots: [StockRobotInfo] = [
  StockRobotInfo(id:0,short:"Dip",group:"Stocks",name:"Dip",branch:"stock-live",account:"account.json",watchlist:"watchlist.json",icon:"chevron.down.2"),
  StockRobotInfo(id:1,short:"Momentum",group:"Stocks",name:"Momentum",branch:"stock-live-momentum",account:"account-momentum.json",watchlist:"watchlist-momentum.json",icon:"chart.bar.fill"),
  StockRobotInfo(id:2,short:"Hot hands",group:"Stocks",name:"Hot hands",branch:"stock-live-hot",account:"account-hot.json",watchlist:"watchlist-hot.json",icon:"flame.fill"),
  StockRobotInfo(id:3,short:"Moonshot",group:"Stocks",name:"Moonshot",branch:"stock-live-moonshot",account:"account-moonshot.json",watchlist:"watchlist-moonshot.json",icon:"paperplane.fill"),
  StockRobotInfo(id:4,short:"Crypto",group:"Crypto",name:"Moonshot",branch:"stock-live-moonshot-crypto",account:"account-moonshot-crypto.json",watchlist:"watchlist-moonshot-crypto.json",icon:"bitcoinsign.circle"),
  StockRobotInfo(id:5,short:"Quality Dip",group:"Stocks",name:"Quality Dip",branch:"stock-live-quality",account:"account-quality.json",watchlist:"watchlist-quality.json",icon:"rhombus"),
  StockRobotInfo(id:6,short:"Volatility",group:"Stocks",name:"Volatility",branch:"stock-live-volatility",account:"account-volatility.json",watchlist:"watchlist-volatility.json",icon:"waveform.path.ecg"),
 ]

 static func num(_ v: Any?) -> Double? {
  if v is NSNull { return nil }
  if let n = v as? NSNumber { return n.doubleValue }
  if let s = v as? String { return Double(s) }
  return nil
 }
 static func date(_ v: Any?) -> Date? {
  guard let s = v as? String, !s.isEmpty else { return nil }
  let f = ISO8601DateFormatter()
  if let d = f.date(from:s) { return d }
  f.formatOptions = [.withInternetDateTime,.withFractionalSeconds]
  if let d = f.date(from:s) { return d }
  f.formatOptions = [.withFullDate]
  return f.date(from:s)
 }

 // MARK: account file
 static func parseAccount(_ data: Data) -> PaperAccount? {
  guard let d = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return nil }
  var a = PaperAccount()
  a.started = date(d["started"]); a.startCash = num(d["start_cash"]) ?? 1000
  a.spyAtStart = num(d["spy_at_start"]); a.spyUnits = num(d["spy_units"]); a.benchUnits = num(d["bench_units"])
  a.cash = num(d["cash"]) ?? 0
  a.deposits = ((d["deposits"] as? [[String:Any]]) ?? []).compactMap { x in
   guard let t = date(x["date"] ?? x["time"]), let usd = num(x["usd"] ?? x["amount"]) else { return nil }
   return (t,usd)
  }
  a.orders = ((d["orders"] as? [[String:Any]]) ?? []).compactMap { o in
   guard (o["status"] as? String ?? "filled") == "filled", let t = date(o["time"]), let sym = o["symbol"] as? String,
         let side = o["side"] as? String, let q = num(o["qty"]), let p = num(o["price"]) else { return nil }
   return PaperOrder(t:t,symbol:sym.uppercased(),side:side.lowercased(),qty:q,price:p,fee:num(o["fee"]) ?? 0)
  }.sorted { $0.t < $1.t }
  realizedPnL(&a.orders)
  return a
 }

 // Sells get their result after fees, against the average cost (fees included) of what was held.
 static func realizedPnL(_ orders: inout [PaperOrder]) {
  var qty: [String:Double] = [:], cost: [String:Double] = [:]
  for i in orders.indices {
   let o = orders[i]
   if o.side == "buy" { qty[o.symbol,default:0] += o.qty; cost[o.symbol,default:0] += o.qty * o.price + o.fee; continue }
   let held = qty[o.symbol] ?? 0
   guard held > 0 else { continue }
   let part = min(o.qty,held) / held
   let basis = (cost[o.symbol] ?? 0) * part
   orders[i].realized = (o.qty * o.price - o.fee) - basis
   qty[o.symbol] = held - min(o.qty,held); cost[o.symbol] = (cost[o.symbol] ?? 0) - basis
  }
 }

 static func benchSymbol(watchlist: Data?) -> String? {
  guard let w = watchlist, let d = (try? JSONSerialization.jsonObject(with:w)) as? [String:Any] else { return nil }
  return (d["benchmark"] as? String).map { $0.uppercased() }
 }

 // MARK: Yahoo chart
 static func query(_ symbol: String,range: ChartRange,crypto: Bool,started: Date?,now: Date = Date()) -> String {
  let sym = symbol.addingPercentEncoding(withAllowedCharacters:.alphanumerics.union(CharacterSet(charactersIn:"-.^="))) ?? symbol
  let base = "https://query1.finance.yahoo.com/v8/finance/chart/\(sym)?includePrePost=false&"
  if range == .all {
   let from = (started ?? now.addingTimeInterval(-30 * 86400)).addingTimeInterval(-3600)
   let age = now.timeIntervalSince(from) / 86400
   let interval = age < 2 ? "5m" : age < 8 ? "30m" : age < 60 ? "1h" : "1d"
   return base + "period1=\(Int(from.timeIntervalSince1970))&period2=\(Int(now.timeIntervalSince1970))&interval=\(interval)"
  }
  if crypto {   // crypto trades all week: exact windows
   let (days,interval): (Double,String) = { switch range { case .day: return (1,"5m"); case .week: return (7,"30m"); case .month: return (30,"1h"); default: return (365,"1d") } }()
   return base + "period1=\(Int(now.addingTimeInterval(-days * 86400).timeIntervalSince1970))&period2=\(Int(now.timeIntervalSince1970))&interval=\(interval)"
  }
  // stocks: trading sessions (1D = the last session, 1W = the last 5 sessions)
  switch range {
  case .day: return base + "range=1d&interval=5m"
  case .week: return base + "range=5d&interval=30m"
  case .month: return base + "range=1mo&interval=1h"
  default: return base + "range=1y&interval=1d"
  }
 }

 static func parseChart(_ data: Data) -> [PricePoint]? {
  guard let root = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
        let chart = root["chart"] as? [String:Any], let result = (chart["result"] as? [[String:Any]])?.first else { return nil }
  let ts = (result["timestamp"] as? [Any]) ?? []
  let quote = ((result["indicators"] as? [String:Any])?["quote"] as? [[String:Any]])?.first
  let closes = (quote?["close"] as? [Any]) ?? []
  var out: [PricePoint] = []
  for (i,t) in ts.enumerated() where i < closes.count {
   if let s = num(t), let c = num(closes[i]), c > 0 { out.append(PricePoint(t:Date(timeIntervalSince1970:s),v:c)) }
  }
  return out
 }

 // MARK: rebuild the account value (and "just holding") over a window
 // `prices`: series per symbol; `bench`: the benchmark's series (its timestamps are the grid). Points before `started` are left out.
 static func rebuild(_ a: PaperAccount,prices: [String:[PricePoint]],bench: [PricePoint],benchIsSpy: Bool,
                     last: (t: Date,value: Double,hold: Double)? = nil) -> (value: [PricePoint],hold: [PricePoint],unpriced: [String]) {
  var value: [PricePoint] = [], hold: [PricePoint] = []
  var unpriced = Set<String>()
  let start = a.started ?? .distantPast
  var cash = a.startCash, qty: [String:Double] = [:], lastTrade: [String:Double] = [:]
  var oi = 0, di = 0
  let deposits = a.deposits.sorted { $0.t < $1.t }
  var idx: [String:Int] = [:]
  // Benchmark units at time t. SPY robots: the final units minus units bought by later deposits. Others: fixed bench_units.
  func benchPrice(at t: Date) -> Double? { bench.last { $0.t <= t }?.v ?? bench.first?.v }
  func units(at t: Date) -> Double {
   if benchIsSpy {
    let final = a.spyUnits ?? (a.spyAtStart.map { a.startCash / $0 } ?? 0)
    let later = deposits.filter { $0.t > t }.reduce(0.0) { s,d in s + (benchPrice(at:d.t).map { d.usd / $0 } ?? 0) }
    return max(final - later,0)
   }
   return a.benchUnits ?? 0
  }
  for p in bench where p.t >= start {
   while oi < a.orders.count && a.orders[oi].t <= p.t {
    let o = a.orders[oi]; cash += o.cash
    qty[o.symbol,default:0] += o.side == "buy" ? o.qty : -o.qty
    lastTrade[o.symbol] = o.price; oi += 1
   }
   while di < deposits.count && deposits[di].t <= p.t { cash += deposits[di].usd; di += 1 }
   var held = 0.0
   for (sym,q) in qty where abs(q) > 1e-9 {
    let series = prices[sym] ?? []
    var i = idx[sym] ?? 0
    while i + 1 < series.count && series[i + 1].t <= p.t { i += 1 }
    idx[sym] = i
    if !series.isEmpty && series[i].t <= p.t { held += q * series[i].v }
    else if let lt = lastTrade[sym] { held += q * lt; if series.isEmpty { unpriced.insert(sym) } }
   }
   value.append(PricePoint(t:p.t,v:cash + held))
   hold.append(PricePoint(t:p.t,v:units(at:p.t) * p.v))
  }
  if let l = last, l.t > (value.last?.t ?? .distantPast) {
   value.append(PricePoint(t:l.t,v:l.value)); hold.append(PricePoint(t:l.t,v:l.hold))
  }
  return (value,hold,unpriced.sorted())
 }

 // Which symbols the account held at any moment inside [from, to] (so only those prices are fetched).
 static func symbolsHeld(_ a: PaperAccount,from: Date,to: Date) -> [String] {
  var out = Set<String>()
  for o in a.orders where o.t >= from && o.t <= to { out.insert(o.symbol) }
  // held at the window start too
  var q2: [String:Double] = [:]
  for o in a.orders where o.t < from { q2[o.symbol,default:0] += o.side == "buy" ? o.qty : -o.qty }
  for (s,q) in q2 where q > 1e-9 { out.insert(s) }
  return out.sorted()
 }

 // Stretches where the line sat more than `pct`% below its running high inside the window ("dips").
 static func dips(_ series: [PricePoint],pct: Double) -> [(from: Date,to: Date,depth: Double)] {
  var out: [(Date,Date,Double)] = []
  var peak = -Double.infinity, inDip: Date? = nil, deepest = 0.0
  for (i,p) in series.enumerated() {
   if p.v >= peak { peak = p.v }
   let down = peak > 0 ? (peak - p.v) / peak * 100 : 0
   if down >= pct {
    if inDip == nil { inDip = series[max(i - 1,0)].t; deepest = 0 }
    deepest = max(deepest,down)
   } else if let s = inDip {
    out.append((s,p.t,deepest)); inDip = nil
   }
  }
  if let s = inDip, let l = series.last { out.append((s,l.t,deepest)) }
  return out
 }

 // MARK: plain words
 static func money(_ v: Double?) -> String {
  guard let v else { return "-" }
  let f = NumberFormatter(); f.numberStyle = .currency; f.currencyCode = "USD"; f.currencySymbol = "$"; f.maximumFractionDigits = 2; f.minimumFractionDigits = 2
  return f.string(from:NSNumber(value:v)) ?? String(format:"$%.2f",v)
 }
 static func signed(_ v: Double?) -> String { guard let v else { return "-" }; return (v > 0.004 ? "+" : v < -0.004 ? "−" : "") + money(abs(v)) }
 static func pct(_ v: Double?) -> String { guard let v else { return "-" }; return (v > 0.004 ? "+" : v < -0.004 ? "−" : "") + String(format:"%.2f%%",abs(v)) }
 static func price(_ v: Double) -> String {
  if v >= 1000 { return money(v) }
  if v >= 1 { return String(format:"$%.2f",v) }
  if v >= 0.01 { return String(format:"$%.4f",v) }
  return String(format:"$%.8f",v)
 }
 static func age(_ d: Date?,now: Date = Date()) -> String {
  guard let d else { return "time unknown" }
  let m = Int(now.timeIntervalSince(d) / 60)
  if m < 1 { return "just now" }
  if m < 60 { return "\(m) min ago" }
  if m < 48 * 60 { return "\(m / 60) h ago" }
  return "\(m / 1440) days ago"
 }
 // green: under 2 h old · amber: under 26 h · red: older (a weekend can make a stock robot's snapshot old; the age is always shown)
 static func freshness(_ d: Date?,now: Date = Date()) -> Int {
  guard let d else { return 2 }
  let h = now.timeIntervalSince(d) / 3600
  return h < 2 ? 0 : h < 26 ? 1 : 2
 }
 // Robot rules from the snapshot ("trail_pct": 15) in plain words.
 static func ruleWords(_ key: String,_ value: Any) -> String {
  var name = key.replacingOccurrences(of:"_",with:" ")
  let swaps = ["pct":"%","min ":"minimum ","max ":"maximum ","stop loss":"stop-loss"]
  for (a,b) in swaps { name = name.replacingOccurrences(of:a,with:b) }
  name = name.prefix(1).uppercased() + name.dropFirst()
  let v: String = { if let b = value as? Bool { return b ? "yes" : "no" }; if let n = num(value) { return n == n.rounded() ? String(Int(n)) : String(n) }; return "\(value)" }()
  return "\(name): \(v)"
 }
}

// MARK: price cache (memory + disk). Offline: the newest cached copy, flagged as old.
actor PriceCache {
 static let shared = PriceCache()
 private var memory: [String:(at: Date,points: [PricePoint])] = [:]
 private let dir: URL? = FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask).first?
  .appendingPathComponent((Bundle.main.bundleIdentifier ?? "local.mattyb.gamecompanion") + "/prices",isDirectory:true)

 struct Result { var points: [PricePoint]; var fetched: Date?; var offline: Bool }

 func series(_ symbol: String,range: ChartRange,crypto: Bool,started: Date?) async -> Result {
  let key = "\(symbol)|\(range.rawValue)|\(crypto)|\(range == .all ? Int((started ?? .distantPast).timeIntervalSince1970) : 0)"
  if let m = memory[key], Date().timeIntervalSince(m.at) < range.ttl { return Result(points:m.points,fetched:m.at,offline:false) }
  if let url = URL(string:StockHistory.query(symbol,range:range,crypto:crypto,started:started)) {
   var req = URLRequest(url:url,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15)
   req.setValue("Mozilla/5.0",forHTTPHeaderField:"User-Agent")
   if let (data,resp) = try? await URLSession.shared.data(for:req), (resp as? HTTPURLResponse)?.statusCode == 200,
      let pts = StockHistory.parseChart(data) {
    memory[key] = (Date(),pts); save(key,pts)
    return Result(points:pts,fetched:Date(),offline:false)
   }
  }
  if let m = memory[key] { return Result(points:m.points,fetched:m.at,offline:true) }
  if let d = load(key) { memory[key] = d; return Result(points:d.points,fetched:d.at,offline:true) }
  return Result(points:[],fetched:nil,offline:true)
 }

 private func file(_ key: String) -> URL? {
  dir?.appendingPathComponent(key.replacingOccurrences(of:"|",with:"_").replacingOccurrences(of:"/",with:"-") + ".json")
 }
 private func save(_ key: String,_ pts: [PricePoint]) {
  guard let f = file(key) else { return }
  try? FileManager.default.createDirectory(at:f.deletingLastPathComponent(),withIntermediateDirectories:true)
  let rows = pts.map { [$0.t.timeIntervalSince1970,$0.v] }
  if let data = try? JSONSerialization.data(withJSONObject:["at":Date().timeIntervalSince1970,"p":rows]) { try? data.write(to:f,options:.atomic) }
 }
 private func load(_ key: String) -> (at: Date,points: [PricePoint])? {
  guard let f = file(key), let data = try? Data(contentsOf:f), let d = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
        let at = d["at"] as? Double, let rows = d["p"] as? [[Double]] else { return nil }
  return (Date(timeIntervalSince1970:at),rows.compactMap { $0.count == 2 ? PricePoint(t:Date(timeIntervalSince1970:$0[0]),v:$0[1]) : nil })
 }
}
