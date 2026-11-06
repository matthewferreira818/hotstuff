import SwiftUI
import AppKit

// The Hack Room (Friday's design, meeting-room/notes/friday-hack-room.md; built by Friday 2026-11-06).
// A movie-style ops screen over feeds The Helm ALREADY reads. Matthew's rule: "all real, no fake scrolling code, no fake numbers".
// So: every line on the tape comes from a source the app actually read, with that source's own time. No source = no line.
// Decoration (glow, scanlines, the orb, the cursor) never looks like data. A failed read says so; old data is shown with "as of".
// NO NEW GITHUB READS: it reuses the room/Hotline reader (crew chat, max once per 5 min), CrewSignals (1 per 6 min), and the hub loaders.
// The only things it can DO: ask Friday (FridayBrain, unchanged) and, after a Yes on screen, post Matthew's own words to the Hotline (PR #35)
// through his gh login, tagged [Matthew → Local Claude], where the Switchboard's own locks decide what happens. Esc hides the screen.

enum HackSource: String, CaseIterable { case room, robots, runs, crew, store, orders, inbox }

enum HackLight { case fresh, stale, failed, off }

// The inbox, the honest way: the app never touches Gmail. Whichever chat checks the business inbox writes counts only to this private file.
struct HackInbox: Codable {
 var checkedAt: String       // ISO 8601
 var by: String
 var replies: Int
 var bounces: Int
 var unsubscribes: Int
 var cbdc: Bool

 static var fileURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Claude/Helm-Private/friday/hackroom/inbox.json") }
 static func read() -> (inbox: HackInbox, at: Date)? {
  guard let d = try? Data(contentsOf:fileURL), let box = try? JSONDecoder().decode(HackInbox.self,from:d) else { return nil }
  let iso = ISO8601DateFormatter()
  guard let at = iso.date(from:box.checkedAt) else { return nil }
  return (box,at)
 }
}

@MainActor final class HackRoomState: ObservableObject {
 static let shared = HackRoomState()
 @Published var hidden = false
 @Published var pendingJob: String?          // words waiting for his Yes before they go to the Hotline
 @Published var jobNote = ""                 // plain result of the last Hotline send (only what gh actually reported)
 @Published var sending = false

 func sendToHotline(_ text: String) {
  guard !sending else { return }
  sending = true
  jobNote = ""
  let body = "**[Matthew → Local Claude]** " + text + "\n\n(sent from The Helm's Hack Room)"
  Task.detached {
   let ok = HackRoomState.gh(["pr","comment","35","--repo","matthewferreira818/hotstuff","--body",body])
   await MainActor.run {
    self.sending = false
    self.pendingJob = nil
    self.jobNote = ok ? "Sent to the Hotline (PR #35). The Switchboard picks it up only if it's ON; its result shows on the tape as JOB."
                      : "Not sent: gh couldn't post (not logged in, offline, or GitHub refused). Nothing went out."
   }
  }
 }

 nonisolated static func gh(_ args: [String]) -> Bool {
  let home = FileManager.default.homeDirectoryForCurrentUser.path
  let candidates = [home + "/Claude/bin/gh","/opt/homebrew/bin/gh","/usr/local/bin/gh"]
  guard let exe = candidates.first(where:{ FileManager.default.isExecutableFile(atPath:$0) }) else { return false }
  let p = Process()
  p.executableURL = URL(fileURLWithPath:exe)
  p.arguments = args
  p.standardOutput = FileHandle.nullDevice
  p.standardError = FileHandle.nullDevice
  do { try p.run() } catch { return false }
  p.waitUntilExit()
  return p.terminationStatus == 0
 }
}

enum HackPalette {
 static let bg = HubTheme.hex(0x060607)
 static let panel = HubTheme.hex(0x0F0F12)
 static let crimson = Color(red:0.86,green:0.16,blue:0.24)
 static let cyan = Color(red:0.35,green:0.85,blue:0.95)
}

extension CompanionInterfaceView {

 // MARK: the tape: every line from a real read

