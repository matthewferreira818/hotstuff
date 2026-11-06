import SwiftUI
import AppKit

// Phase 2 screens (LC-Pixels): the crew chat writing box, "Friday & me" (private), the Memory page, and the Money Move card on Home.
// Pure rules live in ScreensP2Data.swift. Nothing here holds a key: posting uses the room key already saved on this Mac, else Matthew's own gh login.
// No @State here (the command-line build can't expand it): small shared models hold each screen's state.

// MARK: posting to the room (issue 15) with an id back

enum GitHubPost {
 // Saved key first, then his gh login (the same chain the reads use). Returns the new comment's id so the screen can show "pinged ✓".
 static func comment(issue: Int,body: String,token: String?) async -> (ok: Bool,id: Int?,error: String) {
  if let token = token, !token.isEmpty, MeetingData.tokenProblem(token) == nil,
     let json = try? JSONSerialization.data(withJSONObject:["body":body]),
     let call = MeetingData.api("/issues/\(issue)/comments",token:token,method:"POST",body:json),
     let (data,response) = try? await URLSession.shared.data(for:call), let code = (response as? HTTPURLResponse)?.statusCode, code == 201 {
   return (true,ComposerRules.commentID(data),"")
  }
  guard FileManager.default.isExecutableFile(atPath:GitHubRead.ghPath) else {
   return (false,nil,"Couldn't send: posting isn't connected on this Mac yet (Accounts → GitHub key, or the gh login).")
  }
  let args = ["api","repos/\(MeetingData.owner)/\(MeetingData.repo)/issues/\(issue)/comments","-f","body=\(body)"]
  let result: (Bool,Data) = await withCheckedContinuation { cont in
   DispatchQueue.global().async {
    let p = Process()
    p.executableURL = URL(fileURLWithPath:GitHubRead.ghPath)
    p.arguments = args
    p.standardInput = FileHandle.nullDevice
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { cont.resume(returning:(false,Data())); return }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    cont.resume(returning:(p.terminationStatus == 0,data))
   }
  }
  if result.0, let id = ComposerRules.commentID(result.1) { return (true,id,"") }
  return (false,nil,"Couldn't send: GitHub didn't take the message. Check your internet and try again.")
 }
}

// MARK: 1. Crew chat writing box

@MainActor final class CrewComposerModel: ObservableObject {
 static let shared = CrewComposerModel()
 @Published var draft = ""
 @Published var target = "Everyone"
 @Published var sending = false
 @Published var note = ""
 @Published var noteOK = true
}

struct CrewComposerBar: View {
 @ObservedObject var m = CrewComposerModel.shared
 @ObservedObject var board = Switchboard.shared
 let targets: [String]
 let send: () -> Void

 var body: some View {
  VStack(alignment:.leading,spacing:4) {
   // Nobody gets woken while the Switchboard is off, so say so right above the box (nothing extra when it is on).
   if !board.on {
    Text("Pings are off. Turn on the Switchboard on the Friday tab so the crew gets woken.").font(.system(size:12.5,weight:.medium)).foregroundStyle(HubTheme.amber).fixedSize(horizontal:false,vertical:true)
   }
   HStack(spacing:8) {
    Menu {
     ForEach(targets,id:\.self) { name in Button { m.target = name } label: { Label(name,systemImage:m.target == name ? "checkmark" : "person") } }
    } label: {
     HStack(spacing:5) {
      Text("To: \(m.target)").font(.system(size:14,weight:.medium)).lineLimit(1)
      Image(systemName:"chevron.down").font(.system(size:9,weight:.bold))
     }
     .foregroundStyle(HubTheme.text).padding(.horizontal,12).frame(height:40)
     .overlay(RoundedRectangle(cornerRadius:10).stroke(HubTheme.controlOutline,lineWidth:1))
    }
    .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
    .accessibilityLabel("Send to: \(m.target). Pick who the message is for")
    TextField("Message \(m.target)…",text:$m.draft)
     .textFieldStyle(.plain).font(.system(size:14))
     .padding(.horizontal,12).frame(minHeight:40)
     .background(HubTheme.control,in:RoundedRectangle(cornerRadius:10))
     .overlay(RoundedRectangle(cornerRadius:10).stroke(HubTheme.controlOutline,lineWidth:1))
     .onSubmit { send() }
     .disabled(m.sending)
     .accessibilityLabel("Message to \(m.target)")
    Button { send() } label: {
     Text(m.sending ? "Sending…" : "Send").font(.system(size:14,weight:.semibold)).foregroundStyle(HubTheme.background)
      .padding(.horizontal,16).frame(height:40).background(HubTheme.green.opacity(m.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || m.sending ? 0.4 : 1),in:RoundedRectangle(cornerRadius:10))
    }
    .buttonStyle(.plain).disabled(m.sending || m.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
    .accessibilityLabel("Send message")
   }
   if !m.note.isEmpty {
    Text(m.note).font(.system(size:12)).foregroundStyle(m.noteOK ? HubTheme.green : HubTheme.amber).fixedSize(horizontal:false,vertical:true)
   }
  }
  .padding(.top,6)
 }
}

// The small "pinged ✓ LC-Manager" mark under a message of his, from the Switchboard's wake results (shows nothing if it wasn't a ping).
struct PingBadge: View {
 let id: Int
 @ObservedObject var wake = WakeRunner.shared
 // The engine writes the wording itself (pinged ✓ X, X isn't open, "X closed → Friday has it", "pinged ✓ X (when it reopened)"); the screen shows it as is.
 var body: some View {
  if let r = wake.result(forComment:Int64(id)) {
   let words = r.badge
   Text(words).font(.system(size:11.5,weight:.medium)).foregroundStyle(r.allOK ? HubTheme.green : HubTheme.amber)
    .accessibilityLabel(words)
  }
 }
}

extension CompanionInterfaceView {
 var crewComposer: some View {
  CrewComposerBar(targets:ComposerRules.targets(openChats:meeting.lcNames)) { Task { await crewSend() } }
 }

