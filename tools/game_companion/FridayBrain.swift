import SwiftUI
import AppKit

// Friday Phase 1 piece 1 "She thinks": the runner and the chat box on her page. Every rule is in FridayBrainData.swift; README: FRIDAY-BRAIN.md.
// One call per message, started only by his Send, never in the background. The context goes only to Claude through his own login:
// it is not written to any file, log or repo (the chat log keeps just his messages and her answers).

@MainActor final class FridayBrain: ObservableObject {
 static let shared = FridayBrain()

 @Published var draft = ""
 @Published private(set) var turns: [FridayBrainRules.Turn] = []
 @Published private(set) var thinking = false
 @Published private(set) var note = ""          // small grey line: "Opus (you said think hard)", a source warning, an error
 private var process: Process?

 // Per app ID, so a test copy never shares a chat with the real Helm.
 private let folder: URL = {
  let base = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
  let dir = base.appendingPathComponent("FridayBrain-\(Bundle.main.bundleIdentifier ?? "helm")",isDirectory:true)
  try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  return dir
 }()
 private var logURL: URL { folder.appendingPathComponent("chat.json") }
 // The brain runs here: an empty folder. It has no tools, so it reads nothing, and no repo notes (CLAUDE.md) get loaded into the call.
 private var workURL: URL {
  let dir = folder.appendingPathComponent("work",isDirectory:true)
  try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  return dir
 }

 private init() {
  if let d = try? Data(contentsOf:logURL), let t = try? JSONDecoder().decode([FridayBrainRules.Turn].self,from:d) { turns = t }
 }

 private func saveLog() {
  turns = Array(turns.suffix(FridayBrainLimits.logKeep))
  if let d = try? JSONEncoder().encode(turns) { try? d.write(to:logURL,options:.atomic) }
 }

 func clear() { guard !thinking else { return }; turns = []; note = ""; saveLog() }

 // MARK: sending

 func send() {
  let question = draft.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !question.isEmpty, !thinking else { return }
  draft = ""
  note = ""
  let before = turns
  turns.append(.init(role:"you",text:question))
  saveLog()
  thinking = true
  Task { await run(question,history:before) }
 }

 private func run(_ question: String,history: [FridayBrainRules.Turn]) async {
  defer { thinking = false }
  // Offline backup brain (FridayLocalBrain.swift): only when Claude truly can't run, never because it's slow.
  if GuardHub.isOffline { finish(await offlineAnswer(question,history:history,context:nil,why:"Offline mode is on")); return }
  let found = Switchboard.checkClaude()
  guard let exe = found.exe, found.version != nil else {
   finish(await offlineAnswer(question,history:history,context:nil,why:"the Claude app's engine wasn't found"))
   return
  }
  let settings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
  if let problem = SwitchboardRules.settingsProblem(try? Data(contentsOf:settings)) {
   finish(.init(ok:false,text:"I won't run: \(problem).",note:problem))
   return
  }

  let now = Date()
  async let boardRead = readBoard()
  async let roomRead = readRoom(now:now)
  let board = await boardRead, room = await roomRead
  let context = FridayBrainRules.buildContext(now:now,board:board,room:room,handoff:readHandoff())
  var warnings: [String] = []
  if board.value == nil { warnings.append("couldn't read the board") }
  if room.value == nil { warnings.append("couldn't read the room") }

  let model = FridayBrainRules.wantsOpus(question) ? FridayBrainLimits.hardModel : FridayBrainLimits.model
  let prompt = FridayBrainRules.prompt(context:context,history:FridayBrainRules.history(history),question:question)
  let args = FridayBrainRules.arguments(prompt:prompt,model:model)
  guard FridayBrainRules.argumentsAreSafe(args) else {
   finish(.init(ok:false,text:"I won't run: the command line didn't pass my own safety check.",note:"unsafe command line"))
   return
  }
  FridayBrainTestHooks.saveContext(context,prompt:prompt)   // test copies only

  let began = Date()
  let out = await runProcess(exe,args)
  var answer = FridayBrainRules.answer(from:out.data,exitCode:out.code,timedOut:out.timedOut)
  UsageLedger.shared.record(who:"Friday (brain)",job:model,started:began,ok:answer.ok,data:out.data)   // labels only, never her words
  if !answer.ok && LocalBrainRules.limitHit(out.data) {
   finish(await offlineAnswer(question,history:history,context:context,why:"Claude's usage limit is reached"))
   return
  }
  var notes = warnings
  if model == FridayBrainLimits.hardModel { notes.append("Opus, because you said \"think hard\"") }
  if let n = answer.note { notes.append(n) }
  answer.note = notes.isEmpty ? nil : notes.joined(separator:" · ")
  finish(answer)
 }

