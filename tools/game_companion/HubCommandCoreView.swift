import SwiftUI
import AppKit

// Command Core, redesign (Matthew's DM 2026-11-06 ~9:56 AM: "cinematic mission control rather than a traditional hacker dashboard ... a strong central
// visualization, interactive device and network displays, elegant system-status cards, smooth animations, a collapsible terminal").
// Same honesty rule as the Hack Room: EVERY node, number and word comes from something the app actually read. The motion (slow orbit, the pulse)
// is decoration and never carries data: how many nodes there are, their size, their colour and their words are the real part.
//   centre   = this Mac (colour = Guard's verdict + failing automations)
//   inner    = apps Guard saw using the internet (size = number of connections)
//   middle   = the crew (lit = a real post or commit in the last 30 minutes)
//   outer    = the seven practice robots (paper money)
// Tap or hover a node for what it is. The old live tape and the command line live in the drawer at the bottom (collapsed by default).

enum CoreStyle {
 static let bg = HubTheme.hex(0x030A0B)            // deep teal-black
 static let charcoal = HubTheme.hex(0x08131A)
 static let card = HubTheme.hex(0x0B1A1E)
 static let teal = HubTheme.hex(0x1FA39A)          // structure: rings, lines, labels
 static let emerald = HubTheme.hex(0x2FD39A)       // healthy, alive
 static let amber = HubTheme.hex(0xE07888)         // "needs a look": a soft rose, no yellow (name kept so the code stays small)
 static let crimson = HubTheme.hex(0xD6293F)       // real failures, and a faint rim of Friday's identity
 static let ink = Color.white.opacity(0.92)
 static let dim = Color.white.opacity(0.52)
 static let faint = Color.white.opacity(0.08)
}

struct CoreRow: Identifiable {
 var id = UUID()
 var label: String
 var value: String
 var tone: Int = 0        // 0 normal, 1 good, 2 attention, 3 bad
}

struct CoreNode: Identifiable {
 var id: String
 var kind = ""            // shown small above the name in the detail panel
 var rows: [CoreRow] = []
 var ring: Int            // 0 centre, 1 apps, 2 crew, 3 robots
 var label: String
 var detail: String
 var lit: Bool            // true = real recent activity / healthy
 var warn: Bool
 var weight: Double       // 0...1, from a real number (connections, etc.)
}

struct CoreCardData: Identifiable {
 var id: String
 var title: String
 var big: String
 var bigTone: Int         // 0 normal, 1 good, 2 warning, 3 bad
 var sub: String
 var foot: String
}

struct CoreSnapshot {
 var verdict: Int         // 0 unknown, 1 calm, 2 needs a look
 var headline: String
 var nodes: [CoreNode]
 var cards: [CoreCardData]
 var newest: String       // latest tape line, one line
}

extension CompanionInterfaceView {

 func coreAgo(_ d: Date) -> String {
  let s = Int(Date().timeIntervalSince(d))
  return s < 90 ? "just now" : (s < 3600 ? "\(s / 60) min ago" : "\(s / 3600) h ago")
 }