 func crewSend() async {
  let m = CrewComposerModel.shared
  guard !m.sending, let body = ComposerRules.body(to:m.target,text:m.draft) else { return }
  m.sending = true
  m.note = ""
  let token = meeting.hasToken ? meeting.savedToken() : nil
  let r = await GitHubPost.comment(issue:MeetingData.issue,body:body,token:token)
  m.sending = false
  if r.ok {
   m.draft = ""
   m.noteOK = true
   m.note = "sent ✓ to \(m.target)"
   await meeting.chat.refresh(token:token,force:true)
  } else {
   m.noteOK = false
   m.note = r.error
  }
 }
}

// MARK: 2. Friday & me (private)

@MainActor final class FridayMeModel: ObservableObject {
 static let shared = FridayMeModel()
 @Published var open = false
 @Published var draft = ""
}

struct FridayMeSection: View {
 @ObservedObject var model = FridayMeModel.shared
 @ObservedObject var dm = FridayDM.shared
 var reduceMotion = false

 struct Line: Identifiable { var id: String; var at: Date; var mine: Bool; var text: String }
 var lines: [Line] {
  (dm.sent.map { Line(id:"s-" + $0.id,at:$0.at,mine:true,text:$0.text) } + dm.replies.map { Line(id:"r-" + $0.id,at:$0.at,mine:false,text:$0.text) })
   .sorted { $0.at < $1.at }
 }
 var thinking: Bool {
  let last = dm.sent.last?.id
  return DMScreenRules.thinking(lastSentID:last,repliedTo:Set(dm.replies.map { $0.replyTo }),state:last.flatMap { dm.statuses[$0]?.state })
 }
 private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; f.timeZone = TimeZone(identifier:"America/Moncton"); return f }()

 var body: some View {
  VStack(alignment:.leading,spacing:8) {
   Button { withAnimation(.easeOut(duration:0.2)) { model.open.toggle() } } label: {
    HStack(spacing:8) {
     Image(systemName:"lock.fill").font(.system(size:12))
     Text("Friday & me").font(.system(size:15,weight:.medium))
     Image(systemName:model.open ? "chevron.up" : "chevron.down").font(.system(size:10,weight:.bold))
    }
    .foregroundStyle(HubTheme.text).padding(.horizontal,18).frame(height:42)
    .overlay(RoundedRectangle(cornerRadius:12).stroke(model.open ? HubTheme.green : HubTheme.controlOutline,lineWidth:1))
   }
   .buttonStyle(.plain).frame(maxWidth:.infinity)
   .accessibilityLabel("Friday and me, a private chat").accessibilityValue(model.open ? "open" : "closed")
   if model.open { panel }
  }
 }

