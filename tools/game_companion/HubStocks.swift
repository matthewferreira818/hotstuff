import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Public practice-account snapshots only. The page changes presentation, not the bot or its permissions.
extension CompanionInterfaceView {
 var hubStocks: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:16) {
    VStack(alignment:.leading,spacing:6) {
     HStack(spacing:10) {
      Label("Practice money",systemImage:"chart.line.uptrend.xyaxis")
       .font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
      Spacer(minLength:4)
      Button { Task { await stocks.refresh() } } label: {
       Label(stocks.loading ? "Refreshing…" : "Refresh",systemImage:"arrow.clockwise")
        .font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
        .padding(.horizontal,12).frame(minHeight:44)
        .background(HubTheme.control,in:RoundedRectangle(cornerRadius:12))
        .overlay(RoundedRectangle(cornerRadius:12).stroke(HubTheme.controlOutline,lineWidth:1))
      }
      .buttonStyle(.plain).disabled(stocks.loading || DesignPreview.enabled)
      .accessibilityLabel("Refresh public practice-account snapshots")
     }
     Text("Read-only public snapshots · account amounts in USD")
      .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    HStack(spacing:8) {
     hubStockChoice("Dip",index:0).accessibilityLabel("Dip robot")
     hubStockChoice("Momentum",index:1).accessibilityLabel("Momentum robot")
     hubStockChoice("Hot hands",index:2).accessibilityLabel("Hot hands robot")
    }
    .accessibilityElement(children:.contain).accessibilityLabel("Choose a practice robot")
    if let robot = stocks.current {
     StockSnapshotDashboard(robot:robot,money:hubMoney,signed:hubSigned,ago:hubAgo)
    } else {
     VStack(alignment:.leading,spacing:10) {
      if stocks.loading { ProgressView().controlSize(.small) }
      Text(stocks.loading ? "Loading this robot's snapshot…" : "This robot's snapshot is unavailable")
       .font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
      Text(stocks.loading ? "Reading the public practice account." : "Use Refresh to try again. Other robots may still have snapshots.")
       .font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.subtext)
     }
     .padding(20).frame(maxWidth:.infinity,minHeight:140,alignment:.leading)
     .background(HubTheme.card,in:RoundedRectangle(cornerRadius:20))
     .overlay(RoundedRectangle(cornerRadius:20).stroke(HubTheme.line,lineWidth:1))
    }
    Text("Practice money only. This page reads snapshots and cannot place an order.")
     .font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
   }
   .padding(.horizontal,hub.compact ? 16 : 32).padding(.top,4).padding(.bottom,24)
  }
  .scrollIndicators(.hidden).background(HubTheme.background)
 }

 private func hubStockChoice(_ title: String,index: Int) -> some View {
  let selected = stocks.robot == index
  return Button { stocks.robot = index } label: {
   Text(title).font(.system(size:13,weight:selected ? .semibold : .medium,design:.rounded))
    .foregroundStyle(selected ? HubTheme.text : HubTheme.subtext)
    .frame(maxWidth:.infinity,minHeight:44)
    .background(selected ? HubTheme.control : HubTheme.card,in:RoundedRectangle(cornerRadius:12))
    .overlay(RoundedRectangle(cornerRadius:12).stroke(selected ? HubTheme.controlOutline : HubTheme.line,lineWidth:1))
  }
  .buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
 }

 // Shared stat API used by the other venture pages, kept intact.
 func hubStat(_ title: String,_ value: String,_ note: String,tint: Color) -> some View {
  VStack(alignment:.leading,spacing:6) {
   Text(title).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.55))
   Text(value).font(.system(size:26,weight:.bold,design:.rounded)).foregroundStyle(tint)
   Text(note).font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.5)).lineLimit(2)
  }
  .padding(18)
  .frame(maxWidth:.infinity,alignment:.leading)
  .hubCard()
 }
}

private enum StockSnapshotTab: String,CaseIterable {
 case overview = "Overview", holdings = "Holdings", activity = "Activity"
}

// UI state stays local to this page. No engines, credentials, posting, or extra data requests.
// StateObject works with this Mac's command-line Swift toolchain; @State requires Xcode's macro plugin.
@MainActor private final class StockSnapshotPageState: ObservableObject {
 @Published var tab = StockSnapshotTab.overview
 @Published var allHoldings = false
 @Published var allEvents = false
 @Published var allTrades = false
}

