import SwiftUI

// Stock bot area revamp (LC-Pixels with Roxy as design partner, NB2 gates; Matthew picked Roxy's "Robot fleet" concept, 2026-11-10).
// READ-ONLY, practice money only: every number comes from a robot's public snapshot, its paper account file or public prices.
// Missing data says what's missing. No buy button, no money switch, no keys.

// MARK: model (account files + chart series, cached)

struct ChartSeries {
 var lines: [(points: [PricePoint],color: Color,dashed: Bool,label: String)] = []
 var marks: [PaperOrder] = []          // buys / sells drawn on the first line
 var dips: [(from: Date,to: Date,depth: Double)] = []
 var levels: [(value: Double,label: String,color: Color)] = []
 var offline = false
 var fetched: Date?
 var note = ""                         // plain words under the chart
 var empty = ""                        // set when there's nothing honest to draw
}

@MainActor final class StockAreaModel: ObservableObject {
 static let shared = StockAreaModel()
 @Published var accounts: [Int:PaperAccount] = [:]
 @Published var bench: [Int:String] = [:]
 @Published var accountProblem: [Int:String] = [:]
 @Published var charts: [String:ChartSeries] = [:]
 @Published var loading: Set<String> = []
 private var accountAt: [Int:Date] = [:]

 private var accountTasks: [Int:Task<Void,Never>] = [:]
 // One load at a time per robot; a second caller waits for the same load (the cards and the chart ask at once).
 func account(_ r: StockRobotInfo) async {
  if let t = accountTasks[r.id] { await t.value; return }
  if let at = accountAt[r.id], Date().timeIntervalSince(at) < 600, accounts[r.id] != nil { return }
  let task = Task { @MainActor in
   async let a = Self.get(StockHistory.raw + "paper/" + r.account)
   async let w = Self.get(StockHistory.raw + r.watchlist)
   let (ad,wd) = await (a,w)
   if let ad, let acct = StockHistory.parseAccount(ad) { self.accounts[r.id] = acct; self.accountProblem[r.id] = nil; self.accountAt[r.id] = Date() }
   else if self.accounts[r.id] == nil { self.accountProblem[r.id] = "Couldn't load this robot's order history from GitHub. Refresh tries again." }
   self.bench[r.id] = StockHistory.benchSymbol(watchlist:wd) ?? (r.crypto ? "BTC-USD" : "SPY")
  }
  accountTasks[r.id] = task
  await task.value
  accountTasks[r.id] = nil
 }

 static func get(_ url: String) async -> Data? {
  guard let u = URL(string:url + "?nc=\(Int(Date().timeIntervalSince1970))") else { return nil }
  var req = URLRequest(url:u,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:15)
  req.setValue("TheHelm",forHTTPHeaderField:"User-Agent")
  guard let (d,resp) = try? await URLSession.shared.data(for:req), (resp as? HTTPURLResponse)?.statusCode == 200 else { return nil }
  return d
 }

 // Account value vs just holding, rebuilt from the robot's own orders + public prices.
 // Charts load in an unstructured task too, so a view rebuild can't cancel a fetch into a stored "no prices" chart.
 func trajectory(_ r: StockRobotInfo,range: ChartRange,snap: StockRobot?) async { await Task { await self.trajectoryNow(r,range:range,snap:snap) }.value }
 func price(_ r: StockRobotInfo,holding h: StockHolding,range: ChartRange) async { await Task { await self.priceNow(r,holding:h,range:range) }.value }
 private func trajectoryNow(_ r: StockRobotInfo,range: ChartRange,snap: StockRobot?) async {
  let key = "traj|\(r.id)|\(range.rawValue)"
  guard !loading.contains(key) else { return }
  loading.insert(key); defer { loading.remove(key) }
  await account(r)
  guard let acct = accounts[r.id] else {
   charts[key] = ChartSeries(empty:accountProblem[r.id] ?? "No order history loaded yet."); return
  }
  let benchSym = bench[r.id] ?? "SPY"
  let b = await PriceCache.shared.series(benchSym,range:range,crypto:r.crypto,started:acct.started)
  guard let first = b.points.first, let lastT = b.points.last?.t else {
   charts[key] = ChartSeries(offline:true,empty:"No price history for \(benchSym) right now (offline, or Yahoo didn't answer). Nothing is drawn rather than a guess."); return
  }
  let syms = StockHistory.symbolsHeld(acct,from:first.t,to:max(lastT,Date()))
  var prices: [String:[PricePoint]] = [:]
  var offline = b.offline
  await withTaskGroup(of:(String,PriceCache.Result).self) { g in
   for s in syms where s != benchSym { g.addTask { (s,await PriceCache.shared.series(s,range:range,crypto:r.crypto,started:acct.started)) } }
   for await (s,res) in g { prices[s] = res.points; offline = offline || res.offline }
  }
  if syms.contains(benchSym) { prices[benchSym] = b.points }
  let benchIsSpy = acct.benchUnits == nil || benchSym == "SPY"
  let last = snap.flatMap { s in s.updated.map { (t:$0,value:s.value,hold:s.spyValue) } }
  let rebuilt = StockHistory.rebuild(acct,prices:prices,bench:b.points,benchIsSpy:benchIsSpy,last:last)
  guard rebuilt.value.count >= 2 else {
   charts[key] = ChartSeries(offline:offline,empty:"The robot started \(acct.started.map { StockHistory.age($0) } ?? "recently"): not enough history in this range yet. Try ALL.")
   return
  }
  var c = ChartSeries()
  c.lines = [(rebuilt.value,HubTheme.green,false,"Robot's account"),(rebuilt.hold,HubTheme.subtext,true,"Just holding \(benchSym == "BTC-USD" ? "Bitcoin" : benchSym)")]
  let from = rebuilt.value.first!.t
  c.marks = acct.orders.filter { $0.t >= from }
  c.dips = StockHistory.dips(rebuilt.value,pct:range.dipPct,window:range.dipWindow)
  c.offline = offline; c.fetched = b.fetched
  var note = "Rebuilt from the robot's recorded orders (stock_bot/paper/\(r.account)) and public Yahoo prices; no value history is recorded yet. Both lines use the same time points. Shaded: more than \(StockHistory.clean(range.dipPct))% below its high of the past \(range.windowWords)."
  if !rebuilt.unpriced.isEmpty { note += " No public price for \(rebuilt.unpriced.joined(separator:", ")): valued at its last trade." }
  c.note = note
  charts[key] = c
 }

