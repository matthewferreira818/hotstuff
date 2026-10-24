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
   VStack(alignment:.leading,spacing:16) {
    VStack(alignment:.leading,spacing:6) {
     HStack(spacing:10) {
      Label("HotsTuff",systemImage:"bag.fill")
       .font(.system(size:17,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
      Spacer(minLength:4)
      Button { Task { await ventures.refresh(force:true) } } label: {
       Label(ventures.loading ? "Refreshing…" : "Refresh",systemImage:"arrow.clockwise")
        .font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
        .padding(.horizontal,12).frame(minHeight:44)
        .background(HubTheme.control,in:RoundedRectangle(cornerRadius:12))
        .overlay(RoundedRectangle(cornerRadius:12).stroke(HubTheme.controlOutline,lineWidth:1))
      }
      .buttonStyle(.plain).disabled(ventures.loading || DesignPreview.enabled)
      .accessibilityLabel("Refresh public visitor counters and catalog")
     }
     Text("Public visitor counts and the published product list")
      .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    StoreSnapshotDashboard(store:ventures.store,catalog:ventures.catalog,loading:ventures.loading,ago:hubAgo,salesContent:hubSalesBlock)
   }
   .padding(.horizontal,hub.compact ? 16 : 32).padding(.top,4).padding(.bottom,24)
  }
  .scrollIndicators(.hidden).background(HubTheme.background)
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

private enum StoreSnapshotTab: String,CaseIterable {
 case overview = "Overview", sources = "Sources", catalog = "Catalog", sales = "Sales"
}

// The command-line Swift toolchain supports StateObject without Xcode's State macro plugin.
@MainActor private final class StoreSnapshotPageState: ObservableObject {
 @Published var tab = StoreSnapshotTab.overview
 @Published var allSources = false
}

// Presentation of existing loaded values only. Sales retains the existing view and its access/refresh behavior.
private struct StoreSnapshotDashboard<SalesContent: View>: View {
 let store: StoreStats?
 let catalog: CatalogStats?
 let loading: Bool
 let ago: (Date?) -> String
 let salesContent: SalesContent
 @StateObject private var page = StoreSnapshotPageState()

 var body: some View {
  VStack(alignment:.leading,spacing:16) {
   HStack(spacing:5) {
    ForEach(StoreSnapshotTab.allCases,id:\.self) { option in
     Button { page.tab = option } label: {
      Text(option.rawValue).font(.system(size:12,weight:page.tab == option ? .semibold : .medium,design:.rounded))
       .foregroundStyle(page.tab == option ? HubTheme.text : HubTheme.subtext)
       .frame(maxWidth:.infinity,minHeight:44)
       .background(page.tab == option ? HubTheme.control : HubTheme.card,in:RoundedRectangle(cornerRadius:11))
       .overlay(RoundedRectangle(cornerRadius:11).stroke(page.tab == option ? HubTheme.controlOutline : HubTheme.line,lineWidth:1))
     }
     .buttonStyle(.plain).accessibilityAddTraits(page.tab == option ? .isSelected : [])
    }
   }
   .accessibilityElement(children:.contain).accessibilityLabel("Store views")
   switch page.tab {
   case .overview: overview
   case .sources: sources
   case .catalog: catalogDetails
   case .sales:
    heading("Sales",detail:"The existing read-only sales connection")
    salesContent
   }
  }
 }

 private var overview: some View {
  VStack(alignment:.leading,spacing:16) {
   heading("Visitors",detail:"Unique visitors reported by the public counters")
   if let store = store {
    HStack(alignment:.top,spacing:10) {
     visitorMetric("Today",count:store.today,note:"UTC date")
     visitorMetric("7 days",count:store.week,note:"Including today")
     visitorMetric("30 days",count:store.month,note:"Including today")
    }
    Text("The reader requests date ranges using UTC. A counter day can differ from your local day.")
     .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
   } else {
    unavailable("Visitor counts",detail:"Use Refresh to try the public counters again.")
   }
   Button { page.tab = .sources } label: {
    HStack(spacing:10) {
     VStack(alignment:.leading,spacing:4) {
      Text("Traffic sources").font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
      Text("Tagged links, pins and QR codes · last 30 days")
       .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
     }
     Spacer(minLength:4)
     Image(systemName:"chevron.right").font(.system(size:11,weight:.semibold)).foregroundStyle(HubTheme.subtext)
    }
    .padding(16).frame(maxWidth:.infinity,minHeight:64,alignment:.leading).storeSnapshotCard()
   }
   .buttonStyle(.plain).accessibilityHint("Opens the loaded traffic-source counters")
   if let catalog = catalog {
    Button { page.tab = .catalog } label: {
     HStack(spacing:10) {
      VStack(alignment:.leading,spacing:4) {
       Text("Catalog").font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
       Text("\(catalog.count) products · \(catalog.categories) categories")
        .font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.subtext)
       Text(catalog.refreshed.map { "Recorded refresh \(ago($0))" } ?? "Refresh date unavailable")
        .font(.system(size:12,design:.rounded)).foregroundStyle(catalog.isStale() || catalog.refreshed == nil ? HubTheme.amber : HubTheme.subtext)
      }
      Spacer(minLength:4)
      Image(systemName:"chevron.right").font(.system(size:11,weight:.semibold)).foregroundStyle(HubTheme.subtext)
     }
     .padding(16).frame(maxWidth:.infinity,minHeight:76,alignment:.leading).storeSnapshotCard()
    }
    .buttonStyle(.plain).accessibilityHint("Opens the published catalog counts and recorded refresh date")
   } else {
    unavailable("Product catalog",detail:"Use Refresh to try the published product list again.")
   }
   Text("Counts reflect the loaded data. Visitor counts are not orders; orders and revenue are under Sales.")
    .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
 }

 private var sources: some View {
  VStack(alignment:.leading,spacing:14) {
   heading("Traffic sources",detail:"Positive tagged-link counts returned for the last 30 days, using UTC date ranges")
   if let store = store {
    let channels = store.channels.sorted { $0.count > $1.count }
    let shown = page.allSources ? channels : Array(channels.prefix(5))
    let largest = max(1,channels.first?.count ?? 1)
    if shown.isEmpty {
     Text("No tagged source returned a positive count in the loaded data.")
      .font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.subtext)
      .padding(18).frame(maxWidth:.infinity,alignment:.leading).storeSnapshotCard()
    } else {
     VStack(alignment:.leading,spacing:16) {
      ForEach(shown) { channel in
       VStack(alignment:.leading,spacing:8) {
        HStack(alignment:.top,spacing:12) {
         Text(channel.label).font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.text)
          .fixedSize(horizontal:false,vertical:true)
         Spacer(minLength:4)
         Text(String(channel.count)).font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
        }
        GeometryReader { geometry in
         ZStack(alignment:.leading) {
          Capsule().fill(HubTheme.line)
          Capsule().fill(HubTheme.amber)
           .frame(width:geometry.size.width * min(1,max(0,Double(channel.count) / Double(largest))))
         }
        }
        .frame(height:6).accessibilityHidden(true)
       }
       .accessibilityElement(children:.combine)
      }
      if channels.count > 5 {
       Button { page.allSources.toggle() } label: {
        Label(page.allSources ? "Show fewer sources" : "Show all \(channels.count) sources",systemImage:page.allSources ? "chevron.up" : "chevron.down")
         .font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
         .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
       }
       .buttonStyle(.plain)
      }
     }
     .padding(18).frame(maxWidth:.infinity,alignment:.leading).storeSnapshotCard()
    }
    Text("Bars compare the returned source counts. Separate source counters can overlap and do not add up to a unique-visitor total.")
     .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
    Text("An unlisted source can have no recorded visits or an unavailable counter. Tagged links do not cover every visit.")
     .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
   } else {
    unavailable("Traffic sources",detail:"Source counters are unavailable with the visitor snapshot. Use Refresh to try again.")
   }
  }
 }

 private var catalogDetails: some View {
  VStack(alignment:.leading,spacing:14) {
   heading("Catalog",detail:"Counts from the published product list")
   if let catalog = catalog {
    HStack(alignment:.top,spacing:12) {
     visitorMetric("Products",count:catalog.count,note:"Listed products")
     visitorMetric("Categories",count:catalog.categories,note:"Named in the list")
    }
    VStack(alignment:.leading,spacing:8) {
     Text("Last recorded refresh").font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
     if let date = catalog.refreshed {
      Text(date.formatted(date:.abbreviated,time:.shortened))
       .font(.system(size:17,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
      Text("\(ago(date)) · displayed in this Mac's time zone")
       .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
      if catalog.isStale() {
       Label("The recorded refresh is over five days old.",systemImage:"exclamationmark.triangle")
        .font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.amber)
      }
     } else {
      Text("Refresh date unavailable. Product counts loaded, but the last matching refresh commit could not be read.")
       .font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.amber)
     }
     Text("The configured refresh interval is three days. This date records the last matching product-refresh commit; it does not verify supplier availability.")
      .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    .padding(18).frame(maxWidth:.infinity,alignment:.leading).storeSnapshotCard()
   } else {
    unavailable("Product catalog",detail:"Use Refresh to try the published product list again. Visitor counts may still be available.")
   }
  }
 }

 private func visitorMetric(_ title: String,count: Int,note: String) -> some View {
  VStack(alignment:.leading,spacing:7) {
   Text(title).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.subtext)
   Text(String(count)).font(.system(size:28,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
    .lineLimit(1).minimumScaleFactor(0.5)
   Text(note).font(.system(size:11,design:.rounded)).foregroundStyle(HubTheme.subtext)
    .fixedSize(horizontal:false,vertical:true)
  }
  .padding(14).frame(maxWidth:.infinity,minHeight:116,alignment:.topLeading).storeSnapshotCard()
  .accessibilityElement(children:.combine)
 }

 private func heading(_ title: String,detail: String) -> some View {
  VStack(alignment:.leading,spacing:4) {
   Text(title).font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
    .accessibilityAddTraits(.isHeader)
   Text(detail).font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
    .fixedSize(horizontal:false,vertical:true)
  }
 }

 private func unavailable(_ title: String,detail: String) -> some View {
  VStack(alignment:.leading,spacing:8) {
   if loading { ProgressView().controlSize(.small) }
   Text(loading ? "Loading \(title.lowercased())…" : "\(title) unavailable")
    .font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
   Text(loading ? "Reading the public data." : detail)
    .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
  .padding(18).frame(maxWidth:.infinity,minHeight:110,alignment:.leading).storeSnapshotCard()
 }
}

private extension View {
 func storeSnapshotCard() -> some View {
  background(HubTheme.card,in:RoundedRectangle(cornerRadius:18))
   .overlay(RoundedRectangle(cornerRadius:18).stroke(HubTheme.line,lineWidth:1))
 }
}
