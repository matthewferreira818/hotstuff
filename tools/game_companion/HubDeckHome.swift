import SwiftUI
import AppKit

// A tiny helper so a chart can draw itself in once when its page opens (the command-line build can't expand @State, so it is an object).
@MainActor final class DeckReveal: ObservableObject {
 @Published var shown = false
 func play(after delay: Double = 0.15) {
  guard !shown else { return }
  DispatchQueue.main.asyncAfter(deadline:.now() + delay) { withAnimation(.easeOut(duration:0.9)) { self.shown = true } }
 }
}

// Home, Signal Deck style (2026-11-06). Everything on it is read from what the app already loaded: the room thread, the board, GitHub's
// public workflow runs and the robots' public snapshots. Anything not connected says so.
extension CompanionInterfaceView {
 var deckNow: Date { Date() }

 // CONFIRM:/URGENT: messages for Matthew in the last 3 days that he has not answered since. Links only: approving still happens the normal way.
 var deckOkCards: [RoomMessage] {
  let cutoff = Date().addingTimeInterval(-3 * 86400)
  let lastMine = meeting.messages.filter { MeetingData.canonical($0.author) == "Matthew" }.compactMap { $0.date }.max() ?? .distantPast
  return meeting.messages.filter { message in
   guard let date = message.date, date > cutoff, date > lastMine else { return false }
   let text = message.text.trimmingCharacters(in:.whitespaces).uppercased()
   guard text.hasPrefix("CONFIRM:") || text.hasPrefix("URGENT:"), !hub.dismissed.contains(message.id) else { return false }
   // Old pings that only tested the alert, and ones that say there is nothing to approve, are not real requests.
   let flat = text.lowercased()
   let body = flat.drop { $0 != ":" }.dropFirst().trimmingCharacters(in:.whitespaces)
   if flat.contains("nothing to approve") || flat.contains("nothing happened") || flat.contains("this only checks") { return false }
   if body.hasPrefix("test") || body.hasPrefix("second test") || body.hasPrefix("third test") { return false }
   return true
  }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
 }

 // Test copies only (defaults write ... crew.testStates -bool true): forces one away and one failing desk so those pictures can be checked. Never set in the real app.
 var deckCrew: [CrewMember] {
  var crew = deckCrewReal
  guard UserDefaults.standard.bool(forKey:"crew.testStates") else { return crew }
  for i in crew.indices {
   if crew[i].id == "Roxy" { crew[i].state = .away; crew[i].awayUntil = Date().addingTimeInterval(3 * 86400); crew[i].detail = "TEST DATA: away" }
   if crew[i].id == "stock-bot" { crew[i].state = .failing; crew[i].detail = "TEST DATA: failing" }
  }
  return crew
 }
 var deckCrewReal: [CrewMember] { CrewData.build(messages:meeting.messages,runs:ventures.runs,snapshots:Dictionary(uniqueKeysWithValues:deckRobots.compactMap { entry in entry.robot.map { (entry.name,$0) } }),fridayLive:live.running) }

 var deckRobots: [(name: String,robot: StockRobot?)] {
  [("stock-bot",stocks.dip),("stock-momentum",stocks.momentum),("stock-hot",stocks.hot),("stock-moonshot",stocks.moon),
   ("stock-moonshot-crypto",stocks.moonCrypto),("stock-quality",stocks.quality),("stock-volatility",stocks.volatility)]
 }

 func deckStateColor(_ state: CrewState) -> Color {
  switch state {
  case .working: return HubTheme.green
  case .idle: return HubTheme.sage.opacity(0.55)
  case .away: return HubTheme.blue
  case .failing: return Color(red:0.95,green:0.38,blue:0.38)
  case .unknown: return HubTheme.subtext.opacity(0.35)
  }
 }

 func deckLabel(_ text: String,tag: String? = nil) -> some View {
  HStack(spacing:8) {
   Text(text).font(.system(size:11,weight:.medium,design:.monospaced)).tracking(1.3).foregroundStyle(HubTheme.subtext)
   if let tag = tag {
    Text(tag).font(.system(size:10,weight:.medium,design:.monospaced)).foregroundStyle(HubTheme.subtext)
     .padding(.horizontal,5).padding(.vertical,1).overlay(RoundedRectangle(cornerRadius:3).stroke(HubTheme.controlOutline,lineWidth:1))
   }
  }
  .accessibilityAddTraits(.isHeader)
 }