 // One position's price, with entry / peak / stop and the robot's buys and sells of it.
 private func priceNow(_ r: StockRobotInfo,holding h: StockHolding,range: ChartRange) async {
  let key = "px|\(r.id)|\(h.symbol)|\(range.rawValue)"
  guard !loading.contains(key) else { return }
  loading.insert(key); defer { loading.remove(key) }
  await account(r)
  let res = await PriceCache.shared.series(h.symbol,range:range,crypto:r.crypto || h.symbol.hasSuffix("-USD"),started:accounts[r.id]?.started)
  guard res.points.count >= 2, let from = res.points.first?.t else {
   charts[key] = ChartSeries(offline:res.offline,empty:"No public price history for \(h.symbol) right now. Nothing is drawn rather than a guess."); return
  }
  var c = ChartSeries()
  c.lines = [(res.points,HubTheme.teal,false,h.symbol)]
  c.marks = (accounts[r.id]?.orders ?? []).filter { $0.symbol == h.symbol && $0.t >= from }
  c.dips = StockHistory.dips(res.points,pct:range.dipPct,window:range.dipWindow)
  if let e = h.entry { c.levels.append((e,"Bought at \(StockHistory.price(e))",HubTheme.subtext)) }
  if let s = h.stop { c.levels.append((s,"Stop \(StockHistory.price(s))",HubTheme.crimson)) }
  if let p = h.peak { c.levels.append((p,"Peak \(StockHistory.price(p))",HubTheme.amber)) }
  c.offline = res.offline; c.fetched = res.fetched
  c.note = "Public prices. Shaded: more than \(StockHistory.clean(range.dipPct))% below its high of the past \(range.windowWords)."
  charts[key] = c
 }
}

// MARK: the area

@MainActor final class StockAreaPageState: ObservableObject {
 @Published var tab = "Overview"
 @Published var range = ChartRange.all
 @Published var allOrders = false
 @Published var allNotes = false
}

struct StockArea: View {
 @ObservedObject var stocks: StockHub
 @ObservedObject var model = StockAreaModel.shared
 @StateObject private var page = StockAreaPageState()
 var compact: Bool
 var showSideCards: Bool       // Fleet comparison + Research notes go under the page when Friday's column isn't shown

 static let researchTab = 7
 var info: StockRobotInfo? { StockHistory.robots.first { $0.id == stocks.robot } }

