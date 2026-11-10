import SwiftUI
import AppKit

// Signal Deck (2026-11-06): the window around every page. A top tab bar (Home, Friday, Stock bot, Store, ECS, the green Hacking area and a
// More menu that holds every other page), and Friday docked on the right of every page. Nothing was deleted: every page that used to be on
// the left rail is still one click away. The dock only shows what the live session already knows; it starts nothing by itself.
extension CompanionInterfaceView {
 static let deckPrimary: [HubSection] = [.home,.friday,.stocks,.store,.ecs]
 static let deckHack: [HubSection] = [.hacking,.systems,.shield,.lab,.realFake,.crewStation]
 static let deckMore: [HubSection] = [.launchpad,.game,.accounts,.meeting,.stream,.helper,.council]

 var deckInHack: Bool { Self.deckHack.contains(hub.section) }
 var deckInMore: Bool { Self.deckMore.contains(hub.section) }
 // Wide enough for the dock? Friday's own page is the big version of it, so the dock steps aside there.
 var deckShowsDock: Bool { !hub.compact && hub.section != .friday }

 var deckShell: some View {
  GeometryReader { geo in
   VStack(spacing:0) {
    if hub.simple { simpleTopBar } else { deckTopBar }
    HStack(spacing:0) {
     VStack(spacing:0) {
      if hub.simple { simplePageTop }
      else if deckInHack { deckHackNav }
      else if ![.home,.friday,.stocks].contains(hub.section) { deckPageHeader }
      hubContent
       .frame(maxWidth:.infinity,maxHeight:.infinity)
       .id(hub.section)
       .transition(.opacity)
     }
     if deckShowsDock && !hub.simple { deckDock.transition(.opacity) }
    }
   }
   .overlay { if hub.tourStep >= 0 && hub.simple { simpleTour } }
   .onAppear { hub.compact = geo.size.width < 900; hub.width = geo.size.width }
   .onChange(of:geo.size.width) { _,width in hub.compact = width < 900; hub.width = width }
   .sheet(isPresented:$hub.jumpPresented) { hubJumpSheet }
  }
  .background(HubTheme.background)
 }

 // MARK: top bar

 var deckTopBar: some View {
  HStack(spacing:hub.compact ? 8 : 14) {
   Button { hubSelect(.home) } label: {
    HStack(spacing:5) {
     Text("The").foregroundStyle(HubTheme.text)
     Text("Helm").foregroundStyle(HubTheme.green)
    }
    .font(.system(size:17,weight:.bold,design:.rounded))
   }
   .buttonStyle(.plain).accessibilityLabel("The Helm Home")
   HStack(spacing:2) {
    ForEach(Self.deckPrimary) { section in deckTab(section) }
   }
   .padding(3)
   .overlay(RoundedRectangle(cornerRadius:11).stroke(HubTheme.line,lineWidth:1))
   deckHackButton
   deckMoreMenu
   Spacer(minLength:6)
   if c.tab == 0 && live.running {
    HStack(spacing:6) {
     Circle().fill(Noir.crimsonLight).frame(width:7,height:7)
     Text("LIVE").font(.system(size:10,weight:.bold,design:.monospaced)).tracking(1.2)
    }
    .foregroundStyle(HubTheme.text)
    .padding(.horizontal,10).padding(.vertical,6)
    .background(Capsule().fill(Noir.crimson.opacity(0.35)))
    .accessibilityLabel("Friday is live")
   }
   if hub.width >= 1180 {
    Text(GuardHub.isOffline ? "OFFLINE: ON" : "OFFLINE: OFF")
     .font(.system(size:11,weight:.medium,design:.monospaced))
     .foregroundStyle(GuardHub.isOffline ? HubTheme.amber : HubTheme.subtext)
     .padding(.horizontal,10).frame(height:28)
     .overlay(RoundedRectangle(cornerRadius:6).stroke(GuardHub.isOffline ? HubTheme.amber : HubTheme.line,lineWidth:1))
     .help("The Offline switch lives in Guard. When it is ON the app makes no network requests.")
    TimelineView(.periodic(from:.now,by:20)) { timeline in
     Text(deckClock(timeline.date))
      .font(.system(size:11,weight:.medium,design:.monospaced)).foregroundStyle(HubTheme.subtext)
      .padding(.horizontal,10).frame(height:28)
      .overlay(RoundedRectangle(cornerRadius:6).stroke(HubTheme.line,lineWidth:1))
    }
    .help("Moncton time")
   }
   deckIconButton("arrow.clockwise",label:"Refresh everything (Command-R)",spinning:hubAnyLoading) { Task { await hubRefreshAll() } }
    .keyboardShortcut("r",modifiers:.command).disabled(hubAnyLoading)
   deckIconButton("magnifyingglass",label:"Jump to a page (Command-K)") { hub.jumpQuery = ""; hub.jumpPresented = true }
    .keyboardShortcut("k",modifiers:.command)
   deckIconButton("slider.horizontal.3",label:"Settings (Command-comma)") { c.showPanel = true }
    .keyboardShortcut(",",modifiers:.command)
  }
  .padding(.horizontal,hub.compact ? 12 : 22).frame(height:56)
  .background(HubTheme.sidebar)
  .overlay(alignment:.bottom) { Rectangle().fill(HubTheme.line).frame(height:1) }
 }

