import SwiftUI
import AppKit

// The hub: a slim icon rail, a card dashboard, and a page per venture. Friday is one page of it and stays live while you browse.
// Everything here is read-only. Nothing in the hub sends, posts, spends or trades.

enum HubColor {
 static let green = Color(red:0.30,green:0.85,blue:0.55)
 static let amber = Color(red:1.0,green:0.70,blue:0.22)
 static let violet = Color(red:0.58,green:0.42,blue:0.98)
 static let sky = Color(red:0.22,green:0.70,blue:0.96)
 static let slate = Color(red:0.62,green:0.67,blue:0.80)
 static let coral = Color(red:1.0,green:0.50,blue:0.40)
 static let indigo = Color(red:0.40,green:0.46,blue:1.0)
}

enum HubSection: Int, CaseIterable, Identifiable {
 case home, friday, stocks, store, ecs, systems, launchpad, game, accounts
 var id: Int { rawValue }
 var title: String {
  switch self {
  case .home: return "Home"
  case .friday: return "Friday"
  case .stocks: return "Stock bot"
  case .store: return "Store"
  case .ecs: return "ECS"
  case .systems: return "Systems"
  case .launchpad: return "Launchpad"
  case .game: return "Game"
  case .accounts: return "Accounts"
  }
 }
 var icon: String {
  switch self {
  case .home: return "house.fill"
  case .friday: return "waveform"
  case .stocks: return "chart.line.uptrend.xyaxis"
  case .store: return "bag.fill"
  case .ecs: return "megaphone.fill"
  case .systems: return "gearshape.2.fill"
  case .launchpad: return "square.grid.2x2.fill"
  case .game: return "gamecontroller.fill"
  case .accounts: return "key.fill"
  }
 }
 var tint: Color {
  switch self {
  case .home: return Noir.crimson
  case .friday: return Noir.crimson
  case .stocks: return HubColor.green
  case .store: return HubColor.amber
  case .ecs: return HubColor.violet
  case .systems: return HubColor.coral
  case .launchpad: return HubColor.indigo
  case .game: return HubColor.sky
  case .accounts: return HubColor.slate
  }
 }
 var blurb: String {
  switch self {
  case .home: return "Here's everything at a glance."
  case .friday: return "Talk, show her your game, ask anything."
  case .stocks: return "Practice money only. Reads a public snapshot."
  case .store: return "Who visits findhotstuff.com, and from where."
  case .ecs: return "Your daily feed, the proof that it runs."
  case .systems: return "Your automations, at a glance."
  case .launchpad: return "Every dashboard you use, one click away."
  case .game: return "Window, key and live status."
  case .accounts: return "What's connected, and what's not."
  }
 }
}

@MainActor final class HubModel: ObservableObject {
 @Published var section: HubSection = .home
 @Published var query = ""
 // Which card or button the pointer is over, so it can lift a little. Empty means none.
 @Published var hovered = ""
 // Which account row on the Accounts page is open, showing its connect form. Empty means none.
 @Published var expanded = ""
}

// Store visits, the ECS feed and the automations' status. All public, all read-only (see VentureData.swift).
@MainActor final class VentureHub: ObservableObject {
 @Published var store: StoreStats?
 @Published var feed: FeedStats?
 @Published var runs: [AutomationRun]?
 @Published var loading = false
 @Published var failed = false
 var lastRefresh = Date.distantPast
 var attention: [AutomationRun] { (runs ?? []).filter { $0.isFailing } }

 // Counters are day-precision, so the background refresh waits at least nine minutes. Refresh buttons force it.
 func refresh(force: Bool = false) async {
  guard !loading else { return }
  if !force && Date().timeIntervalSince(lastRefresh) < 540 { return }
  loading = true
  defer { loading = false }
  async let storeResult = VentureData.fetchStore()
  async let feedResult = VentureData.fetchFeed()
  async let runsResult = VentureData.fetchAutomations()
  let (a,b,c) = await (storeResult,feedResult,runsResult)
  if let a = a { store = a }
  if let b = b { feed = b }
  if let c = c { runs = c }
  failed = (store == nil && feed == nil && runs == nil)
  lastRefresh = Date()
 }
}

