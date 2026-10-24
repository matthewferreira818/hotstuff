import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The Store, ECS and Systems pages, with the shared refresh button and offline card.
// Split out of Hub.swift on 2026-10-24 with no change in behaviour, so pages can have one owner each.
extension CompanionInterfaceView {
 // MARK: store, ECS, systems

 func hubRefreshButton() -> some View {
  Button { Task { await ventures.refresh(force:true) } } label: { Label(ventures.loading ? "Refreshing…" : "Refresh",systemImage:"arrow.clockwise") }
   .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   .disabled(ventures.loading)
 }

 func hubOffline(_ what: String) -> some View {
  VStack(spacing:8) {
   Text("Couldn't reach \(what)").font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
   Text("Check your internet, then try Refresh.").font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.6))
  }
  .frame(maxWidth:.infinity).padding(40).hubCard()
 }

 var hubStore: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:18) {
    HStack(spacing:10) {
     hubPill("PUBLIC COUNTERS · UNIQUE VISITORS",tint:HubColor.amber)
     Spacer()
     hubRefreshButton()
    }
    hubSalesBlock
    if let s = ventures.store {
     LazyVGrid(columns:[GridItem(.adaptive(minimum:200),spacing:14)],spacing:14) {
      hubStat("Today",String(s.today),"unique visitors so far",tint:Color.white)
      hubStat("Last 7 days",String(s.week),"unique visitors",tint:Color.white)
      hubStat("Last 30 days",String(s.month),"unique visitors",tint:Color.white)
     }
     hubChannels(s)
     hubCatalogCard
     Text(sales.hasKey ? "Visits come from your site's public visitor counters, by day. Orders and revenue come from Stripe through a read-only key, and no customer names or emails are read. Order alerts keep reaching your phone the way they do now." : "Visits come from your site's public visitor counters, by day. Orders and revenue show up here once you connect Stripe on the Accounts page. Order alerts keep reaching your phone the way they do now.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
    } else if ventures.failed {
     hubOffline("the visitor counters")
    } else {
     ProgressView().controlSize(.large).frame(maxWidth:.infinity).padding(50)
    }
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 func hubChannels(_ s: StoreStats) -> some View {
  let biggest = max(1,s.channels.first?.count ?? 1)
  return VStack(alignment:.leading,spacing:12) {
   Text("Where visitors came from · last 30 days").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
   if s.channels.isEmpty {
    Text("No visits from tagged links yet. Counts show up here once a tagged post, pin or QR code brings someone.").font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.55))
   }
   ForEach(s.channels) { channel in
    HStack(spacing:12) {
     Text(channel.label).font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.85)).frame(minWidth:90,idealWidth:210,maxWidth:210,alignment:.leading)
     RoundedRectangle(cornerRadius:5,style:.continuous).fill(LinearGradient(colors:[HubColor.amber,HubColor.amber.opacity(0.5)],startPoint:.leading,endPoint:.trailing)).frame(width:max(8,CGFloat(channel.count) / CGFloat(biggest) * 260),height:10)
     Text(String(channel.count)).font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
     Spacer()
    }
   }
  }
  .padding(18)
  .frame(maxWidth:.infinity,alignment:.leading)
  .hubCard()
 }

 var hubEcs: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:18) {
    HStack(spacing:10) {
     hubPill("THE SITE'S OWN FEED",tint:HubColor.violet)
     Spacer()
     Button { if let url = URL(string:"https://findhotstuff.com/automation/") { NSWorkspace.shared.open(url) } } label: { Label("Open the site",systemImage:"arrow.up.right.square") }
      .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
     hubRefreshButton()
    }
    if let f = ventures.feed {
     let streak = f.streakDays()
     LazyVGrid(columns:[GridItem(.adaptive(minimum:200),spacing:14)],spacing:14) {
      hubStat("Feed streak",streak.map { "\($0) days" } ?? "Not claimed",streak != nil ? "A new post every day since \(f.since)" : "A day is missing, or the latest post is old",tint:streak != nil ? HubColor.green : HubColor.amber)
      hubStat("Posts published",String(f.total),"since \(f.since)",tint:Color.white)
      hubStat("Latest post",f.last,"the feed's newest card",tint:Color.white)
     }
     if let days = streak {
      VStack(alignment:.leading,spacing:6) {
       Text("Honest wording for anything you post").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.55))
       Text("\"my own store's feed has published a new post every day for \(days) days\" (findhotstuff.com/automation)").font(.system(size:13.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.9)).textSelection(.enabled)
       Text("It counts the site's feed, not any social page.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.45))
      }
      .padding(16).frame(maxWidth:.infinity,alignment:.leading).hubCard()
     }
     HStack(alignment:.top,spacing:14) {
      ForEach(f.cards) { card in
       VStack(alignment:.leading,spacing:8) {
        AsyncImage(url:URL(string:"\(VentureData.feed)\(card.image)")) { image in image.resizable().scaledToFit() } placeholder: { ProgressView().frame(height:120) }
         .clipShape(RoundedRectangle(cornerRadius:14,style:.continuous))
        Text(card.date).font(.system(size:11,weight:.semibold,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
        Text(card.message).font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.85)).lineLimit(3)
       }
       .padding(12).frame(maxWidth:.infinity,alignment:.topLeading).hubCard()
      }
     }
    } else if ventures.failed {
     hubOffline("the site's feed files")
    } else {
     ProgressView().controlSize(.large).frame(maxWidth:.infinity).padding(50)
    }
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 var hubSystems: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:14) {
    HStack(spacing:10) {
     if let runs = ventures.runs {
      if ventures.alerts.isEmpty { hubPill("ALL \(runs.count) RAN WITHOUT ERRORS",tint:HubColor.green) }
      else { hubPill("\(ventures.alerts.count) NEED ATTENTION",tint:Noir.crimsonLight) }
     }
     if let open = ventures.issues?.count, open > 0 {
      hubPill("\(open) OPEN ALERT\(open == 1 ? "" : "S")",tint:HubColor.amber)
     }
     Spacer()
     hubRefreshButton()
    }
    hubCatalogCard
    hubIssuesCard
    if let runs = ventures.runs {
     ForEach(runs) { run in hubRunRow(run) }
     Text("Read from GitHub's public status of your repo. Each line is that automation's latest run. A green tick means it ran without crashing, not that it posted: when something it needs is out (like X credits), it raises an alert above instead. Nothing here can start, stop or change an automation.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
    } else if ventures.failed {
     hubOffline("GitHub")
    } else {
     ProgressView().controlSize(.large).frame(maxWidth:.infinity).padding(50)
    }
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 func hubRunRow(_ run: AutomationRun) -> some View {
  let icon = run.isFailing ? "xmark.circle.fill" : (run.isRunning ? "arrow.triangle.2.circlepath.circle.fill" : "checkmark.circle.fill")
  let tint = run.isFailing ? Noir.crimsonLight : (run.isRunning ? HubColor.amber : HubColor.green)
  return HStack(spacing:14) {
   Image(systemName:icon).font(.system(size:22)).foregroundStyle(tint)
   VStack(alignment:.leading,spacing:2) {
    Text(run.name).font(.system(size:14.5,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
    Text("Last run \(hubAgo(run.created))\(run.isFailing ? " · it failed" : (run.isRunning ? " · running now" : ""))").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.55))
   }
   Spacer()
   if let url = URL(string:run.url), !run.url.isEmpty {
    Button("Open") { NSWorkspace.shared.open(url) }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   }
  }
  .padding(14)
  .hubCard()
 }
}