 func buildCoreSnapshot() -> CoreSnapshot {
  let g = GuardHub.shared
  let counts = CoreFacts.summarize(g.results)
  let runs = ventures.runs ?? []
  let failing = runs.filter { $0.isFailing }
  let crew = deckCrewReal.filter { $0.kind == .chat || $0.kind == .cloud || $0.kind == .friday || $0.kind == .agent }
  let working = crew.filter { $0.state == .working }
  let robots = deckRobots

  var nodes: [CoreNode] = []
  let macWarn = g.locked || counts.warn > 0 || !failing.isEmpty
  var macRows: [CoreRow] = [
   CoreRow(label:"macOS",value:"\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)"),
   CoreRow(label:"Memory",value:"\(Int(CoreFacts.memoryGB().rounded())) GB"),
   CoreRow(label:"Up for",value:CoreFacts.uptimeText(ProcessInfo.processInfo.systemUptime)),
  ]
  if let free = CoreFacts.freeDiskGB() { macRows.append(CoreRow(label:"Free disk",value:"\(Int(free.rounded())) GB")) }
  for r in g.results { macRows.append(CoreRow(label:r.title,value:r.verdict == .ok ? "ok" : (r.verdict == .warn ? "needs a look" : "unknown"),tone:r.verdict == .ok ? 1 : (r.verdict == .warn ? 2 : 0))) }
  if g.results.isEmpty { macRows.append(CoreRow(label:"Guard",value:"not checked yet")) }
  nodes.append(CoreNode(id:"mac",kind:"THIS DEVICE",rows:macRows,ring:0,label:"This Mac",
   detail:"macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)",
   lit:!g.results.isEmpty,warn:macWarn,weight:1))
  let maxConn = Double(max(1,g.network.map { $0.connections }.max() ?? 1))
  for app in g.network.sorted(by:{ $0.connections > $1.connections }).prefix(9) {
   nodes.append(CoreNode(id:"app-\(app.name)",kind:"APPLICATION ONLINE",rows:[
     CoreRow(label:"Connections",value:"\(app.connections)"),
     CoreRow(label:"Seen before",value:app.isNew ? "no, new since Guard's first look" : "yes",tone:app.isNew ? 2 : 1),
     CoreRow(label:"Source",value:"Guard's check" + (g.lastChecked.map { ", \(coreAgo($0))" } ?? "")),
    ],ring:1,label:app.name,detail:"\(app.connections) internet connection\(app.connections == 1 ? "" : "s")",
    lit:true,warn:app.isNew,weight:Double(app.connections) / maxConn))
  }
  for m in crew {
   nodes.append(CoreNode(id:"crew-\(m.id)",kind:"CREW",rows:[
     CoreRow(label:"State",value:m.state == .working ? "working" : (m.state == .idle ? "idle" : (m.state == .away ? "away" : "no data")),tone:m.state == .working ? 1 : 0),
     CoreRow(label:"Evidence",value:m.detail),
     CoreRow(label:"Last sign",value:m.since.map { coreAgo($0) } ?? "none seen"),
     CoreRow(label:"Source",value:"room posts and commits only"),
    ],ring:2,label:m.name,detail:m.since.map { "\(m.detail) · \(coreAgo($0))" } ?? m.detail,
    lit:m.state == .working,warn:m.state == .failing,weight:0.5))
  }
  for r in robots {
   guard let robot = r.robot else { continue }
   let name = r.name.replacingOccurrences(of:"stock-",with:"")
   nodes.append(CoreNode(id:"bot-\(r.name)",kind:"PRACTICE ROBOT · PAPER MONEY",rows:[
     CoreRow(label:"Since start",value:(robot.sinceStart >= 0 ? "+" : "") + hubMoney(robot.sinceStart),tone:robot.sinceStart >= 0 ? 1 : 2),
     CoreRow(label:"Versus holding",value:(robot.vsHolding >= 0 ? "+" : "") + hubMoney(robot.vsHolding),tone:robot.vsHolding >= 0 ? 1 : 2),
     CoreRow(label:"Account value",value:hubMoney(robot.value)),
     CoreRow(label:"Trades",value:"\(robot.trades)"),
     CoreRow(label:"Updated",value:robot.updated.map { coreAgo($0) } ?? "unknown"),
    ],ring:3,label:name,
    detail:"practice robot (paper money)",
    lit:robot.sinceStart >= 0,warn:false,weight:0.5))
  }

  let verdict: Int = (g.results.isEmpty && g.network.isEmpty && runs.isEmpty) ? 0 : (macWarn ? 2 : 1)
  let headline: String
  if g.locked { headline = "Lockdown is on" }
  else if verdict == 0 { headline = "Waiting for the first readings" }
  else if verdict == 1 { headline = "All systems calm" }
  else {
   var bits: [String] = []
   if counts.warn > 0 { bits.append("\(counts.warn) Mac check\(counts.warn == 1 ? "" : "s")") }
   if !failing.isEmpty { bits.append("\(failing.count) automation\(failing.count == 1 ? "" : "s")") }
   headline = bits.joined(separator:" and ") + (counts.warn + failing.count == 1 ? " needs a look" : " need a look")
  }

  var cards: [CoreCardData] = []
  let macSub = "macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion) · \(Int(CoreFacts.memoryGB().rounded())) GB" + (CoreFacts.freeDiskGB().map { " · \(Int($0.rounded())) GB free" } ?? "")
  if g.locked {
   cards.append(CoreCardData(id:"mac",title:"THIS MAC",big:"Lockdown",bigTone:2,sub:macSub,foot:"checks paused until you unlock"))
  } else if let at = g.lastChecked, !g.results.isEmpty {
   cards.append(CoreCardData(id:"mac",title:"THIS MAC",big:counts.warn == 0 ? "All clear" : "\(counts.warn) to look at",bigTone:counts.warn == 0 ? 1 : 2,sub:macSub,foot:"Guard checked \(coreAgo(at)) · \(counts.ok) ok"))
  } else {
   cards.append(CoreCardData(id:"mac",title:"THIS MAC",big:"Not checked",bigTone:0,sub:macSub,foot:"press Run checks"))
  }
  if g.offline {
   cards.append(CoreCardData(id:"net",title:"NETWORK",big:"Offline mode",bigTone:2,sub:"The Helm makes no internet calls of its own",foot:""))
  } else if g.network.isEmpty {
   cards.append(CoreCardData(id:"net",title:"NETWORK",big:"Not read",bigTone:0,sub:"run checks to see which apps are online",foot:""))
  } else {
   let fresh = g.network.filter { $0.isNew }.count
   cards.append(CoreCardData(id:"net",title:"NETWORK",big:"\(g.network.count) apps online",bigTone:fresh > 0 ? 2 : 1,
    sub:g.network.sorted { $0.connections > $1.connections }.prefix(3).map { $0.name }.joined(separator:", "),
    foot:(fresh > 0 ? "\(fresh) new · " : "") + (g.lastChecked.map { "as of \(coreAgo($0))" } ?? "")))
  }
  cards.append(CoreCardData(id:"crew",title:"CREW",big:crew.isEmpty ? "No data" : "\(working.count) working",bigTone:working.isEmpty ? 0 : 1,
   sub:working.isEmpty ? (crew.isEmpty ? "crew not read yet" : "nobody posted or saved in the last 30 min") : working.prefix(3).map { $0.name }.joined(separator:", "),
   foot:crew.isEmpty ? "" : "of \(crew.count) chats · real posts and commits only"))
  let sb = Switchboard.shared
  let loadedBots = robots.filter { $0.robot != nil }.count
  let opsBig: String, opsTone: Int
  if !failing.isEmpty { opsBig = "\(failing.count) failing"; opsTone = 3 }
  else if let job = sb.runningJob { opsBig = "Job #\(job) running"; opsTone = 1 }
  else if ventures.runs == nil { opsBig = "Not read"; opsTone = 0 }
  else { opsBig = "All running"; opsTone = 1 }
  cards.append(CoreCardData(id:"ops",title:"OPERATIONS",big:opsBig,bigTone:opsTone,
   sub:"\(runs.count) automations · Switchboard \(sb.on ? "on" : "off")",
   foot:stocks.failed ? "robot snapshots unavailable" : "\(loadedBots) of 7 practice robots loaded"))

  let newest = hackTape.first.map { "\(deckTapeTime($0.date))  \($0.tag)  \($0.text)" } ?? "quiet: nothing read yet"
  return CoreSnapshot(verdict:verdict,headline:headline,nodes:nodes,cards:cards,newest:newest)
 }