 // The offline brain's turn. Without Claude it builds a context from this Mac only (no board or room reads: those use the internet).
 private func offlineAnswer(_ question: String,history: [FridayBrainRules.Turn],context: String?,why: String) async -> FridayBrainRules.Answer {
  let ctx = context ?? FridayBrainRules.buildContext(now:Date(),board:.init(value:nil,readAt:nil),room:.init(value:nil,readAt:nil),handoff:readHandoff())
  return await FridayLocalBrain.answer(question:question,history:FridayBrainRules.history(history),context:ctx,why:why)
 }

 private func finish(_ a: FridayBrainRules.Answer) {
  turns.append(.init(role:"friday",text:a.text))
  note = a.note ?? ""
  saveLog()
 }

 // MARK: the process (2-minute kill, no shell, no stdin)

 private func runProcess(_ exe: URL,_ args: [String]) async -> (data: Data,code: Int32,timedOut: Bool) {
  let cwd = workURL
  return await withCheckedContinuation { cont in
   DispatchQueue.global().async {
    let p = Process()
    p.executableURL = exe
    p.arguments = args
    p.currentDirectoryURL = cwd
    p.standardInput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    let pipe = Pipe()
    p.standardOutput = pipe
    do { try p.run() } catch { cont.resume(returning:(Data(),-1,false)); return }
    var timedOut = false
    let killer = DispatchWorkItem {
     timedOut = true
     p.terminate()
     DispatchQueue.global().asyncAfter(deadline:.now() + FridayBrainLimits.killGrace) { if p.isRunning { kill(p.processIdentifier,SIGKILL) } }
    }
    DispatchQueue.global().asyncAfter(deadline:.now() + FridayBrainLimits.callTimeout,execute:killer)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    killer.cancel()
    cont.resume(returning:(data,p.terminationStatus,timedOut))
   }
  }
 }

 // MARK: the three sources (GitHub through his own gh login, the handoff from his Helm-Private clone)

 private func gh(_ args: [String]) async -> Data? {
  let path = Switchboard.ghPath
  guard FileManager.default.isExecutableFile(atPath:path) else { return nil }
  return await withCheckedContinuation { cont in
   DispatchQueue.global().async {
    let p = Process()
    p.executableURL = URL(fileURLWithPath:path)
    p.arguments = args
    p.standardInput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    let out = Pipe()
    p.standardOutput = out
    do { try p.run() } catch { cont.resume(returning:nil); return }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    cont.resume(returning:p.terminationStatus == 0 ? data : nil)
   }
  }
 }

 private func readBoard() async -> FridayBrainRules.Source<String> {
  let data = await gh(["api","repos/\(SwitchboardRules.repo)/contents/meeting-room/BOARD.md?ref=master","-H","Accept: application/vnd.github.raw"])
  guard let d = data, let text = String(data:d,encoding:.utf8), text.contains("## ") else { return .init(value:nil,readAt:nil) }
  return .init(value:text,readAt:Date())
 }

 // Issue 15, last 3 days, owner account only (MeetingData.parseMessages drops everyone else).
 private func readRoom(now: Date) async -> FridayBrainRules.Source<[RoomMessage]> {
  let since = SwitchboardRules.iso.string(from:now.addingTimeInterval(-(FridayBrainLimits.roomDays + 1) * 86400))
  var all: [RoomMessage] = []
  for page in 1...FridayBrainLimits.roomPages {
   guard let d = await gh(["api","repos/\(SwitchboardRules.repo)/issues/\(SwitchboardRules.roomIssue)/comments?per_page=100&page=\(page)&since=\(since)"]),
         let rows = MeetingData.parseMessages(d) else { return .init(value:nil,readAt:nil) }
   all += rows
   let count = ((try? JSONSerialization.jsonObject(with:d)) as? [Any])?.count ?? 0
   if count < 100 { break }
  }
  return .init(value:all,readAt:Date())
 }

 private func readHandoff() -> FridayBrainRules.Source<(file: String,text: String)> {
  let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Claude/Helm-Private/matthew",isDirectory:true)
  guard let names = try? FileManager.default.contentsOfDirectory(atPath:dir.path), let newest = FridayBrainRules.newestHandoff(names),
        let text = try? String(contentsOf:dir.appendingPathComponent(newest),encoding:.utf8) else { return .init(value:nil,readAt:nil) }
  return .init(value:(newest,text),readAt:Date())
 }
}

// MARK: the box on the Friday page: one text field and one Send button

struct FridayChatBox: View {
 @ObservedObject var brain = FridayBrain.shared
 var compact = false
 private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()

