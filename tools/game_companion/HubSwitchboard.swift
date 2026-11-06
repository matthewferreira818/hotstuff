import SwiftUI
import AppKit

// Friday's Switchboard: the runner (checks GitHub, starts and stops the one job) and its panel on the Friday page.
// Every rule lives in SwitchboardData.swift; every limit in SwitchboardLimits. README: SWITCHBOARD.md next to this file.

struct SwitchboardLogEntry: Codable, Identifiable, Equatable {
 var id = UUID()
 var at: Date
 var kind: String     // on, off, run, done, failed, stopped, refused, wait, error, note
 var text: String
}

private struct SwitchboardState: Codable {
 var seen: [Int64] = []
 var armedAt: Date = .distantFuture
 var starts: [Date] = []
 var jobCount = 0
}

@MainActor final class Switchboard: ObservableObject {
 static let shared = Switchboard()
 // Real default 5 min; 30 s only in a test copy with switchboard.testFastPoll (hooks are dead in the real Helm).
 static var interval: TimeInterval { SwitchboardTestHooks.active && UserDefaults.standard.bool(forKey:"switchboard.testFastPoll") ? SwitchboardLimits.testPollEvery : SwitchboardLimits.pollEvery }
 static var intervalText: String { interval < 60 ? "\(Int(interval)) s" : "\(Int(interval / 60)) min" }
 static let onKey = "switchboard.on"   // UserDefaults, per app ID: absent = OFF, so a fresh install and the test copy start OFF

 @Published private(set) var on = UserDefaults.standard.bool(forKey:Switchboard.onKey)
 @Published private(set) var log: [SwitchboardLogEntry] = []
 @Published private(set) var runningJob: Int?
 @Published private(set) var runningSince: Date?
 @Published private(set) var runningTitle = ""
 private var runningThread = SwitchboardRules.roomIssue
 @Published private(set) var lastCheck: Date?
 @Published private(set) var claudeVersion: String?
 @Published private(set) var startsThisHour = 0
 @Published private(set) var startsToday = 0
 // Panel UI flags live here: this SDK's @State is a macro the command-line build can't expand.
 @Published var confirmOn = false
 @Published var showLog = false

 private var state = SwitchboardState()
 private var loop: Task<Void,Never>?
 private var process: Process?
 private var booted = false

 // Per app ID, so the test copy never shares state with the real Helm.
 private let folder: URL = {
  let base = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
  let dir = base.appendingPathComponent("Switchboard-\(Bundle.main.bundleIdentifier ?? "helm")",isDirectory:true)
  try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  return dir
 }()
 private var stateURL: URL { folder.appendingPathComponent("state.json") }
 private var logURL: URL { folder.appendingPathComponent("log.json") }
 var jobsFolder: URL { folder.appendingPathComponent("jobs",isDirectory:true) }

 private init() {
  if let d = try? Data(contentsOf:stateURL), let s = try? JSONDecoder().decode(SwitchboardState.self,from:d) { state = s }
  if let d = try? Data(contentsOf:logURL), let l = try? JSONDecoder().decode([SwitchboardLogEntry].self,from:d) { log = l }
  recount()
 }

 // Called once at app start. If Matthew left it ON, it keeps watching; it never turns itself on.
 func boot() {
  guard !booted else { return }
  booted = true
  claudeVersion = Self.checkClaude().version
  if on { startLoop() }
  SwitchboardTestHooks.boot(self)
 }

 func setOn(_ value: Bool,by source: String = "the switch on the Friday page") {
  guard value != on else { return }
  on = value
  UserDefaults.standard.set(value,forKey:Switchboard.onKey)
  if value {
   state.armedAt = Date()   // only comments posted from now on can start a job
   save()
   add("on","Switchboard ON (turned on by \(source)). Watching issue 15 and the Hotline every \(Switchboard.intervalText).")
   startLoop()
  } else {
   loop?.cancel(); loop = nil
   add("off","Switchboard OFF (turned off by \(source)).")
   if runningJob != nil { stopJob(reason:"stopped (switch turned off)") }
  }
 }