@MainActor final class StockHub: ObservableObject {
 @Published var dip: StockRobot?
 @Published var momentum: StockRobot?
 @Published var loading = false
 @Published var failed = false
 @Published var robot = 0
 var current: StockRobot? { robot == 0 ? dip : momentum }

 func refresh() async {
  guard !loading else { return }
  loading = true
  defer { loading = false }
  async let first = StockData.fetch(branch:"stock-live",name:"Dip robot")
  async let second = StockData.fetch(branch:"stock-live-momentum",name:"Momentum robot")
  let (a,b) = await (first,second)
  if let a = a { dip = a }
  if let b = b { momentum = b }
  failed = (a == nil && b == nil && dip == nil && momentum == nil)
 }
}

struct HubLink: Identifiable {
 var id: String { title }
 var title: String
 var note: String
 var icon: String
 var tint: Color
 var url: String
}

// The Claude chats that hold each venture's work. The app can only open them: chats cannot see each other.
struct HubAgent: Identifiable {
 var id: String { name }
 var name: String
 var job: String
 var chat: String
 var icon: String
 var tint: Color
 var url: String
}

enum HubLaunch {
 static let agents: [HubAgent] = [
  HubAgent(name:"Stock agent",job:"Where the stock work happens: the practice robots, research and tuning. Real money stays on your three switches.",chat:"Stock buyer AI",icon:"chart.line.uptrend.xyaxis",tint:HubColor.green,url:"https://claude.ai/code/session_01MxbaVsvi7dG9udLX6P3Sjz"),
  HubAgent(name:"Website agent",job:"Page checks, traffic and the daily automations.",chat:"Health and traffic check",icon:"globe",tint:HubColor.amber,url:"https://claude.ai/code/session_01Uex1MVpnEmy66XPQn1iW6t"),
  HubAgent(name:"Build agent",job:"This app and Friday.",chat:"new beginning",icon:"hammer.fill",tint:Noir.crimson,url:"https://claude.ai/code/session_016WBRFe1MJn1UQSZgzashZd")
 ]