 var hackTape: [DeckTapeLine] {
  var lines: [DeckTapeLine] = []
  // Paper trades + automation runs: the existing tape (its room lines are replaced by the crew chat's room + Hotline below).
  lines += deckTape.filter { $0.tag != "ROOM" }
  // Room (issue 15) and Hotline (PR 35): only while the last read succeeded (CrewChatHub empties the list on a failed read).
  for m in meeting.chat.shown.suffix(30) {
   guard let date = m.date else { continue }
   let who = MeetingData.display(MeetingData.canonical(m.author) ?? m.author)
   let to = m.to.isEmpty ? "" : " → \(m.to)"
   let hot = m.source == "hotline"
   lines.append(DeckTapeLine(id:"c-\(m.source)-\(m.id)",date:date,tag:hot ? "HOTLN" : "CREW",text:"[\(who)\(to)] " + MeetingData.brief(m.text,limit:120),tone:hot ? 2 : 0))
  }
  // Code saved: commits on crew branches (CrewSignals, last 30 min).
  for s in CrewSignals.current().signals where s.what.hasPrefix("commit: ") {
   lines.append(DeckTapeLine(id:"s-\(s.chat)-\(s.date.timeIntervalSince1970)",date:s.date,tag:"SAVE",text:"\(s.chat)  " + String(s.what.dropFirst(8)),tone:1))
  }
  // Jobs: the Switchboard's own log on this Mac (only what it recorded).
  for e in Switchboard.shared.log where ["run","done","failed","stopped","refused"].contains(e.kind) {
   let tone = e.kind == "done" ? 1 : (e.kind == "run" ? 0 : 3)
   lines.append(DeckTapeLine(id:"j-\(e.id)",date:e.at,tag:"JOB",text:MeetingData.brief(e.text,limit:120),tone:tone))
  }
  // Orders: Stripe (read-only key), amounts only, never who.
  if let s = sales.sales {
   for o in s.latest.prefix(10) {
    lines.append(DeckTapeLine(id:"o-\(o.id)",date:o.time,tag:"ORDER",text:"store order  \(o.amount.formatted(.currency(code:o.currency.uppercased())))" + (s.testMode ? "  (test mode)" : ""),tone:1))
   }
  }
  // Visits: one line per GoatCounter read, stamped with the read time (the counter gives totals, not single visits).
  if let st = ventures.store, let at = ventures.storeAt {
   lines.append(DeckTapeLine(id:"v-\(at.timeIntervalSince1970)",date:at,tag:"VISIT",text:"store visitors: \(st.today) today, \(st.week) this week (GoatCounter read)",tone:0))
  }
  // Inbox: counts only, from the crew's private note.
  if let ib = HackInbox.read() {
   let i = ib.inbox
   lines.append(DeckTapeLine(id:"i-\(i.checkedAt)",date:ib.at,tag:"INBOX",text:"check by \(i.by): \(i.replies) replies, \(i.bounces) bounces, \(i.unsubscribes) unsubscribes" + (i.cbdc ? ", CBDC wrote back" : ""),tone:i.cbdc ? 1 : 0))
  }
  var seen = Set<String>()
  return lines.filter { seen.insert($0.id).inserted }.sorted { $0.date > $1.date }.prefix(90).map { $0 }
 }

 // MARK: source lights (green fresh, amber stale, red failed, hollow not connected)