 private func startLoop() {
  loop?.cancel()
  loop = Task { [weak self] in
   while !Task.isCancelled {
    await self?.check()
    try? await Task.sleep(nanoseconds:UInt64(Switchboard.interval * 1_000_000_000))
   }
  }
 }

 // MARK: one check

 func check() async {
  guard on else { return }
  let since = max(state.armedAt,Date().addingTimeInterval(-SwitchboardLimits.maxAge)).addingTimeInterval(-60)
  var all: [SwitchboardComment] = []
  for thread in SwitchboardRules.watched.sorted() {
   guard let rows = await fetch(thread:thread,since:since) else {
    add("error","Couldn't read \(SwitchboardRules.where_(thread)) on GitHub; trying again next check.")
    continue
   }
   all += rows
  }
  all += SwitchboardTestHooks.fakeComments(armedAt:state.armedAt)   // test copies only; empty in the real Helm
  lastCheck = Date()
  recount()
  for c in all.sorted(by:{ $0.createdAt < $1.createdAt }) {
   let v = SwitchboardRules.verdict(c,seen:Set(state.seen),armedAt:state.armedAt,now:Date(),starts:state.starts,running:runningJob == nil ? 0 : 1)
   switch v {
   case .ignore:
    remember(c.id)
   case .wait:
    continue   // left unseen: the next check tries it again (until it is 6 hours old)
   case .refuse(let reason,let mirror):
    remember(c.id)
    add("refused","Refused comment \(c.id) on \(SwitchboardRules.where_(c.thread)): \(reason).")
    if mirror { _ = await post(SwitchboardRules.mirrorRefusal(c,reason:reason)) }
   case .run:
    remember(c.id)
    await start(c)
   }
  }
 }

 // GitHub goes through Matthew's own `gh` login (the same one every Local Claude uses). The Switchboard never holds or stores a key.
 // Arguments are an array, no shell, so a comment's text can't become a command.
 nonisolated static let ghPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Claude/bin/gh").path

