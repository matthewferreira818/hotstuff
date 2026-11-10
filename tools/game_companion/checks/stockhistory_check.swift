import Foundation
// Stock bot history (pixels/research-tab): account replay, realized P&L, Yahoo query/parse, rebuilt value line, dips, words. Offline: real account files + fixtures.
var fails = 0
func check(_ ok: Bool,_ what: String) { print(ok ? "PASS" : "FAIL",what); if !ok { fails += 1 } }
func near(_ a: Double,_ b: Double,_ tol: Double) -> Bool { abs(a - b) <= tol }
let root = URL(fileURLWithPath:CommandLine.arguments[1])
let t0 = Date(timeIntervalSince1970:1_800_000_000)
func at(_ h: Double) -> Date { t0.addingTimeInterval(h * 3600) }

// 1. All 7 real account files replay to the recorded cash and positions
for r in StockHistory.robots {
 let url = root.appendingPathComponent("stock_bot/paper/" + r.account)
 guard let data = try? Data(contentsOf:url), let a = StockHistory.parseAccount(data),
       let raw = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { check(false,"\(r.account): parses"); continue }
 check(true,"\(r.account): parses (\(a.orders.count) orders)")
 let replay = a.startCash + a.deposits.reduce(0) { $0 + $1.usd } + a.orders.reduce(0) { $0 + $1.cash }
 let fileCash = StockHistory.num(raw["cash"]) ?? -1
 check(near(replay,fileCash,0.05),"\(r.account): replayed cash \(String(format:"%.2f",replay)) matches file \(String(format:"%.2f",fileCash))")
 var net: [String:Double] = [:]
 for o in a.orders { net[o.symbol,default:0] += o.side == "buy" ? o.qty : -o.qty }
 var posOK = true
 let pos = (raw["positions"] as? [String:Any]) ?? [:]
 for (s,v) in pos {
  let fq = StockHistory.num((v as? [String:Any])?["qty"]) ?? 0
  if abs((net[s.uppercased()] ?? 0) - fq) > max(1e-4,abs(fq) * 1e-9) { posOK = false }
 }
 for (s,q) in net where abs(q) > 1e-4 && pos[s] == nil { if abs(q) > max(1e-4,abs(q) * 1e-9) { posOK = false } }
 check(posOK,"\(r.account): net quantities match recorded positions")
}

// 2. realizedPnL
func ord(_ h: Double,_ s: String,_ side: String,_ q: Double,_ p: Double,_ f: Double) -> PaperOrder { PaperOrder(t:at(h),symbol:s,side:side,qty:q,price:p,fee:f,realized:nil) }
var seq = [ord(0,"X","buy",10,10,1),ord(1,"X","buy",10,20,1),ord(2,"X","sell",10,30,1)]
StockHistory.realizedPnL(&seq)
check(seq[0].realized == nil && seq[1].realized == nil,"buys carry no realized result")
check(near(seq[2].realized ?? .nan,148,1e-9),"sell realized = 299 - 151 = 148 (avg cost incl. fees)")
var none = [ord(0,"Y","sell",5,10,0)]
StockHistory.realizedPnL(&none)
check(none[0].realized == nil,"sell with nothing held stays nil")

