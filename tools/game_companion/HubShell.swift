import SwiftUI
import AppKit
import UniformTypeIdentifiers

// The window around every page: the rail, the top bar, refresh and which page shows.
// Split out of Hub.swift on 2026-10-24 with no change in behaviour, so pages can have one owner each.
extension CompanionInterfaceView {
 // MARK: shell

 var hubShell: some View {
  GeometryReader { geo in
   HStack(spacing:0) {
    hubRail
    VStack(spacing:0) {
     hubTopBar
     hubContent
      .frame(maxWidth:.infinity,maxHeight:.infinity)
      .id(hub.section)
      .transition(.opacity.combined(with:.scale(scale:0.985)))
    }
   }
   .onAppear { hub.compact = geo.size.width < 720 }
   .onChange(of:geo.size.width) { _,width in hub.compact = width < 720 }
   .sheet(isPresented:$hub.jumpPresented) { hubJumpSheet }
  }
 }

 // Compact windows keep a labelled, keyboard-accessible way to reach every page.
 var hubRail: some View {
  VStack(alignment:.leading,spacing:8) {
   Button { hubSelect(.home) } label: {
    HStack(spacing:11) {
     Circle()
      .fill(RadialGradient(colors:[HubTheme.crimson,HubTheme.hex(0x6C1C38),HubTheme.hex(0x17080E)],center:UnitPoint(x:0.3,y:0.25),startRadius:2,endRadius:24))
      .frame(width:30,height:30)
     if !hub.compact {
      Text("MoneyHub").font(.system(size:18,weight:.bold,design:.rounded))
       .foregroundStyle(HubTheme.text)
     }
    }
    .frame(maxWidth:.infinity,minHeight:48,alignment:hub.compact ? .center : .leading)
   }
   .buttonStyle(.plain).accessibilityLabel("MoneyHub Home")
   .padding(.horizontal,hub.compact ? 4 : 12)

   Button { hub.jumpQuery = ""; hub.jumpPresented = true } label: {
    HStack(spacing:9) {
     Image(systemName:"magnifyingglass").font(.system(size:16,weight:.semibold))
     if !hub.compact {
      Text("Jump to…").font(.system(size:13,weight:.medium))
      Spacer(minLength:2)
      Text("⌘K").font(.system(size:11,weight:.medium))
     }
    }
    .foregroundStyle(HubTheme.subtext)
    .frame(maxWidth:.infinity,minHeight:48,alignment:hub.compact ? .center : .leading)
    .padding(.horizontal,hub.compact ? 0 : 12)
    .background(HubTheme.control,in:RoundedRectangle(cornerRadius:11))
    .overlay(RoundedRectangle(cornerRadius:11).stroke(HubTheme.controlOutline,lineWidth:1))
   }
   .buttonStyle(.plain).keyboardShortcut("k",modifiers:.command)
   .accessibilityLabel("Jump to a page")
   .help("Search all pages (Command-K)")
   .padding(.horizontal,hub.compact ? 7 : 10)

   ScrollView(showsIndicators:false) {
    VStack(alignment:.leading,spacing:4) {
     hubRailButton(.home)
     hubRailGroup("CREW",pages:[.friday,.helper,.meeting])
     hubRailGroup("BUSINESS",pages:[.stocks,.store,.ecs,.systems])
     hubRailGroup("STREAM",pages:[.stream,.game])
     hubRailGroup("SETUP",pages:[.launchpad,.accounts])
    }
    .padding(.horizontal,hub.compact ? 4 : 10)
    .padding(.bottom,10)
   }
   Spacer(minLength:0)
   Button { c.showPanel = true } label: {
    HStack(spacing:10) {
     Image(systemName:"slider.horizontal.3").frame(width:22)
     if !hub.compact { Text("Settings") }
    }
    .font(.system(size:14,weight:.medium))
    .foregroundStyle(HubTheme.subtext)
    .frame(maxWidth:.infinity,minHeight:48,alignment:hub.compact ? .center : .leading)
    .padding(.horizontal,hub.compact ? 0 : 12)
   }
   .buttonStyle(.plain)
   .keyboardShortcut(",",modifiers:.command)
   .accessibilityLabel("Settings")
   .padding(.horizontal,hub.compact ? 4 : 10)
  }
  .padding(.vertical,16)
  .frame(width:hub.compact ? 60 : 214)
  .background(HubTheme.sidebar)
  .overlay(alignment:.trailing) { Rectangle().fill(HubTheme.line).frame(width:1) }
 }

