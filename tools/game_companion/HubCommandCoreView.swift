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
 static let bg = HubTheme.hex(0x060607)            // near-black
 static let charcoal = HubTheme.hex(0x0C0C0E)
 static let card = HubTheme.hex(0x0F0F12)
 static let teal = HubTheme.hex(0x1FA39A)          // structure: rings, lines, labels
 static let emerald = HubTheme.hex(0x2FD39A)       // healthy, alive
 static let amber = HubTheme.hex(0xC9A04A)         // restrained amber: "needs a look" only
 static let crimson = HubTheme.hex(0xE0394B)       // real failures, and a faint rim of Friday's identity
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

  // Devices you added in Cyber Lab (records only; nothing probes them).
  for d in LabStore.shared.devices {
   nodes.append(CoreNode(id:"dev-\(d.id)",kind:"DEVICE · ADDED BY YOU",rows:[
     CoreRow(label:"Platform",value:d.platform.label),
     CoreRow(label:"Yours",value:d.owned ? "yes" : "not ticked",tone:d.owned ? 1 : 2),
     CoreRow(label:"Connector",value:d.platform.connector),
    ],ring:4,label:d.name,detail:d.platform.label,lit:false,warn:false,weight:0.5))
  }
  // Automations that are running or failing right now (GitHub's public status).
  for r in runs where r.isFailing || r.isRunning {
   nodes.append(CoreNode(id:"run-\(r.name)",kind:"AUTOMATION · GITHUB",rows:[
     CoreRow(label:"State",value:r.isFailing ? "failing" : "running",tone:r.isFailing ? 3 : 1),
     CoreRow(label:"Started",value:r.created.map { coreAgo($0) } ?? "unknown"),
    ],ring:5,label:r.name,detail:r.isFailing ? "failing" : "running",lit:r.isRunning,warn:r.isFailing,weight:0.5))
  }

  let verdict: Int = macWarn ? 2 : (g.results.isEmpty ? 0 : 1)   // "calm" only once Guard has actually checked this Mac
  let headline: String
  if g.locked { headline = "Lockdown is on" }
  else if verdict == 0 { headline = "Waiting for the first readings" }
  else if verdict == 1 { headline = counts.unknown > 0 ? "No problems found · \(counts.unknown) check\(counts.unknown == 1 ? "" : "s") couldn't be read" : "All systems calm" }
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
   cards.append(CoreCardData(id:"mac",title:"THIS MAC",big:counts.warn > 0 ? "\(counts.warn) to look at" : (counts.unknown > 0 ? "\(counts.ok) ok · \(counts.unknown) unread" : "All clear"),bigTone:counts.warn > 0 ? 2 : (counts.unknown > 0 ? 0 : 1),sub:macSub,foot:"Guard checked \(coreAgo(at)) · \(counts.ok) ok"))
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
   foot:stocks.failed ? "robot snapshots unavailable" : "\(loadedBots) of \(robots.count) practice robots loaded"))

  let newest = hackTape.first.map { "\(deckTapeTime($0.date))  \($0.tag)  \($0.text)" } ?? "quiet: nothing read yet"
  return CoreSnapshot(verdict:verdict,headline:headline,nodes:nodes,cards:cards,newest:newest)
 }

 var commandCoreRoom: some View {
  let snap = buildCoreSnapshot()
  return coreFrame("Overview",snap.headline,tone:snap.verdict == 2 ? 2 : 0,observations:coreObservations(),
                   content:AnyView(CoreRoomView(snapshot:snap,guardHub:GuardHub.shared)))
 }
}

@MainActor final class CoreUIState: ObservableObject {
 @Published var hub: Int?           // the open group on the ring (1 apps, 2 crew, 3 robots, 4 devices, 5 automations)
 @Published var selected: String?   // a member pinned for the detail panel
 @Published var hovered: String?
}

// The Overview, closer to Matthew's discreet reference: compact cards on both sides, and in the middle ONE ring around This Mac with a badge
// per group (apps online, crew, robots, devices, automations). Tap a badge and its members fan out around it; tap a member for its detail panel.
// Badges show real counts; a group with nothing in it shows 0, never filler.
struct CoreRoomView: View {
 var snapshot: CoreSnapshot
 @ObservedObject var guardHub: GuardHub
 @StateObject private var ui = CoreUIState()
 @Environment(\.accessibilityReduceMotion) private var reduceMotion