 func hackLight(_ s: HackSource) -> (HackLight,String) {
  let now = Date()
  func age(_ d: Date?,fresh: TimeInterval) -> HackLight { guard let d else { return .off }; return now.timeIntervalSince(d) < fresh ? .fresh : .stale }
  switch s {
  case .room:
   switch meeting.chat.status {
   case .loaded(let d): return (age(d,fresh:900),"room + Hotline read \(hubAgo(d))")
   case .failed(let d): return (.failed,"couldn't read the room (as of \(crewChatTime(d)))")
   case .loading: return (.stale,"reading the room…")
   case .idle: return (.off,"room not read yet")
   }
  case .robots:
   if stocks.failed { return (.failed,"robot snapshots unavailable") }
   let n = deckRobots.filter { $0.robot != nil }.count
   let newest = deckRobots.compactMap { $0.robot?.updated }.max()
   return n == 0 ? (.off,"robots not loaded") : (age(newest,fresh:3600),"\(n) of 7 robot snapshots, newest \(hubAgo(newest))")
  case .runs:
   guard let runs = ventures.runs else { return (ventures.failed ? .failed : .off,"automation runs not loaded") }
   return (runs.contains { $0.isFailing } ? .stale : .fresh,"\(runs.count) GitHub automations, \(runs.filter { $0.isFailing }.count) failing")
  case .crew:
   let c = CrewSignals.current()
   if !c.loaded { return (.off,"crew signals not read yet") }
   return c.failed ? (.failed,"couldn't read crew signals") : (.fresh,"\(c.signals.count) crew signs of life in 30 min")
  case .store:
   if ventures.storeFailed { return (.failed,"couldn't read GoatCounter") }
   return (age(ventures.storeAt,fresh:1800),ventures.storeAt.map { "GoatCounter read \(hubAgo($0))" } ?? "store visits not read yet")
  case .orders:
   if !sales.hasKey { return (.off,"Stripe isn't connected to The Helm") }
   guard sales.sales != nil else { return (.failed,"couldn't read Stripe yet") }
   return (age(sales.lastRefresh == .distantPast ? nil : sales.lastRefresh,fresh:1800),"Stripe read \(hubAgo(sales.lastRefresh))")
  case .inbox:
   guard let ib = HackInbox.read() else { return (.off,"inbox not connected: waiting for the crew's counts file") }
   return (age(ib.at,fresh:12 * 3600),"inbox checked by \(ib.inbox.by) \(hubAgo(ib.at))")
  }
 }

 func hackLightColor(_ l: HackLight) -> Color {
  switch l { case .fresh: return HubTheme.green; case .stale: return HubTheme.amber; case .failed: return Color(red:0.95,green:0.40,blue:0.40); case .off: return HubTheme.subtext }
 }

 func hackTagColor(_ line: DeckTapeLine) -> Color {
  switch line.tag {
  case "CREW": return HackPalette.cyan
  case "HOTLN": return HubTheme.amber
  case "SAVE": return HubTheme.green
  case "JOB": return line.tone == 3 ? deckToneColor(3) : HackPalette.crimson
  case "ORDER": return HubTheme.green
  case "VISIT", "INBOX": return HubTheme.teal
  default: return deckToneColor(line.tone)
  }
 }

 // MARK: the screen

 var hackRoom: some View {
  HackRoomFrame(state:HackRoomState.shared) {
   VStack(spacing:0) {
    hackTopBar
    coreTiles.padding(.horizontal,16).padding(.top,12)
    HStack(alignment:.top,spacing:12) {
     hackCrewRail.frame(width:220)
     hackTapePanel
     hackRightRail.frame(width:250)
    }
    .padding(.horizontal,16).padding(.top,12)
    HackCommandLine(brain:FridayBrain.shared,room:HackRoomState.shared,switchboard:Switchboard.shared)
     .padding(.horizontal,16).padding(.vertical,12)
   }
  }
  .onAppear {
   Task { await meeting.chat.refresh(token:meeting.hasToken ? meeting.savedToken() : nil) }   // self-limited to once per 5 min
   CrewSignals.refreshIfStale()
  }
 }

 var hackTopBar: some View {
  HStack(spacing:14) {
   Text("F.R.I.D.A.Y.").font(DeckMono.font(14,.heavy)).foregroundStyle(HackPalette.crimson).shadow(color:HackPalette.crimson.opacity(0.7),radius:6)
   Text("// COMMAND CORE").font(DeckMono.font(13,.bold)).foregroundStyle(HubTheme.text.opacity(0.85))
   TimelineView(.periodic(from:.now,by:1)) { t in
    Text(hackClock(t.date)).font(DeckMono.font(12)).foregroundStyle(HubTheme.subtext)
   }
   Spacer(minLength:0)
   ForEach(HackSource.allCases,id:\.self) { s in
    let l = hackLight(s)
    HStack(spacing:4) {
     Circle().fill(l.0 == .off ? Color.clear : hackLightColor(l.0)).overlay(Circle().stroke(hackLightColor(l.0),lineWidth:1)).frame(width:7,height:7)
      .shadow(color:l.0 == .fresh ? HubTheme.green.opacity(0.8) : .clear,radius:3)
     Text(s.rawValue).font(DeckMono.font(10.5)).foregroundStyle(HubTheme.subtext)
    }
    .help(l.1)
   }
  }
  .padding(.horizontal,18).padding(.vertical,10)
  .overlay(alignment:.bottom) { Rectangle().fill(LinearGradient(colors:[.clear,HackPalette.crimson.opacity(0.6),.clear],startPoint:.leading,endPoint:.trailing)).frame(height:1) }
 }

