import SwiftUI

// The Crew station: a pixel-art station with Friday at the core, four rooms off one hallway, and a desk per crew member, with a list
// beside it. ALL art here is our own, drawn with plain rectangles. What a character does on screen is only what the evidence says
// (CrewData.swift + PixelCrew.swift): typing at the desk = a post or commit in the last 30 min; walking over to someone = a message
// to them in the last 15 min; asleep at the desk = no sign of work; dim with an "away until" sign = a room message said so; red alarm =
// its last run failed; dim with "?" = no data. Click a character for one plain line and a link. Nothing here can start or change anything.
struct CrewStationView: View {
 let crew: [CrewMember]
 let visits: [PixelVisit]
 let reduceMotion: Bool
 @ObservedObject var pick = PixelCrewModel.shared

 struct Room { var name: String; var rect: CGRect; var tint: Color; var perRow: Int; var door: CGPoint; var has: (CrewMember) -> Bool }
 struct Spot { var member: CrewMember; var desk: CGPoint; var door: CGPoint? }
 struct Place { var feet: CGPoint; var walking: Bool; var talking: Bool; var away: Bool }

 static let logical = CGSize(width:760,height:640)
 static let core = CGPoint(x:380,y:320)
 static let coreRadius: CGFloat = 44
 static let hallY: CGFloat = 320
 static let rooms: [Room] = [
  Room(name:"BRIDGE · LOCAL CLAUDE CHATS",rect:CGRect(x:12,y:12,width:470,height:262),tint:HubTheme.hex(0x1F2B26),perRow:5,door:CGPoint(x:200,y:282),has:{ $0.kind == .chat }),
  Room(name:"AI LOUNGE",rect:CGRect(x:498,y:12,width:250,height:262),tint:HubTheme.hex(0x2A2330),perRow:2,door:CGPoint(x:623,y:282),has:{ $0.kind == .cloud || $0.kind == .agent }),
  Room(name:"TRADING FLOOR · PRACTICE MONEY",rect:CGRect(x:12,y:366,width:470,height:262),tint:HubTheme.hex(0x262A21),perRow:4,door:CGPoint(x:200,y:358),has:{ $0.kind == .robot }),
  Room(name:"ENGINE ROOM",rect:CGRect(x:498,y:366,width:250,height:262),tint:HubTheme.hex(0x222A2E),perRow:3,door:CGPoint(x:623,y:358),has:{ $0.kind == .watcher || $0.kind == .poster }),
 ]

 // Desks: Friday at the core, everyone else in their room, at most two rows per room (a busy room gets narrower desks instead).
 static func spots(_ crew: [CrewMember]) -> [Spot] {
  var out: [Spot] = []
  if let friday = crew.first(where:{ $0.kind == .friday }) { out.append(Spot(member:friday,desk:core,door:nil)) }
  for room in rooms {
   let members = crew.filter { room.has($0) }
   if members.isEmpty { continue }
   let perRow = max(room.perRow,(members.count + 1) / 2)
   let rows = max(1,(members.count + perRow - 1) / perRow)
   let cellW = room.rect.width / CGFloat(perRow)
   let cellH = (room.rect.height - 30) / CGFloat(rows)
   for (i,member) in members.enumerated() {
    let col = CGFloat(i % perRow), row = CGFloat(i / perRow)
    out.append(Spot(member:member,desk:CGPoint(x:room.rect.minX + cellW * (col + 0.5),y:room.rect.minY + 30 + cellH * (row + 0.42)),door:room.door))
   }
  }
  return out
 }

 private static func seed(_ text: String) -> Double { Double(text.unicodeScalars.reduce(7) { ($0 * 31 + Int($1.value)) % 9973 }) }

 // A point a fraction of the way along a path of straight legs.
 static func along(_ path: [CGPoint],_ f: Double) -> CGPoint {
  guard path.count > 1 else { return path.first ?? .zero }
  var legs: [Double] = []
  for i in 1..<path.count { legs.append(Double(hypot(path[i].x - path[i - 1].x,path[i].y - path[i - 1].y))) }
  var left = max(0,min(1,f)) * legs.reduce(0,+)
  for i in 1..<path.count {
   if left <= legs[i - 1] || i == path.count - 1 {
    let k = legs[i - 1] > 0 ? CGFloat(min(1,left / legs[i - 1])) : 1
    return CGPoint(x:path[i - 1].x + (path[i].x - path[i - 1].x) * k,y:path[i - 1].y + (path[i].y - path[i - 1].y) * k)
   }
   left -= legs[i - 1]
  }
  return path[path.count - 1]
 }

 // Where a character stands right now. A visitor follows the hallway: out of its room, along the hall, into the other room.
 func place(_ s: Spot,all: [Spot],t: Double) -> Place {
  let home = seated(s.member) ? CGPoint(x:s.desk.x,y:s.desk.y + 38) : CGPoint(x:s.desk.x + 36,y:s.desk.y + 16)
  guard !reduceMotion, s.member.kind != .friday, let v = visits.first(where:{ $0.from == s.member.id }),
        let target = all.first(where:{ $0.member.id == v.to }) else { return Place(feet:home,walking:false,talking:false,away:false) }
  let w = PixelCrew.walk(t + Self.seed(s.member.id).truncatingRemainder(dividingBy:20))
  if w.progress == 0 && !w.walking { return Place(feet:home,walking:false,talking:false,away:false) }
  let start = CGPoint(x:s.desk.x,y:s.desk.y + 44)
  let end = target.member.kind == .friday ? CGPoint(x:Self.core.x + 64,y:Self.core.y + 22) : CGPoint(x:target.desk.x + 30,y:target.desk.y + 44)
  var path = [start]
  if let door = s.door, door != target.door {
   path += [door,CGPoint(x:door.x,y:Self.hallY + 16)]
   if let other = target.door { path += [CGPoint(x:other.x,y:Self.hallY + 16),other] }
  }
  path.append(end)
  return Place(feet:Self.along(path,w.progress),walking:w.walking,talking:w.talking,away:true)
 }