 var panel: some View {
  VStack(alignment:.leading,spacing:8) {
   HStack(spacing:8) {
    TimelineView(.animation(minimumInterval:1.0/24.0,paused:reduceMotion || !thinking)) { timeline in
     FridayOrb(state:thinking ? .thinking : .idle,t:timeline.date.timeIntervalSinceReferenceDate,level:0,size:30,animated:!reduceMotion && thinking,showsPicker:false)
    }
    .frame(width:36,height:36)
    VStack(alignment:.leading,spacing:1) {
     Text("Private chat with Friday").font(.system(size:13,weight:.semibold)).foregroundStyle(HubTheme.text)
     Text(thinking ? "Friday is thinking…" : "Only on this Mac. Not in the crew chat, the room or GitHub.").font(.system(size:11.5)).foregroundStyle(thinking ? HubTheme.amber : HubTheme.subtext)
    }
    Spacer(minLength:0)
   }
   if let closed = dm.closedNote, dm.sent.last.map({ dm.statuses[$0.id]?.state == "closed" }) ?? false {
    Text(closed).font(.system(size:12)).foregroundStyle(HubTheme.amber).fixedSize(horizontal:false,vertical:true)
   }
   ScrollViewReader { proxy in
    ScrollView {
     VStack(spacing:8) {
      if lines.isEmpty { Text("Say hi. Only the two of us see this.").font(.system(size:13)).foregroundStyle(HubTheme.subtext).padding(.vertical,14) }
      ForEach(lines) { line in bubble(line) }
      Color.clear.frame(height:1).id("end")
     }
    }
    .frame(maxHeight:230).scrollIndicators(.hidden)
    .onAppear { proxy.scrollTo("end",anchor:.bottom) }
    .onChange(of:lines.count) { _,_ in proxy.scrollTo("end",anchor:.bottom) }
   }
   HStack(spacing:8) {
    TextField("Message Friday…",text:$model.draft)
     .textFieldStyle(.plain).font(.system(size:13))
     .padding(.horizontal,10).frame(minHeight:HubTheme.minTarget)
     .background(HubTheme.control,in:RoundedRectangle(cornerRadius:8))
     .overlay(RoundedRectangle(cornerRadius:8).stroke(HubTheme.controlOutline,lineWidth:1))
     .onSubmit { sendNow() }
     .accessibilityLabel("Private message to Friday")
    Button { sendNow() } label: {
     Text("Send").font(.system(size:13,weight:.semibold)).foregroundStyle(HubTheme.background).padding(.horizontal,14).frame(height:HubTheme.minTarget)
      .background(HubTheme.green.opacity(model.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty ? 0.4 : 1),in:RoundedRectangle(cornerRadius:8))
    }.buttonStyle(.plain).disabled(model.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
   }
  }
  .padding(12)
  .background(HubTheme.card,in:RoundedRectangle(cornerRadius:12))
  .onAppear { dm.start() }
 }

 func sendNow() {
  let text = model.draft.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !text.isEmpty else { return }
  if dm.send(text) != nil { model.draft = "" }
 }

 func bubble(_ line: Line) -> some View {
  HStack {
   if line.mine { Spacer(minLength:40) }
   VStack(alignment:line.mine ? .trailing : .leading,spacing:2) {
    Text(line.text).font(.system(size:13.5)).foregroundStyle(line.mine ? HubTheme.background : HubTheme.text).textSelection(.enabled)
     .padding(.horizontal,12).padding(.vertical,8)
     .background(line.mine ? HubTheme.green : HubTheme.control,in:RoundedRectangle(cornerRadius:14))
    Text((line.mine ? "You" : "Friday") + " · " + Self.time.string(from:line.at)).font(.system(size:10.5)).foregroundStyle(HubTheme.subtext)
    if line.mine, let note = dm.note(forMessage:String(line.id.dropFirst(2))) { Text(note).font(.system(size:11)).foregroundStyle(HubTheme.amber) }
   }
   if !line.mine { Spacer(minLength:40) }
  }
  .accessibilityElement(children:.combine)
 }
}

// MARK: 3. Memory page (Keep / Edit / Forget)

@MainActor final class MemoryModel: ObservableObject {
 static let shared = MemoryModel()
 static let fileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Claude/Helm-Private/friday/memory.md")
 @Published var entries: [MemoryEntry] = []
 @Published var loaded = false
 @Published var missing = false
 @Published var note = ""
 @Published var editing: String? = nil
 @Published var editText = ""
 @Published var forgetting: String? = nil