 func hackClock(_ d: Date) -> String {
  let f = DateFormatter()
  f.timeZone = TimeZone(identifier:"America/Moncton")
  f.dateFormat = "EEE HH:mm:ss"
  return f.string(from:d) + " Moncton"
 }

 func hackPanel<C: View>(_ title: String,@ViewBuilder _ content: () -> C) -> some View {
  VStack(alignment:.leading,spacing:7) {
   Text(title).font(DeckMono.font(10.5,.bold)).foregroundStyle(HackPalette.crimson.opacity(0.9)).tracking(1.5)
   content()
  }
  .padding(12).frame(maxWidth:.infinity,alignment:.leading)
  .background(HackPalette.panel,in:RoundedRectangle(cornerRadius:6))
  .overlay(RoundedRectangle(cornerRadius:6).stroke(HackPalette.crimson.opacity(0.25),lineWidth:1))
 }

 var hackCrewRail: some View {
  let crew = deckCrewReal.filter { $0.kind == .chat || $0.kind == .cloud || $0.kind == .friday || $0.kind == .agent }
  return ScrollView {
   hackPanel("CREW") {
    if crew.isEmpty { Text("no crew data read yet").font(DeckMono.font(11)).foregroundStyle(HubTheme.subtext) }
    ForEach(crew) { m in
     HStack(alignment:.firstTextBaseline,spacing:7) {
      Circle().fill(m.state == .working ? HubTheme.green : Color.clear).overlay(Circle().stroke(deckStateColor(m.state),lineWidth:1)).frame(width:7,height:7)
      VStack(alignment:.leading,spacing:1) {
       Text(m.name).font(DeckMono.font(11.5,.semibold)).foregroundStyle(HubTheme.text).lineLimit(1)
       Text(m.since.map { "\(m.detail) · \(hubAgo($0))" } ?? m.detail).font(DeckMono.font(10)).foregroundStyle(HubTheme.subtext).lineLimit(2)
      }
      Spacer(minLength:0)
     }
    }
    Text("lit = a real post or commit in the last 30 min").font(DeckMono.font(9.5)).foregroundStyle(HubTheme.subtext.opacity(0.8)).padding(.top,4)
   }
  }
 }

 var hackTapePanel: some View {
  let tape = hackTape
  return VStack(alignment:.leading,spacing:0) {
   HStack(spacing:8) {
    Text("LIVE TAPE").font(DeckMono.font(10.5,.bold)).foregroundStyle(HackPalette.crimson).tracking(1.5)
    Text("newest first · real events only").font(DeckMono.font(10.5)).foregroundStyle(HubTheme.subtext)
    Spacer(minLength:0)
    if let newest = tape.first?.date { Text("latest \(hubAgo(newest))").font(DeckMono.font(10.5)).foregroundStyle(HubTheme.subtext) }
   }
   .padding(.horizontal,12).padding(.vertical,9)
   .overlay(alignment:.bottom) { Rectangle().fill(HubTheme.line).frame(height:1) }
   ScrollView {
    VStack(alignment:.leading,spacing:5) {
     if tape.isEmpty {
      Text(meeting.loading || ventures.loading || stocks.loading ? "reading…" : "quiet: nothing read yet. Refresh with Command-R.").font(DeckMono.font(12)).foregroundStyle(HubTheme.subtext)
     }
     ForEach(tape) { line in
      HStack(alignment:.firstTextBaseline,spacing:10) {
       Text(deckTapeTime(line.date)).font(DeckMono.font(11)).foregroundStyle(HubTheme.subtext).frame(width:96,alignment:.leading)
       Text(line.tag).font(DeckMono.font(11,.bold)).foregroundStyle(hackTagColor(line)).frame(width:46,alignment:.leading)
       Text(line.text).font(DeckMono.font(11.5)).foregroundStyle(HubTheme.text).lineLimit(2).fixedSize(horizontal:false,vertical:true)
       Spacer(minLength:0)
      }
      .transition(.move(edge:.top).combined(with:.opacity))
     }
    }
    .padding(12)
    .animation(reduceMotion ? nil : .easeOut(duration:0.45),value:tape.map { $0.id })
   }
  }
  .frame(maxWidth:.infinity,maxHeight:.infinity)
  .background(HackPalette.panel,in:RoundedRectangle(cornerRadius:6))
  .overlay(RoundedRectangle(cornerRadius:6).stroke(HackPalette.crimson.opacity(0.35),lineWidth:1))
  .shadow(color:HackPalette.crimson.opacity(0.18),radius:12)
 }

