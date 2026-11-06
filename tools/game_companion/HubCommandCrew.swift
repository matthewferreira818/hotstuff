import SwiftUI
import AppKit

// Command Core › Crew Station (LC-Pixels, 2026-11-06). The crew on a ring around Friday, a status list, the board's open tasks, and what waits on Matthew.
// REAL SIGNALS ONLY: states come from CrewData.build (room posts, GitHub commits/runs, robot snapshots, "away until" notes). Roxy and Grok show their
// away dates. Tasks are the open items of BOARD.md "On the table". Approvals are the board's Questions plus room messages to Matthew that start with
// CONFIRM: or URGENT:. The only button opens the Meeting Room (where he answers); there are no fake Review/Later buttons and no progress bars.

struct CoreCrewView: View {
 var crew: [CrewMember]
 var tasks: [BoardItem]
 var questions: [BoardItem]
 var confirms: [RoomMessage]
 var boardKnown: Bool
 var openMeeting: () -> Void

 private func color(_ s: CrewState) -> Color {
  switch s { case .working: return CoreStyle.emerald; case .idle: return CoreStyle.teal.opacity(0.7); case .away: return CoreStyle.amber
  case .failing: return CoreStyle.crimson; case .unknown: return CoreStyle.dim.opacity(0.7) }
 }
 private func word(_ m: CrewMember) -> String {
  switch m.state {
  case .working: return "working"
  case .idle: return "idle"
  case .away: return m.awayUntil.map { "away until " + Self.day.string(from:$0) } ?? "away"
  case .failing: return "last run failed"
  case .unknown: return "no data"
  }
 }
 private static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "MMM d"; f.timeZone = TimeZone(identifier:"America/Moncton"); return f }()
 private func rank(_ s: CrewState) -> Int { switch s { case .failing: return 0; case .working: return 1; case .away: return 2; case .idle: return 3; case .unknown: return 4 } }

 var friday: CrewMember? { crew.first { $0.kind == .friday } }
 var ringCrew: [CrewMember] { crew.filter { $0.kind != .friday && ($0.kind == .chat || $0.kind == .cloud || $0.kind == .agent) } }

 var body: some View {
  ScrollView {
   HStack(alignment:.top,spacing:12) {
    VStack(spacing:12) {
     ringCard
     tasksCard
    }.frame(maxWidth:.infinity)
    VStack(spacing:12) {
     listCard
     approvalsCard
    }.frame(width:320)
   }
   .padding(.horizontal,24).padding(.bottom,16)
  }
  .scrollIndicators(.hidden)
 }

 func node(_ m: CrewMember,size: CGFloat) -> some View {
  VStack(spacing:3) {
   ZStack {
    Circle().fill(HubTheme.hex(0x0C0C0E))
    Circle().stroke(color(m.state),lineWidth:m.state == .working ? 2 : 1.2)
    Text(String(m.name.replacingOccurrences(of:"LC-",with:"").prefix(2))).font(.system(size:size * 0.32,weight:.semibold,design:.rounded)).foregroundStyle(CoreStyle.ink)
   }.frame(width:size,height:size)
   Text(m.name).font(.system(size:10.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.9)).lineLimit(1)
   Text(word(m)).font(.system(size:9.5,design:.rounded)).foregroundStyle(color(m.state)).lineLimit(1)
  }
  .frame(width:96)
  .accessibilityElement(children:.ignore)
  .accessibilityLabel("\(m.name): \(word(m))")
 }

 var ringCard: some View {
  CoreCard(title:"Crew around Friday",icon:"person.3") {
   GeometryReader { geo in
    let c = CGPoint(x:geo.size.width / 2,y:geo.size.height / 2)
    let rx = max(80,min(geo.size.width / 2 - 56,230)), ry = max(60,geo.size.height / 2 - 40)
    let n = max(ringCrew.count,1)
    ZStack {
     Ellipse().stroke(CoreStyle.teal.opacity(0.28),lineWidth:1).frame(width:rx * 2,height:ry * 2).position(c)
     if let f = friday { node(f,size:52).position(c) }
     ForEach(Array(ringCrew.enumerated()),id:\.element.id) { i,m in
      let a = -Double.pi / 2 + Double(i) * 2 * Double.pi / Double(n)
      node(m,size:38).position(x:c.x + CGFloat(cos(a)) * rx,y:c.y + CGFloat(sin(a)) * ry)
     }
    }
   }
   .frame(height:290)
   Text("Rings show real states: green is working (a post or commit in the last 30 minutes), teal is idle, amber is away.").font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
  }
 }

 var listCard: some View {
  let sorted = crew.sorted { rank($0.state) < rank($1.state) }
  return CoreCard(title:"Crew status · \(crew.filter { $0.state == .working }.count) working",icon:"list.bullet") {
   ForEach(sorted) { m in
    HStack(alignment:.top,spacing:8) {
     Circle().fill(color(m.state)).frame(width:7,height:7).padding(.top,5)
     VStack(alignment:.leading,spacing:1) {
      HStack(spacing:6) {
       Text(m.name).font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(CoreStyle.ink)
       Text(word(m)).font(.system(size:10.5,design:.rounded)).foregroundStyle(color(m.state))
      }
      Text(m.detail).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(2).fixedSize(horizontal:false,vertical:true)
     }
    }
   }
  }
 }

 var tasksCard: some View {
  CoreCard(title:"Active tasks · from the board",icon:"checklist") {
   if !boardKnown { Text("The board hasn't loaded yet.").font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.dim) }
   else if tasks.isEmpty { Text("Nothing open on the board's \"On the table\" list.").font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.dim) }
   ForEach(tasks.prefix(8)) { t in
    HStack(alignment:.top,spacing:8) {
     Text(t.owner.isEmpty ? "—" : t.owner).font(.system(size:10.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.teal).frame(width:92,alignment:.leading).lineLimit(1)
     Text(t.text).font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.88)).lineLimit(2).fixedSize(horizontal:false,vertical:true)
     Spacer(minLength:4)
     if !t.status.isEmpty { Text(t.status).font(.system(size:10,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(1) }
    }
   }
   if tasks.count > 8 { Text("+ \(tasks.count - 8) more on the board").font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim) }
  }
 }

 var approvalsCard: some View {
  let n = questions.count + confirms.count
  return CoreCard(title:"Waiting on you · \(n)",icon:"hand.raised") {
   if n == 0 { Text(boardKnown ? "Nothing needs your OK right now." : "The board hasn't loaded yet.").font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.dim) }
   ForEach(questions.prefix(4)) { q in
    VStack(alignment:.leading,spacing:1) {
     Text(q.text).font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.88)).lineLimit(3).fixedSize(horizontal:false,vertical:true)
     Text("Board question · \(q.owner)").font(.system(size:10,design:.rounded)).foregroundStyle(CoreStyle.dim)
    }
   }
   ForEach(confirms.prefix(4)) { m in
    VStack(alignment:.leading,spacing:1) {
     Text(m.text).font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.88)).lineLimit(3).fixedSize(horizontal:false,vertical:true)
     Text("Room · from \(m.author)").font(.system(size:10,design:.rounded)).foregroundStyle(CoreStyle.amber)
    }
   }
   if n > 0 {
    Button(action:openMeeting) { Text("Answer in the Meeting Room ›").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.teal) }.buttonStyle(.plain)
   }
  }
 }
}