 func load() {
  guard let text = try? String(contentsOf:Self.fileURL,encoding:.utf8) else { entries = []; missing = true; loaded = true; return }
  missing = false
  entries = MemoryBank.parse(text)
  loaded = true
 }

 // Every change re-reads the file first, so an entry Friday saved a minute ago is never lost.
 private func change(_ what: String,_ op: (String) -> String?) {
  guard let text = try? String(contentsOf:Self.fileURL,encoding:.utf8) else { note = "Couldn't read Friday's memory file."; return }
  guard let out = op(text) else { note = "That note is no longer in the file."; load(); return }
  do { try out.write(to:Self.fileURL,atomically:true,encoding:.utf8); note = what } catch { note = "Couldn't save the change." }
  load()
 }
 func keep(_ id: String) { change("Kept. She can bring it up on her own.") { MemoryBank.keep($0,id:id) } }
 func save(_ id: String) { let t = editText; change("Saved.") { MemoryBank.edit($0,id:id,text:t) }; editing = nil }
 func forget(_ id: String) { change("Forgotten. It's out of her memory file.") { MemoryBank.forget($0,id:id) }; forgetting = nil }
}

struct MemoryPageView: View {
 @ObservedObject var m = MemoryModel.shared

 var body: some View {
  VStack(alignment:.leading,spacing:10) {
   HStack(alignment:.firstTextBaseline) {
    VStack(alignment:.leading,spacing:2) {
     Text("\(m.entries.count) notes").font(.system(size:13)).foregroundStyle(HubTheme.subtext)
    }
    Spacer()
    Button { m.load() } label: { Label("Reload",systemImage:"arrow.clockwise").font(.system(size:13,weight:.medium)).foregroundStyle(HubTheme.text).padding(.horizontal,12).frame(height:34).overlay(RoundedRectangle(cornerRadius:9).stroke(HubTheme.controlOutline,lineWidth:1)) }.buttonStyle(.plain)
   }
   if !m.note.isEmpty { Text(m.note).font(.system(size:12)).foregroundStyle(HubTheme.green) }
   if m.missing {
    Text("Friday's memory file isn't on this Mac yet.").font(.system(size:14)).foregroundStyle(HubTheme.subtext).padding(.vertical,24)
   } else if m.loaded && m.entries.isEmpty {
    Text("Nothing remembered yet.").font(.system(size:14)).foregroundStyle(HubTheme.subtext).padding(.vertical,24)
   }
   ScrollView {
    LazyVStack(spacing:8) {
     ForEach(m.entries.reversed()) { entry in row(entry) }
    }
   }
   .scrollIndicators(.hidden)
  }
  .padding(.horizontal,28).padding(.vertical,16)
  .onAppear { m.load() }
  .confirmationDialog("Forget this?",isPresented:Binding(get:{ m.forgetting != nil },set:{ if !$0 { m.forgetting = nil } })) {
   Button("Forget it",role:.destructive) { if let id = m.forgetting { m.forget(id) } }
   Button("Cancel",role:.cancel) { m.forgetting = nil }
  } message: { Text("It is deleted from Friday's memory file. She won't remember it.") }
 }

 func row(_ e: MemoryEntry) -> some View {
  let editing = m.editing == e.id
  return VStack(alignment:.leading,spacing:6) {
   HStack(spacing:8) {
    Text(e.tag.isEmpty ? "Note" : e.tag).font(.system(size:10.5,weight:.bold,design:.monospaced)).foregroundStyle(HubTheme.teal)
     .padding(.horizontal,6).padding(.vertical,1).overlay(RoundedRectangle(cornerRadius:4).stroke(HubTheme.teal.opacity(0.6),lineWidth:1))
    if e.isMood { Label("private",systemImage:"lock.fill").font(.system(size:10.5)).foregroundStyle(HubTheme.subtext) }
    if e.important { Label("kept",systemImage:"star.fill").font(.system(size:10.5)).foregroundStyle(HubTheme.amber) }
    Text("saved \(e.saved) · by \(e.by)").font(.system(size:11)).foregroundStyle(HubTheme.subtext)
    Spacer(minLength:0)
   }
   if editing {
    TextField("Note",text:Binding(get:{ m.editText },set:{ m.editText = $0 }),axis:.vertical)
     .textFieldStyle(.plain).font(.system(size:14)).padding(8).background(HubTheme.control,in:RoundedRectangle(cornerRadius:8))
     .overlay(RoundedRectangle(cornerRadius:8).stroke(HubTheme.green.opacity(0.7),lineWidth:1)).lineLimit(1...4)
     .onSubmit { m.save(e.id) }
   } else {
    Text(e.text).font(.system(size:14)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true).textSelection(.enabled)
   }
   HStack(spacing:8) {
    if editing {
     pill("Save",HubTheme.green) { m.save(e.id) }
     pill("Cancel",HubTheme.subtext) { m.editing = nil }
    } else {
     if !e.important { pill("Keep",HubTheme.green) { m.keep(e.id) } }
     pill("Edit",HubTheme.text) { m.editText = e.text; m.editing = e.id }
     pill("Forget",HubTheme.amber) { m.forgetting = e.id }
    }
   }
  }
  .padding(12).frame(maxWidth:.infinity,alignment:.leading)
  .background(HubTheme.card,in:RoundedRectangle(cornerRadius:12))
 }

