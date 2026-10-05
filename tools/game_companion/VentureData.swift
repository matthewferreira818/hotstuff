import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Free, read-only data for the hub's Store, ECS and Systems pages. No logins and no keys: it reads the store's public
// visitor counters (GoatCounter), the site's own feed files, and GitHub's public automation status.
// Nothing here can change anything. Tested against the live sources on 2026-10-05.

struct StoreChannel: Identifiable {
 var id: String { tag }
 var tag: String
 var label: String
 var count: Int
}

struct StoreStats {
 var today = 0
 var week = 0
 var month = 0
 // Last 30 days, only channels that sent someone, biggest first.
 var channels: [StoreChannel] = []
}

struct FeedCard: Identifiable {
 var id: String { date }
 var date: String
 var image: String
 var message: String
}

struct FeedStats {
 var total = 0
 var since = ""
 var last = ""
 var cards: [FeedCard] = []

 // The honest streak. Claims "in a row" only when every day from the first post to the last has a post and the last post
 // is today or yesterday. Otherwise it returns nil and the screen shows the plain count instead.
 func streakDays(today: Date = Date()) -> Int? {
  guard let first = VentureData.day(since), let end = VentureData.day(last) else { return nil }
  let span = Int(end.timeIntervalSince(first) / 86400.0 + 0.5) + 1
  let age = Int(today.timeIntervalSince(end) / 86400.0)
  return (span == total && age <= 1) ? total : nil
 }
}

// The store's product list as published on the site, and when the 3-day refresh last updated it.
struct CatalogStats {
 var count = 0
 var categories = 0
 var refreshed: Date?
 // The refresh runs every 3 days. Five days with no refresh means it is not running.
 func ageDays(now: Date = Date()) -> Int? { refreshed.map { Int(now.timeIntervalSince($0) / 86400.0) } }
 func isStale(now: Date = Date()) -> Bool { (ageDays(now:now) ?? 0) > 5 }
}

struct AutomationRun: Identifiable {
 var id: String { name }
 var name: String
 var status: String
 var conclusion: String
 var created: Date?
 var url: String
 var isFailing: Bool { status == "completed" && conclusion == "failure" }
 var isRunning: Bool { status != "completed" }
}

enum VentureData {
 static let counters = "https://theycallmemattyb.goatcounter.com/counter/"
 static let feed = "https://findhotstuff.com/automation/feed/"
 static let runsURL = "https://api.github.com/repos/matthewferreira818/hotstuff/actions/runs?per_page=60"

 // The same channel tags traffic_report.py uses: pages fire a "ref-<tag>" event when someone arrives from that channel.
 static let channelList: [(String,String)] = [
  ("x","X posts"),("x-qr","X QR replies"),("pin","Pinterest product pins"),("pin-ecs","Pinterest ECS pins"),
  ("ecs","ECS daily caption"),("fb","Facebook posts and groups"),("fb-ad","Moncton group ad slot"),
  ("gbp","Google Business Profile"),("tt","TikTok product QR"),("tt-ecs","TikTok agent QR"),
  ("print","Print QR (flyers)"),("card","Business cards"),("sample","Sample-pack QR"),
  ("merch","Merch QR (the sweater)"),("buyer","Post-purchase page"),("setup","Setup page to automation")
 ]

 static let utc: TimeZone = TimeZone(identifier:"UTC") ?? TimeZone.current