 var hackRightRail: some View {
  ScrollView {
   VStack(spacing:10) {
    hackPanel("ROBOTS · PAPER MONEY") {
     let loaded = deckRobots.filter { $0.robot != nil }
     if loaded.isEmpty { Text(stocks.failed ? "snapshots unavailable" : "not loaded yet").font(DeckMono.font(11)).foregroundStyle(HubTheme.subtext) }
     ForEach(loaded,id:\.name) { e in
      if let r = e.robot {
       HStack {
        Text(e.name.replacingOccurrences(of:"stock-",with:"")).font(DeckMono.font(11)).foregroundStyle(HubTheme.text).lineLimit(1)
        Spacer(minLength:4)
        Text((r.sinceStart >= 0 ? "+" : "") + hubMoney(r.sinceStart)).font(DeckMono.font(11,.semibold)).foregroundStyle(r.sinceStart >= 0 ? HubTheme.green : deckToneColor(3))
       }
      }
     }
     if let newest = deckRobots.compactMap({ $0.robot?.updated }).max() {
      Text("since start · as of \(deckTapeTime(newest))").font(DeckMono.font(9.5)).foregroundStyle(HubTheme.subtext)
     }
    }
    hackPanel("STORE") {
     if let st = ventures.store {
      Text("visitors today \(st.today) · week \(st.week)").font(DeckMono.font(11)).foregroundStyle(HubTheme.text)
     } else {
      Text(ventures.storeFailed ? "couldn't read GoatCounter" : "visits not read yet").font(DeckMono.font(11)).foregroundStyle(HubTheme.subtext)
     }
     Text(simpleOrdersLine.0).font(DeckMono.font(11)).foregroundStyle(HubTheme.text)
     Text(simpleOrdersLine.1).font(DeckMono.font(9.5)).foregroundStyle(HubTheme.subtext)
    }
    hackPanel("INBOX · COUNTS ONLY") {
     if let ib = HackInbox.read() {
      Text("\(ib.inbox.replies) replies · \(ib.inbox.bounces) bounces · \(ib.inbox.unsubscribes) unsubs").font(DeckMono.font(11)).foregroundStyle(HubTheme.text)
      Text(ib.inbox.cbdc ? "CBDC wrote back" : "no word from CBDC yet").font(DeckMono.font(11)).foregroundStyle(ib.inbox.cbdc ? HubTheme.green : HubTheme.subtext)
      Text("checked by \(ib.inbox.by) · \(deckTapeTime(ib.at))").font(DeckMono.font(9.5)).foregroundStyle(HubTheme.subtext)
     } else {
      Text("not connected yet: the crew's Gmail check will write the counts here").font(DeckMono.font(10.5)).foregroundStyle(HubTheme.subtext)
     }
    }
    hackPanel("SWITCHBOARD") {
     Text(Switchboard.shared.on ? "ON · jobs from the Hotline run on this Mac" : "OFF · jobs wait until you switch it on (Friday page)").font(DeckMono.font(10.5)).foregroundStyle(Switchboard.shared.on ? HubTheme.green : HubTheme.subtext)
    }
   }
  }
 }
}

