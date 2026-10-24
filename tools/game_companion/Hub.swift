import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
 case home, friday, stocks, store, ecs, systems, launchpad, game, accounts, meeting, stream, helper
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
  case .meeting: return "Meeting Room"
  case .stream: return "Stream"
  case .helper: return "Helper"
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
  case .meeting: return "person.3.fill"
  case .stream: return "dot.radiowaves.left.and.right"
  case .helper: return "hand.raised.fill"
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
  case .meeting: return HubColor.violet
  case .stream: return HubColor.violet
  case .helper: return HubColor.green
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
  case .meeting: return "Claude, GPT and Friday on one shared board."
  case .stream: return "Your Twitch channel: go-live checks, title, category and clips."
  case .helper: return "Tell Friday a job; she does it with her hands, and asks before anything risky."
  }
 }
}

@MainActor final class HubModel: ObservableObject {
 @Published var section: HubSection = .home
 @Published var query = ""
 @Published var jumpQuery = ""
 @Published var jumpPresented = false
 // True when the window is narrow (under 720 points): a slimmer rail and top bar, so the window can be shrunk a lot.
 @Published var compact = false
 // Which card or button the pointer is over, so it can lift a little. Empty means none.
 @Published var hovered = ""
 // Which account row on the Accounts page is open, showing its connect form. Empty means none.
 @Published var expanded = ""
 // When the refresh-everything button last finished.
 @Published var refreshedAt: Date?
 // The order of the icons on the left rail. Drag an icon to move it; the order is remembered. A page added in a later
 // version lands at the end.
 @Published var order: [HubSection] = HubModel.savedOrder() {
  didSet { UserDefaults.standard.set(order.map { $0.rawValue },forKey:"hub.order") }
 }
 // The icon being dragged right now.
 @Published var dragging: HubSection?

 static func savedOrder() -> [HubSection] {
  let saved = (UserDefaults.standard.array(forKey:"hub.order") as? [Int] ?? []).compactMap { HubSection(rawValue:$0) }
  var seen = Set<HubSection>()
  var result = saved.filter { seen.insert($0).inserted }
  for section in HubSection.allCases where !seen.contains(section) { result.append(section) }
  return result
 }

 // Drops the dragged icon into the slot of the one it is over.
 func move(_ item: HubSection,onto target: HubSection) {
  guard item != target, let from = order.firstIndex(of:item), let to = order.firstIndex(of:target) else { return }
  var next = order
  next.remove(at:from)
  next.insert(item,at:to)
  order = next
 }

 func nudge(_ item: HubSection,by step: Int) {
  guard let from = order.firstIndex(of:item) else { return }
  let to = min(max(from + step,0),order.count - 1)
  guard to != from else { return }
  var next = order
  next.remove(at:from)
  next.insert(item,at:to)
  order = next
 }

 func resetOrder() { order = HubSection.allCases }

 // Command-1 to Command-9 for the first nine icons on the rail, Command-0 for the tenth. They follow the order you set.
 func shortcut(for section: HubSection) -> Character? {
  guard let index = order.firstIndex(of:section), index < 10 else { return nil }
  return index < 9 ? Character(String(index + 1)) : "0"
 }
}

// Lets a rail icon be dropped onto another to swap places, with the others sliding aside as it passes over them.
@MainActor struct RailDropDelegate: DropDelegate {
 let target: HubSection
 let hub: HubModel
 func validateDrop(info: DropInfo) -> Bool { hub.dragging != nil }
 func dropEntered(info: DropInfo) {
  guard let item = hub.dragging, item != target else { return }
  withAnimation(.spring(response:0.34,dampingFraction:0.8)) { hub.move(item,onto:target) }
 }
 func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation:.move) }
 func performDrop(info: DropInfo) -> Bool { hub.dragging = nil; return true }
}

// Store visits, the ECS feed and the automations' status. All public, all read-only (see VentureData.swift).
@MainActor final class VentureHub: ObservableObject {
 @Published var store: StoreStats?
 @Published var feed: FeedStats?
 @Published var runs: [AutomationRun]?
 @Published var catalog: CatalogStats?
 @Published var issues: [OpenAlert]?
 @Published var loading = false
 @Published var failed = false
 var lastRefresh = Date.distantPast
 var attention: [AutomationRun] { (runs ?? []).filter { $0.isFailing } }
 // Everything that needs a look: failing automations, plus a product list the 3-day refresh hasn't touched in over 5 days.
 var alerts: [String] {
  attention.map { $0.name } + ((catalog?.isStale() ?? false) ? ["Product catalog is \(catalog?.ageDays() ?? 0) days old"] : [])
 }