 private func gh(_ args: [String]) async -> (ok: Bool,out: Data) {
  guard FileManager.default.isExecutableFile(atPath:Self.ghPath) else { return (false,Data()) }
  return await withCheckedContinuation { cont in
   DispatchQueue.global().async {
    let p = Process()
    p.executableURL = URL(fileURLWithPath:Self.ghPath)
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
 }

 private func fetch(thread: Int,since: Date) async -> [SwitchboardComment]? {
  let path = "repos/\(SwitchboardRules.repo)/issues/\(thread)/comments?per_page=100&since=\(SwitchboardRules.iso.string(from:since))"
  let r = await gh(["api",path])
  return r.ok ? SwitchboardRules.parseComments(r.out,thread:thread) : nil
 }

 private func post(_ body: String,thread: Int = SwitchboardRules.roomIssue) async -> Bool {
  let kind = thread == SwitchboardRules.hotline ? "pr" : "issue"
  let r = await gh([kind,"comment","\(thread)","--repo",SwitchboardRules.repo,"--body",body])
  if !r.ok { add("error","Couldn't post to \(SwitchboardRules.where_(thread)) through gh (not logged in, offline, or GitHub refused).") }
  return r.ok
 }

 // MARK: the job

 static func checkClaude() -> (exe: URL?,version: String?) {
  guard let exe = SwitchboardRules.findClaude() else { return (nil,nil) }
  let p = Process()
  p.executableURL = exe
  p.arguments = ["--version"]
  let pipe = Pipe()
  p.standardOutput = pipe
  p.standardError = FileHandle.nullDevice
  do { try p.run() } catch { return (exe,nil) }
  p.waitUntilExit()
  let out = String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self)
  return (exe,SwitchboardRules.versionLine(out))
 }

 private func start(_ c: SwitchboardComment) async {
  // Every check below is done in code before anything starts; any "no" is logged and nothing runs.
  let found = Self.checkClaude()
  claudeVersion = found.version
  guard let exe = found.exe, found.version != nil else {
   add("error","No working Claude Code found in the desktop app's folder; job not started (nothing gets installed).")
   _ = await post(SwitchboardRules.mirrorRefusal(c,reason:"Claude Code not found on the Mac"))
   return
  }
  let settings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
  if let problem = SwitchboardRules.settingsProblem(try? Data(contentsOf:settings)) {
   add("error","\(problem). Job not started.")
   return
  }
  let args = SwitchboardRules.arguments(prompt:SwitchboardRules.prompt(for:c))
  guard SwitchboardRules.argumentsAreSafe(args) else { add("error","Unsafe command line; job not started."); return }
  let work = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Claude/hotstuff",isDirectory:true)
  guard FileManager.default.fileExists(atPath:work.appendingPathComponent(".git").path) else {
   add("error","~/Claude/hotstuff isn't there; job not started.")
   return
  }

  let job = state.jobCount + 1
  // Lock 6: the start is mirrored BEFORE the job runs. If issue 15 can't be told, the job doesn't run.
  guard await post(SwitchboardRules.mirrorStart(job:job,c:c)) else {
   add("refused","Job for comment \(c.id) not started: couldn't mirror it to issue 15.")
   return
  }
  state.jobCount = job
  state.starts.append(Date())
  save(); recount()

  try? FileManager.default.createDirectory(at:jobsFolder,withIntermediateDirectories:true)
  let out = jobsFolder.appendingPathComponent("job-\(job).json")
  let err = jobsFolder.appendingPathComponent("job-\(job).stderr.txt")
  FileManager.default.createFile(atPath:out.path,contents:nil)
  FileManager.default.createFile(atPath:err.path,contents:nil)
  let p = Process()
  p.executableURL = exe
  p.arguments = args            // one argument per item, no shell: the comment can't add flags
  p.currentDirectoryURL = work
  p.standardInput = FileHandle.nullDevice
  p.standardOutput = try? FileHandle(forWritingTo:out)
  p.standardError = try? FileHandle(forWritingTo:err)
  let began = Date()
  p.terminationHandler = { proc in
   let code = proc.terminationStatus
   Task { @MainActor in Switchboard.shared.finished(job:job,code:code,began:began,out:out) }
  }
  do { try p.run() } catch {
   add("error","Job \(job) couldn't start: \(error.localizedDescription)")
   _ = await post(SwitchboardRules.mirrorEnd(job:job,outcome:"failed to start",minutes:0,result:"the process didn't launch"))
   return
  }
  process = p
  runningJob = job
  runningSince = began
  runningTitle = SwitchboardRules.jobTitle(c.body)
  runningThread = c.thread
  add("run","Job \(job) started (\(found.version ?? "")): \(runningTitle)")

  // Lock 4: the 30-minute stop.
  Task { [weak self] in
   try? await Task.sleep(nanoseconds:UInt64(SwitchboardLimits.jobTimeout * 1_000_000_000))
   await MainActor.run { if self?.runningJob == job { self?.stopJob(reason:"stopped at the \(Int(SwitchboardLimits.jobTimeout / 60))-minute limit") } }
  }
 }

 private var stopReason: String?

 func stopJob(reason: String = "stopped by Matthew") {
  guard let p = process, p.isRunning else { return }
  stopReason = reason
  p.terminate()
  let pid = p.processIdentifier
  Task {
   try? await Task.sleep(nanoseconds:UInt64(SwitchboardLimits.killGrace * 1_000_000_000))
   if p.isRunning { kill(pid,SIGKILL) }
  }
 }

 private func finished(job: Int,code: Int32,began: Date,out: URL) {
  let minutes = max(0,Int(Date().timeIntervalSince(began) / 60 + 0.5))
  let outcome = SwitchboardRules.parseOutcome((try? Data(contentsOf:out)) ?? Data(),exitCode:code)
  let word: String
  if let reason = stopReason { word = reason } else { word = outcome.ok ? "finished" : "failed (exit \(code))" }
  let denials = outcome.denials > 0 ? " · \(outcome.denials) tool use(s) refused by the permission list" : ""
  let unproven = stopReason == nil && SwitchboardRules.isUnproven(outcome)
  let turns = outcome.turns.map { " · \($0) turn(s)" } ?? ""
  add(stopReason != nil ? "stopped" : (unproven ? "unproven" : (outcome.ok ? "done" : "failed")),
      "Job \(job) \(word) after \(minutes) min\(turns)\(denials)\(unproven ? " · " + SwitchboardRules.unprovenNote : ""): \(SwitchboardRules.firstLine(outcome.result,limit:300))")
  let thread = runningThread
  stopReason = nil
  process = nil
  runningJob = nil
  runningSince = nil
  runningTitle = ""
  let line = SwitchboardRules.mirrorEnd(job:job,outcome:word,minutes:minutes,result:outcome.result,unproven:unproven)
  Task {
   _ = await post(line)                                              // lock 6: always on issue 15
   if thread == SwitchboardRules.hotline { _ = await post(line,thread:thread) }   // Hotline jobs also answer on PR #35
  }
 }

 // MARK: bookkeeping

 private func remember(_ id: Int64) {
  state.seen.append(id)
  if state.seen.count > SwitchboardLimits.seenKeep { state.seen.removeFirst(state.seen.count - SwitchboardLimits.seenKeep) }
  save()
 }

 private func recount() {
  let now = Date()
  state.starts = state.starts.filter { now.timeIntervalSince($0) < 2 * 86400 }
  startsThisHour = SwitchboardRules.startsInLastHour(state.starts,now:now)
  startsToday = SwitchboardRules.startsToday(state.starts,now:now)
 }

 private func add(_ kind: String,_ text: String) {
  log.append(SwitchboardLogEntry(at:Date(),kind:kind,text:text))
  if log.count > SwitchboardLimits.logKeep { log.removeFirst(log.count - SwitchboardLimits.logKeep) }
  if let d = try? JSONEncoder().encode(log) { try? d.write(to:logURL,options:.atomic) }
 }

 private func save() {
  if let d = try? JSONEncoder().encode(state) { try? d.write(to:stateURL,options:.atomic) }
 }
}

// MARK: the panel on the Friday page

struct SwitchboardPanel: View {
 @ObservedObject var sb = Switchboard.shared
 var compact = false