 private func palette(_ name: String) -> (skin: Color,hair: Color,shirt: Color) {
  let s = Int(Self.seed(name))
  let skins = [HubTheme.hex(0xF1C27D),HubTheme.hex(0xC68642),HubTheme.hex(0xE0AC69),HubTheme.hex(0x8D5524),HubTheme.hex(0xFFDBAC)]
  let hairs = [HubTheme.hex(0x2C1B10),HubTheme.hex(0x111111),HubTheme.hex(0xA0522D),HubTheme.hex(0xD9B13B),HubTheme.hex(0x5A3A1A)]
  let shirts = [HubTheme.hex(0x6B9FFF),HubTheme.hex(0xE88A5A),HubTheme.hex(0x87C895),HubTheme.hex(0xC58BE0),HubTheme.hex(0xDDB66D),HubTheme.hex(0x83C9C0)]
  return (skins[s % skins.count],hairs[(s / 5) % hairs.count],shirts[(s / 25) % shirts.count])
 }

 private enum Look { case person, ghost, eyeBot, antennaBot, boxBot, loopBot }
 private func look(_ m: CrewMember) -> Look {
  switch m.id {
  case "Roxy": return .ghost
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
   return list[Int(Self.seed(m.id)) % list.count]
  }
 }

 // One sprite, drawn from the feet up on a grid of `px` points. Every look is our own: people with their job's tool in hand, a ghost,
 // small robots. Each Local Claude chat carries its own tool, so no two look alike.
 private func figure(_ ctx: GraphicsContext,_ m: CrewMember,at feet: CGPoint,px: CGFloat,step: Bool,armsUp: Bool,dim: Double,flash: Bool,t: Double,asleep: Bool = false) {
  var c = ctx
  c.opacity = dim
  let ink = HubTheme.hex(0x101413)
  func block(_ x: Int,_ y: Int,_ w: Int,_ h: Int,_ color: Color) {
   c.fill(Path(CGRect(x:feet.x + CGFloat(x - 3) * px,y:feet.y - CGFloat(10 - y) * px,width:CGFloat(w) * px,height:CGFloat(h) * px)),with:.color(color))
  }
  func shut(_ x: Int,_ y: Int) {   // a closed eye: a thin line instead of a square
   c.fill(Path(CGRect(x:feet.x + CGFloat(x - 3) * px,y:feet.y - CGFloat(10 - y) * px + px * 0.55,width:px,height:px * 0.35)),with:.color(ink))
  }
  let body = m.state == .failing && flash ? Color(red:1,green:0.4,blue:0.4) : tint(m)
  switch look(m) {
  case .person:
   let col = palette(m.name)
   let hair = m.id == "Grok" ? HubTheme.hex(0x15151B) : col.hair
   let style = Int(Self.seed(m.name + "hair")) % 3
   block(1,1,4,1,hair)
   if style == 1 { block(1,0,1,1,hair); block(3,0,1,1,hair); block(4,0,1,1,hair) }     // spiky
   if style == 2 { block(0,1,1,4,hair); block(5,1,1,4,hair) }                          // long
   block(1,2,4,3,col.skin)
   if asleep { shut(1,3); shut(4,3) } else { block(1,3,1,1,ink); block(4,3,1,1,ink) }
   if m.id == "Cloud Claude" { block(0,0,2,1,.white); block(2,-1,3,2,.white); block(4,0,2,1,.white) }                                       // cloud hat
   block(1,5,4,3,m.id == "Grok" ? HubTheme.hex(0x2E2E38) : body)
   if m.id == "Grok" { block(5,5,1,1,HubTheme.hex(0xFFD84D)); block(4,6,1,1,HubTheme.hex(0xFFD84D)); block(5,7,1,1,HubTheme.hex(0xFFD84D)) } // bolt
   if m.id == "facebook" { block(5,4,2,2,HubTheme.hex(0x4D8DFF)) }                                                                           // megaphone
   if m.id == "tiktok" { block(5,4,1,3,HubTheme.hex(0x83C9C0)); block(6,4,1,1,HubTheme.hex(0xFF5D8F)) }                                     // note
   if m.kind == .chat {
    let pink = HubTheme.hex(0xFF5D8F), grey = HubTheme.hex(0xA9B4B0)
    switch CrewSignals.canon(m.name) {
    case "lc-manager": block(5,4,2,3,.white); block(5,4,2,1,HubTheme.amber)                                        // clipboard
    case "lc-tiktok": block(5,4,1,3,HubTheme.hex(0x83C9C0)); block(6,4,1,1,pink)                                   // music note
    case "lc-helm-build": block(5,5,1,3,grey); block(5,4,2,1,grey)                                                 // wrench
    case "lc-helm": block(5,3,1,4,HubTheme.hex(0xFFD84D)); block(5,7,1,1,pink)                                     // pencil
    case "lc-makeover": block(5,4,1,3,HubTheme.hex(0x8A5A3A)); block(5,3,1,1,pink)                                 // paintbrush
    case "lc-trends": block(5,6,1,1,HubTheme.green); block(6,5,1,1,HubTheme.green); block(7,4,1,1,HubTheme.green)  // arrow up
    case "lc-work": block(5,5,3,2,.white); block(6,5,1,1,grey)                                                     // envelope
    case "lc-crewstate": block(5,4,2,2,HubTheme.green.opacity(Int(t * 2) % 2 == 0 ? 1 : 0.45))                     // signal light
    case "lc-pixels": block(5,4,1,1,Color(red:0.95,green:0.35,blue:0.4)); block(6,4,1,1,HubTheme.hex(0xFFD84D)); block(5,5,1,1,HubTheme.blue); block(6,5,1,1,HubTheme.green) // pixels
    default: block(2,6,2,1,HubTheme.amber)                                                                         // plain badge
    }
   }
   block(0,armsUp ? 4 : 5,1,armsUp ? 2 : 3,col.skin); block(5,armsUp ? 4 : 5,1,armsUp ? 2 : 3,col.skin)
   block(1,8,2,2,HubTheme.hex(0x2A3566)); block(3,8,2,2,HubTheme.hex(0x2A3566))
   if step { block(1,9,2,1,HubTheme.hex(0x1B2244)) } else { block(3,9,2,1,HubTheme.hex(0x1B2244)) }
  case .ghost:
   let w = HubTheme.hex(0xE8ECF5)
   block(1,1,4,1,w); block(0,2,6,6,w)
   if asleep { shut(1,3); shut(4,3) } else { block(1,3,1,2,ink); block(4,3,1,2,ink) }
   let wave = Int(t * 2) % 2
   block(0,8,2,1,w); block(2,8 + wave,2,1,w); block(4,8,2,1,w)
   block(0,armsUp ? 4 : 6,1,1,w.opacity(0.7)); block(5,armsUp ? 4 : 6,1,1,w.opacity(0.7))
  case .eyeBot:
   block(0,2,6,5,HubTheme.hex(0x7E8AA6)); block(1,3,4,3,.white)
   if asleep { shut(2,4); shut(3,4) } else { block(2,4,2,1,m.state == .failing ? Color.red : HubTheme.hex(0x2E6B5A)) }
   block(1,7,4,2,HubTheme.hex(0x5A6680)); block(1,9,1,1,ink); block(4,9,1,1,ink)
  case .antennaBot:
   block(3,0,1,2,HubTheme.sage); block(2,0,1,1,asleep ? HubTheme.hex(0x5A4A2A) : HubTheme.amber)
   block(1,2,4,3,HubTheme.hex(0x9FC3D9))
   if asleep { shut(1,3); shut(4,3) } else { block(1,3,1,1,ink); block(4,3,1,1,ink) }
   block(0,5,6,3,HubTheme.hex(0x6D93AB)); block(1,8,2,2,ink); block(3,8,2,2,ink)
  case .boxBot:
   block(2,1,2,1,body); block(1,2,4,3,body.opacity(0.9))
   if asleep { shut(1,3); shut(4,3) } else { block(1,3,1,1,ink); block(4,3,1,1,ink) }
   block(0,5,6,3,body); block(2,6,2,1,.white.opacity(0.7))
   block(1,8,1,2,ink); block(4,8,1,2,ink)
   if step { block(1,9,2,1,ink) } else { block(3,9,2,1,ink) }
  case .loopBot:
   let b = HubTheme.hex(0xC9B49A)
   block(1,2,4,5,b)
   if asleep { shut(2,3); shut(3,3) } else { block(2,3,2,1,ink) }
   block(2,5,2,1,ink); block(1,7,4,2,HubTheme.hex(0x9A7F66)); block(1,9,1,1,ink); block(4,9,1,1,ink)
   if !asleep { block(Int(t * 3) % 2 == 0 ? 5 : 0,4,1,1,HubTheme.amber) }
  }
 }