extension CompanionInterfaceView {
 var commandCoreCrew: some View {
  let crew = deckCrewReal
  let needs = meeting.needs
  let tasks = (meeting.board?.sections.first { $0.title.lowercased() == "on the table" }?.items ?? []).filter { !$0.isDone }
  let confirms = needs.messages.filter { let t = $0.text.trimmingCharacters(in:.whitespaces).uppercased(); return t.hasPrefix("CONFIRM") || t.hasPrefix("URGENT") }
  let away = crew.filter { $0.state == .away }
  let working = crew.filter { $0.state == .working }.count
  let failing = crew.filter { $0.state == .failing }
  var obs = coreObservations()
  for a in away { obs.append(CoreObservation(tone:0,text:"\(a.name) is away" + (a.awayUntil.map { " until " + $0.formatted(.dateTime.month().day()) } ?? "") + ".",why:"They said so in the room; nothing is waiting on them.",source:"Room message")) }
  for f in failing { obs.insert(CoreObservation(tone:3,text:"\(f.name): \(f.detail)",why:"Its last run failed. The crew can look at it.",source:"GitHub Actions read"),at:0) }
  if needs.questions.count + confirms.count > 0 {
   obs.insert(CoreObservation(tone:2,text:"\(needs.questions.count + confirms.count) thing\(needs.questions.count + confirms.count == 1 ? "" : "s") waiting on your OK.",why:"They're listed in the Waiting on you card.",source:"Board and room, now",actionTitle:"Open Meeting Room",run:{ hubSelect(.meeting) }),at:0)
  }
  return coreFrame("Crew Station","\(working) working · \(away.count) away · \(failing.count) failing. Real signals only.",tone:failing.isEmpty ? 0 : 3,observations:obs,
                   content:AnyView(CoreCrewView(crew:crew,tasks:tasks,questions:needs.questions,confirms:confirms,boardKnown:meeting.board != nil,openMeeting:{ hubSelect(.meeting) })))
 }
}