 static func dayString(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier:"en_US_POSIX")
  formatter.timeZone = utc
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.string(from:date)
 }

 static func day(_ text: String) -> Date? {
  let formatter = DateFormatter()
  formatter.locale = Locale(identifier:"en_US_POSIX")
  formatter.timeZone = utc
  formatter.dateFormat = "yyyy-MM-dd"
  return formatter.date(from:text)
 }

 static func get(_ urlText: String,headers: [String:String] = [:]) async -> Data? {
  guard let url = URL(string:urlText) else { return nil }
  var request = URLRequest(url:url)
  request.cachePolicy = .reloadIgnoringLocalCacheData
  request.timeoutInterval = 12
  for (name,value) in headers { request.setValue(value,forHTTPHeaderField:name) }
  guard let (data,response) = try? await URLSession.shared.data(for:request),
        (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
  return data
 }

 // GoatCounter's public counter: {"count_unique":"21","count":"21"}, day precision, no login. A path with no hits
 // answers 404, which is a zero, not a failure.
 static func count(_ path: String,since: String) async -> Int? {
  guard let url = URL(string:"\(counters)\(path).json?start=\(since)") else { return nil }
  var request = URLRequest(url:url)
  request.cachePolicy = .reloadIgnoringLocalCacheData
  request.timeoutInterval = 12
  guard let (data,response) = try? await URLSession.shared.data(for:request),
        let code = (response as? HTTPURLResponse)?.statusCode else { return nil }
  if code == 404 { return 0 }
  guard code == 200, let json = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return nil }
  if let text = json["count_unique"] as? String { return Int(text) }
  if let number = json["count_unique"] as? Int { return number }
  return nil
 }

 static func fetchStore() async -> StoreStats? {
  let now = Date()
  let today = dayString(now)
  let week = dayString(now.addingTimeInterval(-6 * 86400))
  let month = dayString(now.addingTimeInterval(-29 * 86400))
  async let t = count("TOTAL",since:today)
  async let w = count("TOTAL",since:week)
  async let m = count("TOTAL",since:month)
  let (todayCount,weekCount,monthCount) = await (t,w,m)
  guard let todayValue = todayCount, let weekValue = weekCount, let monthValue = monthCount else { return nil }
  var stats = StoreStats(today:todayValue,week:weekValue,month:monthValue)
  let found: [StoreChannel] = await withTaskGroup(of:StoreChannel.self) { group in
   for (tag,label) in channelList {
    group.addTask { StoreChannel(tag:tag,label:label,count:await count("ref-\(tag)",since:month) ?? 0) }
   }
   var all: [StoreChannel] = []
   for await channel in group { all.append(channel) }
   return all
  }
  stats.channels = found.filter { $0.count > 0 }.sorted { $0.count > $1.count }
  return stats
 }

 // The site's own files: stats.json is the odometer, index.json lists the posts, newest first.
 static func fetchFeed() async -> FeedStats? {
  let stamp = Int(Date().timeIntervalSince1970)
  guard let statsData = await get("\(feed)stats.json?nc=\(stamp)"),
        let stats = (try? JSONSerialization.jsonObject(with:statsData)) as? [String:Any] else { return nil }
  var result = FeedStats()
  result.total = (stats["total"] as? Int) ?? Int(stats["total"] as? Double ?? 0)
  result.since = (stats["since"] as? String) ?? ""
  result.last = (stats["last"] as? String) ?? ""
  if let indexData = await get("\(feed)index.json?nc=\(stamp)"),
     let cards = (try? JSONSerialization.jsonObject(with:indexData)) as? [[String:Any]] {
   result.cards = cards.prefix(3).map { FeedCard(date:($0["date"] as? String) ?? "",image:($0["image"] as? String) ?? "",message:($0["message"] as? String) ?? "") }
  }
  return result
 }

 // The live product list plus the date of the last "Refresh: trending products" commit (GitHub's public commit list).
 static func parseCatalog(products: Data,commits: Data?) -> CatalogStats? {
  guard let list = (try? JSONSerialization.jsonObject(with:products)) as? [[String:Any]], !list.isEmpty else { return nil }
  var stats = CatalogStats()
  stats.count = list.count
  stats.categories = Set(list.compactMap { $0["category"] as? String }).count
  if let commits = commits, let rows = (try? JSONSerialization.jsonObject(with:commits)) as? [[String:Any]] {
   let iso = ISO8601DateFormatter()
   for row in rows {
    guard let commit = row["commit"] as? [String:Any], let message = commit["message"] as? String,
          message.hasPrefix("Refresh: trending products"),
          let committer = commit["committer"] as? [String:Any], let when = committer["date"] as? String else { continue }
    stats.refreshed = iso.date(from:when)
    break
   }
  }
  return stats
 }

 static func fetchCatalog() async -> CatalogStats? {
  let stamp = Int(Date().timeIntervalSince1970)
  guard let products = await get("https://findhotstuff.com/products.json?nc=\(stamp)") else { return nil }
  let commits = await get("https://api.github.com/repos/matthewferreira818/hotstuff/commits?path=products.json&per_page=15",headers:["Accept":"application/vnd.github+json","User-Agent":"GameCompanion"])
  return parseCatalog(products:products,commits:commits)
 }

 // GitHub's public workflow runs, newest first. Keeps the latest run of each automation.
 static func parseRuns(_ data: Data) -> [AutomationRun]? {
  guard let json = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
        let runs = json["workflow_runs"] as? [[String:Any]] else { return nil }
  let iso = ISO8601DateFormatter()
  var seen = Set<String>()
  var latest: [AutomationRun] = []
  for run in runs {
   let name = (run["name"] as? String) ?? "?"
   if seen.contains(name) { continue }
   seen.insert(name)
   latest.append(AutomationRun(name:name,status:(run["status"] as? String) ?? "",conclusion:(run["conclusion"] as? String) ?? "",created:iso.date(from:(run["created_at"] as? String) ?? ""),url:(run["html_url"] as? String) ?? ""))
  }
  return latest
 }

 static func fetchAutomations() async -> [AutomationRun]? {
  guard let data = await get(runsURL,headers:["Accept":"application/vnd.github+json","User-Agent":"GameCompanion"]) else { return nil }
  return parseRuns(data)
 }
}
