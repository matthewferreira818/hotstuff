import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Reads the stock bot's PUBLIC practice-account snapshots (live.json on the stock-live and stock-live-momentum branches).
// Read-only. No login, no keys, and nothing here can place an order. Tested against the live files on 2026-10-05.

struct StockHolding: Identifiable {
 var id: String { symbol }
 var symbol: String
 var value: Double
 var changePct: Double?
}

struct StockTrade: Identifiable {
 var id: String { "\(symbol)-\(side)-\(time?.timeIntervalSince1970 ?? 0)" }
 var time: Date?
 var symbol: String
 var side: String
 var dollars: Double
}

struct StockRobot {
 var name: String
 var updated: Date?
 var marketOpen = false
 var value = 0.0
 var cash = 0.0
 var held = 0.0
 var spyValue = 0.0
 var fees = 0.0
 var startCash = 0.0
 var trades = 0
 var nextDeposit = ""
 var paused = false
 var holdings: [StockHolding] = []
 var recentTrades: [StockTrade] = []
 var events: [String] = []
 // Positive means the robot is ahead of simply holding the index with the same money.
 var vsHolding: Double { value - spyValue }
 var sinceStart: Double { value - startCash }
}

enum StockData {
 static let base = "https://raw.githubusercontent.com/matthewferreira818/hotstuff/"

 static func number(_ value: Any?) -> Double {
  if let d = value as? Double { return d }
  if let i = value as? Int { return Double(i) }
  if let n = value as? NSNumber { return n.doubleValue }
  if let s = value as? String, let d = Double(s) { return d }
  return 0
 }

 static func date(_ value: Any?) -> Date? {
  guard let text = value as? String else { return nil }
  return ISO8601DateFormatter().date(from:text)
 }

 // The dip robot lists every watched stock under "stocks" and marks the ones it holds; the momentum robot lists "positions".
 static func parse(_ json: [String:Any], name: String) -> StockRobot? {
  guard let account = json["account"] as? [String:Any] else { return nil }
  var robot = StockRobot(name:name,updated:date(json["updated"]))
  robot.marketOpen = (json["market_open"] as? Bool) ?? false
  robot.value = number(account["value"])
  robot.cash = number(account["cash"])
  robot.held = number(account["held"])
  robot.spyValue = number(account["spy_value"])
  robot.fees = number(account["fees"])
  robot.startCash = number(account["start_cash"])
  robot.trades = Int(number(account["trades"]))
  robot.nextDeposit = (account["next_deposit"] as? String) ?? ""
  robot.paused = ((json["settings"] as? [String:Any])?["paused"] as? Bool) ?? false

  if let positions = json["positions"] as? [[String:Any]] {
   for p in positions {
    robot.holdings.append(StockHolding(symbol:(p["symbol"] as? String) ?? "?",value:number(p["value"]),changePct:p["change_pct"] == nil ? nil : number(p["change_pct"])))
   }
  } else if let stocks = json["stocks"] as? [[String:Any]] {
   for s in stocks where (s["held"] as? Bool) == true {
    robot.holdings.append(StockHolding(symbol:(s["symbol"] as? String) ?? "?",value:number(s["value"]),changePct:s["change_pct"] == nil ? nil : number(s["change_pct"])))
   }
  }

  if let orders = json["orders"] as? [[String:Any]] {
   let all = orders.map { StockTrade(time:date($0["time"]),symbol:($0["symbol"] as? String) ?? "?",side:($0["side"] as? String) ?? "",dollars:number($0["dollars"])) }
   robot.recentTrades = Array(all.sorted { ($0.time ?? .distantPast) > ($1.time ?? .distantPast) }.prefix(5))
  }
  if let events = (json["bot"] as? [String:Any])?["events"] as? [[String:Any]] {
   robot.events = Array(events.compactMap { $0["text"] as? String }.suffix(4).reversed())
  }
  return robot
 }

 // The "nc" number defeats the 5-minute cache GitHub puts on raw files.
 static func fetch(branch: String, name: String) async -> StockRobot? {
  guard let url = URL(string:"\(base)\(branch)/live.json?nc=\(Int(Date().timeIntervalSince1970))") else { return nil }
  var request = URLRequest(url:url)
  request.cachePolicy = .reloadIgnoringLocalCacheData
  request.timeoutInterval = 10
  guard let (data,response) = try? await URLSession.shared.data(for:request),
        (response as? HTTPURLResponse)?.statusCode == 200,
        let json = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return nil }
  return parse(json,name:name)
 }
}