 // Friday at the core: her crimson orb. Working (live, or a post of hers in the last 30 min) = bright and pulsing, teal ring only while
 // her voice session is live; otherwise dim, slow breathing, asleep.
 private func drawFriday(_ g: GraphicsContext,_ m: CrewMember,t: Double) {
  let c = Self.core
  let awake = m.state == .working
  let live = m.detail.hasPrefix("live")
  let breath = awake ? 0.8 + 0.2 * sin(t * 3) : 0.55 + 0.1 * sin(t * 0.8)
  for (r,a) in [(30.0,0.18),(24.0,0.3),(18.0,0.5)] {
   let rr = CGFloat(r * (awake ? 1 + 0.06 * sin(t * 3) : 1))
   g.fill(Path(ellipseIn:CGRect(x:c.x - rr,y:c.y - rr,width:rr * 2,height:rr * 2)),with:.color(Noir.crimson.opacity(a * breath)))
  }
  g.fill(Path(ellipseIn:CGRect(x:c.x - 12,y:c.y - 12,width:24,height:24)),with:.color(Noir.crimsonLight.opacity(awake ? 1 : 0.55)))
  g.fill(Path(ellipseIn:CGRect(x:c.x - 5,y:c.y - 5,width:10,height:10)),with:.color(Color.white.opacity(awake ? 0.95 : 0.4)))
  if live { g.stroke(Path(ellipseIn:CGRect(x:c.x - 36,y:c.y - 36,width:72,height:72)),with:.color(HubTheme.hex(0x5FD3C6).opacity(0.85)),lineWidth:2) }
  if !awake { g.draw(Text("z").font(.system(size:11,weight:.bold,design:.monospaced)).foregroundColor(HubTheme.sage),at:CGPoint(x:c.x + 22,y:c.y - 26 - CGFloat(Int(t) % 3) * 3),anchor:.center) }
 }

 // MARK: the deck (our own art, in the spirit of a top-down sci-fi station: metal hull, tiled floors, bulkheads, workstations)

 // People sit at their desk with their back to us; robots, the ghost and the watchers stand beside it.
 func seated(_ m: CrewMember) -> Bool { look(m) == .person }

 private static func hx(_ v: UInt32) -> Color { HubTheme.hex(v) }
 private static let floorA = hx(0x1F2023), floorB = hx(0x1B1C1F), seam = hx(0x121315)
 private static let wall = hx(0x2C2E33), wallHi = hx(0x4B4E55), wallLo = hx(0x151618)
 private static let metal = hx(0x34363B), metalHi = hx(0x4C4F56), metalLo = hx(0x1C1D21)
 private static let screenOn = hx(0x5FE0EE), hazard = hx(0xB89A4E)

 private func rect(_ g: GraphicsContext,_ x: CGFloat,_ y: CGFloat,_ w: CGFloat,_ h: CGFloat,_ c: Color) { g.fill(Path(CGRect(x:x,y:y,width:w,height:h)),with:.color(c)) }

 // A tiled floor: 32-point plates, each a touch lighter or darker, with seams and corner bolts.
 private func floor(_ g: GraphicsContext,_ r: CGRect) {
  let tile: CGFloat = 32
  var y = r.minY
  while y < r.maxY {
   var x = r.minX
   while x < r.maxX {
    let w = min(tile,r.maxX - x), h = min(tile,r.maxY - y)
    let k = Int(Self.seed("\(Int(x))-\(Int(y))")) % 3
    rect(g,x,y,w,h,k == 0 ? Self.floorA : Self.floorB)
    rect(g,x,y,w,1,Self.seam); rect(g,x,y,1,h,Self.seam)
    rect(g,x + 1,y + 1,w - 2,1,Color.white.opacity(0.025))
    if w > 6 && h > 6 { rect(g,x + 3,y + 3,1.5,1.5,Self.hx(0x2C2D31)); rect(g,x + w - 4.5,y + h - 4.5,1.5,1.5,Self.hx(0x2C2D31)) }
    x += tile
   }
   y += tile
  }
 }

