import SwiftUI

// The Crew station: a pixel-art station (rooms joined by corridors) with one desk per crew member and a list with timers on the side.
// ALL art here is our own, drawn with plain rectangles. Every character shows only its REAL state, worked out in CrewData.swift from the
// room thread, GitHub's public workflow runs and the robots' snapshots: working at the desk, idle and wandering, away until a date that a
// room message gave, red when its last run failed, or dim with "?" when there is no data. Nothing here can start or change anything.
struct CrewStationView: View {
 let crew: [CrewMember]
 let reduceMotion: Bool

 private struct Room { var name: String; var rect: CGRect; var tint: Color; var perRow: Int; var has: (CrewMember) -> Bool }
 private let logical = CGSize(width:760,height:580)
 private var rooms: [Room] { [
  Room(name:"BRIDGE",rect:CGRect(x:12,y:12,width:452,height:272),tint:HubTheme.hex(0x1F2B26),perRow:5,has:{ [.chat,.cloud,.agent,.friday].contains($0.kind) }),
  Room(name:"ENGINE ROOM",rect:CGRect(x:480,y:12,width:268,height:272),tint:HubTheme.hex(0x222A2E),perRow:3,has:{ [.watcher].contains($0.kind) || $0.id == "refresh" }),
  Room(name:"TRADING FLOOR",rect:CGRect(x:12,y:300,width:560,height:268),tint:HubTheme.hex(0x262A21),perRow:4,has:{ $0.kind == .robot }),
  Room(name:"GALLERY",rect:CGRect(x:588,y:300,width:160,height:268),tint:HubTheme.hex(0x2A2330),perRow:1,has:{ $0.kind == .poster && $0.id != "refresh" }),
 ] }

 private func desks() -> [(member: CrewMember,desk: CGPoint,room: CGRect)] {
  var out: [(CrewMember,CGPoint,CGRect)] = []
  for room in rooms {
   let members = crew.filter { room.has($0) }
   let rows = max(1,(members.count + room.perRow - 1) / room.perRow)
   let cellW = room.rect.width / CGFloat(room.perRow)
   let cellH = (room.rect.height - 30) / CGFloat(rows)
   for (i,member) in members.enumerated() {
    let col = i % room.perRow, row = i / room.perRow
    out.append((member,CGPoint(x:room.rect.minX + cellW * (CGFloat(col) + 0.5),y:room.rect.minY + 30 + cellH * (CGFloat(row) + 0.42)),room.rect))
   }
  }
  return out
 }

 private func seed(_ text: String) -> Double { Double(text.unicodeScalars.reduce(7) { ($0 * 31 + Int($1.value)) % 9973 }) }

 private func palette(_ name: String) -> (skin: Color,hair: Color,shirt: Color) {
  let s = Int(seed(name))
  let skins = [HubTheme.hex(0xF1C27D),HubTheme.hex(0xC68642),HubTheme.hex(0xE0AC69),HubTheme.hex(0x8D5524),HubTheme.hex(0xFFDBAC)]
  let hairs = [HubTheme.hex(0x2C1B10),HubTheme.hex(0x111111),HubTheme.hex(0xA0522D),HubTheme.hex(0xD9B13B),HubTheme.hex(0x5A3A1A)]
  let shirts = [HubTheme.hex(0x6B9FFF),HubTheme.hex(0xE88A5A),HubTheme.hex(0x87C895),HubTheme.hex(0xC58BE0),HubTheme.hex(0xDDB66D),HubTheme.hex(0x83C9C0)]
  return (skins[s % skins.count],hairs[(s / 5) % hairs.count],shirts[(s / 25) % shirts.count])
 }

 private enum Look { case person, ghost, orb, eyeBot, antennaBot, boxBot, loopBot }
 private func look(_ m: CrewMember) -> Look {
  switch m.id {
  case "Roxy": return .ghost
  case "Friday": return .orb
  case "watcher": return .eyeBot
  case "changes": return .antennaBot
  case "refresh": return .loopBot
  default: return m.kind == .robot ? .boxBot : .person
  }
 }
 private func tint(_ m: CrewMember) -> Color {
  switch m.id {
  case "Roxy": return HubTheme.hex(0xE8ECF5)
  case "Grok": return HubTheme.hex(0x2E2E38)
  case "Cloud Claude": return HubTheme.hex(0xE88A5A)
  case "facebook": return HubTheme.hex(0x4D8DFF)
  case "tiktok": return HubTheme.hex(0x83C9C0)
  default:
   let list = [HubTheme.hex(0x6B9FFF),HubTheme.hex(0x87C895),HubTheme.hex(0xDDB66D),HubTheme.hex(0xC58BE0),HubTheme.hex(0x83C9C0),HubTheme.hex(0xE88A5A),HubTheme.hex(0xD9B13B)]
   return list[Int(seed(m.id)) % list.count]
  }
 }

