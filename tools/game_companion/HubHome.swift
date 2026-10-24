import SwiftUI
import AppKit
import UniformTypeIdentifiers

// Home: the greeting, the glance list and a tile per venture.
// Split out of Hub.swift on 2026-10-24 with no change in behaviour, so pages can have one owner each.
extension CompanionInterfaceView {
 // MARK: home

 var hubGreeting: String {
  let hour = Calendar.current.component(.hour,from:Date())
  if hour < 12 { return "Good morning, Matthew" }
  if hour < 18 { return "Good afternoon, Matthew" }
  return "Good evening, Matthew"
 }

 var hubHome: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:22) {
    hubHero
    hubBriefingCard
    hubAttentionBanner
    Text("Your ventures").font(.system(size:18,weight:.semibold,design:.rounded)).foregroundStyle(Color.white.opacity(0.9))
    LazyVGrid(columns:[GridItem(.adaptive(minimum:230),spacing:16)],spacing:16) {
     hubTile(.stocks,hubStockHeadline)
     hubTile(.store,hubStoreHeadline)
     hubTile(.ecs,hubEcsHeadline)
     hubTile(.systems,hubSystemsHeadline)
     hubTile(.launchpad,"Porkbun, Stripe, Cloudflare and more · plus your agents")
     hubTile(.game,hubGameHeadline)
     hubTile(.accounts,hubAccountsHeadline)
    }
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 var hubHero: some View {
  HStack(spacing:20) {
   VStack(alignment:.leading,spacing:12) {
    Text("Friday is ready when you are").font(.system(size:26,weight:.bold,design:.rounded)).foregroundStyle(Color.white)
    Text("Talk to her, show her your game, or ask how any venture is doing.").font(.system(size:14,design:.rounded)).foregroundStyle(Color.white.opacity(0.7))
    Button { hubSelect(.friday) } label: { Label("Talk to Friday",systemImage:"waveform") }.buttonStyle(PillButtonStyle()).padding(.top,4)
   }
   if !hub.compact {
    Spacer()
    TimelineView(.animation(minimumInterval:1.0/60.0)) { timeline in
     FridayOrb(state:orbState(at:timeline.date),t:timeline.date.timeIntervalSinceReferenceDate,level:orbLevel(at:timeline.date),size:130,animated:!reduceMotion,showsPicker:false)
    }
    .frame(width:230,height:190)
   }
  }
  .padding(hub.compact ? 16 : 26)
  .frame(maxWidth:.infinity)
  .background(
   RoundedRectangle(cornerRadius:30,style:.continuous)
    .fill(LinearGradient(colors:[Noir.crimsonDeep.opacity(0.85),Color(red:0.10,green:0.02,blue:0.05)],startPoint:.topLeading,endPoint:.bottomTrailing))
  )
  .overlay(RoundedRectangle(cornerRadius:30,style:.continuous).stroke(Color.white.opacity(0.10),lineWidth:1))
 }

 func hubTile(_ section: HubSection,_ subtitle: String) -> some View {
  Button { hubSelect(section) } label: {
   VStack(alignment:.leading,spacing:12) {
    ZStack {
     RoundedRectangle(cornerRadius:16,style:.continuous)
      .fill(LinearGradient(colors:[section.tint,section.tint.opacity(0.55)],startPoint:.topLeading,endPoint:.bottomTrailing))
      .frame(width:52,height:52)
     Image(systemName:section.icon).font(.system(size:22,weight:.semibold)).foregroundStyle(Color.white)
    }
    Spacer(minLength:6)
    Text(section.title).font(.system(size:18,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
    Text(subtitle).font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(2).multilineTextAlignment(.leading)
   }
   .padding(18)
   .frame(maxWidth:.infinity,minHeight:158,alignment:.topLeading)
   .hubCard(radius:24)
  }
  .buttonStyle(.plain)
  .hubHover("tile-\(section.rawValue)",hub)
 }

 var hubStockHeadline: String {
  if let d = stocks.dip, let m = stocks.momentum { return "Practice money · dip \(hubMoney(d.value)), momentum \(hubMoney(m.value))" }
  if let one = stocks.dip ?? stocks.momentum { return "Practice money · \(hubMoney(one.value))" }
  return stocks.failed ? "Couldn't load right now · open to retry" : "Loading…"
 }

 var hubStoreHeadline: String {
  guard let s = ventures.store else { return "Loading…" }
  if let sold = sales.sales { return "\(s.week) visitors this week · \(sold.month.orders) order\(sold.month.orders == 1 ? "" : "s") in 30 days" }
  return "\(s.week) visitors this week · \(s.today) today"
 }
 var hubEcsHeadline: String {
  guard let f = ventures.feed else { return "Loading…" }
  if let days = f.streakDays() { return "\(days)-day feed streak" }
  return "\(f.total) posts since \(f.since)"
 }
 var hubSystemsHeadline: String {
  guard let runs = ventures.runs else { return "Loading…" }
  let bad = ventures.alerts
  if !bad.isEmpty { return "\(bad.count) need attention · \(bad[0])" }
  let open = ventures.issues?.count ?? 0
  return open > 0 ? "All \(runs.count) ran · \(open) open alert\(open == 1 ? "" : "s")" : "All \(runs.count) automations OK"
 }

 // Shows on Home only when an automation's latest run failed.
 @ViewBuilder var hubAttentionBanner: some View {
  let bad = ventures.alerts
  if !bad.isEmpty {
   Button { hubSelect(.systems) } label: {
    HStack(spacing:12) {
     Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(HubColor.amber)
     Text("\(bad.count == 1 ? "1 thing needs" : "\(bad.count) things need") attention: \(bad.joined(separator:", "))")
      .font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.9))
     Spacer()
     Text("Open").font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(Noir.crimsonLight)
    }
    .padding(14)
    .hubCard(radius:18)
   }
   .buttonStyle(.plain)
  }
 }

 var hubGameHeadline: String {
  if live.running { return "Friday is live" }
  if live.sees == 0 { return "All screens · ready" }
  return c.sharing ? "Window chosen · ready" : "No window chosen yet"
 }
 var hubAccountsHeadline: String {
  let connected = [live.hasKey,clips.signedIn,sales.hasKey,meeting.hasToken].filter { $0 }.count
  return "\(connected) of 4 logins connected"
 }
}