 var commandCoreRoom: some View {
  HackRoomFrame(state:HackRoomState.shared) {
   CoreRoomView(snapshot:buildCoreSnapshot(),guardHub:GuardHub.shared,
                lights:HackSource.allCases.map { s in (s.rawValue,hackLight(s).0,hackLight(s).1) },
                tape:AnyView(hackTapePanel),
                terminal:AnyView(HackCommandLine(brain:FridayBrain.shared,room:HackRoomState.shared,switchboard:Switchboard.shared)))
  }
  .onAppear {
   Task { await meeting.chat.refresh(token:meeting.hasToken ? meeting.savedToken() : nil) }
   CrewSignals.refreshIfStale()
   // Guard's fixed, read-only checks (the same ones its page runs) once when this screen first opens, so the dots are real from the start.
   let g = GuardHub.shared
   if g.results.isEmpty && !g.locked && !g.offline { Task { await g.runChecks() } }
  }
 }
}

@MainActor final class CoreUIState: ObservableObject {
 @Published var selected: String?
 @Published var hovered: String?
 @Published var drawerOpen = false
}

struct CoreRoomView: View {
 var snapshot: CoreSnapshot
 @ObservedObject var guardHub: GuardHub
 var lights: [(String,HackLight,String)]
 var tape: AnyView
 var terminal: AnyView
 @StateObject private var ui = CoreUIState()
 private var selected: String? { get { ui.selected } nonmutating set { ui.selected = newValue } }
 private var hovered: String? { get { ui.hovered } nonmutating set { ui.hovered = newValue } }
 private var drawerOpen: Bool { get { ui.drawerOpen } nonmutating set { ui.drawerOpen = newValue } }
 @Environment(\.accessibilityReduceMotion) private var reduceMotion