 func hubRailGroup(_ label: String,pages: [HubSection]) -> some View {
  VStack(alignment:.leading,spacing:2) {
   if !hub.compact {
    Text(label).font(.system(size:11,weight:.bold,design:.rounded))
     .tracking(1.25).foregroundStyle(HubTheme.subtext)
     .padding(.leading,12).padding(.top,14).padding(.bottom,4)
     .accessibilityAddTraits(.isHeader)
   } else {
    Rectangle().fill(HubTheme.line).frame(height:1).padding(.vertical,9).padding(.horizontal,10)
   }
   ForEach(hub.order.filter { pages.contains($0) }) { section in
    hubRailButton(section)
     .onDrag {
      hub.dragging = section
      return NSItemProvider(object:String(section.rawValue) as NSString)
     }
     .onDrop(of:[UTType.text],delegate:RailDropDelegate(target:section,hub:hub))
     .contextMenu {
      Button("Move up") { hub.nudge(section,by:-1) }
      Button("Move down") { hub.nudge(section,by:1) }
      Button("Reset page order") { hub.resetOrder() }
     }
   }
  }
 }

 func hubRailButton(_ section: HubSection) -> some View {
  let selected = hub.section == section
  return Button { hubSelect(section) } label: {
   HStack(spacing:11) {
    Image(systemName:section.icon)
     .font(.system(size:17,weight:.medium))
     .frame(width:22,height:24)
     .foregroundStyle(selected ? HubTheme.crimson : HubTheme.subtext)
    if !hub.compact {
     Text(section.title).font(.system(size:14,weight:selected ? .semibold : .medium))
      .foregroundStyle(selected ? HubTheme.text : HubTheme.subtext)
      .lineLimit(1)
     Spacer(minLength:0)
    }
   }
   .frame(maxWidth:.infinity,minHeight:48,alignment:hub.compact ? .center : .leading)
   .padding(.horizontal,hub.compact ? 0 : 12)
   .background(selected ? HubTheme.control : Color.clear,in:RoundedRectangle(cornerRadius:11))
   .overlay(RoundedRectangle(cornerRadius:11)
    .stroke(selected ? HubTheme.controlOutline : Color.clear,lineWidth:1))
  }
  .buttonStyle(.plain)
  .accessibilityLabel(section.title)
  .accessibilityAddTraits(selected ? .isSelected : [])
  .help(section.title)
  .hubShortcut(hub.shortcut(for:section))
 }

 var hubJumpSheet: some View {
  VStack(alignment:.leading,spacing:14) {
   Text("Jump to a page").font(.system(size:22,weight:.bold,design:.rounded))
    .foregroundStyle(HubTheme.text)
   HStack(spacing:10) {
    Image(systemName:"magnifyingglass").foregroundStyle(HubTheme.blue)
    TextField("Search pages",text:$hub.jumpQuery)
     .textFieldStyle(.plain)
     .foregroundStyle(HubTheme.text)
     .onSubmit {
      if let first = HubSection.allCases.first(where: {
       hub.jumpQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(hub.jumpQuery)
      }) {
       hub.jumpPresented = false
       hubSelect(first)
      }
     }
   }
   .padding(15)
   .background(HubTheme.control,in:RoundedRectangle(cornerRadius:12))
   .overlay(RoundedRectangle(cornerRadius:12).stroke(HubTheme.controlOutline))
   ScrollView {
    VStack(spacing:3) {
     ForEach(HubSection.allCases.filter {
      hub.jumpQuery.isEmpty || $0.title.localizedCaseInsensitiveContains(hub.jumpQuery)
     }) { section in
      Button {
       hub.jumpPresented = false
       hubSelect(section)
      } label: {
       HStack(spacing:12) {
        Image(systemName:section.icon).frame(width:24)
        Text(section.title)
        Spacer()
        Image(systemName:"arrow.up.left").font(.system(size:11))
       }
       .foregroundStyle(HubTheme.text)
       .frame(minHeight:48)
       .padding(.horizontal,12)
       .background(HubTheme.card,in:RoundedRectangle(cornerRadius:10))
      }
      .buttonStyle(.plain)
     }
    }
   }
  }
  .padding(22)
  .frame(width:460,height:430)
  .background(HubTheme.background)
 }
 // Moves to a page with a spring and a soft tap on the trackpad.
 func hubSelect(_ section: HubSection) {
  guard hub.section != section else { return }
  NSHapticFeedbackManager.defaultPerformer.perform(.alignment,performanceTime:.default)
  withAnimation(.spring(response:0.5,dampingFraction:0.86)) { hub.section = section }
 }

