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
   VStack(alignment:.leading,spacing:16) {
    VStack(alignment:.leading,spacing:6) {
     Text("East Coast Social").font(.system(size:20,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
     Text("Daily cards published to the site's automation/feed")
      .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    HStack(spacing:8) {
     Button {
      if let url = URL(string:"https://findhotstuff.com/automation/") { NSWorkspace.shared.open(url) }
     } label: {
      Label("Open ECS",systemImage:"arrow.up.right.square")
       .font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
       .frame(maxWidth:.infinity,minHeight:44).ecsFeedControl()
     }
     .buttonStyle(.plain).disabled(DesignPreview.enabled)
     .accessibilityHint("Opens the existing East Coast Social site in your browser")
     Button { Task { await ventures.refresh(force:true) } } label: {
      Label(ventures.loading ? "Refreshing…" : "Refresh",systemImage:"arrow.clockwise")
       .font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
       .frame(maxWidth:.infinity,minHeight:44).ecsFeedControl()
     }
     .buttonStyle(.plain).disabled(ventures.loading || DesignPreview.enabled)
     .accessibilityLabel("Refresh the site's feed data")
    }
    EcsFeedDashboard(feed:ventures.feed,loading:ventures.loading) { text in
     NSPasteboard.general.clearContents()
     return NSPasteboard.general.setString(text,forType:.string)
    }
   }
   .padding(.horizontal,hub.compact ? 16 : 32).padding(.top,4).padding(.bottom,24)
  }
  .scrollIndicators(.hidden).background(HubTheme.background)
 }

 var hubSystems: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:16) {
    VStack(alignment:.leading,spacing:6) {
     HStack(spacing:10) {
      Text("Systems").font(.system(size:20,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
      Spacer(minLength:4)
      Button { Task { await ventures.refresh(force:true) } } label: {
       Label(ventures.loading ? "Refreshing…" : "Refresh",systemImage:"arrow.clockwise")
        .font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
        .padding(.horizontal,12).frame(minHeight:44).systemsControl()
      }
      .buttonStyle(.plain).disabled(ventures.loading || DesignPreview.enabled)
      .accessibilityLabel("Refresh the loaded runs, repository issues and catalog")
     }
     Text("Read-only results from the public repository")
      .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    SystemsSnapshotDashboard(runs:ventures.runs,issues:ventures.issues,catalog:ventures.catalog,loading:ventures.loading,lastAttempt:ventures.lastRefresh == .distantPast ? nil : ventures.lastRefresh,ago:hubAgo)
   }
   .padding(.horizontal,hub.compact ? 16 : 32).padding(.top,4).padding(.bottom,24)
  }
  .scrollIndicators(.hidden).background(HubTheme.background)
 }

 func hubRunRow(_ run: AutomationRun) -> some View {
  SystemsLoadedRunRow(run:run,ago:hubAgo)
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

private enum EcsFeedTab: String,CaseIterable {
 case overview = "Overview", cards = "Feed cards", wording = "Wording"
}

@MainActor private final class EcsFeedPageState: ObservableObject {
 @Published var tab = EcsFeedTab.overview
 @Published var openedCards: Set<String> = []
 @Published var copyNote = ""
}

// These counts and claims describe the site's own daily feed cards, never delivery to a social page.
private struct EcsFeedDashboard: View {
 let feed: FeedStats?
 let loading: Bool
 let copyWording: (String) -> Bool
 @StateObject private var page = EcsFeedPageState()

 var body: some View {
  VStack(alignment:.leading,spacing:16) {
   HStack(spacing:6) {
    ForEach(EcsFeedTab.allCases,id:\.self) { option in
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
   .accessibilityElement(children:.contain).accessibilityLabel("Site-feed views")
   if let feed = feed {
    switch page.tab {
    case .overview: overview(feed)
    case .cards: cards(feed)
    case .wording: wordingCard
    }
   } else {
    VStack(alignment:.leading,spacing:8) {
     if loading { ProgressView().controlSize(.small) }
     Text(loading ? "Loading the site's feed…" : "Site-feed data unavailable")
      .font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
     Text(loading ? "Reading the daily-card feed." : "Use Refresh to try the feed again, or Open ECS to view the site. Other venture data may still have loaded.")
      .font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    .padding(18).frame(maxWidth:.infinity,minHeight:130,alignment:.leading).ecsFeedCard()
   }
   Text("This page measures cards on the site's automation/feed, not posts delivered to a social page.")
    .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
  .onChange(of:wording) { _,_ in page.copyNote = "" }
 }

 private func overview(_ feed: FeedStats) -> some View {
  let streak = feed.streakDays()
  return VStack(alignment:.leading,spacing:14) {
   VStack(alignment:.leading,spacing:7) {
    Text("Published site-feed cards").font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.subtext)
    Text(String(feed.total)).font(.system(size:36,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
     .lineLimit(1).minimumScaleFactor(0.6)
    Text(feed.since.isEmpty ? "First feed date unavailable" : "Site-feed count since \(feed.since)")
     .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
   }
   .padding(20).frame(maxWidth:.infinity,alignment:.leading).ecsFeedCard()
   HStack(alignment:.top,spacing:12) {
    VStack(alignment:.leading,spacing:7) {
     Text("Site-feed streak").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.subtext)
     Text(streak.map { "\($0) days" } ?? "Not claimed")
      .font(.system(size:22,weight:.bold,design:.rounded)).foregroundStyle(streak == nil ? HubTheme.amber : HubTheme.green)
      .lineLimit(1).minimumScaleFactor(0.65)
     Text("Consecutive daily feed cards").font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
      .fixedSize(horizontal:false,vertical:true)
    }
    .padding(16).frame(maxWidth:.infinity,minHeight:120,alignment:.topLeading).ecsFeedCard()
    VStack(alignment:.leading,spacing:7) {
     Text("Newest feed card").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.subtext)
     Text(feed.last.isEmpty ? "Unavailable" : feed.last)
      .font(.system(size:19,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
      .lineLimit(1).minimumScaleFactor(0.65)
     Text("Date recorded in the feed").font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
      .fixedSize(horizontal:false,vertical:true)
    }
    .padding(16).frame(maxWidth:.infinity,minHeight:120,alignment:.topLeading).ecsFeedCard()
   }
   if let days = streak {
    Text("The loaded site-feed record supports a daily-card streak of \(days) days.")
     .font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.subtext)
   } else {
    Text("The feed's continuity check did not confirm a current daily run. The published-card count still appears above.")
     .font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.subtext)
   }
  }
 }

 private func cards(_ feed: FeedStats) -> some View {
  VStack(alignment:.leading,spacing:12) {
   heading("Recent site-feed cards",detail:"Loaded recent cards, not the full feed archive")
   if feed.cards.isEmpty {
    VStack(alignment:.leading,spacing:8) {
     Text(loading ? "Reading recent card details…" : "Recent card details unavailable")
      .font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
     Text("The feed count loaded, but no recent card details were returned. Use Refresh or Open ECS to check the site.")
      .font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    .padding(18).frame(maxWidth:.infinity,alignment:.leading).ecsFeedCard()
   } else {
    ForEach(Array(feed.cards.enumerated()),id:\.offset) { index,card in
     cardRow(card,key:"\(index)-\(card.date)")
    }
   }
  }
 }

 private func cardRow(_ card: FeedCard,key: String) -> some View {
  let expanded = page.openedCards.contains(key)
  let flat = card.message.replacingOccurrences(of:"\n",with:" ").trimmingCharacters(in:.whitespacesAndNewlines)
  let brief = flat.count > 140 ? String(flat.prefix(140)) + "…" : flat
  return VStack(alignment:.leading,spacing:12) {
   Button {
    if !page.openedCards.insert(key).inserted { page.openedCards.remove(key) }
   } label: {
    HStack(alignment:.top,spacing:10) {
     VStack(alignment:.leading,spacing:5) {
      Text(card.date.isEmpty ? "Feed-card date unavailable" : card.date)
       .font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.subtext)
      Text(brief.isEmpty ? "No caption supplied for this feed card." : brief)
       .font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.text)
       .lineLimit(2).multilineTextAlignment(.leading)
     }
     Spacer(minLength:4)
     Image(systemName:expanded ? "chevron.up" : "chevron.down")
      .font(.system(size:11,weight:.semibold)).foregroundStyle(HubTheme.subtext)
    }
    .frame(maxWidth:.infinity,minHeight:44,alignment:.leading).contentShape(Rectangle())
   }
   .buttonStyle(.plain)
   .accessibilityLabel("Site-feed card, \(card.date.isEmpty ? "date unavailable" : card.date). \(brief.isEmpty ? "Caption unavailable" : brief)")
   .accessibilityHint(expanded ? "Collapses the full caption and image" : "Opens the full caption and image")
   if expanded {
    if !card.message.isEmpty {
     Text(card.message).font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.text)
      .fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
    }
    cardImage(card)
   }
  }
  .padding(16).frame(maxWidth:.infinity,alignment:.leading).ecsFeedCard()
 }

 @ViewBuilder private func cardImage(_ card: FeedCard) -> some View {
  if card.image.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty {
   imageState("No image supplied for this feed card.",loading:false)
  } else if DesignPreview.enabled {
   imageState("Site-feed image preview",loading:false)
  } else if let url = URL(string:"\(VentureData.feed)\(card.image)") {
   AsyncImage(url:url) { phase in
    switch phase {
    case .success(let image):
     image.resizable().scaledToFit().frame(maxWidth:.infinity,maxHeight:300)
      .clipShape(RoundedRectangle(cornerRadius:12))
      .accessibilityLabel("Site-feed image for \(card.date.isEmpty ? "an undated card" : card.date)")
    case .failure: imageState("The feed-card image couldn't load. The caption is shown above.",loading:false)
    default: imageState("Loading the feed-card image…",loading:true)
    }
   }
  } else {
   imageState("Feed-card image address unavailable.",loading:false)
  }
 }

 private func imageState(_ title: String,loading: Bool) -> some View {
  HStack(spacing:10) {
   if loading { ProgressView().controlSize(.small) }
   Text(title).font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
  .padding(14).frame(maxWidth:.infinity,minHeight:64,alignment:.leading)
  .background(HubTheme.control,in:RoundedRectangle(cornerRadius:12))
 }

 private var wording: String {
  guard let feed = feed else { return "" }
  if let days = feed.streakDays() {
   return "My own store's site feed has published a new card every day for \(days) days (findhotstuff.com/automation/)."
  }
  let since = feed.since.isEmpty ? "" : " since \(feed.since)"
  let through = feed.last.isEmpty ? "" : "; the latest feed-card date is \(feed.last)"
  return "My own store's site feed records \(feed.total) published cards\(since)\(through) (findhotstuff.com/automation/)."
 }

 private var wordingCard: some View {
  VStack(alignment:.leading,spacing:12) {
   heading("Wording for the site feed",detail:"Describes the loaded daily-card record")
   Text(wording).font(.system(size:14,design:.rounded)).foregroundStyle(HubTheme.text)
    .fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
   Text("This wording describes cards published to automation/feed. It makes no claim about delivery to a social page.")
    .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
   Button {
    page.copyNote = copyWording(wording) ? "Wording copied." : "Couldn't copy the wording. You can select the text and copy it."
   } label: {
    Label("Copy wording",systemImage:"doc.on.doc")
     .font(.system(size:12.5,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
     .frame(maxWidth:.infinity,minHeight:44).ecsFeedControl()
   }
   .buttonStyle(.plain).disabled(DesignPreview.enabled)
   .accessibilityHint("Copies the displayed wording to your clipboard")
   if !page.copyNote.isEmpty {
    Text(page.copyNote).font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
   }
  }
  .padding(18).frame(maxWidth:.infinity,alignment:.leading).ecsFeedCard()
 }

 private func heading(_ title: String,detail: String) -> some View {
  VStack(alignment:.leading,spacing:4) {
   Text(title).font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
    .accessibilityAddTraits(.isHeader)
   Text(detail).font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
 }
}

private extension View {
 func ecsFeedCard() -> some View {
  background(HubTheme.card,in:RoundedRectangle(cornerRadius:18))
   .overlay(RoundedRectangle(cornerRadius:18).stroke(HubTheme.line,lineWidth:1))
 }
 func ecsFeedControl() -> some View {
  background(HubTheme.control,in:RoundedRectangle(cornerRadius:12))
   .overlay(RoundedRectangle(cornerRadius:12).stroke(HubTheme.controlOutline,lineWidth:1))
 }
}

private enum SystemsRunCategory { case success, review, active, other, unavailable }

private struct SystemsRunResult {
 let category: SystemsRunCategory
 let label: String
 let icon: String
 var tint: Color {
  switch category {
  case .success: return HubTheme.green
  case .review: return HubTheme.amber
  case .active: return HubTheme.blue
  case .other,.unavailable: return HubTheme.subtext
  }
 }

 static func read(_ run: AutomationRun) -> SystemsRunResult {
  let status = run.status.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
  let conclusion = run.conclusion.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
  if status == "completed" {
   switch conclusion {
   case "success": return Self(category:.success,label:"Completed successfully",icon:"checkmark.circle")
   case "failure": return Self(category:.review,label:"Failed",icon:"xmark.circle")
   case "timed_out": return Self(category:.review,label:"Timed out",icon:"clock.badge.exclamationmark")
   case "action_required": return Self(category:.review,label:"Action required",icon:"hand.raised")
   case "stale": return Self(category:.review,label:"Stale result",icon:"clock.badge.exclamationmark")
   case "startup_failure": return Self(category:.review,label:"Startup failure",icon:"xmark.circle")
   case "cancelled": return Self(category:.other,label:"Cancelled",icon:"minus.circle")
   case "skipped": return Self(category:.other,label:"Skipped",icon:"forward.end.circle")
   case "neutral": return Self(category:.other,label:"Neutral",icon:"minus.circle")
   default: return Self(category:.unavailable,label:"Conclusion unavailable",icon:"questionmark.circle")
   }
  }
  switch status {
  case "in_progress": return Self(category:.active,label:"In progress in loaded data",icon:"arrow.triangle.2.circlepath")
  case "queued": return Self(category:.active,label:"Queued in loaded data",icon:"clock")
  case "requested": return Self(category:.active,label:"Requested in loaded data",icon:"clock")
  case "waiting": return Self(category:.active,label:"Waiting in loaded data",icon:"clock")
  case "pending": return Self(category:.active,label:"Pending in loaded data",icon:"clock")
  case "expected": return Self(category:.active,label:"Expected in loaded data",icon:"clock")
  default: return Self(category:.unavailable,label:"Status unavailable",icon:"questionmark.circle")
  }
 }
}

private enum SystemsSnapshotTab: String,CaseIterable {
 case overview = "Overview", runs = "Runs", issues = "Issues"
}

@MainActor private final class SystemsSnapshotPageState: ObservableObject {
 @Published var tab = SystemsSnapshotTab.overview
 @Published var allRuns = false
 @Published var allIssues = false
}

// The reader retains caches on failure. Counts below describe only the values it returned and kept.
private struct SystemsSnapshotDashboard: View {
 let runs: [AutomationRun]?
 let issues: [OpenAlert]?
 let catalog: CatalogStats?
 let loading: Bool
 let lastAttempt: Date?
 let ago: (Date?) -> String
 @StateObject private var page = SystemsSnapshotPageState()

 var body: some View {
  VStack(alignment:.leading,spacing:16) {
   HStack(spacing:6) {
    ForEach(SystemsSnapshotTab.allCases,id:\.self) { option in
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
   .accessibilityElement(children:.contain).accessibilityLabel("Systems views")
   switch page.tab {
   case .overview: overview
   case .runs: runList
   case .issues: issueList
   }
   VStack(alignment:.leading,spacing:4) {
    Text(lastAttempt.map { "Last refresh attempt: \($0.formatted(date:.abbreviated,time:.shortened))" } ?? "No refresh attempt recorded in this session.")
    Text("Earlier loaded values can remain after a failed refresh. A successful run result does not prove a post or other external action happened. Open issues may explain missing access or credits.")
   }
   .font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
 }

 private var overview: some View {
  VStack(alignment:.leading,spacing:12) {
   if let runs = runs {
    let states = runs.map(SystemsRunResult.read)
    let review = states.filter { $0.category == .review }.count
    let unknown = states.filter { $0.category == .unavailable }.count
    let active = states.filter { $0.category == .active }.count
    let success = states.filter { $0.category == .success }.count
    let other = states.filter { $0.category == .other }.count
    Button { page.tab = .runs } label: {
     summary("Latest loaded runs",value:review > 0 ? "\(review) results to review" : (unknown > 0 ? "\(unknown) results unavailable" : "\(runs.count) loaded run results"),detail:"\(success) success · \(active) active · \(other) other\(unknown > 0 ? " · \(unknown) unavailable" : "")",tint:review > 0 ? HubTheme.amber : HubTheme.text,opens:true)
    }
    .buttonStyle(.plain).accessibilityHint("Opens the loaded workflow results")
   } else {
    unavailable("Run results",detail:"Use Refresh to try the repository's workflow runs again.")
   }
   if let issues = issues {
    Button { page.tab = .issues } label: {
     summary("Repository issues",value:"\(issues.count) loaded open issues",detail:issues.contains { $0.id == 15 } ? "Includes Meeting Room #15; issues are not all outages." : "Issues can be discussions, requests or outages.",tint:HubTheme.text,opens:true)
    }
    .buttonStyle(.plain).accessibilityHint("Opens the loaded repository issues")
   } else {
    unavailable("Repository issues",detail:"Use Refresh to try the open-issue list again.")
   }
   catalogSummary
  }
 }

 private var catalogSummary: some View {
  Group {
   if let catalog = catalog {
    VStack(alignment:.leading,spacing:7) {
     Text("Catalog record").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.subtext)
     Text("\(catalog.count) products · \(catalog.categories) categories")
      .font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
     if let date = catalog.refreshed {
      Text("Recorded refresh \(ago(date))\(catalog.isStale() ? " · over five days old" : "")")
       .font(.system(size:12,design:.rounded)).foregroundStyle(catalog.isStale() ? HubTheme.amber : HubTheme.subtext)
     } else {
      Text("Refresh date unknown").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.amber)
     }
     Text("Date of the matching product-refresh commit; supplier availability is not verified.")
      .font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
    .padding(16).frame(maxWidth:.infinity,alignment:.leading).systemsCard()
   } else {
    unavailable("Catalog record",detail:"Use Refresh to try the product list and its recorded refresh date again.")
   }
  }
 }

 private var runList: some View {
  VStack(alignment:.leading,spacing:12) {
   heading("Latest loaded runs",detail:"From the 60 most recent repository runs, grouped by workflow name. Some workflows may be absent.")
   if let runs = runs {
    if runs.isEmpty {
     empty("No run records were returned in the loaded response.")
    } else {
     let sorted = runs.sorted {
      let a = rank(SystemsRunResult.read($0).category), b = rank(SystemsRunResult.read($1).category)
      return a == b ? ($0.created ?? .distantPast) > ($1.created ?? .distantPast) : a < b
     }
     Text("Review and unavailable results first; times show when runs were created.")
      .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
     ForEach(page.allRuns ? sorted : Array(sorted.prefix(2))) { run in SystemsLoadedRunRow(run:run,ago:ago) }
     if sorted.count > 2 { showAll(page.allRuns,title:"runs",count:sorted.count) { page.allRuns.toggle() } }
    }
   } else {
    unavailable("Run results",detail:"The workflow-run request has no loaded data. Use Refresh to try again.")
   }
  }
 }

 private var issueList: some View {
  VStack(alignment:.leading,spacing:12) {
   heading("Loaded repository issues",detail:"Up to 30 open issues. This list includes discussions such as Meeting Room #15, not only incidents.")
   if let issues = issues {
    if issues.isEmpty {
     empty("No open issues were returned in the loaded response.")
    } else {
     ForEach(page.allIssues ? issues : Array(issues.prefix(3))) { issue in
      VStack(alignment:.leading,spacing:8) {
       HStack(alignment:.top,spacing:10) {
        VStack(alignment:.leading,spacing:5) {
         Text("#\(issue.id) · \(issue.id == 15 ? "Meeting Room" : "Open issue")")
          .font(.system(size:11.5,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.subtext)
         Text(issue.title).font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
          .lineLimit(2).multilineTextAlignment(.leading)
        }
        Spacer(minLength:4)
        if let url = URL(string:issue.url), !issue.url.isEmpty {
         Button { NSWorkspace.shared.open(url) } label: {
          Image(systemName:"arrow.up.right").frame(width:44,height:44).foregroundStyle(HubTheme.text).systemsControl()
         }
         .buttonStyle(.plain).disabled(DesignPreview.enabled)
         .accessibilityLabel("Open issue \(issue.id): \(issue.title)")
        }
       }
       Text(issue.since.map { "Opened \($0.formatted(date:.abbreviated,time:.shortened))" } ?? "Issue creation time unavailable")
        .font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
      }
      .padding(16).frame(maxWidth:.infinity,alignment:.leading).systemsCard()
     }
     if issues.count > 3 { showAll(page.allIssues,title:"issues",count:issues.count) { page.allIssues.toggle() } }
    }
   } else {
    unavailable("Repository issues",detail:"The issue request has no loaded data. Use Refresh to try again.")
   }
  }
 }

 private func summary(_ title: String,value: String,detail: String,tint: Color,opens: Bool) -> some View {
  HStack(alignment:.center,spacing:10) {
   VStack(alignment:.leading,spacing:6) {
    Text(title).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(HubTheme.subtext)
    Text(value).font(.system(size:17,weight:.semibold,design:.rounded)).foregroundStyle(tint)
    Text(detail).font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
     .fixedSize(horizontal:false,vertical:true)
   }
   Spacer(minLength:4)
   if opens { Image(systemName:"chevron.right").font(.system(size:11,weight:.semibold)).foregroundStyle(HubTheme.subtext) }
  }
  .padding(16).frame(maxWidth:.infinity,minHeight:88,alignment:.leading).systemsCard()
 }

 private func heading(_ title: String,detail: String) -> some View {
  VStack(alignment:.leading,spacing:4) {
   Text(title).font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text).accessibilityAddTraits(.isHeader)
   Text(detail).font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
 }

 private func unavailable(_ title: String,detail: String) -> some View {
  VStack(alignment:.leading,spacing:8) {
   if loading { ProgressView().controlSize(.small) }
   Text(loading ? "Loading \(title.lowercased())…" : "\(title) unavailable")
    .font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
   Text(loading ? "Reading the public repository data." : detail)
    .font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
  .padding(16).frame(maxWidth:.infinity,minHeight:100,alignment:.leading).systemsCard()
 }

 private func empty(_ text: String) -> some View {
  Text(text).font(.system(size:13,design:.rounded)).foregroundStyle(HubTheme.subtext)
   .padding(18).frame(maxWidth:.infinity,alignment:.leading).systemsCard()
 }

 private func showAll(_ expanded: Bool,title: String,count: Int,action: @escaping () -> Void) -> some View {
  Button(action:action) {
   Label(expanded ? "Show fewer \(title)" : "Show all \(count) loaded \(title)",systemImage:expanded ? "chevron.up" : "chevron.down")
    .font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text)
    .frame(maxWidth:.infinity,minHeight:44,alignment:.leading)
  }
  .buttonStyle(.plain)
 }

 private func rank(_ category: SystemsRunCategory) -> Int {
  switch category { case .review: return 0; case .unavailable: return 1; case .active: return 2; case .other: return 3; case .success: return 4 }
 }
}

private struct SystemsLoadedRunRow: View {
 let run: AutomationRun
 let ago: (Date?) -> String
 var body: some View {
  let state = SystemsRunResult.read(run)
  return VStack(alignment:.leading,spacing:8) {
   HStack(alignment:.top,spacing:10) {
    Image(systemName:state.icon).font(.system(size:18)).foregroundStyle(state.tint).accessibilityHidden(true)
    VStack(alignment:.leading,spacing:5) {
     Text(run.name).font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text).lineLimit(2)
     Text(state.label).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(state.tint)
    }
    Spacer(minLength:4)
    if let url = URL(string:run.url), !run.url.isEmpty {
     Button { NSWorkspace.shared.open(url) } label: {
      Image(systemName:"arrow.up.right").frame(width:44,height:44).foregroundStyle(HubTheme.text).systemsControl()
     }
     .buttonStyle(.plain).disabled(DesignPreview.enabled)
     .accessibilityLabel("Open run details for \(run.name)")
    }
   }
   Text(run.created.map { "Run created \($0.formatted(date:.abbreviated,time:.shortened)) · \(ago($0))" } ?? "Run creation time unavailable")
    .font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
   Text("Status: \(run.status.isEmpty ? "not supplied" : run.status) · conclusion: \(run.conclusion.isEmpty ? "not supplied" : run.conclusion)")
    .font(.system(size:11.5,design:.rounded)).foregroundStyle(HubTheme.subtext)
  }
  .padding(16).frame(maxWidth:.infinity,alignment:.leading).systemsCard()
 }
}

private extension View {
 func systemsCard() -> some View {
  background(HubTheme.card,in:RoundedRectangle(cornerRadius:18))
   .overlay(RoundedRectangle(cornerRadius:18).stroke(HubTheme.line,lineWidth:1))
 }
 func systemsControl() -> some View {
  background(HubTheme.control,in:RoundedRectangle(cornerRadius:12))
   .overlay(RoundedRectangle(cornerRadius:12).stroke(HubTheme.controlOutline,lineWidth:1))
 }
}