 private func tone(_ t: Int) -> Color {
  switch t { case 1: return CoreStyle.emerald; case 2: return CoreStyle.amber; case 3: return CoreStyle.crimson; default: return CoreStyle.ink }
 }
 private func lightColor(_ l: HackLight) -> Color {
  switch l { case .fresh: return CoreStyle.emerald; case .stale: return CoreStyle.amber; case .failed: return CoreStyle.crimson; case .off: return CoreStyle.dim }
 }

 var body: some View {
  VStack(spacing:0) {
   header
   HStack(alignment:.center,spacing:18) {
    VStack(spacing:14) { card(0); card(1) }.frame(width:218)
    hero.frame(minWidth:300,maxWidth:.infinity,maxHeight:.infinity)
    VStack(spacing:14) { card(2); card(3) }.frame(width:218)
   }
   .padding(.horizontal,22).padding(.vertical,10)
   drawer
  }
 }

 // MARK: header

 var header: some View {
  HStack(alignment:.firstTextBaseline,spacing:14) {
   VStack(alignment:.leading,spacing:3) {
    Text("COMMAND CORE").font(.system(size:12,weight:.semibold,design:.rounded)).tracking(4).foregroundStyle(CoreStyle.crimson.opacity(0.95))
    Text(snapshot.headline).font(.system(size:22,weight:.light,design:.rounded)).foregroundStyle(snapshot.verdict == 2 ? CoreStyle.amber : CoreStyle.ink)
   }
   Spacer(minLength:0)
   HStack(spacing:11) {
    ForEach(Array(lights.enumerated()),id:\.offset) { _,l in
     HStack(spacing:4) {
      Circle().fill(l.1 == .off ? Color.clear : lightColor(l.1)).overlay(Circle().stroke(lightColor(l.1),lineWidth:1)).frame(width:6,height:6)
      Text(l.0).font(.system(size:10,design:.rounded)).foregroundStyle(CoreStyle.dim)
     }
     .help(l.2)
    }
   }
  }
  .padding(.horizontal,26).padding(.top,16).padding(.bottom,8)
 }

 // MARK: cards

