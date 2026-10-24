import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The Stock bot page (practice money only) and the small stat tile the other pages reuse.
// Split out of Hub.swift on 2026-10-24 with no change in behaviour, so pages can have one owner each.
extension CompanionInterfaceView {
 // MARK: stock bot

 var hubStocks: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:18) {
    HStack(spacing:10) {
     hubPill("PRACTICE MONEY · NOT REAL",tint:Noir.crimsonLight)
     if let r = stocks.current {
      hubPill(r.marketOpen ? "MARKET OPEN" : "MARKET CLOSED",tint:r.marketOpen ? HubColor.green : HubColor.slate)
      Text("Updated \(hubAgo(r.updated))").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
     }
     Spacer()
     Button { Task { await stocks.refresh() } } label: { Label(stocks.loading ? "Refreshing…" : "Refresh",systemImage:"arrow.clockwise") }
      .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
      .disabled(stocks.loading)
    }
    Picker("Robot",selection:$stocks.robot) { Text("Dip robot").tag(0); Text("Momentum robot").tag(1) }
     .pickerStyle(.segmented).labelsHidden().frame(maxWidth:300)
    if let r = stocks.current {
     hubRobot(r)
    } else if stocks.failed {
     VStack(spacing:10) {
      Text("Couldn't reach the snapshot").font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
      Text("Check your internet, then try Refresh.").font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.6))
     }
     .frame(maxWidth:.infinity).padding(40).hubCard()
    } else {
     ProgressView().controlSize(.large).frame(maxWidth:.infinity).padding(50)
    }
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 func hubRobot(_ r: StockRobot) -> some View {
  VStack(alignment:.leading,spacing:16) {
   LazyVGrid(columns:[GridItem(.adaptive(minimum:200),spacing:14)],spacing:14) {
    hubStat("Account value",hubMoney(r.value),"\(hubSigned(r.sinceStart)) since it started",tint:Color.white)
    hubStat("Versus just holding",hubSigned(r.vsHolding),r.vsHolding >= 0 ? "Ahead of the plain index" : "Behind the plain index (\(hubMoney(r.spyValue)))",tint:r.vsHolding >= 0 ? HubColor.green : Noir.crimsonLight)
    hubStat("Cash",hubMoney(r.cash),"\(hubMoney(r.held)) invested",tint:Color.white)
    hubStat("Fees paid",hubMoney(r.fees),"\(r.trades) trade\(r.trades == 1 ? "" : "s")",tint:Color.white)
   }
   HStack(alignment:.top,spacing:14) {
    hubHoldings(r)
    hubActivity(r)
   }
   Text("Practice money, read from the bot's public snapshot\(r.paused ? " · the robot is paused" : ""). Nothing on this page can place an order.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
  }
 }

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

 func hubHoldings(_ r: StockRobot) -> some View {
  VStack(alignment:.leading,spacing:12) {
   Text("Holding now").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
   if r.holdings.isEmpty {
    Text("Nothing held right now.").font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
   }
   ForEach(r.holdings) { h in
    HStack {
     Text(h.symbol).font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
     Spacer()
     Text(hubMoney(h.value)).font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.75))
     if let change = h.changePct {
      Text(String(format:"%+.2f%%",change)).font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(change >= 0 ? HubColor.green : Noir.crimsonLight).frame(width:68,alignment:.trailing)
     }
    }
   }
  }
  .padding(18)
  .frame(maxWidth:.infinity,alignment:.topLeading)
  .hubCard()
 }

 func hubActivity(_ r: StockRobot) -> some View {
  VStack(alignment:.leading,spacing:12) {
   Text("Latest activity").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
   ForEach(Array(r.events.enumerated()),id:\.offset) { _,line in
    Text(line).font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.65)).lineLimit(2)
   }
   if !r.recentTrades.isEmpty {
    Divider().overlay(Color.white.opacity(0.08))
    ForEach(r.recentTrades) { t in
     HStack {
      Text("\(t.side.capitalized) \(t.symbol)").font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.85))
      Spacer()
      Text("\(hubMoney(t.dollars)) · \(hubAgo(t.time))").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
     }
    }
   }
  }
  .padding(18)
  .frame(maxWidth:.infinity,alignment:.topLeading)
  .hubCard()
 }
}
