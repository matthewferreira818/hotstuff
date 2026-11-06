import SwiftUI

// The Crew station: a pixel-art station (rooms joined by corridors) with one desk per crew member and a list with timers on the side.
// ALL art here is our own, drawn with plain rectangles. Every character shows only its REAL state, worked out in CrewData.swift from the
// room thread, GitHub's public workflow runs and the robots' snapshots: working at the desk, idle and wandering, away until a date that a
// room message gave, red when its last run failed, or dim with "?" when there is no data. Nothing here can start or change anything.
struct CrewStationView: View {
 let crew: [CrewMember]
 let reduceMotion: Bool

 private struct Room { var name: String; var rect: CGRect; var tint: Color; var kinds: [CrewKind] }
 private let logical = CGSize(width:720,height:430)
 private var rooms: [Room] { [
  Room(name:"CREW ROOM",rect:CGRect(x:16,y:16,width:380,height:196),tint:HubTheme.hex(0x1F2B26),kinds:[.chat,.cloud,.agent]),
  Room(name:"CONTROL ROOM",rect:CGRect(x:424,y:16,width:280,height:196),tint:HubTheme.hex(0x222A2E),kinds:[.watcher,.poster]),
  Room(name:"ROBOT FLOOR",rect:CGRect(x:16,y:244,width:688,height:170),tint:HubTheme.hex(0x262A21),kinds:[.robot]),
 ] }

