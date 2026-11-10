import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Public practice-account snapshots only. The page changes presentation, not the bot or its permissions.
extension CompanionInterfaceView {
 // Revamp 2026-11-10 (Roxy's "Robot fleet" concept, Matthew's pick): fleet column, robot page, research bot tab. See HubStockArea.swift.
 var hubStocks: some View {
  StockArea(stocks:stocks,compact:hub.compact,showSideCards:!(deckShowsDock && !hub.simple))
   .onAppear { if SwitchboardTestHooks.active && UserDefaults.standard.bool(forKey:"stocks.testResearch") { stocks.robot = StockArea.researchTab }
    else if SwitchboardTestHooks.active, UserDefaults.standard.object(forKey:"stocks.testRobot") != nil { stocks.robot = UserDefaults.standard.integer(forKey:"stocks.testRobot") } }
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
