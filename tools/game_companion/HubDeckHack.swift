import SwiftUI

// The Hacking area's home: a dark terminal look with ONE live tape of our own systems (robot trades, GitHub workflow runs, room messages)
// plus a Systems and Guard rail. Read-only: nothing here can send, post, trade or change anything. Systems, Guard, Lab and Real or Fake?
// are the existing pages, opened from the tabs above.
struct DeckTapeLine: Identifiable {
 var id: String
 var date: Date
 var tag: String
 var text: String
 var tone: Int     // 0 normal, 1 good, 2 warning, 3 bad
}

enum DeckMono {
 static let bg = HubTheme.hex(0x0A0E0C)
 static func font(_ size: CGFloat,_ weight: Font.Weight = .regular) -> Font { .system(size:size,weight:weight,design:.monospaced) }
}

extension CompanionInterfaceView {
 var deckTape: [DeckTapeLine] {
  var lines: [DeckTapeLine] = []
  for entry in deckRobots {
   guard let robot = entry.robot else { continue }
   for trade in robot.recentTrades {
    guard let time = trade.time else { continue }
    let buy = trade.side.lowercased() == "buy"
    lines.append(DeckTapeLine(id:"t-\(entry.name)-\(trade.id)",date:time,tag:buy ? "BUY" : "SELL",text:"\(entry.name)  \(trade.symbol)  \(hubMoney(trade.dollars))  (paper)",tone:buy ? 1 : 2))
   }
  }
  for run in ventures.runs ?? [] {
   guard let time = run.created else { continue }
   let tag = run.isRunning ? "RUN" : (run.isFailing ? "FAIL" : (run.conclusion == "success" ? "OK" : "END"))
   lines.append(DeckTapeLine(id:"r-\(run.name)-\(time.timeIntervalSince1970)",date:time,tag:tag,text:run.name,tone:run.isFailing ? 3 : (run.isRunning ? 0 : 1)))
  }
  for message in meeting.messages.suffix(8) {
   guard let time = message.date else { continue }
   let who = MeetingData.display(MeetingData.canonical(message.author) ?? message.author)
   lines.append(DeckTapeLine(id:"m-\(message.id)",date:time,tag:"ROOM",text:"[\(who)] " + MeetingData.brief(message.text,limit:110),tone:0))
  }
  return Array(lines.sorted { $0.date > $1.date }.prefix(70))
 }

 func deckTapeTime(_ date: Date) -> String {
  var calendar = Calendar.current
  calendar.timeZone = TimeZone(identifier:"America/Moncton") ?? calendar.timeZone
  let f = DateFormatter()
  f.timeZone = calendar.timeZone
  f.dateFormat = calendar.isDateInToday(date) ? "HH:mm:ss" : "MMM d HH:mm"
  return f.string(from:date)
 }

 func deckToneColor(_ tone: Int) -> Color {
  switch tone {
  case 1: return HubTheme.green
  case 2: return HubTheme.amber
  case 3: return Color(red:0.95,green:0.40,blue:0.40)
  default: return HubTheme.sage
  }
 }

 var deckHackLive: some View {
  let tape = deckTape
  return VStack(spacing:0) {
   HStack(alignment:.top,spacing:14) {
    VStack(alignment:.leading,spacing:0) {
     HStack(spacing:8) {
      Text("LIVE TAPE").font(DeckMono.font(11,.bold)).foregroundStyle(HubTheme.amber)
      Text("newest first · new lines slide in at the top").font(DeckMono.font(11)).foregroundStyle(HubTheme.amber.opacity(0.8))
      TimelineView(.periodic(from:.now,by:1)) { timeline in
       Circle().fill(HubTheme.green).frame(width:7,height:7).opacity(Int(timeline.date.timeIntervalSince1970) % 2 == 0 ? 1 : 0.35)
      }
      Spacer(minLength:0)
      Text((hub.refreshedAt ?? (ventures.lastRefresh == .distantPast ? nil : ventures.lastRefresh)).map { "refreshed \(hubAgo($0))" } ?? "loading…").font(DeckMono.font(10.5)).foregroundStyle(HubTheme.subtext)
     }
     .padding(.horizontal,14).padding(.vertical,10)
     .overlay(alignment:.bottom) { Rectangle().fill(HubTheme.line).frame(height:1) }
     ScrollView {
      VStack(alignment:.leading,spacing:5) {
       if tape.isEmpty {
        Text(ventures.loading || meeting.loading || stocks.loading ? "reading…" : "nothing loaded yet: use Refresh (Command-R)").font(DeckMono.font(12)).foregroundStyle(HubTheme.subtext)
       }
       ForEach(tape) { line in
        HStack(alignment:.firstTextBaseline,spacing:10) {
         Text(deckTapeTime(line.date)).font(DeckMono.font(11)).foregroundStyle(HubTheme.subtext).frame(width:98,alignment:.leading)
         Text(line.tag).font(DeckMono.font(11,.bold)).foregroundStyle(deckToneColor(line.tone)).frame(width:40,alignment:.leading)
         Text(line.text).font(DeckMono.font(11.5)).foregroundStyle(HubTheme.text).lineLimit(2).fixedSize(horizontal:false,vertical:true)
         Spacer(minLength:0)
        }
        .transition(.move(edge:.top).combined(with:.opacity))
       }
      }
      .padding(14)
      .animation(reduceMotion ? nil : .easeOut(duration:0.45),value:tape.map { $0.id })
     }
    }
    .background(DeckMono.bg,in:RoundedRectangle(cornerRadius:8))
    .overlay(RoundedRectangle(cornerRadius:8).stroke(HubTheme.line,lineWidth:1))
    VStack(spacing:12) { deckSystemsRail; deckGuardRail; Spacer(minLength:0) }.frame(width:280)
   }
   .padding(.horizontal,22).padding(.top,14)
   HStack(spacing:0) {
    Text("helm@mac:~$ ").foregroundStyle(HubTheme.green)
    Text("tail -f live-tape  # our systems only, read-only").foregroundStyle(HubTheme.subtext)
    TimelineView(.periodic(from:.now,by:0.6)) { timeline in
     Text("▌").foregroundStyle(HubTheme.green).opacity(Int(timeline.date.timeIntervalSince1970 * 1.6) % 2 == 0 ? 1 : 0)
    }
    Spacer(minLength:0)
   }
   .font(DeckMono.font(12)).padding(.horizontal,24).padding(.vertical,12)
  }
  .background(DeckMono.bg.opacity(0.55))
 }

