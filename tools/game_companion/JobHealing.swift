import Foundation

// Self-healing job handoffs (Friday, 2026-11-06; delegation demo #1 lesson: "if the 'got it' never comes, resend or flag it, instead of it vanishing").
// While the Switchboard is ON, The Helm checks the crew job file (~/Claude/crew-jobs/jobs.jsonl) once a minute. For a job still at "assigned":
//  - after JobHeal.wait with no "got it", it wakes that chat with FIXED text carrying only the job id (never the title), and records a
//    "resend" in the job file once the wake is proven delivered;
//  - if that chat is closed, or it still hasn't answered after maxResends wakes, it hands the job to the backup (Friday, or LC-Manager for
//    Friday's own jobs) once, with the same id-only text, so a job never just vanishes.
// It never marks a job got it / started / done for anyone: only the crew member does that (job.py's owner rule). Same caps and cooldowns as
// every other wake (PingRules.gate). Pure rules here; the watcher below and WakeRunner (.job) do the work.

enum JobHeal {
 static let wait: TimeInterval = 10 * 60
 static let maxResends = 3
 static let every: TimeInterval = 60
 static let tool = "python3 ~/Claude/hotstuff/tools/crew/job.py"

 enum Action: Equatable { case resend, handToBackup }
 struct Due: Equatable { var id: String; var to: String; var action: Action }

 // `lastTry` = when the watcher last tried this job (so a wake in flight isn't repeated); `handed` = jobs already given to a backup.
 static func due(_ jobs: [CrewJob],now: Date,lastTry: [String: Date],handed: Set<String>) -> [Due] {
  var out: [Due] = []
  for j in jobs where j.stage == .assigned && !handed.contains(j.id) {
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

 // One "resend" line in job.py's own format (by the assigner role, Friday).
 static func resendLine(id: String,at: Date) -> String {
  let iso = ISO8601DateFormatter()
  let obj: [String: String] = ["id":id,"event":"resend","at":iso.string(from:at),"by":"Friday"]
  guard let d = try? JSONSerialization.data(withJSONObject:obj,options:[.sortedKeys]) else { return "" }
  return String(decoding:d,as:UTF8.self)
 }

 // Appends only to an existing job file (The Helm never creates it; job.py does, with its 700/600 permissions).
 static func recordResend(id: String,at: Date = Date()) -> Bool {
  let line = resendLine(id:id,at:at)
  guard !line.isEmpty, let h = try? FileHandle(forWritingTo:JobRules.fileURL) else { return false }
  defer { try? h.close() }
  _ = try? h.seekToEnd()
  return (try? h.write(contentsOf:Data((line + "\n").utf8))) != nil
 }

 static func backup(for chat: String) -> String? { PingRules.backups(for:chat).first }
}

@MainActor final class JobWatcher {
 static let shared = JobWatcher()
 private var loop: Task<Void,Never>?
 private var lastTry: [String: Date] = [:]
 private var handed: Set<String> = []

 func start() {
  guard loop == nil else { return }
  loop = Task { [weak self] in
   while !Task.isCancelled {
    try? await Task.sleep(nanoseconds:UInt64(JobHeal.every * 1_000_000_000))
    self?.tick()
   }
  }
 }

 func tick(now: Date = Date()) {
  guard Switchboard.shared.on, let d = try? Data(contentsOf:JobRules.fileURL) else { return }
  for due in JobHeal.due(JobRules.fold(d),now:now,lastTry:lastTry,handed:handed) {
   lastTry[due.id] = now
   switch due.action {
   case .resend:
    WakeRunner.shared.submitJob(id:due.id,chat:due.to,now:now)
   case .handToBackup:
    handBack(id:due.id,chat:due.to,closed:false,now:now)
   }
  }
 }

 func handBack(id: String,chat: String,closed: Bool,now: Date = Date()) {
  guard !handed.contains(id), let backup = JobHeal.backup(for:chat) else { return }
  handed.insert(id)
  WakeRunner.shared.submitJobBackup(id:id,backup:backup,text:JobHeal.backupText(id:id,chat:chat,closed:closed),now:now)
 }
}