 // A bulkhead band with a lit top edge and a shadowed bottom edge.
 private func bulkhead(_ g: GraphicsContext,_ r: CGRect) {
  rect(g,r.minX,r.minY,r.width,r.height,Self.wall)
  rect(g,r.minX,r.minY,r.width,1.5,Self.wallHi)
  rect(g,r.minX,r.maxY - 2,r.width,2,Self.wallLo)
 }

 private func plant(_ g: GraphicsContext,_ x: CGFloat,_ y: CGFloat) {
  g.fill(Path(ellipseIn:CGRect(x:x - 9,y:y + 6,width:18,height:6)),with:.color(Color.black.opacity(0.35)))
  rect(g,x - 6,y - 2,12,9,Self.hx(0x4A3A2B)); rect(g,x - 6,y - 2,12,2,Self.hx(0x5E4B38))
  let leaf = Self.hx(0x3F8A4F), dark = Self.hx(0x2B6338)
  for (dx,dy,c) in [(-8.0,-10.0,dark),(-4.0,-16.0,leaf),(2.0,-14.0,leaf),(5.0,-8.0,dark),(-2.0,-8.0,leaf),(-10.0,-5.0,leaf),(7.0,-15.0,dark),(0.0,-20.0,leaf)] {
   rect(g,x + CGFloat(dx),y + CGFloat(dy),5,5,c)
  }
 }

 private func cabinet(_ g: GraphicsContext,_ x: CGFloat,_ y: CGFloat,t: Double) {
  rect(g,x,y,18,34,Self.hx(0x17181B)); rect(g,x,y,18,1.5,Self.metalHi); rect(g,x + 17,y,1,34,Self.metalLo)
  for i in 0..<4 {
   rect(g,x + 3,y + 4 + CGFloat(i) * 7,12,4,Self.hx(0x222428))
   let on = (Int(t * 1.3 + Double(i) * 1.7 + Double(x)) % 4) != 0
   rect(g,x + 12,y + 5 + CGFloat(i) * 7,2,2,on ? HubTheme.hex(0x3FD8A0).opacity(0.85) : HubTheme.hex(0x1E3A30))
  }
 }

 private func dish(_ g: GraphicsContext,_ x: CGFloat,_ y: CGFloat) {
  g.fill(Path(ellipseIn:CGRect(x:x - 13,y:y + 10,width:26,height:7)),with:.color(Color.black.opacity(0.35)))
  rect(g,x - 2,y,4,12,Self.metal)
  g.fill(Path(ellipseIn:CGRect(x:x - 14,y:y - 18,width:28,height:22)),with:.color(Self.hx(0xB9BDC5)))
  g.fill(Path(ellipseIn:CGRect(x:x - 10,y:y - 15,width:20,height:15)),with:.color(Self.hx(0x8E939C)))
  rect(g,x - 1,y - 12,2,7,Self.hx(0x5C6068))
 }

 private func wallPanels(_ g: GraphicsContext,_ r: CGRect,t: Double) {
  var x = r.minX + 10
  var i = 0
  while x + 30 < r.maxX - 6 {
   rect(g,x,r.minY + 3,30,r.height - 6,Self.hx(0x25272B)); rect(g,x,r.minY + 3,30,1,Self.hx(0x3A3D43))
   let blink = (Int(t * 0.9 + Double(i) * 2.3) % 5) != 0
   rect(g,x + 24,r.minY + 6,3,2,(i % 3 == 0 ? HubTheme.hex(0x3FD8A0) : HubTheme.hex(0x5FA8D3)).opacity(blink ? 0.75 : 0.2))
   x += 40; i += 1
  }
 }