 func deckRailRow(_ mark: String,_ text: String,_ tone: Int) -> some View {
  HStack(alignment:.firstTextBaseline,spacing:8) {
   Text(mark).font(DeckMono.font(11.5,.bold)).foregroundStyle(deckToneColor(tone)).frame(width:12)
   Text(text).font(DeckMono.font(11.5)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
   Spacer(minLength:0)
  }
 }

 var deckSystemsRail: some View {
  let runs = ventures.runs ?? []
  let failing = runs.filter { $0.isFailing }
  let running = runs.filter { $0.isRunning }
  return VStack(alignment:.leading,spacing:7) {
   deckLabel("SYSTEMS")
   if ventures.runs == nil {
    deckRailRow("?","automation runs not loaded",0)
   } else {
    deckRailRow(failing.isEmpty ? "✓" : "!","GitHub automations: \(runs.count) seen, \(failing.count) failing, \(running.count) running",failing.isEmpty ? 1 : 3)
    ForEach(failing.prefix(3)) { run in deckRailRow("✗",run.name,3) }
   }
   ForEach(ventures.alerts.prefix(2),id:\.self) { alert in deckRailRow("!",alert,2) }
   deckRailRow(stocks.failed ? "!" : "✓",stocks.failed ? "robot snapshots unavailable" : "\(deckRobots.filter { $0.robot != nil }.count) of 7 robot snapshots loaded",stocks.failed ? 2 : 1)
   deckRailRow(meeting.board == nil ? "?" : "✓",meeting.board == nil ? "room not loaded" : "room: \(meeting.messages.count) messages loaded",meeting.board == nil ? 0 : 1)
  }
  .padding(14).frame(maxWidth:.infinity,alignment:.leading)
  .background(DeckMono.bg,in:RoundedRectangle(cornerRadius:8))
  .overlay(RoundedRectangle(cornerRadius:8).stroke(HubTheme.line,lineWidth:1))
 }

 var deckGuardRail: some View {
  VStack(alignment:.leading,spacing:7) {
   deckLabel("GUARD")
   deckRailRow(GuardHub.isOffline ? "!" : "✓",GuardHub.isOffline ? "Offline switch is ON: no network" : "Offline switch is off",GuardHub.isOffline ? 2 : 1)
   deckRailRow(hands.enabled ? "!" : "✓",hands.enabled ? "Her hands are ON (Allow box still asks)" : "Her hands are off",hands.enabled ? 2 : 1)
   deckRailRow(live.running ? "!" : "✓",live.running ? "Live session is sharing mic + screen" : "No live session running",live.running ? 2 : 1)
   Button { hubSelect(.shield) } label: { Text("open Guard ›").font(DeckMono.font(11)).foregroundStyle(HubTheme.teal) }.buttonStyle(.plain)
  }
  .padding(14).frame(maxWidth:.infinity,alignment:.leading)
  .background(DeckMono.bg,in:RoundedRectangle(cornerRadius:8))
  .overlay(RoundedRectangle(cornerRadius:8).stroke(HubTheme.line,lineWidth:1))
 }
}