// 3. parseChart
let chart = #"{"chart":{"result":[{"timestamp":[1000,2000,3000],"indicators":{"quote":[{"close":[1.5,null,2.5]}]}}],"error":null}}"#
let pts = StockHistory.parseChart(Data(chart.utf8))
check(pts?.count == 2 && pts?[0].v == 1.5 && pts?[1].v == 2.5 && pts?[1].t == Date(timeIntervalSince1970:3000),"parseChart skips the null close")
check(StockHistory.parseChart(Data("garbage".utf8)) == nil,"parseChart(garbage) -> nil")
check(StockHistory.parseChart(Data(#"{"chart":{"result":null}}"#.utf8)) == nil,"parseChart(no result) -> nil")

// 4. query
let now = Date(timeIntervalSince1970:1_800_000_000)
func qv(_ q: String,_ k: String) -> Double? { q.components(separatedBy:CharacterSet(charactersIn:"?&")).first { $0.hasPrefix(k + "=") }.flatMap { Double($0.dropFirst(k.count + 1)) } }
let q1 = StockHistory.query("AAPL",range:.day,crypto:false,started:nil,now:now)
check(q1.contains("range=1d&interval=5m") && q1.contains("/chart/AAPL?"),"stocks 1D uses range=1d&interval=5m")
let qw = StockHistory.query("BTC-USD",range:.week,crypto:true,started:nil,now:now)
check(qw.contains("interval=30m") && near((qv(qw,"period2") ?? 0) - (qv(qw,"period1") ?? 0),7 * 86400,5),"crypto week: period1/period2 7 days apart, 30m")
let st = now.addingTimeInterval(-10 * 86400)
let qa = StockHistory.query("AAPL",range:.all,crypto:false,started:st,now:now)
check(near(qv(qa,"period1") ?? 0,st.timeIntervalSince1970,7200),"ALL: period1 near started")

// 5. rebuild
let acct = PaperAccount(started:at(1),startCash:1000,spyAtStart:nil,spyUnits:2,benchUnits:nil,deposits:[],orders:[ord(2,"AAA","buy",10,50,1)],cash:0)
let bench = (0..<5).map { PricePoint(t:at(Double($0)),v:100 + Double($0)) }       // hours 0...4
let aaa = (0..<5).map { PricePoint(t:at(Double($0)),v:50 + Double($0) * 2) }
let rb = StockHistory.rebuild(acct,prices:["AAA":aaa],bench:bench,benchIsSpy:true)
check(rb.value.count == 4 && rb.value.first?.t == at(1),"nothing before started")
var valOK = true
for p in rb.value { let h = (p.t.timeIntervalSince(t0)) / 3600; let exp = h < 2 ? 1000.0 : 1000 - 501 + 10 * (50 + h * 2); if !near(p.v,exp,1e-6) { valOK = false } }
check(valOK,"value = cash + qty*price at each bench point (order applied at its time)")
check(rb.hold.count == 4 && rb.hold.enumerated().allSatisfy { near($1.v,2 * (101 + Double($0)),1e-9) },"hold = spyUnits * bench (no deposits)")
check(rb.unpriced.isEmpty,"priced symbol is not listed unpriced")
let lastT = at(5)
let rl = StockHistory.rebuild(acct,prices:["AAA":aaa],bench:bench,benchIsSpy:true,last:(t:lastT,value:1234,hold:999))
check(rl.value.count == 5 && rl.value.last?.v == 1234 && rl.hold.last?.v == 999 && rl.value.last?.t == lastT,"last tuple appends a final point")
let ru = StockHistory.rebuild(acct,prices:[:],bench:bench,benchIsSpy:true)
check(ru.unpriced == ["AAA"] && near(ru.value.last?.v ?? 0,1000 - 501 + 10 * 50,1e-6),"no series -> last trade price, listed unpriced")

// 6. dips
func series(_ v: [Double]) -> [PricePoint] { v.enumerated().map { PricePoint(t:at(Double($0.offset)),v:$0.element) } }
let dp = StockHistory.dips(series([100,99,94,93,97,101]),pct:5)
check(dp.count == 1 && near(dp.first?.depth ?? 0,7,1e-9),"dips: one dip of depth ~7")
check(StockHistory.dips(series([100,100,100,100]),pct:5).isEmpty,"dips: flat series has none")

// 7. symbolsHeld
let held = PaperAccount(started:at(0),startCash:1000,spyAtStart:nil,spyUnits:nil,benchUnits:nil,deposits:[],orders:[
 ord(0,"OLD","buy",1,10,0),ord(1,"OLD","sell",1,10,0),ord(2,"KEEP","buy",1,10,0),ord(10,"NEW","buy",1,10,0),ord(30,"LATE","buy",1,10,0)],cash:0)
check(StockHistory.symbolsHeld(held,from:at(5),to:at(20)) == ["KEEP","NEW"],"symbolsHeld: window trades + held at start; not fully-sold-before or after the window")

// 8. words
check(StockHistory.freshness(now.addingTimeInterval(-3600),now:now) == 0,"freshness 1 h -> 0")
check(StockHistory.freshness(now.addingTimeInterval(-5 * 3600),now:now) == 1,"freshness 5 h -> 1")
check(StockHistory.freshness(now.addingTimeInterval(-3 * 86400),now:now) == 2,"freshness 3 days -> 2")
check(StockHistory.signed(-3.5).hasPrefix("\u{2212}"),"signed(-3.5) starts with U+2212")
check(StockHistory.price(0.00000528) == "$0.00000528","price(0.00000528) shows 8 decimals")

print(fails == 0 ? "ALL PASS (stock history)" : "\(fails) FAILED (stock history)")
exit(fails == 0 ? 0 : 1)