 func card(_ i: Int) -> some View {
  let c = snapshot.cards.indices.contains(i) ? snapshot.cards[i] : nil
  return Group {
   if let c {
    VStack(alignment:.leading,spacing:6) {
     Text(c.title).font(.system(size:10,weight:.semibold,design:.rounded)).tracking(2.5).foregroundStyle(CoreStyle.dim)
     Text(c.big).font(.system(size:24,weight:.light,design:.rounded)).foregroundStyle(tone(c.bigTone)).lineLimit(1).minimumScaleFactor(0.6)
     Text(c.sub).font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.78)).lineLimit(2).fixedSize(horizontal:false,vertical:true)
     Spacer(minLength:0)
     if c.id == "mac" {
      HStack {
       Text(c.foot).font(.system(size:10,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(1)
       Spacer(minLength:4)
       Button { Task { await guardHub.runChecks() } } label: {
        Text(guardHub.checking ? "checking…" : "Run checks").font(.system(size:11,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.emerald)
         .padding(.horizontal,10).padding(.vertical,4).overlay(Capsule().stroke(CoreStyle.emerald.opacity(0.5),lineWidth:1))
       }
       .buttonStyle(.plain).disabled(guardHub.checking || guardHub.locked)
      }
     } else if !c.foot.isEmpty {
      Text(c.foot).font(.system(size:10,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(2)
     }
    }
    .padding(16).frame(maxWidth:.infinity,minHeight:132,maxHeight:.infinity,alignment:.topLeading)
    .background(RoundedRectangle(cornerRadius:16).fill(LinearGradient(colors:[CoreStyle.card,CoreStyle.charcoal],startPoint:.top,endPoint:.bottom)))
    .overlay(RoundedRectangle(cornerRadius:16).stroke(LinearGradient(colors:[Color.white.opacity(0.10),Color.white.opacity(0.02)],startPoint:.top,endPoint:.bottom),lineWidth:1))
   }
  }
 }

 // MARK: the hero visualization

 static let ringFraction: [CGFloat] = [0,0.30,0.45,0.60]
 static let ringSpeed: [Double] = [0,0.045,-0.028,0.016]
 static let ringCaption = ["","APPS ONLINE","CREW","PRACTICE ROBOTS"]

 // Where a node sits at a given time (the same function draws and hit-tests).
 func position(of node: CoreNode,in group: [CoreNode],size: CGSize,time: Double) -> CGPoint {
  let c = CGPoint(x:size.width / 2,y:size.height / 2 - 10)
  if node.ring == 0 { return c }
  let rx = (size.width / 2 - 24) * Self.ringFraction[node.ring] / 0.60 * 0.98
  let ry = (size.height / 2 - 40) * Self.ringFraction[node.ring] / 0.60 * 0.98
  let idx = group.firstIndex { $0.id == node.id } ?? 0
  let angle = 2 * Double.pi * Double(idx) / Double(max(1,group.count)) + Double(node.ring) * 0.9 + (reduceMotion ? 0 : time * Self.ringSpeed[node.ring])
  return CGPoint(x:c.x + rx * CGFloat(cos(angle)),y:c.y + ry * CGFloat(sin(angle)))
 }

 func nodeColor(_ n: CoreNode) -> Color {
  if n.warn { return CoreStyle.amber }
  switch n.ring {
  case 3: return n.lit ? CoreStyle.emerald : CoreStyle.crimson.opacity(0.75)
  default: return n.lit ? CoreStyle.emerald : CoreStyle.teal.opacity(0.55)
  }
 }

 func nodeRadius(_ n: CoreNode) -> CGFloat {
  switch n.ring {
  case 0: return 34
  case 1: return 5 + 7 * CGFloat(n.weight)
  case 2: return n.lit ? 7 : 5
  default: return 5.5
  }
 }

 var hero: some View {
  GeometryReader { geo in
   TimelineView(.animation(minimumInterval:1.0 / 30,paused:reduceMotion)) { timeline in
    let t = timeline.date.timeIntervalSinceReferenceDate
    let groups = Dictionary(grouping:snapshot.nodes,by:{ $0.ring })
    ZStack {
     Canvas { ctx, size in
      let center = CGPoint(x:size.width / 2,y:size.height / 2 - 10)
      func radii(_ ring: Int) -> (CGFloat,CGFloat) {
       ((size.width / 2 - 24) * Self.ringFraction[ring] / 0.60 * 0.98,(size.height / 2 - 40) * Self.ringFraction[ring] / 0.60 * 0.98)
      }
      // rings and their captions
      for ring in 1...3 {
       let (rx,ry) = radii(ring)
       var p = Path(); p.addEllipse(in:CGRect(x:center.x - rx,y:center.y - ry,width:rx * 2,height:ry * 2))
       ctx.stroke(p,with:.color(CoreStyle.teal.opacity(0.22)),lineWidth:1)
       if (groups[ring] ?? []).isEmpty == false {
        ctx.draw(ctx.resolve(Text(Self.ringCaption[ring]).font(.system(size:8,weight:.semibold,design:.rounded)).foregroundStyle(CoreStyle.teal.opacity(0.75))),at:CGPoint(x:center.x,y:center.y - ry - 7),anchor:.center)
       }
      }
      // slow pulse from the core: decoration only
      if !reduceMotion {
       let phase = (t.truncatingRemainder(dividingBy:6)) / 6
       let (prx,pry) = radii(2)
       var pp = Path(); pp.addEllipse(in:CGRect(x:center.x - prx * CGFloat(phase),y:center.y - pry * CGFloat(phase),width:prx * 2 * CGFloat(phase),height:pry * 2 * CGFloat(phase)))
       ctx.stroke(pp,with:.color(CoreStyle.emerald.opacity(0.18 * (1 - phase))),lineWidth:1.2)
      }
      // links from the Mac to the apps it is talking to (real: these apps were seen on the network)
      for n in groups[1] ?? [] {
       let pt = position(of:n,in:groups[1] ?? [],size:size,time:t)
       var l = Path(); l.move(to:center); l.addLine(to:pt)
       ctx.stroke(l,with:.color(CoreStyle.teal.opacity(selected == n.id || hovered == n.id ? 0.85 : 0.22)),lineWidth:selected == n.id || hovered == n.id ? 1.6 : 1)
      }
      // the selected node's link to the core (a pointer for the eye; the flowing dash is decoration, not traffic)
      if let sel = snapshot.nodes.first(where:{ $0.id == (selected ?? hovered) }), sel.ring > 0 {
       let pt = position(of:sel,in:groups[sel.ring] ?? [],size:size,time:t)
       var l = Path(); l.move(to:center); l.addLine(to:pt)
       ctx.stroke(l,with:.color(CoreStyle.emerald.opacity(0.9)),style:StrokeStyle(lineWidth:1.6,lineCap:.round,dash:[3,7],dashPhase:reduceMotion ? 0 : CGFloat(-t * 14)))
      }
      // nodes
      for ring in 1...3 {
       for n in groups[ring] ?? [] {
        let pt = position(of:n,in:groups[ring] ?? [],size:size,time:t)
        let rad = nodeRadius(n)
        let col = nodeColor(n)
        let on = selected == n.id || hovered == n.id
        if n.lit || on {
         ctx.fill(Path(ellipseIn:CGRect(x:pt.x - rad * 2.6,y:pt.y - rad * 2.6,width:rad * 5.2,height:rad * 5.2)),
                  with:.radialGradient(Gradient(colors:[col.opacity(on ? 0.45 : 0.22),.clear]),center:pt,startRadius:0,endRadius:rad * 2.6))
        }
        ctx.fill(Path(ellipseIn:CGRect(x:pt.x - rad,y:pt.y - rad,width:rad * 2,height:rad * 2)),with:.color(n.lit ? col : col.opacity(0.5)))
        if on {
         let pulse: CGFloat = reduceMotion ? 5 : 5 + 2.5 * CGFloat(sin(t * 3))
         ctx.stroke(Path(ellipseIn:CGRect(x:pt.x - rad - pulse,y:pt.y - rad - pulse,width:(rad + pulse) * 2,height:(rad + pulse) * 2)),with:.color(CoreStyle.emerald.opacity(0.85)),lineWidth:1.2)
        }
        if ring == 1 || on {
         ctx.draw(ctx.resolve(Text(n.label).font(.system(size:9.5,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(on ? 0.95 : 0.6))),at:CGPoint(x:pt.x,y:pt.y + rad + 9),anchor:.center)
        }
       }
      }
      // the core: this Mac. Colour = Guard + automations.
      if let mac = (groups[0] ?? []).first {
       let col: Color = snapshot.verdict == 0 ? CoreStyle.teal.opacity(0.6) : (mac.warn ? CoreStyle.amber : CoreStyle.emerald)
       let breathe: CGFloat = reduceMotion ? 1 : 1 + 0.04 * CGFloat(sin(t * 1.1))
       let rad: CGFloat = 34 * breathe
       ctx.fill(Path(ellipseIn:CGRect(x:center.x - rad * 3,y:center.y - rad * 3,width:rad * 6,height:rad * 6)),
                with:.radialGradient(Gradient(colors:[col.opacity(0.20),.clear]),center:center,startRadius:0,endRadius:rad * 3))
       ctx.fill(Path(ellipseIn:CGRect(x:center.x - rad,y:center.y - rad,width:rad * 2,height:rad * 2)),
                with:.radialGradient(Gradient(colors:[col.opacity(0.95),col.opacity(0.25)]),center:center,startRadius:2,endRadius:rad))
       ctx.stroke(Path(ellipseIn:CGRect(x:center.x - rad - 6,y:center.y - rad - 6,width:(rad + 6) * 2,height:(rad + 6) * 2)),with:.color(CoreStyle.crimson.opacity(0.35)),lineWidth:1)
       ctx.draw(ctx.resolve(Text("THIS MAC").font(.system(size:8.5,weight:.bold,design:.rounded)).foregroundStyle(Color.black.opacity(0.75))),at:center,anchor:.center)
      }
     }
     .contentShape(Rectangle())
     .onContinuousHover { phase in
      switch phase {
      case .active(let loc): hovered = nearest(to:loc,size:geo.size,time:Date.timeIntervalSinceReferenceDate,groups:groups)
      case .ended: hovered = nil
      }
     }
     .onTapGesture { loc in
      let hit = nearest(to:loc,size:geo.size,time:Date.timeIntervalSinceReferenceDate,groups:groups)
      selected = (hit == selected) ? nil : hit
     }
     VStack {
      Spacer()
      detailStrip
     }
    }
   }
  }
 }

 func nearest(to point: CGPoint,size: CGSize,time: Double,groups: [Int:[CoreNode]]) -> String? {
  var best: (String,CGFloat)?
  for n in snapshot.nodes {
   let p = position(of:n,in:groups[n.ring] ?? [],size:size,time:time)
   let d = hypot(p.x - point.x,p.y - point.y)
   if d < max(16,nodeRadius(n) + 8), best == nil || d < best!.1 { best = (n.id,d) }
  }
  return best?.0
 }

 var detailStrip: some View {
  let n = snapshot.nodes.first { $0.id == (hovered ?? selected) }
  return Group {
   if let n {
    VStack(alignment:.leading,spacing:8) {
     HStack(alignment:.firstTextBaseline) {
      VStack(alignment:.leading,spacing:2) {
       Text(n.kind).font(.system(size:9,weight:.semibold,design:.rounded)).tracking(2).foregroundStyle(CoreStyle.teal)
       Text(n.label).font(.system(size:17,weight:.light,design:.rounded)).foregroundStyle(CoreStyle.ink).lineLimit(1)
      }
      Spacer(minLength:8)
      if selected == n.id {
       Button { selected = nil } label: { Image(systemName:"xmark").font(.system(size:10,weight:.semibold)).foregroundStyle(CoreStyle.dim) }.buttonStyle(.plain)
      } else {
       Text("tap to pin").font(.system(size:9.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
      }
     }
     VStack(spacing:4) {
      ForEach(n.rows) { r in
       HStack(alignment:.firstTextBaseline,spacing:8) {
        Text(r.label).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(1)
        Spacer(minLength:6)
        Text(r.value).font(.system(size:11,weight:.medium,design:.rounded)).foregroundStyle(tone(r.tone)).lineLimit(2).multilineTextAlignment(.trailing)
       }
      }
     }
    }
    .padding(14).frame(width:300)
    .background(RoundedRectangle(cornerRadius:14).fill(CoreStyle.card.opacity(0.96)))
    .overlay(RoundedRectangle(cornerRadius:14).stroke(CoreStyle.teal.opacity(0.45),lineWidth:1))
    .shadow(color:CoreStyle.teal.opacity(0.25),radius:16)
    .transition(.opacity.combined(with:.scale(scale:0.97,anchor:.bottom)))
   } else {
    Text("tap a dot to see what it is").font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.teal.opacity(0.6)).padding(.bottom,4)
   }
  }
  .animation(reduceMotion ? nil : .easeOut(duration:0.2),value:hovered ?? selected)
  .frame(maxWidth:.infinity,alignment:.center).padding(.bottom,2)
 }

 // MARK: the collapsible drawer: the live tape and the command line

 var drawer: some View {
  VStack(spacing:0) {
   Button { withAnimation(reduceMotion ? nil : .easeInOut(duration:0.28)) { drawerOpen.toggle() } } label: {
    HStack(spacing:10) {
     Image(systemName:drawerOpen ? "chevron.down" : "chevron.up").font(.system(size:10,weight:.semibold)).foregroundStyle(CoreStyle.emerald)
     Text("ACTIVITY & COMMAND LINE").font(.system(size:10,weight:.semibold,design:.rounded)).tracking(2).foregroundStyle(CoreStyle.dim)
     if !drawerOpen {
      Text(snapshot.newest).font(DeckMono.font(10.5)).foregroundStyle(CoreStyle.ink.opacity(0.7)).lineLimit(1)
     }
     Spacer(minLength:0)
     Text(drawerOpen ? "hide" : "ask Friday").font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.emerald)
    }
    .padding(.horizontal,26).padding(.vertical,11).contentShape(Rectangle())
   }
   .buttonStyle(.plain)
   if drawerOpen {
    VStack(spacing:10) {
     tape.frame(height:150)
     terminal
    }
    .padding(.horizontal,22).padding(.bottom,12)
    .transition(.move(edge:.bottom).combined(with:.opacity))
   }
  }
  .background(CoreStyle.charcoal.opacity(0.92))
  .overlay(alignment:.top) { Rectangle().fill(LinearGradient(colors:[.clear,CoreStyle.crimson.opacity(0.55),.clear],startPoint:.leading,endPoint:.trailing)).frame(height:1) }
 }
}