 // Where each member's desk sits: laid out in rows inside their room.
 private func desks() -> [(member: CrewMember,desk: CGPoint,room: CGRect)] {
  var out: [(CrewMember,CGPoint,CGRect)] = []
  for room in rooms {
   let members = crew.filter { room.kinds.contains($0.kind) }
   let perRow = room.kinds.contains(.robot) ? 7 : 4
   let rowsNeeded = max(1,(members.count + perRow - 1) / perRow)
   let cellW = room.rect.width / CGFloat(perRow)
   let cellH = (room.rect.height - 28) / CGFloat(rowsNeeded)
   for (i,member) in members.enumerated() {
    let col = i % perRow, row = i / perRow
    let point = CGPoint(x:room.rect.minX + cellW * (CGFloat(col) + 0.5),y:room.rect.minY + 30 + cellH * (CGFloat(row) + 0.55))
    out.append((member,point,room.rect))
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

 // A 6 wide by 9 high pixel person, drawn from the feet. `step` swaps the legs; `armsUp` lifts the arms (typing).
 private func person(_ ctx: GraphicsContext,at feet: CGPoint,px: CGFloat,colors: (skin: Color,hair: Color,shirt: Color),step: Bool,armsUp: Bool,tint: Color?,alpha: Double) {
  var c = ctx
  c.opacity = alpha
  func block(_ x: Int,_ y: Int,_ w: Int,_ h: Int,_ color: Color) {
   c.fill(Path(CGRect(x:feet.x + CGFloat(x - 3) * px,y:feet.y - CGFloat(9 - y) * px,width:CGFloat(w) * px,height:CGFloat(h) * px)),with:.color(tint ?? color))
  }
  block(1,0,4,1,colors.hair)            // hair
  block(1,1,4,3,colors.skin)            // face
  block(1,2,1,1,HubTheme.hex(0x101413)) // eyes
  block(4,2,1,1,HubTheme.hex(0x101413))
  block(1,4,4,3,colors.shirt)           // body
  block(armsUp ? 0 : 0,armsUp ? 3 : 4,1,armsUp ? 2 : 3,colors.skin)
  block(5,armsUp ? 3 : 4,1,armsUp ? 2 : 3,colors.skin)
  block(1,7,2,2,HubTheme.hex(0x2A3566)) // legs
  block(3,7,2,2,HubTheme.hex(0x2A3566))
  if step { block(1,8,2,1,HubTheme.hex(0x1B2244)) } else { block(3,8,2,1,HubTheme.hex(0x1B2244)) }
 }

 var body: some View {
  TimelineView(.animation(minimumInterval:1.0 / 8.0,paused:reduceMotion)) { timeline in
   let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
   Canvas { ctx, size in
    let scale = min(size.width / logical.width,size.height / logical.height)
    // The camera glides very slowly (a few points), so the station feels alive without being busy.
    let drift = CGPoint(x:sin(t * 0.07) * 5,y:cos(t * 0.05) * 3)
    var g = ctx
    g.translateBy(x:(size.width - logical.width * scale) / 2 + drift.x * scale,y:(size.height - logical.height * scale) / 2 + drift.y * scale)
    g.scaleBy(x:scale,y:scale)
    // corridors
    let hall = HubTheme.hex(0x181D1B)
    for r in [CGRect(x:150,y:212,width:34,height:32),CGRect(x:540,y:212,width:34,height:32),CGRect(x:396,y:90,width:28,height:34)] { g.fill(Path(r),with:.color(hall)) }
    for r in [CGRect(x:150,y:212,width:34,height:32),CGRect(x:540,y:212,width:34,height:32)] {
     g.stroke(Path { p in p.move(to:CGPoint(x:r.midX,y:r.minY)); p.addLine(to:CGPoint(x:r.midX,y:r.maxY)) },with:.color(HubTheme.line),style:StrokeStyle(lineWidth:1,dash:[3,3]))
    }
    for room in rooms {
     g.fill(Path(roundedRect:room.rect,cornerRadius:4),with:.color(room.tint))
     // floor tiles
     var x = room.rect.minX
     while x < room.rect.maxX { g.stroke(Path { p in p.move(to:CGPoint(x:x,y:room.rect.minY)); p.addLine(to:CGPoint(x:x,y:room.rect.maxY)) },with:.color(Color.white.opacity(0.03)),lineWidth:1); x += 20 }
     g.stroke(Path(roundedRect:room.rect,cornerRadius:4),with:.color(HubTheme.hex(0x44524B)),lineWidth:2)
     g.draw(Text(room.name).font(.system(size:9,weight:.bold,design:.monospaced)).foregroundColor(HubTheme.sage),at:CGPoint(x:room.rect.minX + 10,y:room.rect.minY + 11),anchor:.leading)
    }
    for entry in desks() {
     let m = entry.member
     let colors = palette(m.name)
     let d = entry.desk
     let flash = (Int(t * 2) % 2 == 0)
     func drawDesk() {
       // desk + monitor
       let deskRect = CGRect(x:d.x - 20,y:d.y - 6,width:40,height:14)
       g.fill(Path(roundedRect:deskRect,cornerRadius:2),with:.color(HubTheme.hex(0x3A4640)))
       var screen = HubTheme.hex(0x101413)
       switch m.state {
       case .working: screen = HubTheme.green.opacity(0.85)
       case .failing: screen = flash ? Color(red:0.95,green:0.3,blue:0.3) : HubTheme.hex(0x5A1E1E)
       case .idle: screen = HubTheme.hex(0x2C3A33)
       case .away: screen = HubTheme.hex(0x1A2230)
       case .unknown: screen = HubTheme.hex(0x181D1B)
       }
       g.fill(Path(CGRect(x:d.x - 8,y:d.y - 18,width:16,height:11)),with:.color(HubTheme.hex(0x0C100E)))
       g.fill(Path(CGRect(x:d.x - 7,y:d.y - 17,width:14,height:9)),with:.color(screen))
     }
     let px: CGFloat = 3.0
     let phase = t * 1.3 + seed(m.id)
     if m.state != .working { drawDesk() }
     switch m.state {
     case .working:
      person(g,at:CGPoint(x:d.x,y:d.y + 22),px:px,colors:colors,step:false,armsUp:Int(t * 4 + seed(m.id)) % 2 == 0,tint:nil,alpha:1)
      drawDesk()
     case .idle:
      let range = (entry.room.width - 70) / 2.6
      let wx = sin(phase * 0.35) * range * 0.55
      let wy = abs(sin(phase * 0.21)) * 14
      let feetX = min(max(d.x + wx,entry.room.minX + 12),entry.room.maxX - 12)
      let feetY = min(d.y + 32 + wy,entry.room.maxY - 14)
      person(g,at:CGPoint(x:feetX,y:feetY),px:px,colors:colors,step:Int(phase * 3) % 2 == 0,armsUp:false,tint:nil,alpha:1)
     case .away:
      person(g,at:CGPoint(x:d.x,y:d.y + 22),px:px,colors:colors,step:false,armsUp:false,tint:HubTheme.blue.opacity(0.6),alpha:0.45)
      g.draw(Text("zZ").font(.system(size:9,weight:.bold,design:.monospaced)).foregroundColor(HubTheme.blue),at:CGPoint(x:d.x + 14,y:d.y - 14 - CGFloat(Int(t) % 3)),anchor:.center)
     case .failing:
      person(g,at:CGPoint(x:d.x,y:d.y + 22),px:px,colors:colors,step:false,armsUp:flash,tint:flash ? Color(red:1,green:0.4,blue:0.4) : nil,alpha:1)
      g.draw(Text("!").font(.system(size:13,weight:.heavy,design:.monospaced)).foregroundColor(Color(red:1,green:0.35,blue:0.35)),at:CGPoint(x:d.x + 15,y:d.y - 16),anchor:.center)
     case .unknown:
      person(g,at:CGPoint(x:d.x,y:d.y + 22),px:px,colors:colors,step:false,armsUp:false,tint:HubTheme.sage.opacity(0.4),alpha:0.35)
      g.draw(Text("?").font(.system(size:11,weight:.bold,design:.monospaced)).foregroundColor(HubTheme.sage),at:CGPoint(x:d.x + 14,y:d.y - 14),anchor:.center)
     }
     g.draw(Text(m.name.count > 14 ? String(m.name.prefix(13)) + "…" : m.name).font(.system(size:9,weight:.medium,design:.monospaced)).foregroundColor(HubTheme.text.opacity(0.9)),at:CGPoint(x:d.x,y:d.y + 40),anchor:.top)
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