 func deckClock(_ date: Date) -> String {
  let formatter = DateFormatter()
  formatter.dateFormat = "HH:mm"
  formatter.timeZone = TimeZone(identifier:"America/Moncton") ?? .current
  return formatter.string(from:date)
 }

 func deckIconButton(_ icon: String,label: String,spinning: Bool = false,action: @escaping () -> Void) -> some View {
  Button(action:action) {
   Group {
    if spinning { ProgressView().controlSize(.small) } else { Image(systemName:icon).font(.system(size:14,weight:.medium)) }
   }
   .foregroundStyle(HubTheme.subtext)
   .frame(width:36,height:36)
   .contentShape(Rectangle())
  }
  .buttonStyle(.plain).accessibilityLabel(label).help(label)
 }

 func deckTab(_ section: HubSection) -> some View {
  let selected = hub.section == section
  let index = (Self.deckPrimary.firstIndex(of:section) ?? 0) + 1
  return Button { hubSelect(section) } label: {
   Text(section.title).lineLimit(1).fixedSize()
    .font(.system(size:13,weight:selected ? .semibold : .medium))
    .foregroundStyle(selected ? HubTheme.text : HubTheme.subtext)
    .padding(.horizontal,hub.compact ? 8 : 12).frame(height:34)
    .background(selected ? HubTheme.card : Color.clear,in:RoundedRectangle(cornerRadius:8))
    .overlay(RoundedRectangle(cornerRadius:8).stroke(selected ? HubTheme.controlOutline : Color.clear,lineWidth:1))
    .contentShape(Rectangle())
  }
  .buttonStyle(.plain)
  .accessibilityLabel(section.title).accessibilityAddTraits(selected ? .isSelected : [])
  .keyboardShortcut(KeyEquivalent(Character(String(index))),modifiers:.command)
 }

 var deckHackButton: some View {
  let on = deckInHack
  return Button { hubSelect(.hacking) } label: {
   HStack(spacing:5) {
    Image(systemName:"circle.hexagongrid.fill").font(.system(size:12,weight:.semibold))
    Text(hub.width >= 820 ? "Command Core" : "Core").font(.system(size:12.5,weight:.medium,design:.rounded))
   }
   .foregroundStyle(on ? HubTheme.background : HubTheme.green)
   .padding(.horizontal,10).frame(height:34)
   .background(on ? HubTheme.green : HubTheme.green.opacity(0.10),in:RoundedRectangle(cornerRadius:8))
   .overlay(RoundedRectangle(cornerRadius:8).stroke(HubTheme.green.opacity(0.55),lineWidth:1))
   .contentShape(Rectangle())
  }
  .buttonStyle(.plain)
  .keyboardShortcut("6",modifiers:.command)
  .accessibilityLabel("Command Core").accessibilityAddTraits(on ? .isSelected : [])
  .help("Your Mac, network and crew: Overview, Systems, Guard, Cyber Lab, Verification, Crew station")
 }

 var deckMoreMenu: some View {
  Menu {
   ForEach(Self.deckMore) { section in
    Button { hubSelect(section) } label: { Label("\(section.title)  ·  \(deckMoreBlurb(section))",systemImage:section.icon) }
   }
   Divider()
   Button { hub.simple = true; hubSelect(.home) } label: { Label("Simple mode: fewer buttons, plain words",systemImage:"switch.2") }
  } label: {
   HStack(spacing:4) {
    Text("More").font(.system(size:13,weight:deckInMore ? .semibold : .medium))
    Image(systemName:"chevron.down").font(.system(size:9,weight:.bold))
   }
   .foregroundStyle(deckInMore ? HubTheme.text : HubTheme.subtext)
   .padding(.horizontal,12).frame(height:32)
   .background(deckInMore ? HubTheme.card : Color.clear,in:RoundedRectangle(cornerRadius:8))
   .overlay(RoundedRectangle(cornerRadius:8).stroke(deckInMore ? HubTheme.controlOutline : HubTheme.line,lineWidth:1))
  }
  .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
  .accessibilityLabel("More pages")
 }

