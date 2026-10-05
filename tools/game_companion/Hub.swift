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
}

enum HubSection: Int, CaseIterable, Identifiable {
 case home, friday, stocks, store, ecs, game, accounts
 var id: Int { rawValue }
 var title: String {
  switch self {
  case .home: return "Home"
  case .friday: return "Friday"
  case .stocks: return "Stock bot"
  case .store: return "Store"
  case .ecs: return "ECS"
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
  case .game: return HubColor.sky
  case .accounts: return HubColor.slate
  }
 }
 var blurb: String {
  switch self {
  case .home: return "Here's everything at a glance."
  case .friday: return "Talk, show her your game, ask anything."
  case .stocks: return "Practice money only. Reads a public snapshot."
  case .store: return "Visits and sales."
  case .ecs: return "East Coast Social."
  case .game: return "Window, key and live status."
  case .accounts: return "What's connected, and what's not."
  }
 }
}

@MainActor final class HubModel: ObservableObject {
 @Published var section: HubSection = .home
 @Published var query = ""
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
   .scaleEffect(configuration.isPressed ? 0.97 : 1)
 }
}

extension View {
 func hubCard(radius: CGFloat = 22) -> some View {
  self.background(RoundedRectangle(cornerRadius:radius,style:.continuous).fill(Color.white.opacity(0.05)))
   .overlay(RoundedRectangle(cornerRadius:radius,style:.continuous).stroke(Color.white.opacity(0.08),lineWidth:1))
 }
}

extension CompanionInterfaceView {

 // MARK: shell

 var hubShell: some View {
  HStack(spacing:0) {
   hubRail
   VStack(spacing:0) {
    hubTopBar
    hubContent.frame(maxWidth:.infinity,maxHeight:.infinity)
   }
  }
 }