 static let groups: [(ring: Int,label: String,icon: String)] = [(2,"Crew","person.2.fill"),(1,"Apps online","network"),(3,"Robots","chart.line.uptrend.xyaxis"),(5,"Automations","gearshape.2.fill"),(4,"Devices","iphone")]

 private func tone(_ t: Int) -> Color {
  switch t { case 1: return CoreStyle.emerald; case 2: return CoreStyle.amber; case 3: return CoreStyle.crimson; default: return CoreStyle.ink }
 }

 var body: some View {
  GeometryReader { geo in
   // One centred composition (reference): it grows to a point, then stays together instead of drifting to the window edges.
   let width = min(geo.size.width,1240)
   let col = min(272,max(196,width * 0.2))
   HStack(alignment:.center,spacing:18) {
    VStack(spacing:12) { card(0,"laptopcomputer"); card(1,"wifi") }.frame(width:col)
    hero.frame(minWidth:320,maxWidth:.infinity).frame(height:min(geo.size.height,560))
    VStack(spacing:12) { card(2,"person.2"); card(3,"waveform.path.ecg") }.frame(width:col)
   }
   .frame(width:width)
   .frame(width:geo.size.width,height:geo.size.height)
  }
  .padding(.horizontal,22).padding(.top,4).padding(.bottom,8)
 }

 // MARK: compact cards

