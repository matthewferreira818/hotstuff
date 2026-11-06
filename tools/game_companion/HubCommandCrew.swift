import SwiftUI
import AppKit

// Command Core › Crew Station (LC-Pixels, 2026-11-06). The crew on a ring around Friday, a status list, the board's open tasks, and what waits on Matthew.
// REAL SIGNALS ONLY: states come from CrewData.build (room posts, GitHub commits/runs, robot snapshots, "away until" notes). Roxy and Grok show their
// away dates. Tasks are the open items of BOARD.md "On the table". Approvals are the board's Questions plus room messages to Matthew that start with
// CONFIRM: or URGENT:. The only button opens the Meeting Room (where he answers); there are no fake Review/Later buttons and no progress bars.

struct CoreCrewView: View {
 var baseCrew: [CrewMember]
 @ObservedObject var live = LiveSessionsModel.shared
 @Environment(\.coreWidth) private var width
 var merged: (crew: [CrewMember],closed: [String]) { LiveSessions.apply(live.sessions,to:baseCrew) }
 var crew: [CrewMember] { merged.crew }
 var tasks: [BoardItem]
 var questions: [BoardItem]
 var confirms: [RoomMessage]

 var visits: [PixelVisit]
 var reduceMotion: Bool
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
   Group {
    if width >= 1400 {
     HStack(alignment:.top,spacing:12) {
      stationCard.frame(maxWidth:.infinity)
      listCard.frame(width:300)
      VStack(spacing:12) { approvalsCard; tasksCard }.frame(width:320)
     }
    } else if width >= 720 {
     HStack(alignment:.top,spacing:12) {
      VStack(spacing:12) { stationCard; tasksCard }.frame(maxWidth:.infinity)
      VStack(spacing:12) { listCard; approvalsCard }.frame(width:300)
     }
    } else {
     VStack(spacing:12) { stationCard; approvalsCard; listCard; tasksCard }
    }
   }
   .padding(.horizontal,24).padding(.bottom,16)
  }
  .scrollIndicators(.hidden)
  .onAppear { LiveSessionsModel.shared.start() }
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

 // The living pixel station (our own art, PixelCrew.swift / HubCrew.swift), in Command Core's own frame (near-black, hairline border). Every pose is a real signal: typing = a post or
 // commit in the last 30 min, walking = a message to someone in the last 15 min, asleep = nothing in 30 min, away sign = a room message said so.
 static let crt = CoreStyle.dim
 var stationCard: some View {
  VStack(alignment:.leading,spacing:8) {
   HStack(spacing:10) {
    Text("Crew station").font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(CoreStyle.ink)
    Text("live · real signals only").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim)
    Spacer(minLength:0)
    Text("\(crew.filter { $0.state == .working }.count) typing").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.emerald)
   }
   CrewStationView(crew:crew,visits:visits,reduceMotion:reduceMotion)
    .aspectRatio(760.0 / 640.0,contentMode:.fit)
    .frame(maxWidth:.infinity)
    .background(HubTheme.hex(0x08080A),in:RoundedRectangle(cornerRadius:8))
    .overlay(RoundedRectangle(cornerRadius:8).stroke(Color.white.opacity(0.07),lineWidth:1))
   PixelCrewCard(crew:crew,visits:visits).frame(height:96,alignment:.top)
   LazyVGrid(columns:[GridItem(.adaptive(minimum:118),spacing:10,alignment:.leading)],alignment:.leading,spacing:4) {
    ForEach([(CrewState.working,"typing"),(.idle,"asleep"),(.away,"away"),(.failing,"run failed"),(.unknown,"no data")],id:\.1) { e in
     HStack(spacing:5) { Circle().fill(color(e.0)).frame(width:7,height:7); Text(e.1).font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim) }
    }
    HStack(spacing:4) { Text("✉").font(.system(size:10)).foregroundStyle(CoreStyle.dim); Text("walking: messaged").font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim) }
   }
  }
  .padding(13).frame(maxWidth:.infinity,alignment:.topLeading)
  .background(RoundedRectangle(cornerRadius:11).fill(HubTheme.hex(0x111114)))
  .overlay(RoundedRectangle(cornerRadius:11).stroke(Color.white.opacity(0.065),lineWidth:1))
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
   if !merged.closed.isEmpty {
    Text("Closed right now (no open chat on this Mac): " + merged.closed.joined(separator:", ")).font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim).fixedSize(horizontal:false,vertical:true)
   }
  }
 }

 // A clean one-line title from a raw board line: no markdown, no owner tag, cut at a word near 70 characters.
 static func cleanTitle(_ raw: String,limit: Int = 70) -> String {
  var t = raw
  t = t.replacingOccurrences(of:"\\[([^\\]]*)\\]\\([^)]*\\)",with:"$1",options:.regularExpression)   // [text](url) -> text
  for m in ["**","__","`","*"] { t = t.replacingOccurrences(of:m,with:"") }
  t = t.replacingOccurrences(of:"^\\s*(\\[[^\\]]*\\]\\s*)+",with:"",options:.regularExpression)            // leading [Owner] tags
  t = t.replacingOccurrences(of:"\\s*Status:.*$",with:"",options:[.regularExpression,.caseInsensitive])
  t = t.replacingOccurrences(of:"\\s+",with:" ",options:.regularExpression).trimmingCharacters(in:CharacterSet(charactersIn:" -–—:;,."))
  t = t.replacingOccurrences(of:"^\\([^)]*\\)\\s*",with:"",options:.regularExpression)                        // a leading "(LC-Manager owns)" note
  for sep in [" (",": "] { if let r = t.range(of:sep), t.distance(from:t.startIndex,to:r.lowerBound) >= 12 { t = String(t[..<r.lowerBound]) } }
  if let dot = t.range(of:". ") , t.distance(from:t.startIndex,to:dot.lowerBound) >= 12 { t = String(t[..<dot.lowerBound]) }
  if t.count <= limit { return t }
  let head = String(t.prefix(limit))
  let cut = head.lastIndex(of:" ").map { String(head[..<$0]) } ?? head
  return cut.trimmingCharacters(in:CharacterSet(charactersIn:" ,;:-–—")) + "…"
 }

 // The owner as a short chip: "Local Claude (LC-Pixels)" -> LC-Pixels, "Claude → Matthew" -> Claude.
 static func ownerChip(_ raw: String) -> String {
  var o = raw.components(separatedBy:"→").first ?? raw
  if let open = o.firstIndex(of:"("), let close = o.lastIndex(of:")"), open < close { o = String(o[o.index(after:open)..<close]) }
  return o.trimmingCharacters(in:.whitespaces)
 }

 var tasksCard: some View {
  CoreCard(title:"Active tasks · from the board",icon:"checklist") {
   if !boardKnown { Text("The board hasn't loaded yet.").font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.dim) }
   else if tasks.isEmpty { Text("Nothing open on the board's \"On the table\" list.").font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.dim) }
   ForEach(tasks.prefix(5)) { t in
    HStack(spacing:8) {
     Text(Self.cleanTitle(t.text)).font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.9)).lineLimit(1)
     Spacer(minLength:6)
     if !t.owner.isEmpty {
      Text(Self.ownerChip(t.owner)).font(.system(size:10,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.teal).lineLimit(1)
       .padding(.horizontal,7).padding(.vertical,2).overlay(Capsule().stroke(CoreStyle.teal.opacity(0.5),lineWidth:1))
     }
     Text(t.status.isEmpty ? "—" : Self.cleanTitle(String(t.status.split(separator:"(").first ?? ""),limit:24)).font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(1).frame(minWidth:56,alignment:.trailing)
    }
   }
   if tasks.count > 5 { Text("+ \(tasks.count - 5) more on the board").font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim) }
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
  let messages = PixelCrew.merged(meeting.messages,meeting.chat.messages)
  let crew = LiveSessions.apply(LiveSessionsModel.shared.sessions,to:PixelCrew.withFriday(deckCrewReal,messages:messages)).crew
  let visits = deckPixelVisits(crew:crew,messages:messages)
  let needs = meeting.needs
  let tasks = (meeting.board?.sections.first { $0.title.lowercased() == "on the table" }?.items ?? []).filter { !$0.isDone }
  let confirms = needs.messages.filter { let t = $0.text.trimmingCharacters(in:.whitespaces).uppercased(); return t.hasPrefix("CONFIRM") || t.hasPrefix("URGENT") }
  let away = crew.filter { $0.state == .away }
  let working = crew.filter { $0.state == .working }.count
  let failing = crew.filter { $0.state == .failing }
  var obs = coreObservations()
  for a in away { obs.append(CoreObservation(tone:0,text:"\(a.name) is away" + (a.awayUntil.map { " until " + $0.formatted(.dateTime.month().day()) } ?? "") + ".",why:"They said so in a room message.",source:"Room message")) }
  for f in failing { obs.insert(CoreObservation(tone:3,text:"\(f.name): \(f.detail)",why:"Its last run failed. The crew can look at it.",source:"GitHub Actions read"),at:0) }
  if needs.questions.count + confirms.count > 0 {
   obs.insert(CoreObservation(tone:2,text:"\(needs.questions.count + confirms.count) thing\(needs.questions.count + confirms.count == 1 ? "" : "s") waiting on your OK.",why:"They're listed in the Waiting on you card.",source:"Board and room, now",actionTitle:"Open Meeting Room",run:{ hubSelect(.meeting) }),at:0)
  }
  return coreFrame("Crew Station","\(working) working · \(away.count) away · \(failing.count) failing. Real signals only.",tone:failing.isEmpty ? 0 : 3,observations:obs,
                   content:AnyView(CoreCrewView(baseCrew:crew,tasks:tasks,questions:needs.questions,confirms:confirms,visits:visits,reduceMotion:reduceMotion,boardKnown:meeting.board != nil,openMeeting:{ hubSelect(.meeting) })))
 }
}