 var hubRail: some View {
  VStack(spacing:14) {
   Circle()
    .fill(RadialGradient(colors:[Noir.crimsonLight,Noir.crimson,Noir.crimsonDeep],center:UnitPoint(x:0.35,y:0.3),startRadius:1,endRadius:24))
    .frame(width:34,height:34)
    .padding(.bottom,8)
   ForEach(HubSection.allCases) { section in hubRailButton(section) }
   Spacer()
   Button { c.showPanel = true } label: {
    VStack(spacing:5) {
     Image(systemName:"slider.horizontal.3").font(.system(size:17,weight:.semibold)).foregroundStyle(Color.white.opacity(0.7)).frame(width:48,height:40)
     Text("Settings").font(.system(size:10,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
    }
   }.buttonStyle(.plain)
  }
  .padding(.vertical,22)
  .frame(width:88)
  .background(Color.black.opacity(0.35))
  .overlay(alignment:.trailing) { Rectangle().fill(Color.white.opacity(0.06)).frame(width:1) }
 }

 func hubRailButton(_ section: HubSection) -> some View {
  let selected = hub.section == section
  let fill: AnyShapeStyle = selected ? AnyShapeStyle(LinearGradient(colors:[Noir.crimsonLight,Noir.crimson],startPoint:.topLeading,endPoint:.bottomTrailing)) : AnyShapeStyle(Color.white.opacity(0.06))
  return Button { hub.section = section } label: {
   VStack(spacing:5) {
    ZStack {
     RoundedRectangle(cornerRadius:15,style:.continuous).fill(fill).frame(width:48,height:48)
     Image(systemName:section.icon).font(.system(size:19,weight:.semibold)).foregroundStyle(Color.white.opacity(selected ? 1 : 0.7))
    }
    Text(section.title).font(.system(size:10,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(selected ? 0.95 : 0.5))
   }
  }.buttonStyle(.plain)
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
   .background(Capsule().fill(Color.white.opacity(0.07)))
   .overlay(Capsule().stroke(Color.white.opacity(0.10),lineWidth:1))
   Text("M").font(.system(size:14,weight:.bold,design:.rounded)).foregroundStyle(Color.white)
    .frame(width:36,height:36)
    .background(Circle().fill(LinearGradient(colors:[Noir.crimsonLight,Noir.crimsonDeep],startPoint:.topLeading,endPoint:.bottomTrailing)))
  }
  .padding(.horizontal,32).padding(.top,26).padding(.bottom,12)
 }

 @ViewBuilder var hubContent: some View {
  switch hub.section {
  case .home: hubHome
  case .friday: HStack { Spacer(minLength:0); voiceScreen.frame(width:560); Spacer(minLength:0) }
  case .stocks: hubStocks
  case .store: hubSoon(.store,"Store","Visits, sales and what's selling at findhotstuff.com.",["Visits from your public counters","Sales need a Stripe login, which would be its own switch","Order alerts keep reaching your phone the way they do now"])
  case .ecs: hubSoon(.ecs,"East Coast Social","Your daily feed and your clients in one place.",["The daily feed streak you can verify on the site","Your client list and sample weeks","Posting stays prepared by her and clicked by you"])
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
    Text("Your ventures").font(.system(size:18,weight:.semibold,design:.rounded)).foregroundStyle(Color.white.opacity(0.9))
    LazyVGrid(columns:[GridItem(.adaptive(minimum:230),spacing:16)],spacing:16) {
     hubTile(.stocks,hubStockHeadline)
     hubTile(.store,"Visits and sales · coming next")
     hubTile(.ecs,"Daily feed and clients · coming next")
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
    Button { hub.section = .friday } label: { Label("Talk to Friday",systemImage:"waveform") }.buttonStyle(PillButtonStyle()).padding(.top,4)
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
  Button { hub.section = section } label: {
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
 }

 var hubStockHeadline: String {
  if let d = stocks.dip, let m = stocks.momentum { return "Practice money · dip \(hubMoney(d.value)), momentum \(hubMoney(m.value))" }
  if let one = stocks.dip ?? stocks.momentum { return "Practice money · \(hubMoney(one.value))" }
  return stocks.failed ? "Couldn't load right now · open to retry" : "Loading…"
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
     Button { hub.section = .friday } label: { Label("Open Friday",systemImage:"waveform") }.buttonStyle(PillButtonStyle())
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
    hubAccountRow("waveform",Noir.crimson,"Google Gemini","Friday's voice and eyes.",live.hasKey ? "Connected" : "Not connected",live.hasKey ? HubColor.green : Noir.crimsonLight,"Manage") { c.showPanel = true }
    hubAccountRow("scissors",HubColor.violet,"Twitch clips","A separate clip account makes clips when you ask.",clips.signedIn ? "Connected" : "Not connected",clips.signedIn ? HubColor.green : Noir.crimsonLight,"Manage") { c.showPanel = true }
    hubAccountRow("chart.line.uptrend.xyaxis",HubColor.green,"Stock bot snapshot","Reads the public practice snapshot. No login needed.","Read-only",HubColor.green,nil) {}
    hubAccountRow("lock.shield.fill",HubColor.slate,"Moomoo (real money)","Not connected here, on purpose. Real money only runs on your Mac with your three switches.","Walled off",HubColor.slate,nil) {}
    hubAccountRow("bag.fill",HubColor.amber,"Store","Visits first. Sales would need a Stripe login, added as its own switch.","Coming next",HubColor.amber,nil) {}
    hubAccountRow("megaphone.fill",HubColor.violet,"X, TikTok, Facebook","She prepares posts. You click Post.","Coming later",HubColor.slate,nil) {}
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }

 func hubAccountRow(_ icon: String,_ tint: Color,_ name: String,_ detail: String,_ status: String,_ statusTint: Color,_ button: String?,_ action: @escaping () -> Void) -> some View {
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
    Button(button) { action() }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   }
  }
  .padding(16)
  .hubCard()
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
  hub.section = .friday
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