 // Counters are day-precision, so the background refresh waits at least nine minutes. Refresh buttons force it.
 func refresh(force: Bool = false) async {
  guard !loading else { return }
  if !force && Date().timeIntervalSince(lastRefresh) < 540 { return }
  loading = true
  defer { loading = false }
  async let storeResult = VentureData.fetchStore()
  async let feedResult = VentureData.fetchFeed()
  async let runsResult = VentureData.fetchAutomations()
  async let catalogResult = VentureData.fetchCatalog()
  async let issuesResult = VentureData.fetchAlerts()
  let (a,b,c,d,e) = await (storeResult,feedResult,runsResult,catalogResult,issuesResult)
  if let a = a { store = a }
  if let b = b { feed = b }
  if let c = c { runs = c }
  if let d = d { catalog = d }
  if let e = e { issues = e }
  failed = (store == nil && feed == nil && runs == nil && catalog == nil)
  lastRefresh = Date()
 }
}

// Sales from Stripe, read-only. The restricted key is saved privately on this Mac (see Keychain.swift); it is read at most once per run, on a refresh.
@MainActor final class SalesHub: ObservableObject {
 static let service = "stripe-readonly"
 @Published var hasKey = Keychain.exists(SalesHub.service)
 @Published var keyInput = ""
 @Published var sales: StripeSales?
 @Published var loading = false
 @Published var message = ""
 var lastRefresh = Date.distantPast

 func save() {
  if let problem = StripeData.keyProblem(keyInput) { message = problem; return }
  let key = keyInput.trimmingCharacters(in:.whitespacesAndNewlines)
  guard Keychain.write(SalesHub.service,Data(key.utf8)) else { message = "Couldn't save the key on this Mac."; return }
  keyInput = ""
  hasKey = true
  message = ""
  Task { await refresh(force:true) }
 }

 func forget() {
  Keychain.remove(SalesHub.service)
  hasKey = false
  sales = nil
  message = ""
 }

 func refresh(force: Bool = false) async {
  guard hasKey, !loading else { return }
  if !force && Date().timeIntervalSince(lastRefresh) < 540 { return }
  guard let data = Keychain.read(SalesHub.service), let key = String(data:data,encoding:.utf8) else { message = "Couldn't read the saved key. Remove it and save it again."; return }
  loading = true
  defer { loading = false }
  switch await StripeData.fetch(key:key) {
  case .ok(let result): sales = result; message = ""
  case .failed(let text): message = text
  }
  lastRefresh = Date()
 }
}

@MainActor final class StockHub: ObservableObject {
 @Published var dip: StockRobot?
 @Published var momentum: StockRobot?
 @Published var hot: StockRobot?
 @Published var loading = false
 @Published var failed = false
 @Published var robot = 0
 var current: StockRobot? { robot == 0 ? dip : (robot == 1 ? momentum : hot) }

 func refresh() async {
  guard !loading else { return }
  loading = true
  defer { loading = false }
  async let first = StockData.fetch(branch:"stock-live",name:"Dip robot")
  async let second = StockData.fetch(branch:"stock-live-momentum",name:"Momentum robot")
  async let third = StockData.fetch(branch:"stock-live-hot",name:"Hot hands robot")
  let (a,b,c) = await (first,second,third)
  if let a = a { dip = a }
  if let b = b { momentum = b }
  if let c = c { hot = c }
  failed = (a == nil && b == nil && c == nil && dip == nil && momentum == nil && hot == nil)
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
   HubLink(title:"ECS page",note:"Your automation page.",icon:"megaphone.fill",tint:HubColor.violet,url:"https://findhotstuff.com/automation/")
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
   HubLink(title:"Your channel",note:"Your Twitch page.",icon:"tv",tint:HubColor.violet,url:"https://www.twitch.tv/theycallmemattyb")
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
 // Command plus a number key, when the icon has one.
 @ViewBuilder func hubShortcut(_ key: Character?) -> some View {
  if let key = key { self.keyboardShortcut(KeyEquivalent(key),modifiers:.command) } else { self }
 }

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