 func card(_ i: Int,_ icon: String) -> some View {
  let c = snapshot.cards.indices.contains(i) ? snapshot.cards[i] : nil
  return Group {
   if let c {
    CoreCard(title:coreTitle(c.title),icon:icon) {
     Text(c.big).font(.system(size:14,weight:.medium,design:.rounded)).foregroundStyle(tone(c.bigTone)).lineLimit(1).minimumScaleFactor(0.7)
     Text(c.sub).font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.78)).lineLimit(3).fixedSize(horizontal:false,vertical:true)
     if !c.foot.isEmpty { Text(c.foot).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(2) }
     if c.id == "mac" {
      Button { Task { await guardHub.runChecks() } } label: {
       Text(guardHub.checking ? "checking…" : "Run checks ›").font(.system(size:11.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.teal)
      }.buttonStyle(.plain).disabled(guardHub.checking || guardHub.locked)
     }
    }
   }
  }
 }

 // MARK: the ring

 func members(_ ring: Int) -> [CoreNode] { snapshot.nodes.filter { $0.ring == ring } }

 func geometry(_ size: CGSize) -> (center: CGPoint,r: CGFloat) {
  let c = CGPoint(x:size.width / 2,y:size.height / 2 - 2)
  return (c,min(size.width * 0.38,size.height * 0.37,215))
 }

 func hubPoint(_ index: Int,_ size: CGSize,_ t: Double) -> CGPoint {
  let g = geometry(size)
  let a = -Double.pi / 2 + 2 * Double.pi * Double(index) / Double(Self.groups.count) + (reduceMotion ? 0 : t * 0.006)
  return CGPoint(x:g.center.x + g.r * CGFloat(cos(a)),y:g.center.y + g.r * CGFloat(sin(a)))
 }

 // Members of the open group fan out on a small arc outside their badge.
 func memberPoints(_ index: Int,_ list: [CoreNode],_ size: CGSize,_ t: Double) -> [CGPoint] {
  let g = geometry(size)
  let hub = hubPoint(index,size,t)
  let out = atan2(Double(hub.y - g.center.y),Double(hub.x - g.center.x))
  let n = list.count
  let spread = min(Double.pi * 1.25,0.42 * Double(max(1,n - 1)))
  let rad: CGFloat = 58 + CGFloat(max(0,n - 6)) * 3
  return (0..<n).map { k in
   let a = out - spread / 2 + (n == 1 ? spread / 2 : spread * Double(k) / Double(n - 1))
   return CGPoint(x:hub.x + rad * CGFloat(cos(a)),y:hub.y + rad * CGFloat(sin(a)))
  }
 }

 func hubState(_ ring: Int) -> (count: Int,color: Color) {
  let m = members(ring)
  if m.contains(where:{ $0.warn && ring == 5 }) { return (m.count,CoreStyle.crimson) }
  if m.contains(where:{ $0.warn }) { return (m.count,CoreStyle.amber) }
  if m.contains(where:{ $0.lit }) { return (m.count,CoreStyle.emerald) }
  return (m.count,CoreStyle.dim)
 }

 var hero: some View {
  GeometryReader { geo in
   TimelineView(.animation(minimumInterval:1.0 / 24,paused:reduceMotion)) { timeline in
    let t = timeline.date.timeIntervalSinceReferenceDate
    ZStack(alignment:.topTrailing) {
     Canvas { ctx, size in drawRing(&ctx,size,t) }
     .contentShape(Rectangle())
     .onContinuousHover { phase in
      switch phase {
      case .active(let loc): ui.hovered = hit(loc,geo.size,Date.timeIntervalSinceReferenceDate)
      case .ended: ui.hovered = nil
      }
     }
     .onTapGesture { loc in
      let h = hit(loc,geo.size,Date.timeIntervalSinceReferenceDate)
      withAnimation(reduceMotion ? nil : .easeOut(duration:0.25)) {
       if let h, h.hasPrefix("hub-"), let ring = Int(h.dropFirst(4)) { ui.hub = ui.hub == ring ? nil : ring; ui.selected = nil }
       else if let h { ui.selected = ui.selected == h ? nil : h }
       else { ui.selected = nil; ui.hub = nil }
      }
     }
     detailPanel.padding(8)
    }
   }
  }
 }

 func ringIcon(_ ctx: inout GraphicsContext,_ name: String,_ color: Color,_ rect: CGRect) {
  var img = ctx.resolve(Image(systemName:name))
  img.shading = .color(color)
  ctx.draw(img,in:rect)
 }

 func drawRing(_ ctx: inout GraphicsContext,_ size: CGSize,_ t: Double) {
      let g = geometry(size)
      // the stage: a dark disc with the faintest crimson warmth, one main ring, one hairline outer ring
      ctx.fill(Path(ellipseIn:CGRect(x:g.center.x - g.r * 1.18,y:g.center.y - g.r * 1.18,width:g.r * 2.36,height:g.r * 2.36)),
               with:.radialGradient(Gradient(colors:[CoreStyle.crimson.opacity(0.10),Color.white.opacity(0.012),.clear]),center:g.center,startRadius:0,endRadius:g.r * 1.18))
      ctx.stroke(Path(ellipseIn:CGRect(x:g.center.x - g.r,y:g.center.y - g.r,width:g.r * 2,height:g.r * 2)),with:.color(Color.white.opacity(0.10)),lineWidth:1.2)
      ctx.stroke(Path(ellipseIn:CGRect(x:g.center.x - g.r * 0.62,y:g.center.y - g.r * 0.62,width:g.r * 1.24,height:g.r * 1.24)),with:.color(Color.white.opacity(0.05)),style:StrokeStyle(lineWidth:1,dash:[2,5]))
      ctx.stroke(Path(ellipseIn:CGRect(x:g.center.x - g.r * 1.16,y:g.center.y - g.r * 1.16,width:g.r * 2.32,height:g.r * 2.32)),with:.color(Color.white.opacity(0.04)),lineWidth:1)
      // a slow sweep along the main ring: decoration only
      if !reduceMotion {
       let a = t.truncatingRemainder(dividingBy:12) / 12 * 2 * Double.pi
       var arc = Path(); arc.addArc(center:g.center,radius:g.r,startAngle:.radians(a),endAngle:.radians(a + 0.5),clockwise:false)
       ctx.stroke(arc,with:.color(CoreStyle.crimson.opacity(0.45)),style:StrokeStyle(lineWidth:1.6,lineCap:.round))
      }
      // spokes to every badge; the open one brighter, with a moving dash (decoration)
      for (i,grp) in Self.groups.enumerated() {
       let p = hubPoint(i,size,t)
       var l = Path(); l.move(to:g.center); l.addLine(to:p)
       let open = ui.hub == grp.ring
       if open {
        ctx.stroke(l,with:.color(CoreStyle.crimson.opacity(0.75)),style:StrokeStyle(lineWidth:1.2,lineCap:.round,dash:[3,6],dashPhase:reduceMotion ? 0 : CGFloat(-t * 12)))
       } else {
        ctx.stroke(l,with:.color(Color.white.opacity(0.05)),lineWidth:1)
       }
      }
      // open group: members around its badge
      if let ring = ui.hub, let idx = Self.groups.firstIndex(where:{ $0.ring == ring }) {
       let list = members(ring)
       let hub = hubPoint(idx,size,t)
       for (k,p) in memberPoints(idx,list,size,t).enumerated() {
        let n = list[k]
        let on = ui.selected == n.id || ui.hovered == n.id
        var l = Path(); l.move(to:hub); l.addLine(to:p)
        ctx.stroke(l,with:.color(Color.white.opacity(on ? 0.35 : 0.08)),lineWidth:1)
        let col: Color = n.warn ? (ring == 5 ? CoreStyle.crimson : CoreStyle.amber) : (n.lit ? CoreStyle.emerald : Color.white.opacity(0.35))
        let r: CGFloat = on ? 6 : 4.5
        if n.lit || on { ctx.fill(Path(ellipseIn:CGRect(x:p.x - r * 2.4,y:p.y - r * 2.4,width:r * 4.8,height:r * 4.8)),with:.radialGradient(Gradient(colors:[col.opacity(0.3),.clear]),center:p,startRadius:0,endRadius:r * 2.4)) }
        ctx.fill(Path(ellipseIn:CGRect(x:p.x - r,y:p.y - r,width:r * 2,height:r * 2)),with:.color(col))
        if on { ctx.stroke(Path(ellipseIn:CGRect(x:p.x - r - 4,y:p.y - r - 4,width:(r + 4) * 2,height:(r + 4) * 2)),with:.color(CoreStyle.crimson),lineWidth:1.2) }
        ctx.draw(ctx.resolve(Text(n.label).font(.system(size:10.5,weight:on ? .semibold : .regular,design:.rounded)).foregroundStyle(Color.white.opacity(on ? 0.95 : 0.62))),at:CGPoint(x:p.x,y:p.y + r + 8),anchor:.center)
       }
      }
      // the badges
      for (i,grp) in Self.groups.enumerated() {
       let p = hubPoint(i,size,t)
       let st = hubState(grp.ring)
       let open = ui.hub == grp.ring || ui.hovered == "hub-\(grp.ring)"
       let r: CGFloat = 19
       ctx.fill(Path(ellipseIn:CGRect(x:p.x - r,y:p.y - r,width:r * 2,height:r * 2)),with:.color(HubTheme.hex(0x141417)))
       ctx.stroke(Path(ellipseIn:CGRect(x:p.x - r,y:p.y - r,width:r * 2,height:r * 2)),with:.color(open ? CoreStyle.crimson : st.color.opacity(0.7)),lineWidth:open ? 1.6 : 1.1)
       ringIcon(&ctx,grp.icon,open ? Color.white : (st.color == CoreStyle.dim ? Color.white.opacity(0.55) : st.color),CGRect(x:p.x - 8,y:p.y - 8,width:16,height:16))
       ctx.draw(ctx.resolve(Text("\(grp.label)").font(.system(size:11.5,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.85))),at:CGPoint(x:p.x,y:p.y + r + 9),anchor:.center)
       ctx.draw(ctx.resolve(Text("\(st.count)").font(.system(size:10.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.45))),at:CGPoint(x:p.x,y:p.y + r + 22),anchor:.center)
      }
      // the core: This Mac
      if let mac = snapshot.nodes.first(where:{ $0.ring == 0 }) {
       let col: Color = snapshot.verdict == 0 ? Color.white.opacity(0.35) : (mac.warn ? CoreStyle.amber : CoreStyle.emerald)
       let breathe: CGFloat = reduceMotion ? 1 : 1 + 0.02 * CGFloat(sin(t * 1.0))
       let r: CGFloat = 38 * breathe
       let on = ui.selected == "mac" || ui.hovered == "mac"
       ctx.fill(Path(ellipseIn:CGRect(x:g.center.x - r * 2,y:g.center.y - r * 2,width:r * 4,height:r * 4)),with:.radialGradient(Gradient(colors:[CoreStyle.crimson.opacity(0.18),.clear]),center:g.center,startRadius:0,endRadius:r * 2))
       ctx.fill(Path(ellipseIn:CGRect(x:g.center.x - r,y:g.center.y - r,width:r * 2,height:r * 2)),with:.radialGradient(Gradient(colors:[HubTheme.hex(0x22090D),HubTheme.hex(0x0B0507)]),center:g.center,startRadius:1,endRadius:r))
       ctx.stroke(Path(ellipseIn:CGRect(x:g.center.x - r,y:g.center.y - r,width:r * 2,height:r * 2)),with:.color(CoreStyle.crimson.opacity(on ? 1 : 0.8)),lineWidth:1.6)
       ctx.stroke(Path(ellipseIn:CGRect(x:g.center.x - r + 6,y:g.center.y - r + 6,width:(r - 6) * 2,height:(r - 6) * 2)),with:.color(col.opacity(0.7)),lineWidth:1)
       ringIcon(&ctx,"laptopcomputer",CoreStyle.crimson,CGRect(x:g.center.x - 15,y:g.center.y - 17,width:30,height:22))
       ctx.draw(ctx.resolve(Text("This Mac").font(.system(size:11,weight:.semibold,design:.rounded)).foregroundStyle(Color.white.opacity(0.92))),at:CGPoint(x:g.center.x,y:g.center.y + 15),anchor:.center)
      }
      }

 func hit(_ pt: CGPoint,_ size: CGSize,_ t: Double) -> String? {
  let g = geometry(size)
  if hypot(pt.x - g.center.x,pt.y - g.center.y) < 40 { return "mac" }
  if let ring = ui.hub, let idx = Self.groups.firstIndex(where:{ $0.ring == ring }) {
   let list = members(ring)
   for (k,p) in memberPoints(idx,list,size,t).enumerated() where hypot(pt.x - p.x,pt.y - p.y) < 13 { return list[k].id }
  }
  for (i,grp) in Self.groups.enumerated() { let p = hubPoint(i,size,t); if hypot(pt.x - p.x,pt.y - p.y) < 24 { return "hub-\(grp.ring)" } }
  return nil
 }

 var detailPanel: some View {
  let id = ui.hovered.flatMap { $0.hasPrefix("hub-") ? nil : $0 } ?? ui.selected
  let n = snapshot.nodes.first { $0.id == id }
  return Group {
   if let n {
    VStack(alignment:.leading,spacing:6) {
     HStack(alignment:.firstTextBaseline) {
      VStack(alignment:.leading,spacing:1) {
       Text(coreTitle(n.kind)).font(.system(size:10.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.crimson.opacity(0.9))
       Text(n.label).font(.system(size:15,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink).lineLimit(1)
      }
      Spacer(minLength:6)
      if ui.selected == n.id { Button { ui.selected = nil } label: { Image(systemName:"xmark").font(.system(size:9.5,weight:.semibold)).foregroundStyle(CoreStyle.dim) }.buttonStyle(.plain) }
     }
     ForEach(n.rows.prefix(12)) { r in
      HStack(alignment:.firstTextBaseline,spacing:8) {
       Text(r.label).font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(1)
       Spacer(minLength:6)
       Text(r.value).font(.system(size:11.5,weight:.medium,design:.rounded)).foregroundStyle(tone(r.tone)).lineLimit(2).multilineTextAlignment(.trailing)
      }
     }
    }
    .padding(12).frame(width:260)
    .background(RoundedRectangle(cornerRadius:12).fill(HubTheme.hex(0x111114).opacity(0.97)))
    .overlay(RoundedRectangle(cornerRadius:12).stroke(Color.white.opacity(0.08),lineWidth:1))
    .transition(.opacity)
   } else {
    Text(ui.hub == nil ? "Tap a badge to open it, or This Mac for its details" : "Tap a dot for details · tap the badge again to close")
     .font(.system(size:11,design:.rounded)).foregroundStyle(Color.white.opacity(0.32)).padding(.bottom,4).frame(maxWidth:.infinity)
   }
  }
 }
}