 private func drawRooms(_ g: GraphicsContext,t: Double) {
  let L = Self.logical
  // the hull: a chamfered metal frame with rivets
  rect(g,0,0,L.width,L.height,Self.hx(0x09090B))
  let c: CGFloat = 22
  let hull = Path { p in
   p.move(to:CGPoint(x:c,y:2)); p.addLine(to:CGPoint(x:L.width - c,y:2)); p.addLine(to:CGPoint(x:L.width - 2,y:c))
   p.addLine(to:CGPoint(x:L.width - 2,y:L.height - c)); p.addLine(to:CGPoint(x:L.width - c,y:L.height - 2)); p.addLine(to:CGPoint(x:c,y:L.height - 2))
   p.addLine(to:CGPoint(x:2,y:L.height - c)); p.addLine(to:CGPoint(x:2,y:c)); p.closeSubpath()
  }
  g.fill(hull,with:.color(Self.hx(0x26272B)))
  g.stroke(hull,with:.color(Self.hx(0x4A4D54)),lineWidth:2)
  var rx: CGFloat = 30
  while rx < L.width - 30 { rect(g,rx,6,2,2,Self.hx(0x5A5D64)); rect(g,rx,L.height - 8,2,2,Self.hx(0x5A5D64)); rx += 26 }
  var ry: CGFloat = 30
  while ry < L.height - 30 { rect(g,6,ry,2,2,Self.hx(0x5A5D64)); rect(g,L.width - 8,ry,2,2,Self.hx(0x5A5D64)); ry += 26 }

  // the hallway: a grated walkway with rails and hazard edges
  let hall = CGRect(x:12,y:Self.hallY - 30,width:736,height:60)
  rect(g,hall.minX,hall.minY,hall.width,hall.height,Self.hx(0x18191C))
  var gy = hall.minY + 8
  while gy < hall.maxY - 8 { rect(g,hall.minX,gy,hall.width,1.5,Self.hx(0x222327)); gy += 5 }
  var tx = hall.minX
  while tx < hall.maxX { rect(g,tx,hall.minY,6,5,Self.metal); rect(g,tx,hall.maxY - 5,6,5,Self.metal); rect(g,tx,hall.minY,6,1,Self.metalHi); tx += 10 }

  for room in Self.rooms {
   let r = room.rect
   floor(g,r)
   // bulkheads: a thick top wall with panels, thin side and bottom walls
   let top = CGRect(x:r.minX,y:r.minY,width:r.width,height:22)
   bulkhead(g,top); wallPanels(g,top,t:t)
   bulkhead(g,CGRect(x:r.minX,y:r.minY,width:5,height:r.height)); bulkhead(g,CGRect(x:r.maxX - 5,y:r.minY,width:5,height:r.height))
   bulkhead(g,CGRect(x:r.minX,y:r.maxY - 5,width:r.width,height:5))
   // the doorway onto the hall, with hazard stripes on the sill
   let below = r.minY > Self.hallY
   let gap = below ? CGRect(x:room.door.x - 18,y:hall.maxY,width:36,height:r.minY - hall.maxY + 23)
                   : CGRect(x:room.door.x - 18,y:r.maxY - 6,width:36,height:hall.minY - r.maxY + 7)
   rect(g,gap.minX,gap.minY,gap.width,gap.height,Self.hx(0x18191C))
   let sill = below ? gap.maxY - 4 : gap.minY
   var hxp = gap.minX
   var on = true
   while hxp < gap.maxX { rect(g,hxp,sill,4,4,on ? Self.hazard.opacity(0.55) : Self.hx(0x141416)); hxp += 4; on.toggle() }
   g.draw(Text(room.name).font(.system(size:8,weight:.bold,design:.monospaced)).foregroundColor(Self.hx(0x9A9EA6)),at:CGPoint(x:r.minX + 10,y:r.minY + 11),anchor:.leading)
  }
  // props: our own, decoration only (they show no numbers)
  plant(g,32,326); plant(g,728,326)        // the two ends of the hallway
  plant(g,452,604)                           // trading floor, bottom-right corner
  dish(g,700,232)                            // AI lounge, bottom-right corner
  for i in 0..<3 { cabinet(g,676 + CGFloat(i) * 22,560,t:t) }   // engine room, bottom-right corner

  // Friday's core: a reactor pad on the hallway
  let fc = Self.core, fr = Self.coreRadius
  g.fill(Path(ellipseIn:CGRect(x:fc.x - fr - 4,y:fc.y - fr - 4,width:(fr + 4) * 2,height:(fr + 4) * 2)),with:.color(Self.metalLo))
  g.fill(Path(ellipseIn:CGRect(x:fc.x - fr,y:fc.y - fr,width:fr * 2,height:fr * 2)),with:.color(Self.hx(0x2A2B30)))
  g.stroke(Path(ellipseIn:CGRect(x:fc.x - fr,y:fc.y - fr,width:fr * 2,height:fr * 2)),with:.color(Self.metalHi),lineWidth:1.5)
  for k in 0..<8 {
   let a = Double(k) * .pi / 4
   rect(g,fc.x + CGFloat(cos(a)) * (fr - 5) - 1.5,fc.y + CGFloat(sin(a)) * (fr - 5) - 1.5,3,3,Self.hx(0x5A5D64))
  }
  g.fill(Path(ellipseIn:CGRect(x:fc.x - fr + 9,y:fc.y - fr + 9,width:(fr - 9) * 2,height:(fr - 9) * 2)),with:.color(Self.hx(0x121214)))
 }

 private func screenColor(_ m: CrewMember,flash: Bool) -> Color {
  switch m.state {
  case .working: return Self.screenOn
  case .failing: return flash ? Color(red:0.95,green:0.3,blue:0.3) : Self.hx(0x5A1E1E)
  case .idle: return Self.hx(0x16252A)
  case .away: return Self.hx(0x111418)
  case .unknown: return Self.hx(0x101113)
  }
 }

 // A workstation seen from above: desk, monitor at the back, keyboard, a small thing of theirs, and a chair in front.
 private func drawDesk(_ g: GraphicsContext,_ d: CGPoint,_ m: CrewMember,flash: Bool,t: Double) {
  g.fill(Path(ellipseIn:CGRect(x:d.x - 34,y:d.y + 4,width:68,height:16)),with:.color(Color.black.opacity(0.35)))
  if m.state == .working { g.fill(Path(ellipseIn:CGRect(x:d.x - 38,y:d.y - 34,width:76,height:56)),with:.color(Self.screenOn.opacity(0.08))) }
  rect(g,d.x - 30,d.y - 12,60,22,Self.metal)
  rect(g,d.x - 30,d.y - 12,60,1.5,Self.metalHi)
  rect(g,d.x - 30,d.y + 7,60,3,Self.metalLo)
  // monitor
  rect(g,d.x - 15,d.y - 26,30,17,Self.hx(0x111215))
  let sc = screenColor(m,flash:flash)
  rect(g,d.x - 13,d.y - 24,26,12,sc)
  if m.state == .working {
   rect(g,d.x - 11,d.y - 22,14,1.5,Self.hx(0x0E3B44).opacity(0.8)); rect(g,d.x - 11,d.y - 19,20,1.5,Self.hx(0x0E3B44).opacity(0.8))
   rect(g,d.x - 11,d.y - 16,CGFloat(6 + Int(t * 4) % 12),1.5,Self.hx(0x0E3B44).opacity(0.8))
  }
  rect(g,d.x - 3,d.y - 9,6,2,Self.hx(0x0D0E10))
  // keyboard
  rect(g,d.x - 11,d.y - 5,22,5,Self.hx(0x1F2125))
  var kx = d.x - 10
  while kx < d.x + 10 { rect(g,kx,d.y - 4,1.5,1.2,Self.hx(0x3A3D44)); rect(g,kx,d.y - 2,1.5,1.2,Self.hx(0x3A3D44)); kx += 3 }
  // a small thing of theirs (mug or papers), the same each time
  if Int(Self.seed(m.id)) % 2 == 0 { rect(g,d.x + 18,d.y - 8,5,5,Self.hx(0xD9D6CF)); rect(g,d.x + 23,d.y - 7,1.5,3,Self.hx(0xD9D6CF)) }
  else { rect(g,d.x - 27,d.y - 9,9,7,Self.hx(0xC9C6BC)); rect(g,d.x - 26,d.y - 7,6,1,Self.hx(0x8E8B84)) }
  // chair seat
  if seated(m) || m.state == .away || m.state == .unknown {
   g.fill(Path(roundedRect:CGRect(x:d.x - 10,y:d.y + 14,width:20,height:13),cornerRadius:3),with:.color(Self.hx(0x26282D)))
  }
 }

