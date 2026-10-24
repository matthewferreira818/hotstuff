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
  }
 }

 var hubRail: some View {
  VStack(spacing:10) {
   Circle()
    .fill(RadialGradient(colors:[Noir.crimsonLight,Noir.crimson,Noir.crimsonDeep],center:UnitPoint(x:0.35,y:0.3),startRadius:1,endRadius:22))
    .frame(width:30,height:30)
    .padding(.bottom,4)
   ScrollView(showsIndicators:false) {
    VStack(spacing:5) {
     ForEach(hub.order) { section in
      hubRailButton(section)
       .onDrag {
        hub.dragging = section
        return NSItemProvider(object:String(section.rawValue) as NSString)
       }
       .onDrop(of:[UTType.text],delegate:RailDropDelegate(target:section,hub:hub))
       .contextMenu {
        Button("Move up") { withAnimation(.spring(response:0.34,dampingFraction:0.8)) { hub.nudge(section,by:-1) } }
        Button("Move down") { withAnimation(.spring(response:0.34,dampingFraction:0.8)) { hub.nudge(section,by:1) } }
        Button("Put the icons back in the original order") { withAnimation(.spring(response:0.34,dampingFraction:0.8)) { hub.resetOrder() } }
       }
     }
    }
    .padding(.vertical,2)
   }
   Spacer(minLength:0)
   Button { c.showPanel = true } label: {
    VStack(spacing:5) {
     Image(systemName:"slider.horizontal.3").font(.system(size:17,weight:.semibold)).foregroundStyle(Color.white.opacity(0.7)).frame(width:48,height:32)
     if !hub.compact { Text("Settings").font(.system(size:10,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.5)) }
    }
   }
   .buttonStyle(.plain)
   .keyboardShortcut(",",modifiers:.command)
   .hubHover("rail-settings",hub,lift:1.06)
  }
  .padding(.top,hub.compact ? 28 : 40).padding(.bottom,16)
  .frame(width:hub.compact ? 60 : 88)
  .background(.ultraThinMaterial)
  .overlay(alignment:.trailing) { Rectangle().fill(Color.white.opacity(0.08)).frame(width:1) }
 }

 func hubRailButton(_ section: HubSection) -> some View {
  let selected = hub.section == section
  return Button { hubSelect(section) } label: {
   VStack(spacing:3) {
    ZStack {
     RoundedRectangle(cornerRadius:14,style:.continuous).fill(Color.white.opacity(0.06)).frame(width:42,height:42)
     if selected {
      RoundedRectangle(cornerRadius:14,style:.continuous)
       .fill(LinearGradient(colors:[Noir.crimsonLight,Noir.crimson],startPoint:.topLeading,endPoint:.bottomTrailing))
       .frame(width:42,height:42)
       .matchedGeometryEffect(id:"railSelection",in:railNamespace)
     }
     Image(systemName:section.icon).font(.system(size:17,weight:.semibold)).foregroundStyle(Color.white.opacity(selected ? 1 : 0.7))
    }
    if !hub.compact { Text(section.title).font(.system(size:10,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(selected ? 0.95 : 0.5)) }
   }
  }
  .buttonStyle(.plain)
  .hubShortcut(hub.shortcut(for:section))
  .hubHover("rail-\(section.rawValue)",hub,lift:1.06)
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