 private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()
 private static let dayTime: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f }()

 var body: some View {
  VStack(alignment:.leading,spacing:8) {
   HStack(spacing:10) {
    Text("SWITCHBOARD").font(.system(size:11,weight:.medium,design:.monospaced)).tracking(1.3).foregroundStyle(HubTheme.subtext)
     .accessibilityAddTraits(.isHeader)
    Text(sb.on ? "ON" : "OFF").font(.system(size:10,weight:.bold,design:.monospaced))
     .foregroundStyle(sb.on ? HubTheme.green : HubTheme.subtext)
     .padding(.horizontal,6).padding(.vertical,1)
     .overlay(RoundedRectangle(cornerRadius:3).stroke(sb.on ? HubTheme.green : HubTheme.controlOutline,lineWidth:1))
    Spacer()
    if sb.runningJob != nil {
     Button { sb.stopJob() } label: { Label("Stop job",systemImage:"stop.fill").font(.system(size:11.5,weight:.medium)) }
      .buttonStyle(.bordered).tint(HubTheme.crimson)
    }
    Toggle("Switchboard",isOn:Binding(get:{ sb.on },set:{ value in if value { sb.confirmOn = true } else { sb.setOn(false) } }))
     .toggleStyle(.switch).labelsHidden()
     .accessibilityLabel("Switchboard switch")
     .accessibilityValue(sb.on ? "on" : "off")
   }
   Text(summary).font(.system(size:12)).foregroundStyle(HubTheme.text).fixedSize(horizontal:false,vertical:true)
   if let job = sb.runningJob {
    TimelineView(.periodic(from:.now,by:30)) { t in
     Text("Running job \(job) · \(minutes(since:sb.runningSince,now:t.date)) min · \(sb.runningTitle)")
      .font(.system(size:12,weight:.medium)).foregroundStyle(HubTheme.amber).lineLimit(1)
    }
   }
   if !compact {
    let recent = Array(sb.log.suffix(4).reversed())
    if recent.isEmpty {
     Text("No jobs yet. The log shows every start, end and refusal.").font(.system(size:11.5)).foregroundStyle(HubTheme.subtext)
    } else {
     ForEach(recent) { row($0) }
    }
   }
   Button { sb.showLog = true } label: {
    Text(compact ? "Switchboard log (\(sb.log.count)) ›" : "Full log (\(sb.log.count)) ›").font(.system(size:11,design:.monospaced)).foregroundStyle(HubTheme.teal)
   }.buttonStyle(.plain)
  }
  .padding(compact ? 12 : 16).frame(maxWidth:.infinity,alignment:.topLeading)
  .background(HubTheme.card,in:RoundedRectangle(cornerRadius:10))
  .overlay(RoundedRectangle(cornerRadius:10).stroke(sb.on ? HubTheme.green.opacity(0.45) : HubTheme.line,lineWidth:1))
  .alert("Turn on the Switchboard?",isPresented:$sb.confirmOn) {
   Button("Turn on") { sb.setOn(true) }
   Button("Cancel",role:.cancel) {}
  } message: {
   Text("Friday will start a Local Claude job on this Mac for each NEW comment on issue 15 or the Hotline that starts **[Claude … → Local Claude]** from your account. One at a time, at most \(SwitchboardLimits.perHour) an hour and \(SwitchboardLimits.perDay) a day, each stopped at \(Int(SwitchboardLimits.jobTimeout / 60)) minutes. Your normal permission list applies. Money, logins, messages to people and Moomoo are always refused.")
  }
  .sheet(isPresented:$sb.showLog) { SwitchboardLogSheet(sb:sb) }
 }

