import SwiftUI

// The research bot's own big tab on the Stock bot page. PRACTICE MONEY ONLY.
// Shows the plain-code scorecard (stocks and crypto separate), the latest guesses with their reasons, the practice orders and the status.
// READ-ONLY: no order button, no keys, no real-money switch, no pause/resume. The Pause spot is kept, off, with a "How to pause" box
// (NB2, 2026-11-10). The bot runs hourly since 9:38 that day and pulls master each run, so a pushed PAUSE file stops it next run.
@MainActor final class ResearchBotModel: ObservableObject {
 static let shared = ResearchBotModel()
 @Published var snap: ResearchSnapshot?
 @Published var loading = false
 // Test copies only (SwitchboardTestHooks.active, never the real Helm's app ID):
 //   research.testDir  (path)  read the bot's files from this folder (laid out like stock_bot/) instead of GitHub
 //   stocks.testResearch (bool) open the Stock bot page on the Research bot tab

 func refresh() async {
  guard !loading else { return }
  loading = true; defer { loading = false }
  // An unstructured task: SwiftUI cancels a view's .task when the view is rebuilt, and a cancelled read must not
  // become "no connection" on screen (NB2 caught this on v2). A cancelled load returns nil and the old snapshot stays.
  let dir = SwitchboardTestHooks.active ? UserDefaults.standard.string(forKey:"research.testDir") : nil
  let fresh = await Task {
   if let dir { return await ResearchBotData.load { p in (try? Data(contentsOf:URL(fileURLWithPath:dir).appendingPathComponent(p))).map { .ok($0) } ?? .missing } }
   return await ResearchBotData.load(ResearchBotData.fetchGitHub)
  }.value
  if let fresh { snap = fresh }
 }

}

// Local UI state (StateObject: this Mac's command-line Swift has no @State macro plugin).
@MainActor final class ResearchBotPageState: ObservableObject {
 @Published var allForecasts = false
 @Published var allOrders = false
 @Published var details: Set<String> = []
}

struct ResearchBotPanel: View {
 @ObservedObject var model = ResearchBotModel.shared
 @StateObject private var page = ResearchBotPageState()