private struct StockSnapshotDashboard: View {
 let robot: StockRobot
 let money: (Double) -> String
 let signed: (Double) -> String
 let ago: (Date?) -> String
 @StateObject private var page = StockSnapshotPageState()

 var body: some View {
  VStack(alignment:.leading,spacing:16) {
   snapshotHeader
   HStack(spacing:6) {
    ForEach(StockSnapshotTab.allCases,id:\.self) { option in
     Button { page.tab = option } label: {
      Text(option.rawValue).font(.system(size:12.5,weight:page.tab == option ? .semibold : .medium,design:.rounded))
       .foregroundStyle(page.tab == option ? HubTheme.text : HubTheme.subtext)
       .frame(maxWidth:.infinity,minHeight:44)
       .background(page.tab == option ? HubTheme.control : HubTheme.card,in:RoundedRectangle(cornerRadius:11))
       .overlay(RoundedRectangle(cornerRadius:11).stroke(page.tab == option ? HubTheme.controlOutline : HubTheme.line,lineWidth:1))
     }
     .buttonStyle(.plain).accessibilityAddTraits(page.tab == option ? .isSelected : [])
    }
   }
   .accessibilityElement(children:.contain).accessibilityLabel("Snapshot details")
   switch page.tab {
   case .overview: overview
   case .holdings: holdings
   case .activity: activity
   }
  }
  .onChange(of:robot.name) { _,_ in
   page.allHoldings = false; page.allEvents = false; page.allTrades = false
  }
 }