 private var summary: String {
  let claude = sb.claudeVersion.map { "Claude Code \($0.replacingOccurrences(of:" (Claude Code)",with:""))" } ?? "Claude Code not found"
  let limits = "Jobs \(sb.startsThisHour)/\(SwitchboardLimits.perHour) this hour · \(sb.startsToday)/\(SwitchboardLimits.perDay) today · \(claude)"
  if !sb.on { return "Off. Friday starts no jobs. Turn on to let tagged messages from cloud Claude start Local Claude jobs here.\n\(limits)" }
  let checked = sb.lastCheck.map { "last check \(Self.time.string(from:$0))" } ?? "first check starting"
  return "On. Watching issue 15 and the Hotline every \(Switchboard.intervalText) · \(checked).\n\(limits)"
 }

 private func minutes(since: Date?,now: Date) -> Int { since.map { max(0,Int(now.timeIntervalSince($0) / 60)) } ?? 0 }

 static func color(_ kind: String) -> Color {
  switch kind {
  case "run","on": return HubTheme.green
  case "done": return HubTheme.teal
  case "unproven": return HubTheme.amber
  case "refused","stopped","wait": return HubTheme.amber
  case "failed","error": return HubTheme.crimson
  default: return HubTheme.subtext
  }
 }

 private func row(_ e: SwitchboardLogEntry) -> some View {
  HStack(alignment:.firstTextBaseline,spacing:8) {
   Text(Self.time.string(from:e.at)).font(.system(size:10.5,design:.monospaced)).foregroundStyle(HubTheme.subtext).frame(width:58,alignment:.leading)
   Text(e.kind.uppercased()).font(.system(size:9.5,weight:.bold,design:.monospaced)).foregroundStyle(Self.color(e.kind)).frame(width:58,alignment:.leading)
   Text(e.text).font(.system(size:11.5)).foregroundStyle(HubTheme.text).lineLimit(2)
  }
  .accessibilityElement(children:.combine)
 }
}

struct SwitchboardLogSheet: View {
 @ObservedObject var sb: Switchboard
 @Environment(\.dismiss) private var dismiss
 private static let stamp: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE MMM d, h:mm:ss a"; return f }()

 var body: some View {
  VStack(alignment:.leading,spacing:10) {
   HStack {
    Text("Switchboard log").font(.system(size:16,weight:.semibold))
    Spacer()
    Button("Open job files") { NSWorkspace.shared.open(sb.jobsFolder) }
    Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
   }
   ScrollView {
    LazyVStack(alignment:.leading,spacing:6) {
     ForEach(sb.log.reversed()) { e in
      HStack(alignment:.firstTextBaseline,spacing:8) {
       Text(Self.stamp.string(from:e.at)).font(.system(size:10.5,design:.monospaced)).foregroundStyle(HubTheme.subtext).frame(width:170,alignment:.leading)
       Text(e.kind.uppercased()).font(.system(size:9.5,weight:.bold,design:.monospaced)).foregroundStyle(SwitchboardPanel.color(e.kind)).frame(width:62,alignment:.leading)
       Text(e.text).font(.system(size:12)).foregroundStyle(HubTheme.text).textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
      }
     }
     if sb.log.isEmpty { Text("Nothing yet.").foregroundStyle(HubTheme.subtext) }
    }
   }
  }
  .padding(18).frame(minWidth:640,minHeight:420)
 }
}