 func pill(_ title: String,_ color: Color,_ action: @escaping () -> Void) -> some View {
  Button(action:action) { Text(title).font(.system(size:12.5,weight:.medium)).foregroundStyle(color).padding(.horizontal,12).frame(height:28).overlay(Capsule().stroke(color.opacity(0.7),lineWidth:1)) }.buttonStyle(.plain)
 }
}

// MARK: 4. One Money Move (Home)

@MainActor final class MoneyMoveModel: ObservableObject {
 static let shared = MoneyMoveModel()
 static let fileURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Claude/Helm-Private/friday/money-move.md")
 @Published var move: MoneyMove? = nil
 @Published var loaded = false
 func load() {
  move = (try? String(contentsOf:Self.fileURL,encoding:.utf8)).flatMap { MoneyMoveFile.latest($0) }
  loaded = true
 }
}

struct MoneyMoveCard: View {
 @ObservedObject var model = MoneyMoveModel.shared
 var body: some View {
  VStack(alignment:.leading,spacing:6) {
   Text("One money move").font(.system(size:13,weight:.bold,design:.rounded)).foregroundStyle(HubTheme.amber).accessibilityAddTraits(.isHeader)
   if let move = model.move {
    Text(move.move).font(.system(size:15,weight:.medium)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
    if !move.why.isEmpty { Text(move.why).font(.system(size:12.5)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true) }
    Text("as of \(MoneyMoveFile.asOf(move.date)), from Friday").font(.system(size:11)).foregroundStyle(HubTheme.subtext)
   } else {
    Text(model.loaded ? "Friday hasn't written today's move yet." : "Loading…").font(.system(size:14)).foregroundStyle(HubTheme.subtext)
   }
  }
  .padding(14).frame(maxWidth:.infinity,alignment:.leading)
  .background(HubTheme.card,in:RoundedRectangle(cornerRadius:14))
  .overlay(RoundedRectangle(cornerRadius:14).stroke(HubTheme.amber.opacity(0.35),lineWidth:1))
  .onAppear { model.load() }
  .accessibilityElement(children:.combine)
 }
}

extension CompanionInterfaceView {
 var fridayMemoryPage: some View { MemoryPageView() }
}

// The Friday page's memory card: the count and the newest kept note from the same file as the Memory page.
struct MemoryBankCardBody: View {
 @ObservedObject var m = MemoryModel.shared
 let openPage: () -> Void
 var body: some View {
  let kept = m.entries.last(where:{ $0.important && !$0.isMood })
  VStack(alignment:.leading,spacing:6) {
   Text(m.missing ? "MEMORY · NO FILE YET" : "MEMORY · \(m.entries.count) \(m.entries.count == 1 ? "NOTE" : "NOTES")")
    .font(.system(size:11,weight:.medium,design:.monospaced)).tracking(1.3).foregroundStyle(HubTheme.subtext)
   if let kept = kept { Text(kept.text).font(.system(size:12)).foregroundStyle(HubTheme.text).lineLimit(2) }
   else if m.loaded && !m.missing { Text("Nothing marked to keep yet.").font(.system(size:12)).foregroundStyle(HubTheme.subtext) }
   Button(action:openPage) { Text("What Friday remembers ›").font(.system(size:11,design:.monospaced)).foregroundStyle(HubTheme.teal) }.buttonStyle(.plain)
  }
  .onAppear { m.load() }
 }
}