 // One sprite, drawn from the feet up on a grid of `px` points. Every look is our own: people with job gear, a ghost, a crimson orb, small robots.
 private func figure(_ ctx: GraphicsContext,_ m: CrewMember,at feet: CGPoint,px: CGFloat,step: Bool,armsUp: Bool,dim: Double,flash: Bool,t: Double) {
  var c = ctx
  c.opacity = dim
  let ink = HubTheme.hex(0x101413)
  func block(_ x: Int,_ y: Int,_ w: Int,_ h: Int,_ color: Color) {
   c.fill(Path(CGRect(x:feet.x + CGFloat(x - 3) * px,y:feet.y - CGFloat(10 - y) * px,width:CGFloat(w) * px,height:CGFloat(h) * px)),with:.color(color))
  }
  let body = m.state == .failing && flash ? Color(red:1,green:0.4,blue:0.4) : tint(m)
  switch look(m) {
  case .person:
   let col = palette(m.name)
   block(1,1,4,1,m.id == "Grok" ? HubTheme.hex(0x15151B) : col.hair)
   block(1,2,4,3,col.skin); block(1,3,1,1,ink); block(4,3,1,1,ink)
   if m.kind == .chat { block(0,2,1,3,HubTheme.hex(0x2C3A33)); block(5,2,1,3,HubTheme.hex(0x2C3A33)); block(0,1,6,1,HubTheme.hex(0x2C3A33)) }   // headset
   if m.id == "Cloud Claude" { block(0,0,2,1,.white); block(2,-1,3,2,.white); block(4,0,2,1,.white) }                                       // cloud hat
   block(1,5,4,3,m.id == "Grok" ? HubTheme.hex(0x2E2E38) : body)
   if m.kind == .chat { block(2,6,2,1,HubTheme.amber) }                                                                                      // job badge
   if m.id == "Grok" { block(5,5,1,1,HubTheme.hex(0xFFD84D)); block(4,6,1,1,HubTheme.hex(0xFFD84D)); block(5,7,1,1,HubTheme.hex(0xFFD84D)) } // bolt
   if m.id == "facebook" { block(5,4,2,2,HubTheme.hex(0x4D8DFF)) }                                                                           // megaphone
   if m.id == "tiktok" { block(5,4,1,3,HubTheme.hex(0x83C9C0)); block(6,4,1,1,HubTheme.hex(0xFF5D8F)) }                                     // note
   block(0,armsUp ? 4 : 5,1,armsUp ? 2 : 3,col.skin); block(5,armsUp ? 4 : 5,1,armsUp ? 2 : 3,col.skin)
   block(1,8,2,2,HubTheme.hex(0x2A3566)); block(3,8,2,2,HubTheme.hex(0x2A3566))
   if step { block(1,9,2,1,HubTheme.hex(0x1B2244)) } else { block(3,9,2,1,HubTheme.hex(0x1B2244)) }
  case .ghost:
   let w = HubTheme.hex(0xE8ECF5)
   block(1,1,4,1,w); block(0,2,6,6,w); block(1,3,1,2,ink); block(4,3,1,2,ink)
   let wave = Int(t * 2) % 2
   block(0,8,2,1,w); block(2,8 + wave,2,1,w); block(4,8,2,1,w)
   block(0,armsUp ? 4 : 6,1,1,w.opacity(0.7)); block(5,armsUp ? 4 : 6,1,1,w.opacity(0.7))
  case .orb:
   let glow = 0.75 + 0.25 * sin(t * 2)
   block(1,2,4,6,Noir.crimson.opacity(0.55 * glow)); block(0,3,6,4,Noir.crimson.opacity(0.55 * glow))
   block(1,3,4,4,Noir.crimsonLight); block(2,4,2,2,.white)
  case .eyeBot:
   block(0,2,6,5,HubTheme.hex(0x7E8AA6)); block(1,3,4,3,.white); block(2,4,2,1,m.state == .failing ? Color.red : HubTheme.hex(0x2E6B5A))
   block(1,7,4,2,HubTheme.hex(0x5A6680)); block(1,9,1,1,ink); block(4,9,1,1,ink)
  case .antennaBot:
   block(3,0,1,2,HubTheme.sage); block(2,0,1,1,HubTheme.amber)
   block(1,2,4,3,HubTheme.hex(0x9FC3D9)); block(1,3,1,1,ink); block(4,3,1,1,ink)
   block(0,5,6,3,HubTheme.hex(0x6D93AB)); block(1,8,2,2,ink); block(3,8,2,2,ink)
  case .boxBot:
   block(2,1,2,1,body); block(1,2,4,3,body.opacity(0.9)); block(1,3,1,1,ink); block(4,3,1,1,ink)
   block(0,5,6,3,body); block(2,6,2,1,.white.opacity(0.7))
   block(1,8,1,2,ink); block(4,8,1,2,ink)
   if step { block(1,9,2,1,ink) } else { block(3,9,2,1,ink) }
  case .loopBot:
   let b = HubTheme.hex(0xC9B49A)
   block(1,2,4,5,b); block(2,3,2,1,ink); block(2,5,2,1,ink); block(1,7,4,2,HubTheme.hex(0x9A7F66)); block(1,9,1,1,ink); block(4,9,1,1,ink)
   block(Int(t * 3) % 2 == 0 ? 5 : 0,4,1,1,HubTheme.amber)
  }
 }