 var hubTopBar: some View {
  HStack(spacing:14) {
   VStack(alignment:.leading,spacing:3) {
    Text(hub.section == .home ? hubGreeting : hub.section.title).font(.system(size:hub.compact ? 19 : 26,weight:.bold,design:.rounded)).foregroundStyle(Color.white).lineLimit(1).minimumScaleFactor(0.7)
    if !hub.compact { Text(hub.section.blurb).font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.55)) }
   }
   Spacer()
   if c.tab == 0 && live.running {
    HStack(spacing:6) {
     Circle().fill(Noir.crimsonLight).frame(width:7,height:7)
     Text("LIVE").font(.system(size:10,weight:.bold,design:.rounded)).tracking(1.2)
    }
    .foregroundStyle(Color.white.opacity(0.9))
    .padding(.horizontal,12).padding(.vertical,8)
    .background(Capsule().fill(Noir.crimson.opacity(0.35)))
   }
   Button { Task { await hubRefreshAll() } } label: {
    HStack(spacing:6) {
     if hubAnyLoading { ProgressView().controlSize(.small) } else { Image(systemName:"arrow.clockwise") }
     if !hub.compact { Text(hubAnyLoading ? "Refreshing…" : (hub.refreshedAt.map { "Updated \(hubAgo($0))" } ?? "Refresh")) }
    }
    .font(.system(size:12,weight:.medium,design:.rounded))
   }
   .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   .keyboardShortcut("r",modifiers:.command)
   .disabled(hubAnyLoading)
   .help("Refresh everything: stocks, store, sales, systems and the Meeting Room (Command-R)")
   HStack(spacing:8) {
    Image(systemName:"sparkles").foregroundStyle(Noir.crimsonLight)
    TextField("Ask Friday…",text:$hub.query).textFieldStyle(.plain).onSubmit { hubAskFromBar() }
   }
   .padding(.horizontal,16).padding(.vertical,11)
   .frame(minWidth:110,idealWidth:300,maxWidth:300)
   .background(.ultraThinMaterial,in:Capsule())
   .overlay(Capsule().stroke(Color.white.opacity(0.12),lineWidth:1))
   if !hub.compact {
    Text("M").font(.system(size:14,weight:.bold,design:.rounded)).foregroundStyle(Color.white)
     .frame(width:36,height:36)
     .background(Circle().fill(LinearGradient(colors:[Noir.crimsonLight,Noir.crimsonDeep],startPoint:.topLeading,endPoint:.bottomTrailing)))
   }
  }
  .padding(.horizontal,hub.compact ? 14 : 32).padding(.top,hub.compact ? 14 : 26).padding(.bottom,12)
 }

 var hubAnyLoading: Bool { stocks.loading || ventures.loading || sales.loading || meeting.loading || stream.loading }

 // Everything that goes stale: the stock snapshots, store and ECS numbers, automations, sales and the Meeting Room.
 func hubRefreshAll() async {
  async let stockRun: Void = stocks.refresh()
  async let ventureRun: Void = ventures.refresh(force:true)
  async let salesRun: Void = sales.refresh(force:true)
  async let roomRun: Void = meeting.refresh(force:true)
  async let streamRun: Void = stream.refresh(force:true)
  _ = await (stockRun,ventureRun,salesRun,roomRun,streamRun)
  hub.refreshedAt = Date()
 }

 // Once a minute, refresh just the page that is on screen, so a page left open stays current.
 func hubRefreshVisible() async {
  switch hub.section {
  case .stocks: await stocks.refresh()
  case .meeting: await meeting.refresh(minGap:meeting.hasToken ? 55 : 290)
  case .stream: await stream.refresh()
  case .home,.store,.ecs,.systems: await ventures.refresh()
  default: break
  }
 }

 @ViewBuilder var hubContent: some View {
  switch hub.section {
  case .home: hubHome
  case .friday:
   GeometryReader { geo in
    // In a small window the orb shrinks, the round buttons stay on screen (smaller) and the rest scrolls.
    let tight = hub.compact || geo.size.height < 560
    HStack {
     Spacer(minLength:0)
     fridayStage(orb:tight ? min(max(geo.size.height * 0.26,80),200) : min(max(geo.size.height * 0.36,150),360),tight:tight)
      .frame(width:min(max(geo.size.width * 0.55,520),760,max(geo.size.width - 24,280)),height:geo.size.height)
     Spacer(minLength:0)
    }
   }
  case .stocks: hubStocks
  case .store: hubStore
  case .ecs: hubEcs
  case .systems: hubSystems
  case .launchpad: hubLaunchpad
  case .game: hubGame
  case .accounts: hubAccounts
  case .meeting: hubMeeting
  case .stream: hubStream
  case .helper: hubHelper
  }
 }
}
