import SwiftUI

// Crew job cards in Command Core › Crew Station (Friday, 2026-11-06, after delegation demo #1 lost a job's text on a wake).
// A job lives in ~/Claude/crew-jobs/jobs.jsonl (this Mac only, written by tools/crew/job.py), one event per line:
//   assigned → ack ("got it") → started → done (proof) | failed (reason); Friday may "resend" while there is no "got it".
// This view only READS that file and shows what was recorded, with each stage's real time. Nothing here invents progress:
// no bar, no percent, and "no answer yet" only when an assigned job really has had no "got it" for JobRules.noAnswerAfter.

struct CrewJob: Identifiable, Equatable {
 var id: String
 var to: String
 var by: String
 var title: String
 var assigned: Date
 var after: Date?             // "not before": a job meant for later is never chased or flagged before this time
 var ack: Date?
 var started: Date?
 var done: Date?
 var failed: Date?
 var proof: String?
 var why: String?
 var resends = 0
 var lastResend: Date?
 var handedTo: String?        // a "handoff" event: the job went to a backup because its chat never answered
 var handedAt: Date?
 var ackImplied = false       // a later step proves it happened, but no time was recorded for it
 var startedImplied = false

 enum Stage: Int { case assigned, ack, started, done, failed }
 var stage: Stage { failed != nil ? .failed : (done != nil ? .done : ((started != nil || startedImplied) ? .started : ((ack != nil || ackImplied) ? .ack : .assigned))) }
 var open: Bool { stage != .done && stage != .failed }
}

enum JobRules {
 static let noAnswerAfter: TimeInterval = 10 * 60
 static var fileURL: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Claude/crew-jobs/jobs.jsonl") }

 // Same folding rules as tools/crew/job.py: a later stage proves the earlier ones happened, but never lends them its time
 // (they show as done with "no time recorded").
 static func fold(_ data: Data) -> [CrewJob] {
  let iso = ISO8601DateFormatter()
  var jobs: [String:CrewJob] = [:]
  var order: [String] = []
  for line in String(decoding:data,as:UTF8.self).split(whereSeparator:\.isNewline) {
   guard let j = (try? JSONSerialization.jsonObject(with:Data(line.utf8))) as? [String:Any],
         let id = j["id"] as? String, let kind = j["event"] as? String, let at = (j["at"] as? String).flatMap(iso.date(from:)) else { continue }
   if kind == "assigned" {
    if jobs[id] == nil { order.append(id) }
    jobs[id] = CrewJob(id:id,to:j["to"] as? String ?? "",by:j["by"] as? String ?? "",title:j["title"] as? String ?? "",assigned:at,after:(j["after"] as? String).flatMap(iso.date(from:)))
    continue
   }
   guard var job = jobs[id] else { continue }
   switch kind {
   case "resend": job.resends += 1; job.lastResend = at
   case "handoff": if job.handedAt == nil { job.handedAt = at; job.handedTo = j["to"] as? String }
   case "ack": if job.ack == nil { job.ack = at }
   case "started": if job.started == nil { job.started = at; if job.ack == nil { job.ackImplied = true } }
   case "done": if job.done == nil { job.done = at; job.proof = j["proof"] as? String; if job.ack == nil { job.ackImplied = true }; if job.started == nil { job.startedImplied = true } }
   case "failed": if job.failed == nil { job.failed = at; job.why = j["why"] as? String }
   default: break
   }
   jobs[id] = job
  }
  return order.compactMap { jobs[$0] }
 }

 static func noAnswer(_ job: CrewJob,now: Date) -> Bool {
  if let a = job.after, now < a { return false }
  return job.stage == .assigned && now.timeIntervalSince(max(job.lastResend ?? job.assigned,job.after ?? .distantPast)) > noAnswerAfter
 }

 // Open jobs first (newest first), then the newest finished ones.
 static func shown(_ jobs: [CrewJob],limit: Int = 6) -> [CrewJob] {
  let open = jobs.filter { $0.open }.sorted { $0.assigned > $1.assigned }
  let closed = jobs.filter { !$0.open }.sorted { ($0.done ?? $0.failed ?? $0.assigned) > ($1.done ?? $1.failed ?? $1.assigned) }
  return Array((open + closed).prefix(limit))
 }
}