 var body: some View {
  TimelineView(.animation(minimumInterval:1.0 / 8.0,paused:reduceMotion)) { timeline in
   let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
   Canvas { ctx, size in
    let scale = min(size.width / logical.width,size.height / logical.height)
    let drift = CGPoint(x:sin(t * 0.07) * 4,y:cos(t * 0.05) * 3)
    var g = ctx
    g.translateBy(x:(size.width - logical.width * scale) / 2 + drift.x * scale,y:(size.height - logical.height * scale) / 2 + drift.y * scale)
    g.scaleBy(x:scale,y:scale)
    // corridors between the rooms
    let hall = HubTheme.hex(0x181D1B)
    for r in [CGRect(x:464,y:110,width:16,height:36),CGRect(x:180,y:284,width:36,height:16),CGRect(x:500,y:284,width:36,height:16),CGRect(x:572,y:400,width:16,height:36),CGRect(x:640,y:284,width:36,height:16)] { g.fill(Path(r),with:.color(hall)); g.stroke(Path(r),with:.color(HubTheme.line),style:StrokeStyle(lineWidth:1,dash:[3,3])) }
    for room in rooms {
     g.fill(Path(roundedRect:room.rect,cornerRadius:5),with:.color(room.tint))
     var x = room.rect.minX
     while x < room.rect.maxX { g.stroke(Path { p in p.move(to:CGPoint(x:x,y:room.rect.minY)); p.addLine(to:CGPoint(x:x,y:room.rect.maxY)) },with:.color(Color.white.opacity(0.03)),lineWidth:1); x += 20 }
     g.stroke(Path(roundedRect:room.rect,cornerRadius:5),with:.color(HubTheme.hex(0x44524B)),lineWidth:2)
     g.draw(Text(room.name).font(.system(size:10,weight:.bold,design:.monospaced)).foregroundColor(HubTheme.sage),at:CGPoint(x:room.rect.minX + 10,y:room.rect.minY + 12),anchor:.leading)
    }
    for entry in desks() {
     let m = entry.member
     let d = entry.desk
     let flash = Int(t * 2) % 2 == 0
     func drawDesk() {
      g.fill(Path(roundedRect:CGRect(x:d.x - 26,y:d.y - 6,width:52,height:18),cornerRadius:2),with:.color(HubTheme.hex(0x3A4640)))
      var screen = HubTheme.hex(0x181D1B)
      switch m.state {
      case .working: screen = HubTheme.green.opacity(0.85)
      case .failing: screen = flash ? Color(red:0.95,green:0.3,blue:0.3) : HubTheme.hex(0x5A1E1E)
      case .idle: screen = HubTheme.hex(0x2C3A33)
      case .away: screen = HubTheme.hex(0x1A2230)
      case .unknown: screen = HubTheme.hex(0x181D1B)
      }
      g.fill(Path(CGRect(x:d.x - 11,y:d.y - 23,width:22,height:16)),with:.color(HubTheme.hex(0x0C100E)))
      g.fill(Path(CGRect(x:d.x - 10,y:d.y - 22,width:20,height:14)),with:.color(screen))
     }
     let px: CGFloat = 4.0
     if m.state != .working { drawDesk() }
     switch m.state {
     case .working:
      figure(g,m,at:CGPoint(x:d.x,y:d.y + 28),px:px,step:false,armsUp:Int(t * 4 + seed(m.id)) % 2 == 0,dim:1,flash:flash,t:t)
      drawDesk()
      // typing dots over the monitor
      let dots = Int(t * 3) % 4
      g.draw(Text(String(repeating:".",count:max(1,dots))).font(.system(size:12,weight:.heavy,design:.monospaced)).foregroundColor(HubTheme.green),at:CGPoint(x:d.x + 16,y:d.y - 22),anchor:.leading)
     case .idle:
      let phase = t * 1.3 + seed(m.id)
      let range = max(10,(entry.room.width / 2) - 40)
      let wx = sin(phase * 0.35) * range * 0.5
      let wy = abs(sin(phase * 0.21)) * 12
      let fx = min(max(d.x + wx,entry.room.minX + 14),entry.room.maxX - 14)
      let fy = min(d.y + 40 + wy,entry.room.maxY - 16)
      figure(g,m,at:CGPoint(x:fx,y:fy),px:px,step:Int(phase * 3) % 2 == 0,armsUp:false,dim:1,flash:flash,t:t)
      g.draw(Text("💤").font(.system(size:11)),at:CGPoint(x:fx + 14,y:fy - 36 - CGFloat(Int(t) % 3)),anchor:.center)
     case .away:
      figure(g,m,at:CGPoint(x:d.x,y:d.y + 28),px:px,step:false,armsUp:false,dim:0.35,flash:flash,t:t)
      let until = m.awayUntil.map { "back " + $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "away"
      let sign = CGRect(x:d.x - 38,y:d.y + 12,width:76,height:15)
      g.fill(Path(roundedRect:sign,cornerRadius:2),with:.color(HubTheme.hex(0x2B3F66)))
      g.stroke(Path(roundedRect:sign,cornerRadius:2),with:.color(HubTheme.blue),lineWidth:1)
      g.draw(Text("AWAY · " + until).font(.system(size:7.5,weight:.bold,design:.monospaced)).foregroundColor(.white),at:CGPoint(x:sign.midX,y:sign.midY),anchor:.center)
     case .failing:
      figure(g,m,at:CGPoint(x:d.x,y:d.y + 28),px:px,step:false,armsUp:flash,dim:1,flash:flash,t:t)
      // red alarm light on the desk
      g.fill(Path(ellipseIn:CGRect(x:d.x + 14,y:d.y - 14,width:10,height:10)),with:.color(flash ? Color(red:1,green:0.2,blue:0.2) : Color(red:0.45,green:0.1,blue:0.1)))
      g.draw(Text("ALARM").font(.system(size:7,weight:.heavy,design:.monospaced)).foregroundColor(Color(red:1,green:0.4,blue:0.4)),at:CGPoint(x:d.x + 19,y:d.y - 20),anchor:.center)
     case .unknown:
      figure(g,m,at:CGPoint(x:d.x,y:d.y + 28),px:px,step:false,armsUp:false,dim:0.28,flash:flash,t:t)
      g.draw(Text("?").font(.system(size:13,weight:.bold,design:.monospaced)).foregroundColor(HubTheme.sage),at:CGPoint(x:d.x + 16,y:d.y - 14),anchor:.center)
     }
     let badge = m.kind == .chat ? String(m.name.replacingOccurrences(of:"LC-",with:"").prefix(6)).uppercased() : ""
     g.draw(Text(m.name.count > 15 ? String(m.name.prefix(14)) + "…" : m.name).font(.system(size:9,weight:.medium,design:.monospaced)).foregroundColor(HubTheme.text.opacity(0.92)),at:CGPoint(x:d.x,y:d.y + 52),anchor:.top)
     if !badge.isEmpty { g.draw(Text(badge).font(.system(size:7,weight:.bold,design:.monospaced)).foregroundColor(HubTheme.amber),at:CGPoint(x:d.x,y:d.y + 64),anchor:.top) }
    }
   }
  }
  .accessibilityElement(children:.ignore)
  .accessibilityLabel("Crew station picture. \(crew.filter { $0.state == .working }.count) working, \(crew.filter { $0.state == .idle }.count) idle, \(crew.filter { $0.state == .away }.count) away, \(crew.filter { $0.state == .failing }.count) failing. The list beside it has the same information.")
 }
}

extension CompanionInterfaceView {
 var deckCrewStation: some View {
  let crew = deckCrew
  return HStack(alignment:.top,spacing:14) {
   VStack(alignment:.leading,spacing:8) {
    HStack(spacing:10) {
     Text("CREW STATION").font(DeckMono.font(11,.bold)).foregroundStyle(HubTheme.amber)
     Text("real states only · from the room, the board, GitHub runs and robot snapshots").font(DeckMono.font(10.5)).foregroundStyle(HubTheme.subtext).lineLimit(1)
    }
    CrewStationView(crew:crew,reduceMotion:reduceMotion)
     .frame(maxWidth:.infinity,maxHeight:.infinity)
     .background(DeckMono.bg,in:RoundedRectangle(cornerRadius:8))
     .overlay(RoundedRectangle(cornerRadius:8).stroke(HubTheme.line,lineWidth:1))
    HStack(spacing:16) {
     ForEach([(CrewState.working,"working at desk"),(.idle,"idle, wandering"),(.away,"away"),(.failing,"last run failed"),(.unknown,"no data")],id:\.1) { entry in
      HStack(spacing:6) { Circle().fill(deckStateColor(entry.0)).frame(width:8,height:8); Text(entry.1).font(DeckMono.font(10.5)).foregroundStyle(HubTheme.subtext) }
     }
    }
   }
   VStack(alignment:.leading,spacing:8) {
    deckLabel("CREW LIST · \(crew.filter { $0.state == .working }.count) WORKING")
    ScrollView {
     VStack(spacing:0) {
      ForEach(crew.sorted { deckRank($0.state) < deckRank($1.state) }) { member in deckCrewRow(member) }
     }
    }
   }
   .frame(width:300)
  }
  .padding(.horizontal,22).padding(.vertical,14)
  .background(DeckMono.bg.opacity(0.55))
 }