 var body: some View {
  VStack(alignment:.leading,spacing:16) {
   header
   if let s = model.snap {
    status(s)
    howToPause
    if s.nothingYet {
     card {
      VStack(alignment:.leading,spacing:6) {
       Text("No guesses yet: no trade is a normal day").font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
       Text("The bot writes a guess down before the market moves, then plain code grades it. Until the first guess is written, there's nothing to grade, and that's fine.")
        .font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
      }
     }
    }
    ForEach(s.markets) { scorecard($0) }
    forecasts(s)
    orders(s)
    if let caps = s.caps {
     Text("Its limits: \(caps)").font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
    }
    Text(footnote(s)).font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
   } else {
    card {
     HStack(spacing:10) {
      if model.loading { ProgressView().controlSize(.small) }
      Text(model.loading ? "Reading the research bot's files…" : "Not loaded yet. Press Refresh.")
       .font(.system(size:14,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.text)
     }
    }
   }
  }
  .task { if model.snap == nil { await model.refresh() } }
 }

 // MARK: pieces
 private var header: some View {
  VStack(alignment:.leading,spacing:8) {
   HStack(spacing:10) {
    Text("Research bot").font(.system(size:20,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text).accessibilityAddTraits(.isHeader)
    Spacer(minLength:4)
    Button { Task { await model.refresh() } } label: {
     Label(model.loading ? "Refreshing…" : "Refresh",systemImage:"arrow.clockwise").font(.system(size:12,weight:.semibold,design:.rounded))
      .foregroundStyle(HubTheme.text).padding(.horizontal,12).frame(minHeight:44)
      .background(HubTheme.control,in:RoundedRectangle(cornerRadius:12))
      .overlay(RoundedRectangle(cornerRadius:12).stroke(HubTheme.controlOutline,lineWidth:1))
    }
    .buttonStyle(.plain).disabled(model.loading).accessibilityLabel("Refresh the research bot's files")
   }
   Text("PRACTICE MONEY ONLY").font(.system(size:12,weight:.heavy,design:.rounded)).tracking(1)
    .foregroundStyle(HubTheme.amber).padding(.horizontal,10).padding(.vertical,5)
    .overlay(RoundedRectangle(cornerRadius:8).stroke(HubTheme.amber,lineWidth:1.5))
    .accessibilityLabel("Practice money only")
   Text("It writes each guess down before the market moves, then plain code (not the AI) grades it against simple guesses like a coin flip. \"No edge found\" is a normal, useful answer.")
    .font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
  }
 }

 private func status(_ s: ResearchSnapshot) -> some View {
  let (title,why,tint): (String,String,Color) = {
   switch s.state {
   // Roxy's point: the file being on GitHub isn't proof the runner has seen it yet.
   case .paused(let why): return ("PAUSE REQUESTED","\(why) Requested, not confirmed: the bot stops at its next hourly run, but it doesn't report back yet when it has seen the file. A person deletes the file to let it run again.",HubTheme.amber)
   case .autoPaused(let why): return ("AUTO-PAUSED","It paused itself: \(why). No new practice buys; it can still close trades that are due. A person reads why and deletes AUTO_PAUSE.",HubTheme.crimson)
   case .unknown(let why): return ("CAN'T TELL",why,HubTheme.subtext)
   case .on: return ("NOT PAUSED","It runs by itself every hour on this Mac (at :25). Each run pulls GitHub first, so a PAUSE file stops it at the next run.",HubTheme.green)
   }
  }()
  return card {
   VStack(alignment:.leading,spacing:10) {
    HStack(spacing:8) {
     Circle().fill(tint).frame(width:10,height:10)
     Text(title).font(.system(size:15,weight:.bold,design:.rounded)).foregroundStyle(tint)
     Spacer(minLength:4)
     Label("Pause",systemImage:"pause.fill").font(.system(size:12.5,weight:.semibold,design:.rounded))
      .foregroundStyle(HubTheme.subtext.opacity(0.6)).padding(.horizontal,14).frame(minHeight:44)
      .background(HubTheme.card,in:RoundedRectangle(cornerRadius:12))
      .overlay(RoundedRectangle(cornerRadius:12).stroke(HubTheme.line,lineWidth:1))
      .help("Off for now. See How to pause below.")
      .accessibilityLabel("Pause button, off for now. See How to pause below.")
    }
    Text(why).font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
    if s.practiceOnly == false {
     Text("Its rules file no longer says practice only, so its own checker refuses every order. A crew chat should look.")
      .font(.system(size:12.5,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.crimson).fixedSize(horizontal:false,vertical:true)
    }
    Text("The Pause button is off for now: use How to pause below.").font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
   }
  }
 }

 private var howToPause: some View {
  card {
   VStack(alignment:.leading,spacing:6) {
    Label("How to pause",systemImage:"pause.circle").font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
    Text("1. Ask any crew chat: \"pause the research bot\".\n2. It adds a file named PAUSE in stock_bot/research_bot/ (or stock_bot/PAUSE to stop every robot) and pushes it.\n3. While that file is there, the bot does nothing at all. This tab shows PAUSE REQUESTED once it's there (not confirmed: the bot doesn't report back yet). It stops at its next hourly run.\n4. To let it run again, a person deletes the file.")
     .font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
   }
  }
 }

 private func scorecard(_ m: ResearchMarket) -> some View {
  card {
   VStack(alignment:.leading,spacing:12) {
    HStack {
     Text(m.title).font(.system(size:17,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text).accessibilityAddTraits(.isHeader)
     Spacer()
     Text("\(m.forecasts) guess\(m.forecasts == 1 ? "" : "es") · \(m.graded) graded · \(m.open) open")
      .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    Text("Ideas tried \(m.ideas) · no-trade days \(m.noTradeDays)\(m.late > 0 ? " · \(m.late) written too late (not counted)" : "")")
     .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
    // Guesses vs simple guesses
    VStack(alignment:.leading,spacing:6) {
     Text("Are its guesses better than simple ones?").font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
     Text(ResearchBotData.guessVerdict(m)).font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
     Grid(alignment:.leading,horizontalSpacing:16,verticalSpacing:3) {
      row("The bot",ResearchBotData.brier(m.brier.forecaster),bold:true)
      row("Coin flip / no change",ResearchBotData.brier(m.brier.coinFlip))
      row("How often it went up before",ResearchBotData.brier(m.brier.baseRate))
      row("Tomorrow = today",ResearchBotData.brier(m.brier.tomorrow))
     }
     Text("Score: lower is better. 0 is perfect, 0.25 is a coin flip.\(m.hitRate.map { " Right \(Int(($0 * 100).rounded()))% of the time (\(m.hits) of \(m.graded))." } ?? "")")
      .font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
    }
    Divider().overlay(HubTheme.line)
    // Practice money
    VStack(alignment:.leading,spacing:6) {
     Text("Practice money, after fees").font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
     Text(ResearchBotData.moneyVerdict(m)).font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
     Grid(alignment:.leading,horizontalSpacing:16,verticalSpacing:3) {
      row("The bot's practice trades",ResearchBotData.signed(m.paperPnl),bold:true)
      row("Doing nothing (cash)",ResearchBotData.signed(m.cashPnl ?? 0))
      row("Just holding \(m.benchmark.isEmpty ? "the benchmark" : m.benchmark)",ResearchBotData.signed(m.holdPnl))
      if m.paperTrades > 0 {
       row("Typical trade",ResearchBotData.signed(m.median))
       row("Worst trade",ResearchBotData.signed(m.worst))
       row("Without its best trade",ResearchBotData.signed(m.withoutBest))
      }
     }
    }
    Divider().overlay(HubTheme.line)
    // Evidence bar
    VStack(alignment:.leading,spacing:4) {
     Text("Bar before anyone may even suggest real money: \(m.bar.isEmpty ? "-" : (m.barMet == m.bar.count ? "MET (a reason to talk, never an automatic go)" : "NOT MET (\(m.barMet) of \(m.bar.count))"))")
      .font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
     ForEach(Array(m.bar.enumerated()),id:\.offset) { _,item in
      Label(item.name,systemImage:item.met ? "checkmark.circle.fill" : "circle")
       .font(.system(size:11.5,design:.rounded)).foregroundStyle(item.met ? HubTheme.green : HubTheme.subtext)
     }
    }
   }
  }
 }

 private func forecasts(_ s: ResearchSnapshot) -> some View {
  let shown = page.allForecasts ? s.forecasts : Array(s.forecasts.prefix(5))
  return card {
   VStack(alignment:.leading,spacing:10) {
    Text("Latest guesses").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text).accessibilityAddTraits(.isHeader)
    if shown.isEmpty && s.noTrades.isEmpty {
     Text("No guesses yet: no trade is a normal day.").font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    ForEach(shown) { f in
     VStack(alignment:.leading,spacing:3) {
      HStack(spacing:6) {
       Text("\(f.asset) \(f.direction.lowercased() == "down" ? "down" : "up")").font(.system(size:13.5,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
       if let p = f.probability { Text("\(Int((p * 100).rounded()))% sure").font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext) }
       Spacer(minLength:4)
       Text(window(f)).font(.system(size:11.5,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.subtext)
      }
      if !f.reason.isEmpty {
       let plain = ResearchBotData.why(f)
       Text(plain.map { $0.ours ? "Why (our plain reading of its rule): \($0.text)" : "Why: \($0.text)" } ?? "Why: \(f.reason)").font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
       if plain != nil {
        Button { if page.details.contains(f.id) { page.details.remove(f.id) } else { page.details.insert(f.id) } } label: {
         Text(page.details.contains(f.id) ? "Hide technical details" : "Technical details").font(.system(size:11,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.subtext).underline()
        }.buttonStyle(.plain).accessibilityLabel("Show the bot's own reason text")
        if page.details.contains(f.id) { Text("Technical reason only (the bot's own words): \(f.reason)").font(.system(size:11,design:.monospaced)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true).textSelection(.enabled) }
       }
      }
      Text([when(f.opens).map { "Window \($0)" },when(f.resolves).map { "to \($0)" },f.act ? "asks for a practice trade" : "guess only, no trade",f.author.isEmpty ? nil : "by \(f.author)"].compactMap { $0 }.joined(separator:" · "))
       .font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
     }
     .padding(.vertical,3).accessibilityElement(children:.combine)
    }
    if s.forecasts.count > 5 { more(page.allForecasts,"guesses",s.forecasts.count) { page.allForecasts.toggle() } }
    if let n = s.noTrades.first {
     Text("Latest no-trade day (\(n.market == "crypto" ? "crypto" : "stocks")\(when(n.created).map { ", \($0)" } ?? "")): \(n.reason)")
      .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
    }
   }
  }
 }

 private func orders(_ s: ResearchSnapshot) -> some View {
  let shown = page.allOrders ? s.orders : Array(s.orders.prefix(5))
  return card {
   VStack(alignment:.leading,spacing:10) {
    Text("Practice orders").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text).accessibilityAddTraits(.isHeader)
    if shown.isEmpty {
     Text("No practice orders yet.").font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    ForEach(shown) { o in
     VStack(alignment:.leading,spacing:2) {
      HStack(spacing:6) {
       Text("Practice \(o.side) \(o.asset)").font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
       Spacer(minLength:4)
       if o.side == "sell", let p = o.profit { Text(ResearchBotData.signed(p)).font(.system(size:13,design:.rounded)).foregroundStyle(p >= 0 ? HubTheme.green : HubTheme.crimson) }
       else if let d = o.dollars { Text(ResearchBotData.money(d)).font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.text) }
      }
      Text([o.status == "half-done" ? "HALF-DONE: that market is stopped until a person checks the account" : o.status,when(o.time)].compactMap { $0 }.joined(separator:" · "))
       .font(.system(size:11.5,design:.rounded)).foregroundStyle(o.status == "filled" ? HubTheme.subtext : HubTheme.amber).fixedSize(horizontal:false,vertical:true)
     }
     .accessibilityElement(children:.combine)
    }
    if s.orders.count > 5 { more(page.allOrders,"orders",s.orders.count) { page.allOrders.toggle() } }
   }
  }
 }

 // MARK: helpers
 private func footnote(_ s: ResearchSnapshot) -> String {
  var parts = ["Read from the bot's files on GitHub"]
  if let g = s.generated { parts.append("scorecard made \(g.formatted(date:.abbreviated,time:.shortened))") }
  if let l = s.loaded { parts.append("checked \(l.formatted(date:.omitted,time:.shortened))") }
  var t = parts.joined(separator:" · ") + ". This tab can't place an order and has no real-money switch."
  let other = s.problems.filter { !$0.hasPrefix("No scorecard") || s.generated != nil }
  if !other.isEmpty { t += " " + other.joined(separator:" ") }
  return t
 }
 private func window(_ f: ResearchForecast) -> String {
  let now = Date()
  if let o = f.opens, now < o { return "waiting" }
  if let r = f.resolves, now < r { return "open now" }
  if f.resolves != nil { return "window closed" }
  return ""
 }
 private func when(_ d: Date?) -> String? { d?.formatted(date:.abbreviated,time:.shortened) }
 @ViewBuilder private func row(_ label: String,_ value: String,bold: Bool = false) -> some View {
  GridRow {
   Text(label).font(.system(size:12.5,weight:bold ? .semibold : .regular,design:.rounded)).foregroundStyle(bold ? HubTheme.text : HubTheme.subtext)
   Text(value).font(.system(size:12.5,weight:bold ? .bold : .regular,design:.rounded)).monospacedDigit().foregroundStyle(HubTheme.text)
  }
 }
 private func more(_ expanded: Bool,_ kind: String,_ count: Int,action: @escaping () -> Void) -> some View {
  Button(action:action) {
   Label(expanded ? "Show fewer \(kind)" : "Show all \(count) \(kind)",systemImage:expanded ? "chevron.up" : "chevron.down")
    .font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text).frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
  }.buttonStyle(.plain)
 }
 private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
  content().padding(18).frame(maxWidth:.infinity,alignment:.leading)
   .background(HubTheme.card,in:RoundedRectangle(cornerRadius:18))
   .overlay(RoundedRectangle(cornerRadius:18).stroke(HubTheme.line,lineWidth:1))
 }
}
