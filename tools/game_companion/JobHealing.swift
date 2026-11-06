import Foundation

// Self-healing job handoffs (Friday, 2026-11-06; delegation demo #1 lesson: "if the 'got it' never comes, resend or flag it, instead of it vanishing").
// While the Switchboard is ON, The Helm checks the crew job file (~/Claude/crew-jobs/jobs.jsonl) once a minute. For a job still at "assigned":
//  - after JobHeal.wait with no "got it", it wakes that chat with FIXED text carrying only the job id (never the title), and records a
//    "resend" in the job file once the wake is proven delivered;
//  - if that chat is closed, or it still hasn't answered after maxResends wakes, it hands the job to the backup (Friday, or LC-Manager for
//    Friday's own jobs) with the same id-only text, and records a "handoff" event once THAT wake is proven delivered. The file, not memory,
//    says a job was handed, so a restart never hands it twice; a refused or failed hand-off is simply tried again on a later tick.
// It never marks a job got it / started / done for anyone: only the crew member does that (job.py's owner rule). Same caps and cooldowns as
// every other wake (PingRules.gate). Pure rules in JobHeal; the watcher and WakeRunner (.job / .jobBackup) do the work.
// Test copies only (SwitchboardTestHooks.active): `jobs.testWatch` runs the watcher with the Switchboard OFF (no Hotline loop), on the file
// named by `jobs.testFile`, with a 30-second wait, so the real Helm and the real job file are never touched by a test.

enum JobHeal {
 static let wait: TimeInterval = 10 * 60
 static let maxResends = 3
 static let every: TimeInterval = 60
 static let tool = "python3 ~/Claude/hotstuff/tools/crew/job.py"

 enum Action: Equatable { case resend, handToBackup }
 struct Due: Equatable { var id: String; var to: String; var action: Action }

 // `lastTry` = when the watcher last tried this job (so a wake in flight isn't repeated). A job the file says was handed off is done here.
 static func due(_ jobs: [CrewJob],now: Date,lastTry: [String: Date],wait: TimeInterval = JobHeal.wait) -> [Due] {
  var out: [Due] = []
  for j in jobs where j.stage == .assigned && j.handedAt == nil {
   let since = max(j.lastResend ?? j.assigned,lastTry[j.id] ?? .distantPast)
   guard now.timeIntervalSince(since) >= wait else { continue }
   out.append(Due(id:j.id,to:j.to,action:j.resends >= maxResends ? .handToBackup : .resend))
  }
  return out
 }

 static func wakeText(id: String) -> String { "job \(id) is waiting for you: run `\(tool) show \(id)`, then `\(tool) ack \(id) --by <you>`" }
 static func backupText(id: String,chat: String,closed: Bool) -> String {
  "job \(id) for \(chat) got no 'got it'" + (closed ? " and \(chat) is closed" : " after \(maxResends) wakes") +
  "; handle it or reassign it: `\(tool) show \(id)`"
 }

 // One event line in job.py's own format, by the assigner role (Friday). `to` is only for a handoff (who took it over).
 static func eventLine(id: String,kind: String,at: Date,to: String? = nil) -> String {
  let iso = ISO8601DateFormatter()
  var obj: [String: String] = ["id":id,"event":kind,"at":iso.string(from:at),"by":"Friday"]
  if let to { obj["to"] = to }
  guard let d = try? JSONSerialization.data(withJSONObject:obj,options:[.sortedKeys]) else { return "" }
  return String(decoding:d,as:UTF8.self)
 }
}

enum JobFiles {
 static var testing: Bool { SwitchboardTestHooks.active && UserDefaults.standard.bool(forKey:"jobs.testWatch") }
 // The real file, or (test copies only) the scratch file named by jobs.testFile.
 static var current: URL {
  if SwitchboardTestHooks.active, let p = UserDefaults.standard.string(forKey:"jobs.testFile"), !p.isEmpty { return URL(fileURLWithPath:p) }
  return JobRules.fileURL
 }
 static var wait: TimeInterval { testing ? 30 : JobHeal.wait }

 // Appends only to an existing job file (The Helm never creates it; job.py does, with its 700/600 permissions).
 @discardableResult static func record(_ line: String) -> Bool {
  guard !line.isEmpty, let h = try? FileHandle(forWritingTo:current) else { return false }
  defer { try? h.close() }
  _ = try? h.seekToEnd()
  return (try? h.write(contentsOf:Data((line + "\n").utf8))) != nil
 }
}

@MainActor final class JobWatcher {
 static let shared = JobWatcher()
 private var loop: Task<Void,Never>?
 private var lastTry: [String: Date] = [:]
 private var handing: Set<String> = []     // hand-offs queued but not yet proven delivered (so one isn't queued twice)

 func start() {
  guard loop == nil else { return }
  loop = Task { [weak self] in
   while !Task.isCancelled {
    try? await Task.sleep(nanoseconds:UInt64((JobFiles.testing ? 10 : JobHeal.every) * 1_000_000_000))
    self?.tick()
   }
  }
 }

 func tick(now: Date = Date()) {
  guard Switchboard.shared.on || JobFiles.testing, let d = try? Data(contentsOf:JobFiles.current) else { return }
  for due in JobHeal.due(JobRules.fold(d),now:now,lastTry:lastTry,wait:JobFiles.wait) where !handing.contains(due.id) {
   lastTry[due.id] = now
   switch due.action {
   case .resend: WakeRunner.shared.submitJob(id:due.id,chat:due.to,now:now)
   case .handToBackup: handBack(id:due.id,chat:due.to,closed:false,now:now)
   }
  }
 }

 func handBack(id: String,chat: String,closed: Bool,now: Date = Date()) {
  guard !handing.contains(id), let backup = PingRules.backups(for:chat).first else { return }
  // Only marked once the wake is actually queued; a refusal (cooldown, cap) leaves it for a later tick.
  if WakeRunner.shared.submitJobBackup(id:id,backup:backup,text:JobHeal.backupText(id:id,chat:chat,closed:closed),now:now) {
   handing.insert(id)
  }
 }

 // Called by WakeRunner when a hand-off wake finishes.
 func handOffFinished(id: String,backup: String,delivered: Bool) {
  handing.remove(id)
  if delivered { JobFiles.record(JobHeal.eventLine(id:id,kind:"handoff",at:Date(),to:backup)) }
 }

 func resendDelivered(id: String) { JobFiles.record(JobHeal.eventLine(id:id,kind:"resend",at:Date())) }
}