@MainActor final class CrewJobsModel: ObservableObject {
 static let shared = CrewJobsModel()
 @Published private(set) var jobs: [CrewJob] = []
 @Published private(set) var readAt: Date?
 @Published private(set) var missing = true
 private var timer: Timer?

 func start() {
  read()
  guard timer == nil else { return }
  timer = Timer.scheduledTimer(withTimeInterval:5,repeats:true) { [weak self] _ in Task { @MainActor in self?.read() } }
 }
 func stop() { timer?.invalidate(); timer = nil }

 private func read() {
  if let d = try? Data(contentsOf:JobFiles.current) { jobs = JobRules.fold(d); missing = false } else { jobs = []; missing = true }
  readAt = Date()
 }
}

struct CoreJobsCard: View {
 @ObservedObject var model = CrewJobsModel.shared
 private static let time: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm a"; return f }()
 private static let day: DateFormatter = { let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f }()

 private func chip(_ label: String,_ at: Date?,_ color: Color,implied: Bool = false) -> some View {
  let on = at != nil || implied
  return HStack(spacing:4) {
   Circle().fill(on ? color : Color.clear).overlay(Circle().stroke(on ? color : CoreStyle.dim,lineWidth:1)).frame(width:7,height:7)
   Text(label + (at.map { " " + Self.time.string(from:$0) } ?? (implied ? " · no time recorded" : ""))).font(.system(size:10.5,design:.rounded)).foregroundStyle(on ? CoreStyle.ink.opacity(0.85) : CoreStyle.dim).lineLimit(1).fixedSize()
  }
 }

 var body: some View {
  let now = Date()
  let list = JobRules.shown(model.jobs)
  return CoreCard(title:"Jobs · handed off by Friday",icon:"checklist") {
   if model.missing || list.isEmpty {
    Text(model.missing ? "No jobs recorded on this Mac yet. When Friday hands a crew member a job, it shows here with each step's real time." : "No jobs yet.")
     .font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.dim).fixedSize(horizontal:false,vertical:true)
   }
   ForEach(list) { j in
    VStack(alignment:.leading,spacing:4) {
     HStack(spacing:6) {
      Text(j.title).font(.system(size:12.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink).lineLimit(1)
      Spacer(minLength:6)
      Text("→ " + j.to).font(.system(size:10.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.teal)
       .padding(.horizontal,6).padding(.vertical,1).background(Capsule().fill(CoreStyle.teal.opacity(0.12)))
     }
     ViewThatFits(in:.horizontal) {
      HStack(spacing:10) { stageChips(j) }
      VStack(alignment:.leading,spacing:3) { stageChips(j) }
     }
     if let a = j.after, a > now {
      Text("Not before \(Self.day.string(from:a)): nobody chases it until then").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim)
     }
     if let to = j.handedTo, let at = j.handedAt {
      Text("Handed to \(to) at \(Self.time.string(from:at)): \(j.to) never said 'got it'").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.amber)
     } else if JobRules.noAnswer(j,now:now) {
      Text("No answer yet: nothing came back for \(Int(now.timeIntervalSince(j.lastResend ?? j.assigned) / 60)) min" + (j.resends > 0 ? " (resent \(j.resends)×)" : ""))
       .font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.amber)
     }
     if let p = j.proof { Text("Proof given: " + p).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.7)).lineLimit(2) }
     if let w = j.why { Text("Why it failed: " + w).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.crimson).lineLimit(2) }
    }
    .padding(.vertical,4)
    Divider().overlay(Color.white.opacity(0.05))
   }
   Text((JobFiles.testing ? "From the TEST job file (test copy)" : "From ~/Claude/crew-jobs on this Mac") + (model.readAt.map { " · read \(Self.time.string(from:$0))" } ?? ""))
    .font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
  }
  .onAppear { model.start() }
  .onDisappear { model.stop() }
 }

 @ViewBuilder func stageChips(_ j: CrewJob) -> some View {
  chip("assigned",j.assigned,CoreStyle.teal)
  chip("got it",j.ack,CoreStyle.teal,implied:j.ackImplied)
  chip("started",j.started,CoreStyle.emerald,implied:j.startedImplied)
  if j.failed != nil { chip("failed",j.failed,CoreStyle.crimson) } else { chip("done",j.done,CoreStyle.emerald) }
 }
}