 static let groups: [(name: String,links: [HubLink])] = [
  ("Domains and site",[
   HubLink(title:"Porkbun",note:"Your domains. eastcoastsocial.ca forwards from here.",icon:"globe",tint:HubColor.sky,url:"https://porkbun.com/account/domainsSpeedy"),
   HubLink(title:"Cloudflare",note:"The checkout worker and alerts.",icon:"cloud.fill",tint:HubColor.amber,url:"https://dash.cloudflare.com/"),
   HubLink(title:"GitHub repo",note:"The code. The site deploys from master.",icon:"chevron.left.forwardslash.chevron.right",tint:HubColor.slate,url:"https://github.com/matthewferreira818/hotstuff"),
   HubLink(title:"Your store",note:"findhotstuff.com",icon:"bag.fill",tint:HubColor.amber,url:"https://findhotstuff.com"),
   HubLink(title:"ECS page",note:"findhotstuff.com/automation",icon:"megaphone.fill",tint:HubColor.violet,url:"https://findhotstuff.com/automation/")
  ]),
  ("Money",[
   HubLink(title:"Stripe",note:"Store payments.",icon:"creditcard.fill",tint:HubColor.violet,url:"https://dashboard.stripe.com/"),
   HubLink(title:"CJ Dropshipping",note:"The supplier.",icon:"shippingbox.fill",tint:HubColor.coral,url:"https://www.cjdropshipping.com/"),
   HubLink(title:"Moomoo",note:"Real money. Opens in your browser only.",icon:"lock.shield.fill",tint:HubColor.green,url:"https://www.moomoo.com/ca"),
   HubLink(title:"Stock bot live page",note:"The public practice dashboard.",icon:"chart.line.uptrend.xyaxis",tint:HubColor.green,url:"https://findhotstuff.com/stock_bot/live/")
  ]),
  ("Traffic and streaming",[
   HubLink(title:"GoatCounter",note:"Visitor counts.",icon:"chart.bar.fill",tint:HubColor.amber,url:"https://theycallmemattyb.goatcounter.com/"),
   HubLink(title:"Twitch dashboard",note:"Stream manager and clips.",icon:"play.rectangle.fill",tint:HubColor.violet,url:"https://dashboard.twitch.tv/"),
   HubLink(title:"Your channel",note:"twitch.tv/theycallmemattyb",icon:"tv",tint:HubColor.violet,url:"https://www.twitch.tv/theycallmemattyb")
  ]),
  ("Social",[
   HubLink(title:"X",note:"Posts.",icon:"message.fill",tint:HubColor.slate,url:"https://x.com/"),
   HubLink(title:"TikTok",note:"Drafts land in your inbox.",icon:"play.rectangle.fill",tint:Noir.crimsonLight,url:"https://www.tiktok.com/"),
   HubLink(title:"Facebook",note:"Posts and groups.",icon:"person.2.fill",tint:HubColor.sky,url:"https://www.facebook.com/"),
   HubLink(title:"Pinterest",note:"Product and ECS pins.",icon:"pin.fill",tint:Noir.crimson,url:"https://www.pinterest.com/"),
   HubLink(title:"Google Business",note:"Your business profile.",icon:"mappin.and.ellipse",tint:HubColor.green,url:"https://business.google.com/")
  ])
 ]
}

struct PillButtonStyle: ButtonStyle {
 var tint: Color = Noir.crimson
 func makeBody(configuration: Configuration) -> some View {
  configuration.label
   .font(.system(size:14,weight:.semibold,design:.rounded))
   .foregroundStyle(Color.white)
   .padding(.horizontal,18)
   .padding(.vertical,11)
   .background(Capsule().fill(tint))
   .opacity(configuration.isPressed ? 0.85 : 1)
   .scaleEffect(configuration.isPressed ? 0.96 : 1)
   .animation(.spring(response:0.28,dampingFraction:0.62),value:configuration.isPressed)
 }
}

extension View {
 // Frosted glass: the background gradient shows through, softened.
 func hubCard(radius: CGFloat = 22) -> some View {
  self.background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:radius,style:.continuous))
   .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).stroke(Color.white.opacity(0.10),lineWidth:1))
 }

 // Lifts a little under the pointer, with a soft shadow and a springy settle, the way Apple's controls do.
 @MainActor func hubHover(_ id: String,_ hub: HubModel,lift: CGFloat = 1.025) -> some View {
  let over = hub.hovered == id
  return self
   .scaleEffect(over ? lift : 1)
   .shadow(color:Color.black.opacity(over ? 0.35 : 0),radius:over ? 18 : 0,x:0,y:over ? 8 : 0)
   .animation(.spring(response:0.32,dampingFraction:0.72),value:hub.hovered)
   .onHover { inside in
    if inside { hub.hovered = id } else if hub.hovered == id { hub.hovered = "" }
   }
 }
}

extension CompanionInterfaceView {

 // MARK: shell

 var hubShell: some View {
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
 }