// Esc hides everything behind her orb (for screen-sharing); Esc or a click brings it back.
struct HackRoomFrame<Content: View>: View {
 @ObservedObject var state: HackRoomState
 @ViewBuilder var content: Content
 @Environment(\.accessibilityReduceMotion) private var reduceMotion

 var body: some View {
  ZStack {
   HackPalette.bg
   if !reduceMotion {
    // Decoration only: faint scanlines. No text, no numbers.
    Canvas { ctx, size in
     var y: CGFloat = 0
     while y < size.height { ctx.fill(Path(CGRect(x:0,y:y,width:size.width,height:1)),with:.color(.white.opacity(0.018))); y += 3 }
    }
    .allowsHitTesting(false)
   }
   RadialGradient(colors:[CoreStyle.crimson.opacity(0.06),.clear],center:.top,startRadius:20,endRadius:700).allowsHitTesting(false)
   if state.hidden {
    VStack(spacing:14) {
     Circle().fill(RadialGradient(colors:[HackPalette.crimson,HackPalette.crimson.opacity(0.15)],center:.center,startRadius:2,endRadius:60)).frame(width:110,height:110)
      .shadow(color:HackPalette.crimson.opacity(0.7),radius:24)
     Text("hidden · press Esc to show").font(DeckMono.font(11)).foregroundStyle(HubTheme.subtext)
    }
    .contentShape(Rectangle())
    .onTapGesture { state.hidden = false }
   } else {
    content
   }
   Button("") { state.hidden.toggle() }.keyboardShortcut(.escape,modifiers:[]).opacity(0).frame(width:0,height:0)
  }
 }
}

struct HackCommandLine: View {
 @ObservedObject var brain: FridayBrain
 @ObservedObject var room: HackRoomState
 @ObservedObject var switchboard: Switchboard

 var body: some View {
  VStack(alignment:.leading,spacing:6) {
   if let last = brain.turns.last(where:{ $0.role == "friday" }), !brain.thinking {
    Text("friday › " + last.text).font(DeckMono.font(11.5)).foregroundStyle(HackPalette.cyan).lineLimit(4).textSelection(.enabled)
   }
   if brain.thinking { Text("friday › thinking…").font(DeckMono.font(11.5)).foregroundStyle(HubTheme.subtext) }
   if !brain.note.isEmpty { Text(brain.note).font(DeckMono.font(10)).foregroundStyle(HubTheme.subtext) }
   if let job = room.pendingJob {
    HStack(spacing:10) {
     Text("Send to the crew on the Hotline as [Matthew → Local Claude]: \"\(MeetingData.brief(job,limit:80))\"? It's a public repo.").font(DeckMono.font(11)).foregroundStyle(HubTheme.amber)
     Button(room.sending ? "Sending…" : "Yes, send") { room.sendToHotline(job) }.disabled(room.sending)
     Button("Cancel") { room.pendingJob = nil }.disabled(room.sending)
    }
   }
   if !room.jobNote.isEmpty { Text(room.jobNote).font(DeckMono.font(10.5)).foregroundStyle(HubTheme.subtext) }
   HStack(spacing:0) {
    Text("friday@helm:~$ ").font(DeckMono.font(13,.semibold)).foregroundStyle(HubTheme.green)
    TextField("ask me anything · ⌘↩ sends it to the crew as a job",text:$brain.draft)
     .textFieldStyle(.plain).font(DeckMono.font(13)).foregroundStyle(HubTheme.text)
     .onSubmit { brain.send() }
     .disabled(brain.thinking)
    Button("") {
     let t = brain.draft.trimmingCharacters(in:.whitespacesAndNewlines)
     guard !t.isEmpty else { return }
     room.pendingJob = t
     brain.draft = ""
    }.keyboardShortcut(.return,modifiers:.command).opacity(0).frame(width:0,height:0)
   }
   .padding(.horizontal,12).padding(.vertical,10)
   .background(HackPalette.panel,in:RoundedRectangle(cornerRadius:6))
   .overlay(RoundedRectangle(cornerRadius:6).stroke(HubTheme.green.opacity(0.35),lineWidth:1))
  }
 }
}