 func deckRank(_ state: CrewState) -> Int {
  switch state { case .failing: return 0; case .working: return 1; case .away: return 2; case .idle: return 3; case .unknown: return 4 }
 }

 func deckCrewRow(_ member: CrewMember) -> some View {
  HStack(alignment:.top,spacing:9) {
   Circle().fill(deckStateColor(member.state)).frame(width:8,height:8).padding(.top,5)
   VStack(alignment:.leading,spacing:2) {
    Text(member.name).font(.system(size:12.5,weight:.semibold)).foregroundStyle(HubTheme.text)
    Text(member.detail).font(.system(size:10.5)).foregroundStyle(HubTheme.subtext).lineLimit(2).fixedSize(horizontal:false,vertical:true)
   }
   Spacer(minLength:4)
   TimelineView(.periodic(from:.now,by:1)) { timeline in
    Text(deckCrewTimer(member,timeline.date)).font(DeckMono.font(10.5)).foregroundStyle(HubTheme.sage)
   }
  }
  .padding(.vertical,7)
  .overlay(alignment:.bottom) { Rectangle().fill(HubTheme.line.opacity(0.6)).frame(height:1) }
  .accessibilityElement(children:.combine)
 }

 func deckCrewTimer(_ member: CrewMember,_ now: Date) -> String {
  switch member.state {
  case .away: return member.awayUntil.map { "back in " + CrewData.timer($0.timeIntervalSince(now)) } ?? "away"
  case .working: return member.since.map { CrewData.timer(now.timeIntervalSince($0)) } ?? ""
  case .idle,.failing: return member.since.map { CrewData.timer(now.timeIntervalSince($0)) } ?? ""
  case .unknown: return "—"
  }
 }
}