 private var snapshotHeader: some View {
  VStack(alignment:.leading,spacing:6) {
   Text(robot.name).font(.system(size:20,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
    .accessibilityAddTraits(.isHeader)
   Text(robot.updated.map { "Snapshot \(ago($0)) · \($0.formatted(date:.abbreviated,time:.shortened))" } ?? "Snapshot time unavailable")
    .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
    .fixedSize(horizontal:false,vertical:true)
   Text("Snapshot market: \(robot.marketOpen ? "open" : "closed")\(robot.paused ? " · robot marked paused" : "")")
    .font(.system(size:12,design:.rounded)).foregroundStyle(robot.paused ? HubTheme.amber : HubTheme.subtext)
  }
  .padding(18).frame(maxWidth:.infinity,alignment:.leading).stockSnapshotCard()
 }

 private var overview: some View {
  VStack(alignment:.leading,spacing:12) {
   VStack(alignment:.leading,spacing:7) {
    Text("Practice account value").font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.subtext)
    Text(money(robot.value)).font(.system(size:34,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
     .lineLimit(1).minimumScaleFactor(0.65)
    Text("\(signed(robot.sinceStart)) versus starting cash")
     .font(.system(size:12.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
   }
   .padding(20).frame(maxWidth:.infinity,alignment:.leading).stockSnapshotCard()
   LazyVGrid(columns:[GridItem(.flexible(minimum:110),spacing:12),GridItem(.flexible(minimum:110),spacing:12)],spacing:12) {
    metric("Versus just holding",signed(robot.vsHolding),note:"Index snapshot: \(money(robot.spyValue))",tint:robot.vsHolding >= 0 ? HubTheme.green : HubTheme.crimson)
    metric("Cash",money(robot.cash),note:"Uninvested practice funds")
    metric("Holdings value",money(robot.held),note:"\(robot.holdings.count) position\(robot.holdings.count == 1 ? "" : "s") listed")
    metric("Fees paid",money(robot.fees),note:"\(robot.trades) recorded trade\(robot.trades == 1 ? "" : "s")")
   }
   Text("Values reflect the loaded snapshot. A refresh can retrieve a newer published file; it does not trade.")
    .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
 }

 private func metric(_ title: String,_ value: String,note: String,tint: Color = HubTheme.text) -> some View {
  VStack(alignment:.leading,spacing:6) {
   Text(title).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.subtext)
   Text(value).font(.system(size:22,weight:.bold,design:.rounded)).foregroundStyle(tint)
    .lineLimit(1).minimumScaleFactor(0.6)
   Text(note).font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
    .fixedSize(horizontal:false,vertical:true)
  }
  .padding(16).frame(maxWidth:.infinity,minHeight:112,alignment:.topLeading).stockSnapshotCard()
  .accessibilityElement(children:.combine)
 }

 private var holdings: some View {
  let shown = page.allHoldings ? robot.holdings : Array(robot.holdings.prefix(6))
  return VStack(alignment:.leading,spacing:14) {
   heading("Holdings",detail:"Positions listed in this snapshot")
   if shown.isEmpty {
    empty("No holdings are listed in this snapshot.")
   } else {
    VStack(spacing:0) {
     ForEach(Array(shown.enumerated()),id:\.offset) { index,holding in
      if index > 0 { Divider().overlay(HubTheme.line) }
      HStack(alignment:.top,spacing:10) {
       VStack(alignment:.leading,spacing:4) {
        Text(holding.symbol).font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
        if let change = holding.changePct {
         Text("Reported change \(String(format:"%+.2f%%",change))")
          .font(.system(size:11.5,design:.rounded)).foregroundStyle(change >= 0 ? HubTheme.green : HubTheme.crimson)
        }
       }
       Spacer(minLength:4)
       Text(money(holding.value)).font(.system(size:14,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.text)
        .lineLimit(1).minimumScaleFactor(0.7)
      }
      .padding(.vertical,14).accessibilityElement(children:.combine)
     }
     if robot.holdings.count > 6 {
      showAll(page.allHoldings,kind:"holdings",count:robot.holdings.count) { page.allHoldings.toggle() }
     }
    }
    .padding(.horizontal,18).stockSnapshotCard()
   }
  }
 }

 private var activity: some View {
  VStack(alignment:.leading,spacing:16) {
   heading("Activity",detail:"Recorded events and the recent orders supplied by the snapshot")
   VStack(alignment:.leading,spacing:12) {
    heading("Bot notes",detail:"\(robot.events.count) supplied")
    if robot.events.isEmpty {
     empty("No bot notes are included in this snapshot.")
    } else {
     ForEach(Array((page.allEvents ? robot.events : Array(robot.events.prefix(3))).enumerated()),id:\.offset) { _,line in
      Text(line).font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.text)
       .fixedSize(horizontal:false,vertical:true)
     }
     if robot.events.count > 3 { showAll(page.allEvents,kind:"notes",count:robot.events.count) { page.allEvents.toggle() } }
    }
   }
   .padding(18).frame(maxWidth:.infinity,alignment:.leading).stockSnapshotCard()
   VStack(alignment:.leading,spacing:12) {
    heading("Recent orders",detail:"\(robot.recentTrades.count) supplied; not the full trade history")
    if robot.recentTrades.isEmpty {
     empty("No recent orders are included in this snapshot.")
    } else {
     ForEach(Array((page.allTrades ? robot.recentTrades : Array(robot.recentTrades.prefix(3))).enumerated()),id:\.offset) { _,trade in
      VStack(alignment:.leading,spacing:4) {
       HStack(spacing:10) {
        Text("\(trade.side.capitalized) \(trade.symbol)").font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
        Spacer(minLength:4)
        Text(money(trade.dollars)).font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.text)
       }
       Text(trade.time.map { "\($0.formatted(date:.abbreviated,time:.shortened)) · \(ago($0))" } ?? "Order time unavailable")
        .font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
      }
      .padding(.vertical,4).accessibilityElement(children:.combine)
     }
     if robot.recentTrades.count > 3 { showAll(page.allTrades,kind:"supplied orders",count:robot.recentTrades.count) { page.allTrades.toggle() } }
    }
   }
   .padding(18).frame(maxWidth:.infinity,alignment:.leading).stockSnapshotCard()
  }
 }

 private func heading(_ title: String,detail: String) -> some View {
  VStack(alignment:.leading,spacing:4) {
   Text(title).font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
    .accessibilityAddTraits(.isHeader)
   Text(detail).font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
 }

 private func empty(_ text: String) -> some View {
  Text(text).font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.subtext)
   .padding(.vertical,8).frame(maxWidth:.infinity,alignment:.leading)
 }

 private func showAll(_ expanded: Bool,kind: String,count: Int,action: @escaping () -> Void) -> some View {
  Button(action:action) {
   Label(expanded ? "Show fewer \(kind)" : "Show all \(count) \(kind)",systemImage:expanded ? "chevron.up" : "chevron.down")
    .font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
    .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
  }
  .buttonStyle(.plain)
 }
}

private extension View {
 func stockSnapshotCard() -> some View {
  background(HubTheme.card,in:RoundedRectangle(cornerRadius:18))
   .overlay(RoundedRectangle(cornerRadius:18).stroke(HubTheme.line,lineWidth:1))
 }
}