 func deckMoreBlurb(_ section: HubSection) -> String {
  switch section {
  case .launchpad: return "start apps + games"
  case .game: return "the game you're playing"
  case .accounts: return "login status, no secrets"
  case .meeting: return "crew room + board"
  case .stream: return "stream setup"
  case .helper: return "how-to + help"
  case .council: return "decision council"
  default: return ""
  }
 }

 var deckPageHeader: some View {
  HStack(alignment:.firstTextBaseline,spacing:10) {
   Text(hub.simple ? simpleName(hub.section) : hub.section.title).font(.system(size:26,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
   Text(hub.simple ? simpleBlurb(hub.section) : hub.section.blurb).font(.system(size:12.5)).foregroundStyle(HubTheme.subtext).lineLimit(1)
   if hub.section == .stocks {
    Text("PAPER TRADING · NO REAL MONEY").font(DeckMono.font(10.5,.bold)).foregroundStyle(HubTheme.amber)
     .padding(.horizontal,8).padding(.vertical,3).background(HubTheme.amber.opacity(0.14),in:RoundedRectangle(cornerRadius:4))
   }
   Spacer(minLength:0)
   if let at = hub.refreshedAt { Text("updated \(hubAgo(at))").font(.system(size:11,design:.monospaced)).foregroundStyle(HubTheme.subtext) }
  }
  .padding(.horizontal,hub.compact ? 16 : 32).padding(.top,16).padding(.bottom,8)
 }

 // Command Core's own tabs: flat text tabs, the active one underlined in crimson (Matthew's reference).
 var deckHackNav: some View {
  HStack(spacing:6) {
   Circle().fill(HubTheme.green).frame(width:7,height:7).accessibilityHidden(true)
   if hub.width >= 980 { Text("Command Core").font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(HubTheme.text).lineLimit(1).fixedSize() }
   Spacer(minLength:8)
   ScrollView(.horizontal,showsIndicators:false) {
   HStack(spacing:hub.width >= 980 ? 6 : 2) {
   ForEach(Self.deckHack) { section in
    let on = hub.section == section
    Button { hubSelect(section) } label: {
     VStack(spacing:6) {
      Text(deckHackLabel(section)).font(.system(size:13.5,weight:on ? .semibold : .regular,design:.rounded)).lineLimit(1).fixedSize()
       .foregroundStyle(on ? Color.white : HubTheme.subtext)
      Rectangle().fill(on ? CoreStyle.crimson : Color.clear).frame(height:2)
     }
     .padding(.horizontal,10).padding(.top,6)
     .contentShape(Rectangle())
    }
    .buttonStyle(.plain).accessibilityLabel(section.title).accessibilityAddTraits(on ? .isSelected : [])
   }
   }
   }
   .fixedSize(horizontal:hub.width >= 980,vertical:false)
  }
  .padding(.horizontal,hub.compact ? 12 : 24).padding(.top,4)
  .background(CoreStyle.bg.opacity(0.9))
  .overlay(alignment:.bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height:1) }
 }

 func deckHackLabel(_ section: HubSection) -> String {
  switch section {
  case .hacking: return "Overview"
  case .systems: return "Systems"
  case .shield: return "Guard"
  case .lab: return "Cyber Lab"
  case .realFake: return "Verification"
  case .crewStation: return "Crew Station"
  case .memory: return "Memory"
  default: return section.title.uppercased()
  }
 }

 // MARK: Friday dock

 var deckDock: some View {
  VStack(alignment:.leading,spacing:14) {
   Text("FRIDAY").font(.system(size:11,weight:.medium,design:.monospaced)).tracking(1.4).foregroundStyle(HubTheme.subtext)
   TimelineView(.animation(minimumInterval:1.0/30.0,paused:reduceMotion)) { timeline in
    let now = timeline.date
    let state = orbState(at:now)
    VStack(spacing:4) {
     FridayOrb(state:state,t:now.timeIntervalSinceReferenceDate,level:orbLevel(at:now),size:92,animated:!reduceMotion,showsPicker:false)
      .frame(maxWidth:.infinity)
     Text(deckStateWords(state)).font(.system(size:12,design:.rounded)).foregroundStyle(HubTheme.subtext)
    }
   }
   Button { mainAction() } label: {
    HStack(spacing:8) {
     Image(systemName:mainIcon).font(.system(size:13,weight:.bold))
     Text(c.tab == 0 ? (live.running ? "Stop Friday" : "Talk to Friday") : (c.listening ? "Stop listening" : "Talk to Friday")).font(.system(size:14,weight:.semibold))
    }
    .foregroundStyle(HubTheme.background)
    .frame(maxWidth:.infinity,minHeight:40)
    .background(live.running || c.listening ? HubTheme.amber : HubTheme.green,in:RoundedRectangle(cornerRadius:8))
   }
   .buttonStyle(.plain).disabled(DesignPreview.enabled)
   .accessibilityLabel(live.running ? "Stop Friday" : "Talk to Friday")
   .help(c.tab == 0 ? (live.running ? "Stop the live session" : "Start the live session: shares your mic and screen with Google while it runs") : "Talk")
   if hub.section == .stocks {
    // Stock bot page: Friday's column carries the fleet ranking and the research notes (Roxy's concept).
    ScrollView { StockSideCards(stocks:stocks) }.scrollIndicators(.hidden)
   } else {
   deckDockSection("DOING NOW") {
    ForEach(Array(deckDoingLines.enumerated()),id:\.offset) { _,line in
     Text(line).font(.system(size:12.5)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
    }
   }
   deckDockSection("MUSIC") {
    if live.spotifyInstalled {
     Text("Ask Friday to play, pause, skip or say what's playing.").font(.system(size:12.5)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
     Button { if let url = URL(string:"spotify:") { NSWorkspace.shared.open(url) } } label: {
      Label("Open Spotify",systemImage:"music.note").font(.system(size:11.5,weight:.medium)).foregroundStyle(HubTheme.green)
     }.buttonStyle(.plain)
    } else {
     Text("Spotify isn't installed on this Mac.").font(.system(size:12.5)).foregroundStyle(HubTheme.subtext)
    }
   }
   }
   Spacer(minLength:0)
   HStack(spacing:8) {
    Image(systemName:"sparkles").foregroundStyle(Noir.crimsonLight).accessibilityHidden(true)
    TextField("Ask Friday…",text:$hub.query).textFieldStyle(.plain).font(.system(size:13)).onSubmit { hubAskFromBar() }
   }
   .padding(.horizontal,12).frame(height:36)
   .background(HubTheme.control,in:RoundedRectangle(cornerRadius:8))
   .overlay(RoundedRectangle(cornerRadius:8).stroke(HubTheme.controlOutline,lineWidth:1))
  }
  .padding(16)
  .frame(width:264)
  .frame(maxHeight:.infinity,alignment:.top)
  .background(HubTheme.sidebar)
  .overlay(alignment:.leading) { Rectangle().fill(HubTheme.line).frame(width:1) }
 }

 func deckDockSection<Content: View>(_ title: String,@ViewBuilder content: () -> Content) -> some View {
  VStack(alignment:.leading,spacing:6) {
   Text(title).font(.system(size:11,weight:.medium,design:.monospaced)).tracking(1.4).foregroundStyle(HubTheme.subtext)
   content()
  }
  .frame(maxWidth:.infinity,alignment:.leading)
 }

 func deckStateWords(_ state: OrbState) -> String {
  switch state {
  case .off: return "Asleep · live buddy is off"
  case .idle: return c.tab == 0 ? "Awake · breathing" : "Ready"
  case .listening: return "Listening to you"
  case .thinking: return "Thinking"
  case .speaking: return "Speaking"
  }
 }

 // What she is really doing, from the live session's own status. Nothing is invented: when she is asleep it says so.
 var deckDoingLines: [String] {
  var lines: [String] = []
  let status = c.tab == 0 ? live.status : c.status
  if c.tab == 0 && !live.running {
   lines.append(hub.simple ? "Resting. Type above, or open Voice to talk." : "Asleep. Tap Talk to Friday to wake her.")
  } else if !status.isEmpty { lines.append(status) }
  if hands.enabled && hands.hasAccess && !hands.status.isEmpty { lines.append("Hands: \(hands.status)") }
  if !clips.status.isEmpty { lines.append(clips.status) }
  if c.tab == 0 && live.running && !live.toolNames.isEmpty { lines.append("Tools on: \(live.toolNames.count)") }
  return Array(lines.prefix(4))
 }
}
