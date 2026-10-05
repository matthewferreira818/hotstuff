import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Reads the store's sales from Stripe with a READ-ONLY restricted key that Matthew pastes into the app himself.
// It only ever sends GET requests, and it refuses a full secret key (sk_), so the app could never move money or change
// anything even by mistake. It keeps counts and amounts only: no names, emails or card details are read into the app.
// The parser is tested against Stripe's documented charge list shape (see checks/).

struct StripeOrder: Identifiable {
 var id: String
 var amount: Double      // major units (dollars), after refunds
 var currency: String    // lowercase ISO code, e.g. "cad"
 var time: Date
}

struct StripePeriod {
 var orders = 0
 // Revenue by currency, so mixed currencies are never added together.
 var revenue: [String: Double] = [:]
}

struct StripeSales {
 var today = StripePeriod()
 var week = StripePeriod()
 var month = StripePeriod()
 var latest: [StripeOrder] = []
 var testMode = false
 var capped = false      // true if there were more orders than the page limit read
}

enum StripeOutcome {
 case ok(StripeSales)
 case failed(String)
}

enum StripeData {
 static let base = "https://api.stripe.com/v1/charges"
 static let maxPages = 5   // 500 charges is far more than a month of this store; the screen says so if it is hit

 // What the Save button accepts. A restricted key starts with rk_. A full secret key (sk_) is refused on purpose.
 static func keyProblem(_ raw: String) -> String? {
  let key = raw.trimmingCharacters(in:.whitespacesAndNewlines)
  if key.isEmpty { return "Paste the key first." }
  if key.hasPrefix("sk_") { return "That is a full secret key. Make a restricted read-only key instead (steps above), so this app can never change anything." }
  if key.hasPrefix("pk_") { return "That is a publishable key, which can't read sales. Make a restricted read-only key (steps above)." }
  if !(key.hasPrefix("rk_live_") || key.hasPrefix("rk_test_")) { return "That doesn't look like a Stripe restricted key. It starts with rk_live_." }
  return nil
 }

 // One page of Stripe's charge list: {"object":"list","data":[{charge}],"has_more":false}.
 static func parsePage(_ data: Data) -> (orders: [StripeOrder],hasMore: Bool,lastID: String?)? {
  guard let json = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
        let rows = json["data"] as? [[String:Any]] else { return nil }
  var orders: [StripeOrder] = []
  for row in rows {
   // Only money that really arrived: paid and succeeded. Refunded money is taken off.
   guard (row["paid"] as? Bool) == true, (row["status"] as? String) == "succeeded" else { continue }
   guard let id = row["id"] as? String, let created = number(row["created"]) else { continue }
   let cents = number(row["amount"]) ?? 0
   let refunded = number(row["amount_refunded"]) ?? 0
   if cents > 0 && refunded >= cents { continue }   // a fully refunded order kept no money, so it isn't counted
   let currency = ((row["currency"] as? String) ?? "usd").lowercased()
   orders.append(StripeOrder(id:id,amount:max(0,cents - refunded) / 100.0,currency:currency,time:Date(timeIntervalSince1970:created)))
  }
  let lastID = rows.last?["id"] as? String
  return (orders,(json["has_more"] as? Bool) ?? false,lastID)
 }

 private static func number(_ value: Any?) -> Double? {
  if let n = value as? Double { return n }
  if let n = value as? Int { return Double(n) }
  return nil
 }

 // Turns the orders into today / 7 days / 30 days. "Today" is the Mac's local day.
 static func summarize(_ orders: [StripeOrder],now: Date = Date(),calendar: Calendar = .current,testMode: Bool = false,capped: Bool = false) -> StripeSales {
  var sales = StripeSales()
  sales.testMode = testMode
  sales.capped = capped
  let startOfToday = calendar.startOfDay(for:now)
  let weekAgo = now.addingTimeInterval(-7 * 86400)
  let monthAgo = now.addingTimeInterval(-30 * 86400)
  for order in orders.sorted(by:{ $0.time > $1.time }) {
   if order.time >= monthAgo {
    add(order,to:&sales.month)
    if order.time >= weekAgo { add(order,to:&sales.week) }
    if order.time >= startOfToday { add(order,to:&sales.today) }
   }
  }
  sales.latest = Array(orders.sorted(by:{ $0.time > $1.time }).prefix(3))
  return sales
 }

 private static func add(_ order: StripeOrder,to period: inout StripePeriod) {
  period.orders += 1
  period.revenue[order.currency, default: 0] += order.amount
 }

 // Reads the last 30 days of charges. GET only.
 static func fetch(key raw: String) async -> StripeOutcome {
  let key = raw.trimmingCharacters(in:.whitespacesAndNewlines)
  if let problem = keyProblem(key) { return .failed(problem) }
  let since = Int(Date().addingTimeInterval(-30 * 86400).timeIntervalSince1970)
  var all: [StripeOrder] = []
  var after: String? = nil
  var capped = false
  for page in 0..<maxPages {
   var text = "\(base)?limit=100&created%5Bgte%5D=\(since)"
   if let after = after { text += "&starting_after=\(after)" }
   guard let url = URL(string:text) else { return .failed("Couldn't build the Stripe request.") }
   var request = URLRequest(url:url)
   request.httpMethod = "GET"
   request.cachePolicy = .reloadIgnoringLocalCacheData
   request.timeoutInterval = 15
   request.setValue("Bearer \(key)",forHTTPHeaderField:"Authorization")
   guard let (data,response) = try? await URLSession.shared.data(for:request),
         let code = (response as? HTTPURLResponse)?.statusCode else { return .failed("Couldn't reach Stripe. Check your internet.") }
   if code == 401 { return .failed("Stripe didn't accept that key. Make a fresh restricted key and save it again.") }
   if code == 403 { return .failed("That key can't read sales. Edit the key in Stripe and set Charges to Read.") }
   if code == 429 { return .failed("Stripe asked us to slow down. Try again in a minute.") }
   guard code == 200, let parsed = parsePage(data) else { return .failed("Stripe answered something unexpected (code \(code)).") }
   all += parsed.orders
   guard parsed.hasMore, let last = parsed.lastID else { break }
   after = last
   if page == maxPages - 1 { capped = true }
  }
  return .ok(summarize(all,testMode:key.hasPrefix("rk_test_"),capped:capped))
 }
}