 func deckCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
  VStack(alignment:.leading,spacing:10) { content() }
   .padding(16).frame(maxWidth:.infinity,alignment:.topLeading)
   .background(HubTheme.card,in:RoundedRectangle(cornerRadius:10))
   .overlay(RoundedRectangle(cornerRadius:10).stroke(HubTheme.line,lineWidth:1))
 }

 var deckHome: some View {
  let cards = deckOkCards
  return ScrollView {
   VStack(alignment:.leading,spacing:16) {
    VStack(alignment:.leading,spacing:4) {
     Text(hubGreeting).font(.system(size:30,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.text)
     Text(meeting.board == nil && meeting.messages.isEmpty ? (meeting.loading ? "Reading the room…" : "The room hasn't loaded yet. Use Refresh.") : (cards.isEmpty ? "Friday: nothing waiting for your OK in the room." : "Friday: \(cards.count) \(cards.count == 1 ? "thing needs" : "things need") your OK."))
      .font(.system(size:13.5)).foregroundStyle(HubTheme.subtext)
    }
    deckLabel("CREW · WHO IS WORKING NOW",tag:"FROM ROOM + RUNS")
    deckCrewStrip
    deckLabel("NEEDS YOUR OK")
    deckNeedsCards(cards)
    HStack(alignment:.top,spacing:14) {
     deckTodayCard
     deckStockCard
    }
    hubHomeSection("Your ventures",detail:"Numbers from the loaded snapshots")
    LazyVGrid(columns:[GridItem(.adaptive(minimum:175),spacing:12)],spacing:12) {
     hubHomeVenture(.store,title:"HotsTuff",metric:ventures.store.map { String($0.week) } ?? "—",unit:"visitors · last 7 days",detail:hubStoreHeadline)
     hubHomeVenture(.ecs,title:"East Coast Social",metric:ventures.feed.map { String($0.total) } ?? "—",unit:"published feed posts",detail:hubEcsHeadline)
     hubHomeVenture(.stocks,title:"Stock bot",metric:(stocks.dip ?? stocks.momentum).map { hubMoney($0.value) } ?? "—",unit:"practice-account snapshot",detail:hubStockHeadline)
    }
    Button { meeting.confirmCall = true } label: {
     Label("Call a board meeting",systemImage:"person.3").font(.system(size:13,weight:.semibold)).foregroundStyle(HubTheme.text)
      .frame(maxWidth:.infinity,minHeight:44).background(HubTheme.control,in:RoundedRectangle(cornerRadius:10))
      .overlay(RoundedRectangle(cornerRadius:10).stroke(HubTheme.controlOutline,lineWidth:1))
    }
    .buttonStyle(.plain).disabled(meeting.sending || DesignPreview.enabled)
    .accessibilityHint("Asks for confirmation before posting or copying a call. This is not a live call.")
   }
   .padding(.horizontal,hub.compact ? 16 : 28).padding(.vertical,22)
  }
  .scrollIndicators(.hidden)
  .background(HubTheme.background)
  .confirmationDialog("Call a board meeting?",isPresented:$meeting.confirmCall) {
   Button(meeting.hasToken ? "Post the call" : "Copy the call") { Task { await meeting.callMeeting() } }
   Button("Cancel",role:.cancel) {}
  } message: { Text(hubCallWords(meeting.meetingNow)) }
 }

 var deckCrewStrip: some View {
  let people = deckCrew.filter { [.chat,.cloud,.agent].contains($0.kind) }
  return ScrollView(.horizontal,showsIndicators:false) {
   HStack(spacing:8) {
    if people.isEmpty {
     Text(meeting.loading ? "Reading the room…" : "No room posts loaded.").font(.system(size:12.5)).foregroundStyle(HubTheme.subtext)
    }
    ForEach(people) { member in
     HStack(spacing:8) {
      Circle().fill(deckStateColor(member.state)).frame(width:8,height:8)
      VStack(alignment:.leading,spacing:1) {
       Text(member.name).font(.system(size:12.5,weight:.semibold)).foregroundStyle(HubTheme.text)
       Text(member.detail).font(.system(size:11)).foregroundStyle(HubTheme.subtext).lineLimit(1).frame(maxWidth:150,alignment:.leading)
      }
     }
     .padding(.horizontal,12).padding(.vertical,8)
     .background(HubTheme.card,in:RoundedRectangle(cornerRadius:9))
     .overlay(RoundedRectangle(cornerRadius:9).stroke(HubTheme.line,lineWidth:1))
     .accessibilityElement(children:.combine)
    }
    Button { hubSelect(.crewStation) } label: {
     Text("Crew station ›").font(.system(size:12,weight:.medium,design:.monospaced)).foregroundStyle(HubTheme.green).padding(.horizontal,8).frame(height:44)
    }.buttonStyle(.plain)
   }
  }
 }

 @ViewBuilder func deckNeedsCards(_ cards: [RoomMessage]) -> some View {
  if cards.isEmpty {
   deckCard {
    Text(meeting.messages.isEmpty ? "Room not loaded." : "No CONFIRM or URGENT messages waiting for you in the last 3 days.")
     .font(.system(size:13)).foregroundStyle(HubTheme.subtext)
   }
  } else {
   LazyVGrid(columns:[GridItem(.adaptive(minimum:300),spacing:12)],spacing:12) {
    ForEach(cards.prefix(4)) { message in deckNeedsCard(message) }
   }
  }
 }

 func deckNeedsCard(_ message: RoomMessage) -> some View {
  let urgent = message.text.uppercased().hasPrefix("URGENT")
  let body = message.text.drop { $0 != ":" }.dropFirst().trimmingCharacters(in:.whitespacesAndNewlines)
  let tint = urgent ? Color(red:0.95,green:0.38,blue:0.42) : HubTheme.amber
  return VStack(alignment:.leading,spacing:7) {
   HStack(spacing:8) {
    Text(urgent ? "URGENT" : "CONFIRM").font(.system(size:9.5,weight:.bold,design:.monospaced)).foregroundStyle(tint)
     .padding(.horizontal,6).padding(.vertical,2).background(tint.opacity(0.16),in:RoundedRectangle(cornerRadius:4))
    Text(MeetingData.display(MeetingData.canonical(message.author) ?? message.author)).font(.system(size:11.5)).foregroundStyle(HubTheme.subtext)
   }
   Text(MeetingData.brief(body,limit:150)).font(.system(size:14,weight:.semibold)).foregroundStyle(HubTheme.text)
    .lineLimit(3).fixedSize(horizontal:false,vertical:true)
   HStack(spacing:6) {
    Button { meeting.opened.insert("m\(message.id)"); hubHomeOpenRoom(5) } label: {
     Text("open in the Meeting Room ›").font(.system(size:11.5,design:.monospaced)).foregroundStyle(HubTheme.teal).underline()
    }.buttonStyle(.plain)
    Text("· \(message.date.map { CrewData.ago($0) } ?? "")").font(.system(size:11)).foregroundStyle(HubTheme.subtext)
   }
   Text("Approve the normal way, not from here.").font(.system(size:10.5)).foregroundStyle(HubTheme.subtext)
  }
  .padding(14).frame(maxWidth:.infinity,minHeight:120,alignment:.topLeading)
  .background(HubTheme.card,in:RoundedRectangle(cornerRadius:10))
  .overlay(alignment:.leading) { Rectangle().fill(tint).frame(width:3).clipShape(RoundedRectangle(cornerRadius:2)) }
  .overlay(RoundedRectangle(cornerRadius:10).stroke(HubTheme.line,lineWidth:1))
  .accessibilityElement(children:.combine)
 }

 // MARK: Today

 var deckTodayRows: [(when: String,text: String)] {
  var rows: [(String,String)] = []
  var calendar = Calendar.current
  calendar.timeZone = TimeZone(identifier:"America/Moncton") ?? calendar.timeZone
  let crew = deckCrew
  if ventures.runs != nil {
   let robots = crew.filter { $0.kind == .robot }
   let ranToday = robots.filter { $0.since.map { calendar.isDateInToday($0) } ?? false }.count
   let running = robots.filter { $0.state == .working }.count
   let failed = robots.filter { $0.state == .failing }.count
   rows.append(("robots","\(ranToday) of \(robots.count) ran today" + (running > 0 ? ", \(running) running" : "") + (failed > 0 ? ", \(failed) FAILED" : "")))
   if let smoke = ventures.runs?.first(where:{ $0.name == "Site smoke test" }) {
    rows.append(("smoke",(smoke.isFailing ? "Site smoke test FAILED " : "Site smoke test ok ") + (smoke.created.map { CrewData.ago($0) } ?? "")))
   }
  } else { rows.append(("runs",ventures.loading ? "Reading automation runs…" : "Automation runs not loaded")) }
  if let next = CrewData.nextRefresh() {
   let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; f.timeZone = calendar.timeZone
   rows.append(("refresh","Next store refresh · \(f.string(from:next)) (scheduled; GitHub can run late)"))
  }
  let waiting = (meeting.board?.sections ?? []).flatMap { $0.items }.filter { !$0.isDone && $0.status.hasPrefix("waiting") }
  for item in waiting.prefix(3) { rows.append(("waiting",MeetingData.brief(item.text,limit:70))) }
  rows.append(("calendar","Calendar and EI reminders: not connected to the app yet"))
  return rows
 }

 var deckTodayCard: some View {
  deckCard {
   deckLabel("TODAY",tag:"LIVE DATA")
   VStack(spacing:0) {
    ForEach(Array(deckTodayRows.enumerated()),id:\.offset) { index,row in
     HStack(alignment:.firstTextBaseline,spacing:14) {
      Text(row.when).font(.system(size:11,design:.monospaced)).foregroundStyle(HubTheme.subtext).frame(width:62,alignment:.leading)
      Text(row.text).font(.system(size:13)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
      Spacer(minLength:0)
     }
     .padding(.vertical,7)
     if index < deckTodayRows.count - 1 { Divider().overlay(HubTheme.line) }
    }
   }
  }
 }

 // MARK: Stock bot summary with a real chart

 var deckStockCard: some View {
  let loaded = deckRobots.compactMap { $0.robot }
  return Button { hubSelect(.stocks) } label: {
   deckCard {
    deckLabel("STOCK BOT · PAPER",tag:"PRACTICE MONEY")
    HStack(alignment:.firstTextBaseline,spacing:8) {
     Text("\(loaded.count) / 7").font(.system(size:26,weight:.bold,design:.monospaced)).foregroundStyle(HubTheme.text)
     Text("robot snapshots loaded").font(.system(size:12)).foregroundStyle(HubTheme.subtext)
    }
    DeckRobotChart(robots:deckRobots).frame(height:150)
    Text("Each bar: that robot's practice account vs its starting cash, from its latest public snapshot. Not real money.")
     .font(.system(size:11)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
   }
  }
  .buttonStyle(.plain).accessibilityHint("Opens the Stock bot page")
 }
}

// Horizontal bars, one per robot: percent above or below its starting cash. Draws in once when it appears. A robot with no snapshot shows "no data".
struct DeckRobotChart: View {
 let robots: [(name: String,robot: StockRobot?)]
 @StateObject private var reveal = DeckReveal()

 private func pct(_ robot: StockRobot?) -> Double? {
  guard let robot = robot, robot.startCash > 0 else { return nil }
  return (robot.value / robot.startCash - 1) * 100
 }

 var body: some View {
  let values = robots.compactMap { pct($0.robot) }
  let reach = max(1,values.map { abs($0) }.max() ?? 1)
  return VStack(spacing:5) {
   ForEach(Array(robots.enumerated()),id:\.offset) { _,entry in
    HStack(spacing:8) {
     Text(entry.name.replacingOccurrences(of:"stock-",with:"")).font(.system(size:11,design:.monospaced)).foregroundStyle(HubTheme.subtext)
      .frame(width:118,alignment:.trailing).lineLimit(1)
     GeometryReader { geo in
      let half = geo.size.width / 2
      ZStack(alignment:.leading) {
       Rectangle().fill(HubTheme.line).frame(width:1).offset(x:half)
       if let value = pct(entry.robot) {
        let length = half * CGFloat(abs(value) / reach) * (reveal.shown ? 1 : 0)
        RoundedRectangle(cornerRadius:2).fill(value >= 0 ? HubTheme.green : Color(red:0.93,green:0.45,blue:0.40))
         .frame(width:max(2,length),height:9).offset(x:value >= 0 ? half : half - max(2,length))
       }
      }
      .frame(height:geo.size.height)
     }
     .frame(height:12)
     Text(pct(entry.robot).map { String(format:"%+.1f%%",$0) } ?? "no data").font(.system(size:10,design:.monospaced))
      .foregroundStyle(HubTheme.text).frame(width:54,alignment:.trailing)
    }
   }
  }
  .onAppear { reveal.play() }
  .accessibilityElement(children:.ignore)
  .accessibilityLabel("Chart of each practice robot's gain or loss against its starting cash")
 }
}