 var hubRail: some View {
  VStack(spacing:14) {
   Circle()
    .fill(RadialGradient(colors:[Noir.crimsonLight,Noir.crimson,Noir.crimsonDeep],center:UnitPoint(x:0.35,y:0.3),startRadius:1,endRadius:24))
    .frame(width:34,height:34)
    .padding(.bottom,8)
   ScrollView(showsIndicators:false) {
    VStack(spacing:10) {
     ForEach(HubSection.allCases) { section in hubRailButton(section) }
    }
    .padding(.vertical,2)
   }
   Spacer(minLength:0)
   Button { c.showPanel = true } label: {
    VStack(spacing:5) {
     Image(systemName:"slider.horizontal.3").font(.system(size:17,weight:.semibold)).foregroundStyle(Color.white.opacity(0.7)).frame(width:48,height:40)
     Text("Settings").font(.system(size:10,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
    }
   }
   .buttonStyle(.plain)
   .keyboardShortcut(",",modifiers:.command)
   .hubHover("rail-settings",hub,lift:1.06)
  }
  .padding(.top,46).padding(.bottom,22)
  .frame(width:88)
  .background(.ultraThinMaterial)
  .overlay(alignment:.trailing) { Rectangle().fill(Color.white.opacity(0.08)).frame(width:1) }
 }

 func hubRailButton(_ section: HubSection) -> some View {
  let selected = hub.section == section
  return Button { hubSelect(section) } label: {
   VStack(spacing:5) {
    ZStack {
     RoundedRectangle(cornerRadius:15,style:.continuous).fill(Color.white.opacity(0.06)).frame(width:48,height:48)
     if selected {
      RoundedRectangle(cornerRadius:15,style:.continuous)
       .fill(LinearGradient(colors:[Noir.crimsonLight,Noir.crimson],startPoint:.topLeading,endPoint:.bottomTrailing))
       .frame(width:48,height:48)
       .matchedGeometryEffect(id:"railSelection",in:railNamespace)
     }
     Image(systemName:section.icon).font(.system(size:19,weight:.semibold)).foregroundStyle(Color.white.opacity(selected ? 1 : 0.7))
    }
    Text(section.title).font(.system(size:10,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(selected ? 0.95 : 0.5))
   }
  }
  .buttonStyle(.plain)
  .keyboardShortcut(KeyEquivalent(Character("\(section.rawValue + 1)")),modifiers:.command)
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
    Text(hub.section == .home ? hubGreeting : hub.section.title).font(.system(size:26,weight:.bold,design:.rounded)).foregroundStyle(Color.white)
    Text(hub.section.blurb).font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.55))
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
   HStack(spacing:8) {
    Image(systemName:"sparkles").foregroundStyle(Noir.crimsonLight)
    TextField("Ask Friday…",text:$hub.query).textFieldStyle(.plain).onSubmit { hubAskFromBar() }
   }
   .padding(.horizontal,16).padding(.vertical,11)
   .frame(width:300)
   .background(.ultraThinMaterial,in:Capsule())
   .overlay(Capsule().stroke(Color.white.opacity(0.12),lineWidth:1))
   Text("M").font(.system(size:14,weight:.bold,design:.rounded)).foregroundStyle(Color.white)
    .frame(width:36,height:36)
    .background(Circle().fill(LinearGradient(colors:[Noir.crimsonLight,Noir.crimsonDeep],startPoint:.topLeading,endPoint:.bottomTrailing)))
  }
  .padding(.horizontal,32).padding(.top,26).padding(.bottom,12)
 }

 @ViewBuilder var hubContent: some View {
  switch hub.section {
  case .home: hubHome
  case .friday:
   GeometryReader { geo in
    HStack {
     Spacer(minLength:0)
     fridayStage(orb:min(max(geo.size.height * 0.30,170),300)).frame(width:min(max(geo.size.width * 0.55,520),760))
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
  }
 }

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
   Spacer()
   TimelineView(.animation(minimumInterval:1.0/30.0)) { timeline in
    FridayOrb(state:orbState(at:timeline.date),t:timeline.date.timeIntervalSinceReferenceDate,level:orbLevel(at:timeline.date),size:130,animated:!reduceMotion)
   }
   .frame(width:230,height:190)
  }
  .padding(26)
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
  return "\(s.week) visitors this week · \(s.today) today"
 }
 var hubEcsHeadline: String {
  guard let f = ventures.feed else { return "Loading…" }
  if let days = f.streakDays() { return "\(days)-day feed streak" }
  return "\(f.total) posts since \(f.since)"
 }
 var hubSystemsHeadline: String {
  guard let runs = ventures.runs else { return "Loading…" }
  let bad = ventures.attention
  if bad.isEmpty { return "All \(runs.count) automations OK" }
  return "\(bad.count) need attention · \(bad[0].name)"
 }