 var body: some View {
  VStack(alignment:.leading,spacing:8) {
   HStack {
    Text("ASK FRIDAY").font(.system(size:11,weight:.medium,design:.monospaced)).tracking(1.3).foregroundStyle(HubTheme.subtext)
     .accessibilityAddTraits(.isHeader)
    Spacer()
    if brain.thinking { Text("thinking…").font(.system(size:11,design:.monospaced)).foregroundStyle(HubTheme.amber).accessibilityLabel("Friday is thinking") }
   }
   if !brain.turns.isEmpty {
    ScrollViewReader { proxy in
     ScrollView {
      VStack(alignment:.leading,spacing:6) {
       ForEach(Array(brain.turns.suffix(compact ? 2 : 6).enumerated()),id:\.offset) { i,t in
        HStack(alignment:.firstTextBaseline,spacing:8) {
         Text(t.role == "you" ? "YOU" : "FRIDAY").font(.system(size:9.5,weight:.bold,design:.monospaced))
          .foregroundStyle(t.role == "you" ? HubTheme.subtext : HubTheme.green).frame(width:52,alignment:.leading)
         Text(t.text).font(.system(size:12.5)).foregroundStyle(HubTheme.text).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
        }
        .id(i)
       }
      }
     }
     .frame(maxHeight:compact ? 90 : 170)
     .onChange(of:brain.turns.count) { _,_ in proxy.scrollTo(min(brain.turns.count,compact ? 2 : 6) - 1,anchor:.top) }   // the newest message starts at the top, so an answer is read from its first line
    }
   }
   if !brain.note.isEmpty { Text(brain.note).font(.system(size:11)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true) }
   HStack(spacing:8) {
    TextField("Ask Friday… for example: what needs me today?",text:$brain.draft)
     .textFieldStyle(.plain).font(.system(size:13))
     .padding(.horizontal,10).frame(minHeight:HubTheme.minTarget)
     .background(HubTheme.control,in:RoundedRectangle(cornerRadius:8))
     .overlay(RoundedRectangle(cornerRadius:8).stroke(HubTheme.controlOutline,lineWidth:1))
     .onSubmit { brain.send() }
     .disabled(brain.thinking)
     .accessibilityLabel("Message to Friday")
    Button { brain.send() } label: { Text("Send").font(.system(size:13,weight:.semibold)).frame(minWidth:60,minHeight:HubTheme.minTarget) }
     .buttonStyle(.borderedProminent).tint(HubTheme.crimson)
     .disabled(brain.thinking || brain.draft.trimmingCharacters(in:.whitespaces).isEmpty)
     .accessibilityHint("Sends your message to Friday. One question, one answer.")
   }
  }
  .padding(compact ? 12 : 16).frame(maxWidth:.infinity,alignment:.topLeading)
  .background(HubTheme.card,in:RoundedRectangle(cornerRadius:10))
  .overlay(RoundedRectangle(cornerRadius:10).stroke(HubTheme.line,lineWidth:1))
  .onAppear { FridayBrainTestHooks.boot(brain) }
 }
}

// MARK: test copies only

// In the real Helm (local.mattyb.gamecompanion) this is dead. In a test copy (own app ID, starts "local.mattyb.helm") with
// `defaults write <id> brain.testSavePath <folder>` the pack and prompt of each call are written there so the proof can trace every claim
// to its source line. The files hold private text: a scratch folder only, deleted afterwards, never committed.
//   brain.testAsk (string)   asks that question once, a few seconds after launch (so a run needs no typing)
enum FridayBrainTestHooks {
 @MainActor static func saveContext(_ context: String,prompt: String) {
  guard SwitchboardTestHooks.active, let path = UserDefaults.standard.string(forKey:"brain.testSavePath") else { return }
  let dir = URL(fileURLWithPath:path,isDirectory:true)
  try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  try? context.write(to:dir.appendingPathComponent("context.txt"),atomically:true,encoding:.utf8)
  try? "\(prompt.count) characters in the prompt; \(context.count) in the context pack (cap \(FridayBrainLimits.contextCap))".write(to:dir.appendingPathComponent("sizes.txt"),atomically:true,encoding:.utf8)
 }

 @MainActor static func boot(_ brain: FridayBrain) {
  guard SwitchboardTestHooks.active, let q = UserDefaults.standard.string(forKey:"brain.testAsk") else { return }
  UserDefaults.standard.removeObject(forKey:"brain.testAsk")
  Task {
   try? await Task.sleep(nanoseconds:6_000_000_000)
   brain.draft = q
   brain.send()
  }
 }
}