 // The chair back, drawn over a seated person's lower back.
 private func chairBack(_ g: GraphicsContext,_ d: CGPoint) {
  g.fill(Path(roundedRect:CGRect(x:d.x - 12,y:d.y + 25,width:24,height:8),cornerRadius:2),with:.color(Self.hx(0x30333A)))
  rect(g,d.x - 11,d.y + 25,22,1.2,Self.hx(0x4C5058))
  rect(g,d.x - 1.5,d.y + 33,3,4,Self.hx(0x1C1D21))
  rect(g,d.x - 8,d.y + 37,16,2,Self.hx(0x1C1D21))
 }

 // A seated person from behind: hair, shoulders, arms forward on the keyboard (typing) or folded with the head down (asleep).
 private func personBack(_ ctx: GraphicsContext,_ m: CrewMember,at feet: CGPoint,px: CGFloat,typing: Bool,asleep: Bool,dim: Double) {
  var c = ctx
  c.opacity = dim
  func block(_ x: Int,_ y: Int,_ w: Int,_ h: Int,_ color: Color) {
   c.fill(Path(CGRect(x:feet.x + CGFloat(x - 3) * px,y:feet.y - CGFloat(10 - y) * px,width:CGFloat(w) * px,height:CGFloat(h) * px)),with:.color(color))
  }
  let col = palette(m.name)
  let hair = m.id == "Grok" ? HubTheme.hex(0x15151B) : col.hair
  let shirt = m.id == "Grok" ? HubTheme.hex(0x2E2E38) : tint(m)
  let drop = asleep ? 1 : 0
  if asleep { block(-1,3,8,2,shirt) }                                         // arms folded on the desk
  else {
   let l = typing && Int(Date().timeIntervalSinceReferenceDate * 6) % 2 == 0 ? 0 : 1
   block(-1,3 + l,1,3,shirt); block(6,4 - l,1,3,shirt)
   block(-1,2 + l,1,1,col.skin); block(6,3 - l,1,1,col.skin)
  }
  block(1,1 + drop,4,3,hair); block(0,2 + drop,1,1,col.skin); block(5,2 + drop,1,1,col.skin)
  if Int(Self.seed(m.name + "hair")) % 3 == 2 { block(1,4 + drop,4,1,hair) }  // long hair
  if m.id == "Cloud Claude" { block(0,0 + drop,2,1,.white); block(2,-1 + drop,3,2,.white); block(4,0 + drop,2,1,.white) }
  block(2,4 + drop,2,1,col.skin)
  block(0,5,6,3,shirt)
  block(0,5,6,1,Color.white.opacity(0.08))
 }