// MARK: test copies only

// For screenshots and the in-app dry run on a TEST copy (its own app ID). In the real Helm (local.mattyb.gamecompanion) every hook
// below is dead: `active` is false, so nothing here reads a setting, injects a comment or writes a picture.
//   switchboard.testTurnOn   (bool)    turn the switch ON at launch through the normal setOn(true)
//   switchboard.testComments (path)    a JSON list of fake comments mixed into each check: [{id,thread,login,body,ago,edited}]
//   switchboard.testShowLog  (bool)    open the full log sheet
//   switchboard.testFastPoll (bool)    check every 30 s instead of 5 min
//   switchboard.testShot     (path)    after 8 s, save the window (and the sheet, if open) as <path>-window.png / <path>-sheet.png
enum SwitchboardTestHooks {
 static let realHelmID = "local.mattyb.gamecompanion"
 static var active: Bool {
  let id = Bundle.main.bundleIdentifier ?? ""
  return id != realHelmID && id.hasPrefix("local.mattyb.helm")
 }

 private struct Fake: Codable { var id: Int64; var thread: Int; var login: String; var body: String; var ago: Double; var edited: Double }

 @MainActor static func boot(_ sb: Switchboard) {
  guard active else { return }
  let d = UserDefaults.standard
  if d.bool(forKey:"switchboard.testTurnOn") { sb.setOn(true,by:"the test hook switchboard.testTurnOn") }
  if d.bool(forKey:"switchboard.testShowLog") {
   Task { try? await Task.sleep(nanoseconds:5_000_000_000); sb.showLog = true }
  }
  if let path = d.string(forKey:"switchboard.testShot") {
   Task {
    try? await Task.sleep(nanoseconds:8_000_000_000)
    guard let w = NSApp.windows.first(where:{ $0.isVisible && $0.frame.width > 300 && $0.sheetParent == nil }) else {
     try? "no window; windows: \(NSApp.windows.map { "\($0.frame.width)x\($0.isVisible)" })".write(toFile:path + "-error.txt",atomically:true,encoding:.utf8)
     return
    }
    save(w.contentView,to:path + "-window.png")
    if let sheet = w.attachedSheet { save(sheet.contentView,to:path + "-sheet.png") }
   }
  }
 }

 @MainActor private static func save(_ view: NSView?,to path: String) {
  guard let v = view, let rep = v.bitmapImageRepForCachingDisplay(in:v.bounds) else {
   try? "no bitmap rep".write(toFile:path + "-error.txt",atomically:true,encoding:.utf8)
   return
  }
  v.cacheDisplay(in:v.bounds,to:rep)
  try? rep.representation(using:.png,properties:[:])?.write(to:URL(fileURLWithPath:path))
 }

 static func fakeComments(armedAt: Date) -> [SwitchboardComment] {
  guard active, armedAt != .distantFuture, let path = UserDefaults.standard.string(forKey:"switchboard.testComments"),
        let data = try? Data(contentsOf:URL(fileURLWithPath:path)),
        let fakes = try? JSONDecoder().decode([Fake].self,from:data) else { return [] }
  // "ago" counts back from 1 second after the switch went ON, so ago 0 = a fresh comment, ago 7200 = from before switch-on.
  let made = armedAt.addingTimeInterval(1)
  return fakes.map { f in
   let created = made.addingTimeInterval(-f.ago)
   return SwitchboardComment(id:f.id,thread:f.thread,login:f.login,body:f.body,createdAt:created,updatedAt:created.addingTimeInterval(f.edited),url:"(fake comment \(f.id))")
  }
 }
}
