import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The Launchpad page: agents and links, plus the Today at a glance briefing.
// Split out of Hub.swift on 2026-10-24 with no change in behaviour, so pages can have one owner each.
extension CompanionInterfaceView {
 // MARK: launchpad

 var hubLaunchpad: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:22) {
    Text("Your agents").font(.system(size:18,weight:.semibold,design:.rounded)).foregroundStyle(Color.white.opacity(0.9))
    HStack(alignment:.top,spacing:14) {
     ForEach(HubLaunch.agents) { agent in hubAgentCard(agent) }
    }
    Text("These open the chats where each job lives. Chats can't see each other, and an agent living inside this app would need a paid key, which stays shelved until client #1.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
    ForEach(HubLaunch.groups,id:\.name) { group in
     VStack(alignment:.leading,spacing:12) {
      Text(group.name).font(.system(size:18,weight:.semibold,design:.rounded)).foregroundStyle(Color.white.opacity(0.9))
      LazyVGrid(columns:[GridItem(.adaptive(minimum:235),spacing:14)],spacing:14) {
       ForEach(group.links) { link in hubLinkTile(link) }
      }
     }
    }
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 func hubAgentCard(_ agent: HubAgent) -> some View {
  VStack(alignment:.leading,spacing:10) {
   ZStack {
    RoundedRectangle(cornerRadius:14,style:.continuous).fill(LinearGradient(colors:[agent.tint,agent.tint.opacity(0.55)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:44,height:44)
    Image(systemName:agent.icon).font(.system(size:18,weight:.semibold)).foregroundStyle(Color.white)
   }
   Text(agent.name).font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
   Text(agent.job).font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(4).multilineTextAlignment(.leading)
   Spacer(minLength:4)
   Button { if let url = URL(string:agent.url) { NSWorkspace.shared.open(url) } } label: { Label("Open \(agent.chat)",systemImage:"arrow.up.right") }
    .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
  }
  .padding(16)
  .frame(maxWidth:.infinity,minHeight:210,alignment:.topLeading)
  .hubCard()
 }

 func hubLinkTile(_ link: HubLink) -> some View {
  Button { if let url = URL(string:link.url) { NSWorkspace.shared.open(url) } } label: {
   HStack(spacing:12) {
    ZStack {
     RoundedRectangle(cornerRadius:12,style:.continuous).fill(LinearGradient(colors:[link.tint,link.tint.opacity(0.55)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:40,height:40)
     Image(systemName:link.icon).font(.system(size:16,weight:.semibold)).foregroundStyle(Color.white)
    }
    VStack(alignment:.leading,spacing:2) {
     Text(link.title).font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(Color.white).lineLimit(1).minimumScaleFactor(0.8)
     Text(link.note).font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(2).multilineTextAlignment(.leading)
    }
    Spacer(minLength:0)
    Image(systemName:"arrow.up.right").font(.system(size:11,weight:.semibold)).foregroundStyle(Color.white.opacity(0.35))
   }
   .padding(14)
   .frame(maxWidth:.infinity,alignment:.leading)
   .hubCard(radius:18)
  }
  .buttonStyle(.plain)
  .hubHover("link-\(link.title)",hub,lift:1.03)
 }

 // A few plain sentences from the data already on screen. No AI, no quota: it is just reading the numbers out.
 var hubBriefing: [String] {
  var lines: [String] = []
  if let d = stocks.dip, let m = stocks.momentum {
   lines.append("Stocks (practice money): the dip robot is \(hubSigned(d.vsHolding)) versus just holding, the momentum robot \(hubSigned(m.vsHolding)).")
  }
  if let s = ventures.store { lines.append("Store: \(s.week) visitors this week, \(s.today) today.") }
  if let f = ventures.feed {
   if let days = f.streakDays() { lines.append("ECS feed: a new post every day for \(days) days.") }
   else { lines.append("ECS feed: \(f.total) posts since \(f.since), but the streak isn't unbroken.") }
  }
  if let sold = sales.sales { lines.append("Sales: \(sold.month.orders) order\(sold.month.orders == 1 ? "" : "s") in the last 30 days (\(hubRevenue(sold.month))), \(sold.today.orders) today.") }
  if let cat = ventures.catalog {
   lines.append(cat.isStale() ? "Catalog: \(cat.count) products, but the last refresh was \(cat.ageDays() ?? 0) days ago." : "Catalog: \(cat.count) products, refreshed \(hubAgo(cat.refreshed)).")
  }
  if let board = meeting.board { lines.append("Meeting Room: \(board.openCount) thing\(board.openCount == 1 ? "" : "s") on the table, board updated \(board.updated).") }
  if let runs = ventures.runs {
   let bad = ventures.attention
   lines.append(bad.isEmpty ? "Automations: all \(runs.count) ran without errors." : "Automations needing attention: \(bad.map { $0.name }.joined(separator:", ")).")
  }
  for issue in (ventures.issues ?? []).prefix(2) { lines.append("Open alert: \(issue.title) (raised \(hubAgo(issue.since))).") }
  return lines
 }

 @ViewBuilder var hubBriefingCard: some View {
  let lines = hubBriefing
  if !lines.isEmpty {
   VStack(alignment:.leading,spacing:10) {
    Text("Today at a glance").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
    ForEach(Array(lines.enumerated()),id:\.offset) { _,line in
     HStack(alignment:.top,spacing:10) {
      Circle().fill(Noir.crimsonLight).frame(width:5,height:5).padding(.top,7)
      Text(line).font(.system(size:13.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.82))
     }
    }
   }
   .padding(18)
   .frame(maxWidth:.infinity,alignment:.leading)
   .hubCard()
  }
 }
}