 func draw(_ ctx: GraphicsContext,size: CGSize,t: Double) {
  let scale = min(size.width / Self.logical.width,size.height / Self.logical.height)
  let drift = Self.drift(t)
  var g = ctx
  g.translateBy(x:(size.width - Self.logical.width * scale) / 2 + drift.x * scale,y:(size.height - Self.logical.height * scale) / 2 + drift.y * scale)
  g.scaleBy(x:scale,y:scale)
  drawRooms(g,t:t)
  let all = Self.spots(crew)
  let flash = Int(t * 2) % 2 == 0
  let px: CGFloat = 4
  var walkers: [(Spot,Place)] = []
  for s in all {
   let m = s.member
   let d = s.desk
   if m.kind == .friday { drawFriday(g,m,t:t); continue }
   let p = place(s,all:all,t:t)
   if p.away { drawDesk(g,d,m,flash:flash,t:t); if seated(m) { chairBack(g,d) }; walkers.append((s,p)); continue }
   switch m.state {
   case .working:
    drawDesk(g,d,m,flash:flash,t:t)
    if seated(m) { personBack(g,m,at:p.feet,px:px,typing:true,asleep:false,dim:1); chairBack(g,d) }
    else { figure(g,m,at:p.feet,px:px,step:false,armsUp:Int(t * 4 + Self.seed(m.id)) % 2 == 0,dim:1,flash:flash,t:t) }
   case .idle:
    drawDesk(g,d,m,flash:flash,t:t)
    if seated(m) { personBack(g,m,at:p.feet,px:px,typing:false,asleep:true,dim:0.85); chairBack(g,d) }
    else { figure(g,m,at:p.feet,px:px,step:false,armsUp:false,dim:0.8,flash:flash,t:t,asleep:true) }
    let rise = CGFloat(Int(t * 1.5 + Self.seed(m.id)) % 3) * 4
    g.draw(Text("z").font(.system(size:9,weight:.bold,design:.monospaced)).foregroundColor(HubTheme.sage),at:CGPoint(x:d.x + 25,y:d.y - 28 - rise),anchor:.center)
    g.draw(Text("Z").font(.system(size:11,weight:.bold,design:.monospaced)).foregroundColor(HubTheme.sage.opacity(0.7)),at:CGPoint(x:d.x + 32,y:d.y - 38 - rise),anchor:.center)
   case .away:
    drawDesk(g,d,m,flash:flash,t:t)
    if seated(m) { chairBack(g,d) } else { figure(g,m,at:p.feet,px:px,step:false,armsUp:false,dim:0.3,flash:flash,t:t) }
    let until = m.awayUntil.map { "BACK " + $0.formatted(.dateTime.month(.abbreviated).day()).uppercased() } ?? "AWAY"
    let sign = CGRect(x:d.x - 38,y:d.y + 12,width:76,height:15)
    g.fill(Path(roundedRect:sign,cornerRadius:2),with:.color(HubTheme.hex(0x2B3F66)))
    g.stroke(Path(roundedRect:sign,cornerRadius:2),with:.color(HubTheme.blue),lineWidth:1)
    g.draw(Text("AWAY · " + until).font(.system(size:7,weight:.bold,design:.monospaced)).foregroundColor(.white),at:CGPoint(x:sign.midX,y:sign.midY),anchor:.center)
   case .failing:
    drawDesk(g,d,m,flash:flash,t:t)
    figure(g,m,at:seated(m) ? CGPoint(x:d.x + 36,y:d.y + 16) : p.feet,px:px,step:false,armsUp:flash,dim:1,flash:flash,t:t)
    g.fill(Path(ellipseIn:CGRect(x:d.x - 19,y:d.y - 38,width:10,height:10)),with:.color(flash ? Color(red:1,green:0.2,blue:0.2) : Color(red:0.45,green:0.1,blue:0.1)))
    g.draw(Text("ALARM").font(.system(size:7,weight:.heavy,design:.monospaced)).foregroundColor(Color(red:1,green:0.4,blue:0.4)),at:CGPoint(x:d.x + 2,y:d.y - 33),anchor:.leading)
   case .unknown:
    drawDesk(g,d,m,flash:flash,t:t)
    if seated(m) { chairBack(g,d) } else { figure(g,m,at:p.feet,px:px,step:false,armsUp:false,dim:0.28,flash:flash,t:t) }
    g.draw(Text("?").font(.system(size:13,weight:.bold,design:.monospaced)).foregroundColor(HubTheme.sage),at:CGPoint(x:d.x + 27,y:d.y - 26),anchor:.center)
   }
  }
  // names (and who they messaged) under every desk
  for s in all where s.member.kind != .friday {
   let d = s.desk
   let name = PixelCrew.label(s.member)
   let w = CGFloat(name.count) * 5.6 + 10
   let plate = CGRect(x:d.x - w / 2,y:d.y + 43,width:w,height:12)
   g.fill(Path(roundedRect:plate,cornerRadius:2),with:.color(Self.hx(0x101114).opacity(0.92)))
   g.stroke(Path(roundedRect:plate,cornerRadius:2),with:.color(Self.hx(0x3A3D44)),lineWidth:1)
   g.draw(Text(name).font(.system(size:8.5,weight:.semibold,design:.monospaced)).foregroundColor(Self.hx(0xD3D6DC)),at:CGPoint(x:plate.midX,y:plate.midY),anchor:.center)
   if let v = visits.first(where:{ $0.from == s.member.id }), let to = all.first(where:{ $0.member.id == v.to }) {
    g.draw(Text("✉ → " + PixelCrew.label(to.member)).font(.system(size:7.5,weight:.bold,design:.monospaced)).foregroundColor(HubTheme.hex(0x5FD3C6)),at:CGPoint(x:d.x,y:d.y + 58),anchor:.top)
   }
  }
  if let friday = all.first(where:{ $0.member.kind == .friday }) {
   g.draw(Text("Friday").font(.system(size:9,weight:.semibold,design:.monospaced)).foregroundColor(Noir.crimsonLight),at:CGPoint(x:Self.core.x,y:Self.core.y + Self.coreRadius + 3),anchor:.top)
   if friday.member.state != .working { g.draw(Text("resting").font(.system(size:7.5,design:.monospaced)).foregroundColor(HubTheme.sage),at:CGPoint(x:Self.core.x,y:Self.core.y + Self.coreRadius + 15),anchor:.top) }
  }
  // the walkers last, so they pass in front of desks
  for (s,p) in walkers.sorted(by:{ $0.1.feet.y < $1.1.feet.y }) {
   figure(g,s.member,at:p.feet,px:px,step:p.walking && Int(t * 6) % 2 == 0,armsUp:p.talking && Int(t * 3) % 2 == 0,dim:1,flash:flash,t:t)
   if p.talking {
    let b = CGRect(x:p.feet.x + 6,y:p.feet.y - 62,width:22,height:14)
    g.fill(Path(roundedRect:b,cornerRadius:4),with:.color(.white))
    g.fill(Path { q in q.move(to:CGPoint(x:b.minX + 4,y:b.maxY)); q.addLine(to:CGPoint(x:b.minX + 2,y:b.maxY + 5)); q.addLine(to:CGPoint(x:b.minX + 10,y:b.maxY)) },with:.color(.white))
    g.draw(Text(String(repeating:".",count:1 + Int(t * 3) % 3)).font(.system(size:10,weight:.heavy,design:.monospaced)).foregroundColor(HubTheme.hex(0x101413)),at:CGPoint(x:b.midX,y:b.midY - 2),anchor:.center)
   }
  }
  // the picked character gets an amber outline
  if let id = pick.selected, let s = all.first(where:{ $0.member.id == id }) {
   if s.member.kind == .friday {
    let r = Self.coreRadius + 5
    g.stroke(Path(ellipseIn:CGRect(x:Self.core.x - r,y:Self.core.y - r,width:r * 2,height:r * 2)),with:.color(Noir.crimson),lineWidth:2)
   } else {
    let f = place(s,all:all,t:t).feet
    g.stroke(Path(roundedRect:CGRect(x:f.x - 18,y:f.y - 50,width:36,height:56),cornerRadius:4),with:.color(Noir.crimson),style:StrokeStyle(lineWidth:1.5,dash:[4,2]))
   }
  }
 }

 // A slow camera glide, a few points either way.
 static func drift(_ t: Double) -> CGPoint { CGPoint(x:sin(t * 0.07) * 4,y:cos(t * 0.05) * 3) }

 // Which character is under a click (or nil for empty floor). Same maths as draw().
 func hit(_ loc: CGPoint,size: CGSize,t: Double) -> String? {
  let scale = min(size.width / Self.logical.width,size.height / Self.logical.height)
  guard scale > 0 else { return nil }
  let drift = Self.drift(t)
  let x = (loc.x - (size.width - Self.logical.width * scale) / 2) / scale - drift.x
  let y = (loc.y - (size.height - Self.logical.height * scale) / 2) / scale - drift.y
  let point = CGPoint(x:x,y:y)
  let all = Self.spots(crew)
  var best: (id: String,dist: CGFloat)? = nil
  for s in all {
   let centre: CGPoint
   let reach: CGFloat
   if s.member.kind == .friday { centre = Self.core; reach = Self.coreRadius }
   else {
    let f = place(s,all:all,t:t).feet
    centre = CGPoint(x:f.x,y:f.y - 22); reach = 32
   }
   let dist = hypot(point.x - centre.x,point.y - centre.y)
   if dist <= reach && dist < (best?.dist ?? .infinity) { best = (s.member.id,dist) }
  }
  return best?.id
 }