 // Shows on Home only when an automation's latest run failed.
 @ViewBuilder var hubAttentionBanner: some View {
  let bad = ventures.attention
  if !bad.isEmpty {
   Button { hubSelect(.systems) } label: {
    HStack(spacing:12) {
     Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(HubColor.amber)
     Text("\(bad.count == 1 ? "1 automation needs" : "\(bad.count) automations need") attention: \(bad.map { $0.name }.joined(separator:", "))")
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
  return c.sharing ? "Window chosen · ready" : "No window chosen yet"
 }
 var hubAccountsHeadline: String {
  let connected = [live.hasKey,clips.signedIn].filter { $0 }.count
  return "\(connected) of 2 logins connected"
 }

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
     .pickerStyle(.segmented).labelsHidden().frame(width:300)
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
    if let s = ventures.store {
     LazyVGrid(columns:[GridItem(.adaptive(minimum:200),spacing:14)],spacing:14) {
      hubStat("Today",String(s.today),"unique visitors so far",tint:Color.white)
      hubStat("Last 7 days",String(s.week),"unique visitors",tint:Color.white)
      hubStat("Last 30 days",String(s.month),"unique visitors",tint:Color.white)
     }
     hubChannels(s)
     Text("Counts come from your site's public visitor counters, by day. Orders and revenue need a Stripe login, which isn't connected. Order alerts keep reaching your phone the way they do now.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
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
     Text(channel.label).font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.85)).frame(width:210,alignment:.leading)
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
      if ventures.attention.isEmpty { hubPill("ALL \(runs.count) AUTOMATIONS OK",tint:HubColor.green) }
      else { hubPill("\(ventures.attention.count) NEED ATTENTION",tint:Noir.crimsonLight) }
     }
     Spacer()
     hubRefreshButton()
    }
    if let runs = ventures.runs {
     ForEach(runs) { run in hubRunRow(run) }
     Text("Read from GitHub's public status of your repo. Each line is that automation's latest run. Nothing here can start, stop or change an automation.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
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
      LazyVGrid(columns:[GridItem(.adaptive(minimum:190),spacing:14)],spacing:14) {
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
     Text(link.title).font(.system(size:14,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
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
  if let runs = ventures.runs {
   let bad = ventures.attention
   lines.append(bad.isEmpty ? "Automations: all \(runs.count) look fine." : "Automations needing attention: \(bad.map { $0.name }.joined(separator:", ")).")
  }
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

 // MARK: game, accounts, coming soon

 var hubGame: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:18) {
    LazyVGrid(columns:[GridItem(.adaptive(minimum:200),spacing:14)],spacing:14) {
     hubStat("Game window",c.sharing ? "Shared" : "None chosen",c.sharing ? "Friday can see it" : "Choose one to start",tint:c.sharing ? HubColor.green : Color.white)
     hubStat("Friday",live.running ? "Live" : "Asleep",live.running ? "Window and mic are shared with Google" : "Nothing is being sent",tint:live.running ? Noir.crimsonLight : Color.white)
     hubStat("Google key",live.hasKey ? "Saved" : "Missing",live.hasKey ? "In your Mac's Keychain" : "Add it in Settings",tint:live.hasKey ? HubColor.green : Noir.crimsonLight)
    }
    HStack(spacing:12) {
     Button { hubSelect(.friday) } label: { Label("Open Friday",systemImage:"waveform") }.buttonStyle(PillButtonStyle())
     Button { c.choose() } label: { Label("Choose window",systemImage:"rectangle.on.rectangle") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
     Button { c.showPanel = true } label: { Label("Settings",systemImage:"slider.horizontal.3") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    }
    if c.tab == 0, let seen = live.lastSeen {
     VStack(alignment:.leading,spacing:10) {
      Text("What Friday saw last").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
      Image(nsImage:seen).resizable().scaledToFit().frame(height:150).clipShape(RoundedRectangle(cornerRadius:12,style:.continuous))
      Text("\(live.picturesSent) pictures sent this session. The preview stays in memory only.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.45))
     }
     .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
    }
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 var hubAccounts: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:12) {
    Text("Logins live in your Mac's Keychain. You paste them into the app yourself, never into chat.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.55)).padding(.bottom,4)
    hubAccountRow("google","waveform",Noir.crimson,"Google Gemini","Friday's voice and eyes.",live.hasKey ? "Connected" : "Not connected",live.hasKey ? HubColor.green : Noir.crimsonLight,live.hasKey ? "Manage" : "Connect") { hubGoogleForm }
    hubAccountRow("twitch","scissors",HubColor.violet,"Twitch clips","A separate clip account makes clips when you ask.",clips.signedIn ? "Connected" : "Not connected",clips.signedIn ? HubColor.green : Noir.crimsonLight,clips.signedIn ? "Manage" : "Connect") { clipSettings }
    hubAccountRow("stocks","chart.line.uptrend.xyaxis",HubColor.green,"Stock bot snapshot","Reads the public practice snapshot. No login needed.","Read-only",HubColor.green,nil) { EmptyView() }
    hubAccountRow("moomoo","lock.shield.fill",HubColor.slate,"Moomoo (real money)","Not connected here, on purpose. Real money only runs on your Mac with your three switches.","Walled off",HubColor.slate,nil) { EmptyView() }
    hubAccountRow("counters","chart.bar.fill",HubColor.amber,"GoatCounter (store visits)","Reads your site's public visitor counters. No login needed.","Read-only",HubColor.green,nil) { EmptyView() }
    hubAccountRow("feed","megaphone.fill",HubColor.violet,"Your ECS feed","Reads the feed files findhotstuff.com already publishes. No login needed.","Read-only",HubColor.green,nil) { EmptyView() }
    hubAccountRow("github","gearshape.2.fill",HubColor.coral,"GitHub (automation status)","Reads the public status of your automations. No login needed.","Read-only",HubColor.green,nil) { EmptyView() }
    hubAccountRow("stripe","bag.fill",HubColor.amber,"Stripe (sales)","Not connected. Sales would need a read-only Stripe key that you paste yourself.","Coming next",HubColor.amber,nil) { EmptyView() }
    hubAccountRow("socials","person.2.fill",HubColor.violet,"X, TikTok, Facebook","Not connected. She would prepare posts and you click Post. TikTok and Meta also need their own app reviews first.","Coming later",HubColor.slate,nil) { EmptyView() }
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 // Connect forms open right inside the row, so there is nothing to hunt for.
 func hubAccountRow<Form: View>(_ key: String,_ icon: String,_ tint: Color,_ name: String,_ detail: String,_ status: String,_ statusTint: Color,_ button: String?,@ViewBuilder form: () -> Form) -> some View {
  let open = hub.expanded == key
  let formView = form()
  return VStack(alignment:.leading,spacing:14) {
   HStack(spacing:16) {
    ZStack {
     RoundedRectangle(cornerRadius:14,style:.continuous).fill(LinearGradient(colors:[tint,tint.opacity(0.55)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:46,height:46)
     Image(systemName:icon).font(.system(size:19,weight:.semibold)).foregroundStyle(Color.white)
    }
    VStack(alignment:.leading,spacing:3) {
     Text(name).font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
     Text(detail).font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.55)).lineLimit(2)
    }
    Spacer()
    hubPill(status.uppercased(),tint:statusTint)
    if let button = button {
     Button(open ? "Done" : button) { withAnimation(.spring(response:0.45,dampingFraction:0.86)) { hub.expanded = open ? "" : key } }
      .buttonStyle(PillButtonStyle(tint:open ? Color.white.opacity(0.12) : Noir.crimson))
    }
   }
   if open {
    Divider().overlay(Color.white.opacity(0.10))
    formView
   }
  }
  .padding(16)
  .hubCard()
 }

 // The Google key: get one free (no card needed), paste it, and it goes into the Keychain.
 @ViewBuilder var hubGoogleForm: some View {
  if live.hasKey {
   HStack {
    Label("Key saved in your Mac's Keychain",systemImage:"checkmark.seal.fill").font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(HubColor.green)
    Spacer()
    Button("Remove key") { live.forgetKey() }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   }
  } else {
   Text("1. Click Get a free key and sign in with Google. No card needed.\n2. Create an API key and copy it.\n3. Paste it below and press Save key. Never paste it into a chat.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.65))
   HStack(spacing:10) {
    Button("Get a free key") { NSWorkspace.shared.open(URL(string:"https://aistudio.google.com/apikey")!) }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    SecureField("Paste your key here",text:$live.keyInput).noirField()
    Button("Save key") { live.saveKey() }.buttonStyle(PillButtonStyle())
   }
  }
 }

 func hubSoon(_ section: HubSection,_ title: String,_ blurb: String,_ bullets: [String]) -> some View {
  VStack(spacing:18) {
   Spacer(minLength:0)
   ZStack {
    RoundedRectangle(cornerRadius:26,style:.continuous).fill(LinearGradient(colors:[section.tint,section.tint.opacity(0.5)],startPoint:.topLeading,endPoint:.bottomTrailing)).frame(width:84,height:84)
    Image(systemName:section.icon).font(.system(size:34,weight:.semibold)).foregroundStyle(Color.white)
   }
   Text(title).font(.system(size:24,weight:.bold,design:.rounded)).foregroundStyle(Color.white)
   Text(blurb).font(.system(size:14,design:.rounded)).foregroundStyle(Color.white.opacity(0.65)).multilineTextAlignment(.center)
   hubPill("COMING NEXT",tint:section.tint)
   VStack(alignment:.leading,spacing:8) {
    ForEach(Array(bullets.enumerated()),id:\.offset) { _,line in
     HStack(alignment:.top,spacing:8) {
      Image(systemName:"circle.fill").font(.system(size:5)).foregroundStyle(section.tint).padding(.top,6)
      Text(line).font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.7))
     }
    }
   }
   .padding(20).frame(width:440,alignment:.leading).hubCard()
   Spacer(minLength:0)
  }
  .frame(maxWidth:.infinity)
 }

 // MARK: helpers

 func hubPill(_ text: String,tint: Color) -> some View {
  Text(text).font(.system(size:10,weight:.bold,design:.rounded)).tracking(1)
   .foregroundStyle(tint)
   .padding(.horizontal,11).padding(.vertical,6)
   .background(Capsule().fill(tint.opacity(0.16)))
 }

 func hubMoney(_ value: Double) -> String { value.formatted(.currency(code:"USD")) }
 func hubSigned(_ value: Double) -> String { (value >= 0 ? "+" : "−") + hubMoney(abs(value)) }
 func hubAgo(_ date: Date?) -> String {
  guard let date = date else { return "a while ago" }
  return RelativeDateTimeFormatter().localizedString(for:date,relativeTo:Date())
 }

 // The top bar's "Ask Friday" box: goes to Friday and types the question for her.
 func hubAskFromBar() {
  let text = hub.query.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !text.isEmpty else { return }
  hub.query = ""
  hubSelect(.friday)
  c.showKeyboard = true
  if c.tab == 0 {
   live.typed = text
   if live.running { live.sendTyped() } else { live.status = "Press the big button to wake Friday, then press Send." }
  } else {
   c.input = text
   c.ask(text)
  }
 }
}