 var body: some View {
  HStack(alignment:.top,spacing:0) {
   if !compact { fleet.frame(width:226) }
   ScrollView {
    VStack(alignment:.leading,spacing:14) {
     if compact { fleetChips }
     if stocks.robot == Self.researchTab { ResearchBotPanel() }
     else if let info { robotPage(info) }
     if showSideCards { StockSideCards(stocks:stocks,horizontal:!compact) }
     Text("Read-only paper portfolio · USD · practice money only. This area can't place an order and has no real-money switch.")
      .font(.system(size:11,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
    }
    .padding(.horizontal,compact ? 14 : 24).padding(.vertical,16)
   }
   .scrollIndicators(.hidden)
  }
  .background(HubTheme.background)
  .onChange(of:stocks.robot) { _,_ in page.tab = "Overview"; page.allOrders = false; page.allNotes = false }
  .task {   // test copies only: open on a given sub-tab / range for shots (after the robot switch settles)
   guard SwitchboardTestHooks.active else { return }
   try? await Task.sleep(nanoseconds:1_500_000_000)
   if let t = UserDefaults.standard.string(forKey:"stocks.testTab") { page.tab = t }
   if let r = UserDefaults.standard.string(forKey:"stocks.testRange"), let rg = ChartRange(rawValue:r) { page.range = rg }
  }
 }

 // MARK: fleet column
 private var fleet: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:6) {
    fleetLabel("ROBOT FLEET")
    ForEach(StockHistory.robots) { r in fleetRow(r) }
    fleetLabel("RESEARCH").padding(.top,10)
    researchRow
    Spacer(minLength:0)
   }
   .padding(.horizontal,12).padding(.vertical,16)
  }
  .scrollIndicators(.hidden)
  .background(HubTheme.sidebar)
  .overlay(alignment:.trailing) { Rectangle().fill(HubTheme.line).frame(width:1) }
 }
 private func fleetLabel(_ t: String) -> some View {
  Text(t).font(.system(size:11,weight:.medium,design:.monospaced)).tracking(2.4).foregroundStyle(HubTheme.subtext).padding(.horizontal,6).padding(.bottom,4)
 }
 private func fleetRow(_ r: StockRobotInfo) -> some View {
  let snap = stocks.all[r.id], selected = stocks.robot == r.id
  return Button { stocks.robot = r.id } label: {
   HStack(spacing:10) {
    Image(systemName:r.icon).font(.system(size:15,weight:.semibold)).foregroundStyle(selected ? HubTheme.green : HubTheme.subtext)
     .frame(width:34,height:34).background(HubTheme.control,in:RoundedRectangle(cornerRadius:9))
     .overlay(RoundedRectangle(cornerRadius:9).stroke(HubTheme.line,lineWidth:1))
    VStack(alignment:.leading,spacing:2) {
     Text(r.short).font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text).lineLimit(1).minimumScaleFactor(0.8)
     HStack(spacing:5) {
      FreshDot(level:snap == nil ? 2 : StockHistory.freshness(snap?.updated))
      Text(snap.map { StockHistory.age($0.updated) } ?? (stocks.loading ? "loading…" : "no snapshot"))
       .font(.system(size:11,design:.rounded)).foregroundStyle(HubTheme.subtext)
     }
    }
    Spacer(minLength:2)
    if let s = snap {   // NB2's honesty fix: say what the number is, so -$342 isn't read as "lost $342"
     VStack(alignment:.trailing,spacing:1) {
      Text(StockHistory.signed(s.vsHolding)).font(.system(size:11,weight:.medium,design:.rounded)).monospacedDigit()
       .foregroundStyle(s.vsHolding >= 0 ? HubTheme.green : HubTheme.crimson)
      Text("vs holding").font(.system(size:9.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
     }
    }
   }
   .padding(.horizontal,8).frame(maxWidth:.infinity,minHeight:52,alignment:.leading)
   .background(selected ? HubTheme.card : Color.clear,in:RoundedRectangle(cornerRadius:12))
   .overlay(RoundedRectangle(cornerRadius:12).stroke(selected ? HubTheme.green.opacity(0.7) : Color.clear,lineWidth:1.2))
  }
  .buttonStyle(.plain)
  .accessibilityLabel("\(r.group) robot \(r.short)\(snap.map { ", \(StockHistory.signed($0.vsHolding)) versus just holding" } ?? "")")
  .accessibilityAddTraits(selected ? .isSelected : [])
 }
 private var researchRow: some View {
  let selected = stocks.robot == Self.researchTab
  return Button { stocks.robot = Self.researchTab } label: {
   HStack(spacing:10) {
    Image(systemName:"flask.fill").font(.system(size:16,weight:.semibold)).foregroundStyle(HubTheme.amber)
     .frame(width:34,height:34).background(HubTheme.control,in:RoundedRectangle(cornerRadius:9))
    VStack(alignment:.leading,spacing:2) {
     Text("Research bot").font(.system(size:14,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
     Text("Guesses first, graded by code").font(.system(size:11,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    Spacer(minLength:0)
   }
   .padding(.horizontal,8).frame(maxWidth:.infinity,minHeight:58,alignment:.leading)
   .background(selected ? HubTheme.card : HubTheme.card.opacity(0.5),in:RoundedRectangle(cornerRadius:12))
   .overlay(RoundedRectangle(cornerRadius:12).stroke(selected ? HubTheme.amber : HubTheme.amber.opacity(0.35),lineWidth:selected ? 1.5 : 1))
  }
  .buttonStyle(.plain).accessibilityLabel("Research bot, practice money only").accessibilityAddTraits(selected ? .isSelected : [])
 }
 private var fleetChips: some View {
  ScrollView(.horizontal) {
   HStack(spacing:8) {
    ForEach(StockHistory.robots) { r in chip(r.short,selected:stocks.robot == r.id,tint:HubTheme.green) { stocks.robot = r.id } }
    chip("Research bot",selected:stocks.robot == Self.researchTab,tint:HubTheme.amber) { stocks.robot = Self.researchTab }
   }
  }
  .scrollIndicators(.hidden)
 }
 private func chip(_ t: String,selected: Bool,tint: Color,action: @escaping () -> Void) -> some View {
  Button(action:action) {
   Text(t).font(.system(size:12.5,weight:selected ? .semibold : .medium,design:.rounded)).foregroundStyle(selected ? HubTheme.text : HubTheme.subtext)
    .padding(.horizontal,14).frame(minHeight:40)
    .background(selected ? HubTheme.card : HubTheme.control,in:RoundedRectangle(cornerRadius:10))
    .overlay(RoundedRectangle(cornerRadius:10).stroke(selected ? tint : HubTheme.line,lineWidth:1))
  }.buttonStyle(.plain)
 }

 // MARK: one robot
 @ViewBuilder private func robotPage(_ r: StockRobotInfo) -> some View {
  let snap = stocks.all[r.id]
  header(r,snap)
  if let s = snap {
   cards(r,s)
   tabs
   switch page.tab {
   case "Holdings": holdings(r,s)
   case "Trade journal": journal(r,s,limit:nil)
   case "Rules & risk": rules(r,s)
   default: overview(r,s)
   }
  } else {
   StockCard {
    VStack(alignment:.leading,spacing:6) {
     if stocks.loading { ProgressView().controlSize(.small) }
     Text(stocks.loading ? "Reading this robot's snapshot…" : "This robot's snapshot couldn't be loaded").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
     Text("Its numbers stay blank rather than guessed. The other robots may still have snapshots. Refresh tries again.")
      .font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
    }
   }
  }
 }

 private func header(_ r: StockRobotInfo,_ s: StockRobot?) -> some View {
  VStack(alignment:.leading,spacing:6) {
   HStack(alignment:.firstTextBaseline,spacing:12) {
    Text("\(r.group) / \(r.name)").font(.system(size:compact ? 24 : 30,weight:.bold,design:.serif)).foregroundStyle(HubTheme.text)
     .lineLimit(1).minimumScaleFactor(0.7).accessibilityAddTraits(.isHeader)
    Text("PAPER ONLY").font(.system(size:11,weight:.bold,design:.monospaced)).tracking(1.6).foregroundStyle(HubTheme.amber)
     .padding(.horizontal,9).padding(.vertical,4).overlay(RoundedRectangle(cornerRadius:6).stroke(HubTheme.amber.opacity(0.7),lineWidth:1))
     .accessibilityLabel("Paper only, practice money")
    Spacer(minLength:4)
    Button { Task { await stocks.refresh() } } label: {
     Label(stocks.loading ? "Refreshing…" : "Refresh",systemImage:"arrow.clockwise").font(.system(size:12,weight:.semibold,design:.rounded))
      .foregroundStyle(HubTheme.text).padding(.horizontal,12).frame(minHeight:36)
      .background(HubTheme.control,in:RoundedRectangle(cornerRadius:10)).overlay(RoundedRectangle(cornerRadius:10).stroke(HubTheme.controlOutline,lineWidth:1))
    }.buttonStyle(.plain).disabled(stocks.loading)
   }
   HStack(spacing:6) {
    FreshDot(level:s == nil ? 2 : StockHistory.freshness(s?.updated))
    Text(s?.updated.map { "Snapshot: \($0.formatted(date:.abbreviated,time:.shortened)) · \(StockHistory.age($0))" } ?? "No snapshot loaded")
    if let s { Text("· market \(s.marketOpen ? "open" : "closed")\(s.paused ? " · robot marked paused" : "")").foregroundStyle(s.paused ? HubTheme.amber : HubTheme.subtext) }
   }
   .font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
 }

 private func cards(_ r: StockRobotInfo,_ s: StockRobot) -> some View {
  let acct = model.accounts[r.id]
  let base = acct.map { $0.startCash + $0.deposits.reduce(0) { $0 + $1.usd } } ?? (s.startCash > 0 ? s.startCash : 1000)
  let net = s.value - base
  let cols = compact ? [GridItem(.flexible(),spacing:12),GridItem(.flexible(),spacing:12)] : [GridItem(.adaptive(minimum:190),spacing:12)]
  return LazyVGrid(columns:cols,spacing:12) {
   stat("Portfolio",StockHistory.money(s.value),"briefcase",HubTheme.text,"practice value now")
   stat("Net return",StockHistory.signed(net),net >= 0 ? "arrow.up.right" : "arrow.down.right",net >= 0 ? HubTheme.green : HubTheme.crimson,"\(StockHistory.pct(base > 0 ? net / base * 100 : nil)) vs \(StockHistory.money(base)) put in")
   stat("Ahead of holding",StockHistory.signed(s.vsHolding),"chart.line.uptrend.xyaxis",s.vsHolding >= 0 ? HubTheme.green : HubTheme.crimson,"holding \(s.benchmark.isEmpty ? "SPY" : s.benchmark): \(StockHistory.money(s.spyValue))")
   stat("Cash",StockHistory.money(s.cash),"banknote",HubTheme.text,"not invested")
  }
  .task(id:r.id) { await model.account(r) }
 }
 private func stat(_ title: String,_ value: String,_ icon: String,_ tint: Color,_ foot: String) -> some View {
  HStack(alignment:.top,spacing:12) {
   Image(systemName:icon).font(.system(size:17,weight:.semibold)).foregroundStyle(tint == HubTheme.text ? HubTheme.subtext : tint).frame(width:22)
   VStack(alignment:.leading,spacing:3) {
    Text(title).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.subtext)
    Text(value).font(.system(size:21,weight:.bold,design:.rounded)).monospacedDigit().foregroundStyle(tint).lineLimit(1).minimumScaleFactor(0.55)
    Text(foot).font(.system(size:11,design:.rounded)).foregroundStyle(HubTheme.subtext).lineLimit(1).minimumScaleFactor(0.8)
   }
   Spacer(minLength:0)
  }
  .padding(14).frame(maxWidth:.infinity,minHeight:86,alignment:.topLeading).stockCard()
  .accessibilityElement(children:.combine)
 }

 private var tabs: some View {
  HStack(spacing:6) {
   ForEach(["Overview","Holdings","Trade journal","Rules & risk"],id:\.self) { t in
    Button { page.tab = t } label: {
     Text(t).font(.system(size:12.5,weight:page.tab == t ? .semibold : .medium,design:.rounded)).foregroundStyle(page.tab == t ? HubTheme.text : HubTheme.subtext)
      .frame(maxWidth:.infinity,minHeight:38)
      .background(page.tab == t ? HubTheme.card : HubTheme.control,in:RoundedRectangle(cornerRadius:10))
      .overlay(RoundedRectangle(cornerRadius:10).stroke(page.tab == t ? HubTheme.green.opacity(0.7) : HubTheme.line,lineWidth:1))
    }.buttonStyle(.plain).accessibilityAddTraits(page.tab == t ? .isSelected : [])
   }
  }
 }

 // MARK: overview
 @ViewBuilder private func overview(_ r: StockRobotInfo,_ s: StockRobot) -> some View {
  let key = "traj|\(r.id)|\(page.range.rawValue)"
  StockCard {
   VStack(alignment:.leading,spacing:10) {
    HStack {
     Label("Portfolio trajectory",systemImage:"chart.bar.xaxis").font(.system(size:17,weight:.semibold,design:.serif)).foregroundStyle(HubTheme.text)
     Spacer(minLength:4)
     rangePicker
    }
    StockChartBox(series:model.charts[key],loading:model.loading.contains(key),height:compact ? 190 : 240)
   }
  }
  .task(id:key) { await model.trajectory(r,range:page.range,snap:s) }
  strip(r,s)
  Text("Sources: the cards come from the robot's own snapshot (time above). Orders come from its paper account file on GitHub. Prices come from Yahoo's public charts. Practice money only.")
   .font(.system(size:11,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
  if compact {
   journal(r,s,limit:5); notes(s)
  } else {
   HStack(alignment:.top,spacing:12) { journal(r,s,limit:5); notes(s) }
  }
 }
 private var rangePicker: some View {
  HStack(spacing:0) {
   ForEach(ChartRange.allCases) { rg in
    Button { page.range = rg } label: {
     Text(rg.rawValue).font(.system(size:11.5,weight:page.range == rg ? .bold : .medium,design:.rounded))
      .foregroundStyle(page.range == rg ? HubTheme.text : HubTheme.subtext).frame(width:40,height:28)
      .background(page.range == rg ? HubTheme.card : Color.clear,in:RoundedRectangle(cornerRadius:7))
    }.buttonStyle(.plain).accessibilityLabel("Show \(rg.rawValue)").accessibilityAddTraits(page.range == rg ? .isSelected : [])
   }
  }
  .padding(2).background(HubTheme.control,in:RoundedRectangle(cornerRadius:9)).overlay(RoundedRectangle(cornerRadius:9).stroke(HubTheme.line,lineWidth:1))
 }
 private func strip(_ r: StockRobotInfo,_ s: StockRobot) -> some View {
  HStack(spacing:0) {
   stripItem("square.stack.3d.up","\(s.holdings.count) position\(s.holdings.count == 1 ? "" : "s")")
   Divider().frame(height:22).overlay(HubTheme.line)
   stripItem("arrow.left.arrow.right","\(s.trades) recorded trade\(s.trades == 1 ? "" : "s")")
   Divider().frame(height:22).overlay(HubTheme.line)
   stripItem("creditcard","Fees \(StockHistory.money(s.fees))")
  }
  .frame(minHeight:46).stockCard()
 }
 private func stripItem(_ icon: String,_ t: String) -> some View {
  Label(t,systemImage:icon).font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.text).frame(maxWidth:.infinity)
 }

 // MARK: journal (every order from the account file; the snapshot's recent ones if that file isn't loaded)
 private func journal(_ r: StockRobotInfo,_ s: StockRobot,limit: Int?) -> some View {
  let orders = (model.accounts[r.id]?.orders ?? []).reversed() as [PaperOrder]
  let shown = limit.map { Array(orders.prefix($0)) } ?? (page.allOrders ? orders : Array(orders.prefix(25)))
  return StockCard {
   VStack(alignment:.leading,spacing:8) {
    Label("Trade journal",systemImage:"book").font(.system(size:16,weight:.semibold,design:.serif)).foregroundStyle(HubTheme.text)
    if orders.isEmpty {
     Text(model.accountProblem[r.id] ?? (model.accounts[r.id] == nil ? "Loading the robot's orders…" : "No trades yet: waiting is a normal outcome."))
      .font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
    }
    ForEach(shown) { o in
     VStack(alignment:.leading,spacing:2) {
      HStack(spacing:6) {
       Image(systemName:o.side == "buy" ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size:9)).foregroundStyle(o.side == "buy" ? HubTheme.green : HubTheme.amber)
       Text("\(o.side == "buy" ? "Bought" : "Sold") \(o.symbol)").font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
       Spacer(minLength:4)
       if let p = o.realized { Text(StockHistory.signed(p)).font(.system(size:13,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(p >= 0 ? HubTheme.green : HubTheme.crimson) }
       else { Text(StockHistory.money(o.qty * o.price)).font(.system(size:13,design:.rounded)).monospacedDigit().foregroundStyle(HubTheme.text) }
      }
      Text("\(o.t.formatted(date:.abbreviated,time:.shortened)) · at \(StockHistory.price(o.price)) · fee \(StockHistory.money(o.fee))\(o.realized != nil ? " · result after fees" : "")")
       .font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
     }
     .accessibilityElement(children:.combine)
    }
    if limit == nil && orders.count > 25 {
     Button { page.allOrders.toggle() } label: { Label(page.allOrders ? "Show fewer" : "Show all \(orders.count) orders",systemImage:page.allOrders ? "chevron.up" : "chevron.down").font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text) }.buttonStyle(.plain)
    }
    if limit != nil && orders.count > (limit ?? 0) {
     Button { page.tab = "Trade journal" } label: { Text("All \(orders.count) orders →").font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.green) }.buttonStyle(.plain)
    }
   }
  }
 }

 // MARK: why it acted or waited (the robot's own notes)
 private func notes(_ s: StockRobot) -> some View {
  let shown = page.allNotes ? s.notes : Array(s.notes.prefix(5))
  return StockCard {
   VStack(alignment:.leading,spacing:8) {
    Label("Why it acted or waited",systemImage:"text.bubble").font(.system(size:16,weight:.semibold,design:.serif)).foregroundStyle(HubTheme.text)
    if shown.isEmpty { Text("This snapshot has no notes from the robot.").font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.subtext) }
    ForEach(shown) { n in
     VStack(alignment:.leading,spacing:1) {
      Text(n.text).font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
      Text(n.time.map { "\($0.formatted(date:.abbreviated,time:.shortened)) · \(StockHistory.age($0))" } ?? "time not given").font(.system(size:11,design:.rounded)).foregroundStyle(HubTheme.subtext)
     }
    }
    if s.notes.count > 5 {
     Button { page.allNotes.toggle() } label: { Text(page.allNotes ? "Show fewer" : "Show all \(s.notes.count) notes").font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.green) }.buttonStyle(.plain)
    }
   }
  }
 }

 // MARK: holdings: a price chart per position
 @ViewBuilder private func holdings(_ r: StockRobotInfo,_ s: StockRobot) -> some View {
  HStack { Text("Each position's public price. Its buys and sells are marked, and dips are shaded.").font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.subtext); Spacer(); rangePicker }
  if s.holdings.isEmpty {
   StockCard { Text("No positions right now: all cash. Waiting is a normal outcome.").font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.subtext) }
  }
  ForEach(s.holdings) { h in
   let key = "px|\(r.id)|\(h.symbol)|\(page.range.rawValue)"
   StockCard {
    VStack(alignment:.leading,spacing:8) {
     HStack(alignment:.firstTextBaseline) {
      Text(h.symbol).font(.system(size:17,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
      if let c = h.changePct { Text(StockHistory.pct(c) + " since bought").font(.system(size:12.5,weight:.medium,design:.rounded)).foregroundStyle(c >= 0 ? HubTheme.green : HubTheme.crimson) }
      Spacer()
      Text(StockHistory.money(h.value)).font(.system(size:15,weight:.semibold,design:.rounded)).monospacedDigit().foregroundStyle(HubTheme.text)
     }
     if let p = h.price, let st = h.stop, p > 0 {
      Text("Its stop is \(StockHistory.price(st)), \(String(format:"%.1f",(p - st) / p * 100))% below the snapshot price \(StockHistory.price(p)).")
       .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
     }
     StockChartBox(series:model.charts[key],loading:model.loading.contains(key),height:compact ? 160 : 190)
    }
   }
   .task(id:key) { await model.price(r,holding:h,range:page.range) }
  }
 }

 // MARK: rules & risk
 private func rules(_ r: StockRobotInfo,_ s: StockRobot) -> some View {
  StockCard {
   VStack(alignment:.leading,spacing:8) {
    Label("Its own rules",systemImage:"list.bullet.rectangle").font(.system(size:16,weight:.semibold,design:.serif)).foregroundStyle(HubTheme.text)
    Text("As the robot's snapshot lists them. Changing a rule is a code change that goes through review, never a switch here.")
     .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
    if s.rules.isEmpty { Text("This robot's snapshot doesn't list its rules. They're in stock_bot/\(r.watchlist) and its code.").font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.subtext) }
    ForEach(Array(s.rules.enumerated()),id:\.offset) { _,rule in
     let r = StockHistory.rule(rule.key,rule.value)
     HStack(alignment:.firstTextBaseline,spacing:10) {
      Text(r.value).font(.system(size:13.5,weight:.bold,design:.rounded)).monospacedDigit().foregroundStyle(HubTheme.text).frame(minWidth:64,alignment:.trailing)
      VStack(alignment:.leading,spacing:1) {
       Text(r.meaning).font(.system(size:13,design:.rounded)).foregroundStyle(r.meaning.hasPrefix("Meaning not verified") ? HubTheme.amber : HubTheme.text).fixedSize(horizontal:false,vertical:true)
       Text(rule.key).font(.system(size:10.5,design:.monospaced)).foregroundStyle(HubTheme.subtext)
      }
     }
     .accessibilityElement(children:.combine)
    }
    let stops = s.holdings.filter { $0.stop != nil }
    if !stops.isEmpty {
     Divider().overlay(HubTheme.line)
     Text("Stops on what it holds").font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
     ForEach(stops) { h in
      Text("• \(h.symbol): sells if it falls to \(StockHistory.price(h.stop ?? 0))\(h.price.map { p in p > 0 ? String(format:" (%.1f%% below now)",(p - (h.stop ?? 0)) / p * 100) : "" } ?? "")")
       .font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.text)
     }
    }
   }
  }
 }
}

// MARK: Fleet comparison + Research notes (Friday's column on this page, or under the page)

struct StockSideCards: View {
 @ObservedObject var stocks: StockHub
 @ObservedObject var research = ResearchBotModel.shared
 var horizontal = false

 var body: some View {
  Group {
   if horizontal { HStack(alignment:.top,spacing:12) { fleetCard; notesCard } }
   else { VStack(alignment:.leading,spacing:12) { fleetCard; notesCard } }
  }
  .task { if research.snap == nil { await research.refresh() } }
 }

 private var ranked: [(StockRobotInfo,StockRobot)] {
  StockHistory.robots.compactMap { r in stocks.all[r.id].map { (r,$0) } }.sorted { $0.1.vsHolding > $1.1.vsHolding }
 }

 private var fleetCard: some View {
  side("Fleet comparison","square.3.layers.3d") {
   if ranked.isEmpty {
    Text(stocks.loading ? "Loading the robots' snapshots…" : "No robot snapshots loaded, so nothing to rank yet.").font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
   } else {
    Text("Ahead of just holding, best first").font(.system(size:11,design:.rounded)).foregroundStyle(HubTheme.subtext)
    ForEach(Array(ranked.enumerated()),id:\.offset) { i,pair in
     Button { stocks.robot = pair.0.id } label: {
      HStack(spacing:6) {
       Text("\(i + 1)").font(.system(size:11,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.subtext).frame(width:14)
       FreshDot(level:StockHistory.freshness(pair.1.updated))
       Text(pair.0.short).font(.system(size:12.5,weight:stocks.robot == pair.0.id ? .bold : .medium,design:.rounded)).foregroundStyle(HubTheme.text)
       Spacer(minLength:2)
       Text(StockHistory.signed(pair.1.vsHolding)).font(.system(size:12,weight:.semibold,design:.rounded)).monospacedDigit()
        .foregroundStyle(pair.1.vsHolding >= 0 ? HubTheme.green : HubTheme.crimson)
      }.frame(minHeight:24)
     }.buttonStyle(.plain)
    }
    let missing = StockHistory.robots.filter { stocks.all[$0.id] == nil }
    if !missing.isEmpty { Text("Not loaded: \(missing.map(\.short).joined(separator:", "))").font(.system(size:11,design:.rounded)).foregroundStyle(HubTheme.amber) }
    Text("Each uses its own snapshot time (dot: green under 2 h old, amber under a day, red older).").font(.system(size:10.5,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
   }
  }
 }

 private var notesCard: some View {
  side("Research notes","doc.text") {
   if let s = research.snap {
    if s.forecasts.isEmpty {
     Text("No guesses yet: no trade is a normal day.").font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
    }
    ForEach(Array(s.forecasts.prefix(3))) { f in
     VStack(alignment:.leading,spacing:1) {
      Text("\(f.asset) \(f.direction.lowercased() == "down" ? "down" : "up")\(f.probability.map { " · \(Int(($0 * 100).rounded()))% sure" } ?? "")").font(.system(size:12.5,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
      if !f.reason.isEmpty { Text(ResearchBotData.why(f)?.text ?? f.reason).font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext).lineLimit(3) }
     }
    }
    Button { stocks.robot = StockArea.researchTab } label: { Text("Open the Research bot →").font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.amber) }.buttonStyle(.plain)
   } else {
    Text(research.loading ? "Reading the research bot's files…" : "Research files not loaded.").font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
   }
  }
 }

 private func side<C: View>(_ title: String,_ icon: String,@ViewBuilder _ content: () -> C) -> some View {
  VStack(alignment:.leading,spacing:8) {
   Label(title,systemImage:icon).font(.system(size:15,weight:.semibold,design:.serif)).foregroundStyle(HubTheme.text)
   Divider().overlay(HubTheme.line)
   content()
  }
  .padding(14).frame(maxWidth:.infinity,alignment:.leading).stockCard()
 }
}

// MARK: chart

struct StockChartBox: View {
 var series: ChartSeries?
 var loading: Bool
 var height: CGFloat

 var body: some View {
  VStack(alignment:.leading,spacing:6) {
   if let s = series, s.empty.isEmpty {
    if s.lines.count > 1 || !s.marks.isEmpty {
     HStack(spacing:12) {
      ForEach(Array(s.lines.enumerated()),id:\.offset) { _,l in legend(l.color,l.label,dashed:l.dashed) }
      if !s.marks.isEmpty {
       Label("buy",systemImage:"arrowtriangle.up.fill").foregroundStyle(HubTheme.green)
       Label("sell",systemImage:"arrowtriangle.down.fill").foregroundStyle(HubTheme.amber)
      }
     }
     .font(.system(size:11,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    StockLineChart(series:s).frame(height:height)
    Text(s.note + (s.offline ? " Offline: showing prices saved \(s.fetched.map { StockHistory.age($0) } ?? "earlier")." : ""))
     .font(.system(size:11,design:.rounded)).foregroundStyle(s.offline ? HubTheme.amber : HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
   } else {
    VStack(spacing:8) {
     if loading || series == nil { ProgressView().controlSize(.small) ; Text("Loading prices…").font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.subtext) }
     else {
      Image(systemName:"chart.xyaxis.line").font(.system(size:28,weight:.light)).foregroundStyle(HubTheme.subtext)
      Text(series?.empty ?? "").font(.system(size:13,design:.rounded)).italic().foregroundStyle(HubTheme.subtext).multilineTextAlignment(.center).fixedSize(horizontal:false,vertical:true)
     }
    }
    .frame(maxWidth:.infinity,minHeight:height)
   }
  }
 }
 private func legend(_ c: Color,_ t: String,dashed: Bool) -> some View {
  HStack(spacing:5) {
   Capsule().fill(dashed ? c.opacity(0.6) : c).frame(width:16,height:dashed ? 2 : 3)
   Text(t)
  }
 }
}

@MainActor final class ChartHover: ObservableObject { @Published var x: CGFloat? }

struct StockLineChart: View {
 var series: ChartSeries
 @StateObject private var hover = ChartHover()

 var body: some View {
  GeometryReader { geo in
   let all = series.lines.flatMap { $0.points }
   let t0 = all.map(\.t).min() ?? Date(), t1 = all.map(\.t).max() ?? Date()
   let vals = all.map(\.v) + series.levels.map(\.value)
   let lo0 = vals.min() ?? 0, hi0 = vals.max() ?? 1
   let pad = max((hi0 - lo0) * 0.08,abs(hi0) * 0.002)
   let lo = lo0 - pad, hi = hi0 + pad
   let left: CGFloat = 64, top: CGFloat = 8, w = max(geo.size.width - left - 8,10), h = max(geo.size.height - 20 - top,10)
   let span = max(t1.timeIntervalSince(t0),1)
   let X: (Date) -> CGFloat = { left + CGFloat($0.timeIntervalSince(t0) / span) * w }
   let Y: (Double) -> CGFloat = { top + CGFloat((hi - $0) / max(hi - lo,1e-12)) * h }
   ZStack(alignment:.topLeading) {
    // grid + axis labels
    ForEach(0..<4) { i in
     let v = hi - (hi - lo) * Double(i) / 3
     Path { p in p.move(to:CGPoint(x:left,y:Y(v))); p.addLine(to:CGPoint(x:left + w,y:Y(v))) }.stroke(HubTheme.line.opacity(0.6),lineWidth:0.5)
     Text(StockHistory.price(v)).font(.system(size:9.5,design:.rounded)).monospacedDigit().foregroundStyle(HubTheme.subtext)
      .lineLimit(1).minimumScaleFactor(0.6).frame(width:left - 6,alignment:.trailing).position(x:(left - 6) / 2,y:Y(v))
    }
    // dips
    ForEach(Array(series.dips.enumerated()),id:\.offset) { _,d in
     Rectangle().fill(HubTheme.crimson.opacity(0.08)).frame(width:max(X(d.to) - X(d.from),2),height:h).offset(x:X(d.from),y:top)
    }
    // each dip's depth, where there's room for the label
    ForEach(Array(series.dips.enumerated()),id:\.offset) { _,d in
     if X(d.to) - X(d.from) > 34 {
      Text("−\(StockHistory.clean((d.depth * 10).rounded() / 10))%").font(.system(size:9,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.crimson.opacity(0.9))
       .position(x:(X(d.from) + X(d.to)) / 2,y:top + h - 8)
     }
    }
    // reference levels
    ForEach(Array(series.levels.enumerated()),id:\.offset) { i,l in
     Path { p in p.move(to:CGPoint(x:left,y:Y(l.value))); p.addLine(to:CGPoint(x:left + w,y:Y(l.value))) }
      .stroke(l.color.opacity(0.8),style:StrokeStyle(lineWidth:1,dash:[4,4]))
     Text(l.label).font(.system(size:9.5,weight:.medium,design:.rounded)).foregroundStyle(l.color).padding(.horizontal,4)
      .background(HubTheme.card.opacity(0.85)).position(x:left + w - 60 - CGFloat(i) * min(150,w / 4),y:Y(l.value) - 8)
    }
    // lines
    ForEach(Array(series.lines.enumerated()).reversed(),id:\.offset) { _,l in
     Path { p in
      for (i,pt) in l.points.enumerated() { let c = CGPoint(x:X(pt.t),y:Y(pt.v)); if i == 0 { p.move(to:c) } else { p.addLine(to:c) } }
     }
     .stroke(l.color.opacity(l.dashed ? 0.65 : 1),style:StrokeStyle(lineWidth:l.dashed ? 1.3 : 2,lineJoin:.round,dash:l.dashed ? [5,4] : []))
    }
    // buys / sells on the first line
    if let first = series.lines.first?.points, !first.isEmpty {
     ForEach(series.marks) { o in
      let v = first.last { $0.t <= o.t }?.v ?? first.first!.v
      Image(systemName:o.side == "buy" ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill").font(.system(size:9))
       .foregroundStyle(o.side == "buy" ? HubTheme.green : HubTheme.amber)
       .position(x:X(o.t),y:Y(v) + (o.side == "buy" ? 10 : -10))
       .help("\(o.side == "buy" ? "Bought" : "Sold") \(o.symbol) at \(StockHistory.price(o.price)), \(o.t.formatted(date:.abbreviated,time:.shortened))")
     }
    }
    // x labels
    Text(t0.formatted(date:.abbreviated,time:span < 3 * 86400 ? .shortened : .omitted)).font(.system(size:9.5,design:.rounded)).foregroundStyle(HubTheme.subtext).position(x:left + 40,y:top + h + 12)
    Text(t1.formatted(date:.abbreviated,time:span < 3 * 86400 ? .shortened : .omitted)).font(.system(size:9.5,design:.rounded)).foregroundStyle(HubTheme.subtext).position(x:left + w - 40,y:top + h + 12)
    // hover readout
    if let hx = hover.x, hx >= left, hx <= left + w {
     let t = t0.addingTimeInterval(Double((hx - left) / w) * span)
     Path { p in p.move(to:CGPoint(x:hx,y:top)); p.addLine(to:CGPoint(x:hx,y:top + h)) }.stroke(HubTheme.subtext.opacity(0.5),lineWidth:0.7)
     VStack(alignment:.leading,spacing:2) {
      Text(t.formatted(date:.abbreviated,time:.shortened)).foregroundStyle(HubTheme.subtext)
      ForEach(Array(series.lines.enumerated()),id:\.offset) { _,l in
       if let v = l.points.last(where:{ $0.t <= t })?.v { Text("\(l.label): \(StockHistory.price(v))").foregroundStyle(l.color) }
      }
     }
     .font(.system(size:10.5,weight:.medium,design:.rounded)).monospacedDigit().padding(6)
     .background(HubTheme.background.opacity(0.92),in:RoundedRectangle(cornerRadius:6)).overlay(RoundedRectangle(cornerRadius:6).stroke(HubTheme.line,lineWidth:1))
     .position(x:min(max(hx,left + 90),left + w - 90),y:28)
    }
   }
   .contentShape(Rectangle())
   .onContinuousHover { phase in
    switch phase { case .active(let p): hover.x = p.x; case .ended: hover.x = nil }
   }
  }
  .accessibilityElement(children:.ignore)
  .accessibilityLabel(accessibilitySummary)
 }

 private var accessibilitySummary: String {
  series.lines.compactMap { l in
   guard let a = l.points.first?.v, let b = l.points.last?.v else { return nil }
   return "\(l.label): from \(StockHistory.price(a)) to \(StockHistory.price(b))"
  }.joined(separator:". ") + (series.dips.isEmpty ? "" : ". \(series.dips.count) dip\(series.dips.count == 1 ? "" : "s") shaded.")
 }
}

// MARK: small pieces

struct FreshDot: View {
 var level: Int
 var body: some View {
  Circle().fill(level == 0 ? HubTheme.green : level == 1 ? HubTheme.amber : HubTheme.crimson).frame(width:7,height:7)
   .accessibilityLabel(level == 0 ? "fresh" : level == 1 ? "older than 2 hours" : "older than a day")
 }
}

struct StockCard<C: View>: View {
 @ViewBuilder var content: C
 var body: some View { content.padding(16).frame(maxWidth:.infinity,alignment:.leading).stockCard() }
}

extension View {
 func stockCard() -> some View {
  background(HubTheme.card,in:RoundedRectangle(cornerRadius:16))
   .overlay(RoundedRectangle(cornerRadius:16).stroke(HubTheme.line,lineWidth:1))
 }
}