 var body: some View {
  GeometryReader { geo in
   TimelineView(.animation(minimumInterval:1.0 / 8.0,paused:reduceMotion)) { timeline in
    let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
    Canvas { ctx, size in draw(ctx,size:size,t:t) }
   }
   .contentShape(Rectangle())
   .onTapGesture(coordinateSpace:.local) { loc in
    let t = reduceMotion ? 0 : Date().timeIntervalSinceReferenceDate
    let id = hit(loc,size:geo.size,t:t)
    pick.selected = id == pick.selected ? nil : id
   }
  }
  .accessibilityElement(children:.ignore)
  .accessibilityLabel("Crew station picture. \(crew.filter { $0.state == .working }.count) working, \(crew.filter { $0.state == .idle }.count) resting, \(crew.filter { $0.state == .away }.count) away, \(crew.filter { $0.state == .failing }.count) failing, \(visits.count) visiting someone they messaged. The list beside it has the same information; pick a name there for details.")
 }
}

// The card under the station for the picked character: who, one plain line, and a link to the evidence.
struct PixelCrewCard: View {
 let crew: [CrewMember]
 let visits: [PixelVisit]
 @ObservedObject var pick = PixelCrewModel.shared

 var body: some View {
  Group {
   if let id = pick.selected, let m = crew.first(where:{ $0.id == id }) {
    let link = PixelCrew.link(m)
    HStack(alignment:.top,spacing:10) {
     VStack(alignment:.leading,spacing:3) {
      HStack(spacing:8) {
       Text(m.name).font(.system(size:13,weight:.semibold)).foregroundStyle(HubTheme.text)
       Text(m.role).font(.system(size:10.5)).foregroundStyle(HubTheme.subtext).lineLimit(1)
      }
      Text(PixelCrew.line(m,visit:visits.first(where:{ $0.from == id }),crew:crew)).font(.system(size:12)).foregroundStyle(HubTheme.text.opacity(0.9)).lineLimit(2)
      if let url = URL(string:link.url) { Link(link.title + " ↗",destination:url).font(.system(size:11,weight:.medium)).foregroundStyle(HubTheme.teal) }
     }
     Spacer(minLength:6)
     Button { pick.selected = nil } label: { Image(systemName:"xmark").font(.system(size:10,weight:.bold)) }
      .buttonStyle(.plain).foregroundStyle(HubTheme.subtext).accessibilityLabel("Close details")
    }
    .padding(10)
    .frame(maxHeight:96,alignment:.top)
    .background(HubTheme.hex(0x141A17),in:RoundedRectangle(cornerRadius:8))
    .overlay(RoundedRectangle(cornerRadius:8).stroke(Color(red:0.88,green:0.22,blue:0.29).opacity(0.55),lineWidth:1))
   } else {
    Text("Click a character (or a name in the list) to see what they're doing.").font(DeckMono.font(10.5)).foregroundStyle(HubTheme.subtext)
   }
  }
 }
}

extension CompanionInterfaceView {
 // Who walked to whom, from what the app already loaded (no new GitHub reads). Test copies only: `defaults write ... crew.testVisits
 // -bool true` adds two clearly labelled sample visits so the walk can be checked. Never set in the real app.
 func deckPixelVisits(crew: [CrewMember],messages: [RoomMessage]) -> [PixelVisit] {
  var visits = PixelCrew.visits(messages:messages,signals:CrewSignals.current().signals,crew:crew)
  guard UserDefaults.standard.bool(forKey:"crew.testVisits") else { return visits }
  let chats = crew.filter { $0.kind == .chat }
  if chats.count >= 2 {
   visits.removeAll { $0.from == chats[0].id || $0.from == chats[1].id }
   visits.append(PixelVisit(from:chats[0].id,to:"Friday",date:Date().addingTimeInterval(-60),what:"TEST DATA: sample visit"))
   visits.append(PixelVisit(from:chats[1].id,to:"Cloud Claude",date:Date().addingTimeInterval(-120),what:"TEST DATA: sample visit"))
  }
  return visits
 }

 var deckCrewStation: some View {
  let messages = PixelCrew.merged(meeting.messages,meeting.chat.messages)
  let crew = PixelCrew.withFriday(deckCrew,messages:messages)
  let visits = deckPixelVisits(crew:crew,messages:messages)
  return HStack(alignment:.top,spacing:14) {
   VStack(alignment:.leading,spacing:8) {
    HStack(spacing:10) {
     Text("CREW STATION").font(DeckMono.font(11,.bold)).foregroundStyle(HubTheme.amber)
     Text("real states only · from the room, the Hotline, branch commits, GitHub runs and robot snapshots").font(DeckMono.font(10.5)).foregroundStyle(HubTheme.subtext).lineLimit(1)
    }
    CrewStationView(crew:crew,visits:visits,reduceMotion:reduceMotion)
     .frame(maxWidth:.infinity,maxHeight:.infinity)
     .background(DeckMono.bg,in:RoundedRectangle(cornerRadius:8))
     .overlay(RoundedRectangle(cornerRadius:8).stroke(HubTheme.line,lineWidth:1))
    PixelCrewCard(crew:crew,visits:visits).frame(height:96,alignment:.top)
    LazyVGrid(columns:[GridItem(.adaptive(minimum:190),spacing:12,alignment:.leading)],alignment:.leading,spacing:4) {
     ForEach([(CrewState.working,"typing · post/commit in 30 min"),(.idle,"asleep · nothing in 30 min"),(.away,"away"),(.failing,"run failed"),(.unknown,"no data")],id:\.1) { entry in
      HStack(spacing:6) { Circle().fill(deckStateColor(entry.0)).frame(width:8,height:8); Text(entry.1).font(DeckMono.font(10.5)).foregroundStyle(HubTheme.subtext).lineLimit(1) }
     }
     HStack(spacing:6) { Text("✉").font(.system(size:10)).foregroundStyle(HubTheme.amber); Text("walking · messaged in 15 min").font(DeckMono.font(10.5)).foregroundStyle(HubTheme.subtext).lineLimit(1) }
    }
   }
   VStack(alignment:.leading,spacing:8) {
    deckLabel("CREW LIST · \(crew.filter { $0.state == .working }.count) WORKING")
    ScrollView {
     VStack(spacing:0) {
      ForEach(crew.sorted { deckRank($0.state) < deckRank($1.state) }) { member in
       deckCrewRow(member)
        .contentShape(Rectangle())
        .onTapGesture { PixelCrewModel.shared.selected = member.id }
        .accessibilityAddTraits(.isButton)
      }
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
