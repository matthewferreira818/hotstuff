import Foundation
// Job cards: JobRules.fold must read job.py's file the same way job.py does. Run by checks/run.sh.
var fails = 0
func check(_ ok: Bool,_ name: String) { print(ok ? "PASS \(name)" : "FAIL \(name)"); if !ok { fails += 1 } }
let lines = """
{"id":"J-1","event":"assigned","at":"2026-11-06T18:00:00Z","to":"LC-Pixels","by":"Friday","title":"Fix the legend"}
{"id":"J-1","event":"resend","at":"2026-11-06T18:12:00Z","by":"Friday"}
{"id":"J-1","event":"started","at":"2026-11-06T18:13:00Z","by":"LC-Pixels"}
not json at all
{"id":"J-2","event":"assigned","at":"2026-11-06T18:20:00Z","to":"LC-TikTok","by":"Friday","title":"Second"}
{"id":"J-1","event":"done","at":"2026-11-06T18:30:00Z","by":"LC-Pixels","proof":"commit abc"}
{"id":"J-3","event":"ack","at":"2026-11-06T18:31:00Z","by":"X"}
"""
let jobs = JobRules.fold(Data(lines.utf8))
check(jobs.count == 2,"two jobs; a broken line and an event for an unknown job are skipped")
let j1 = jobs.first { $0.id == "J-1" }!
check(j1.stage == .done && j1.proof == "commit abc","done with its proof")
check(j1.ack == nil && j1.ackImplied && j1.started != nil,"'started' proves 'got it' happened but never lends it a time")
check(j1.resends == 1,"the resend is counted")
let j2 = jobs.first { $0.id == "J-2" }!
let iso = ISO8601DateFormatter()
check(!JobRules.noAnswer(j2,now:iso.date(from:"2026-11-06T18:25:00Z")!),"5 minutes without a 'got it' is not flagged yet")
check(JobRules.noAnswer(j2,now:iso.date(from:"2026-11-06T18:31:00Z")!),"11 minutes without a 'got it' says 'no answer yet'")
check(!JobRules.noAnswer(j1,now:iso.date(from:"2026-11-06T20:00:00Z")!),"a finished job is never 'no answer'")
check(JobRules.shown(jobs).first?.id == "J-2","open jobs are listed before finished ones")
let straight = JobRules.fold(Data("""
{"id":"J-9","event":"assigned","at":"2026-11-06T18:00:00Z","to":"A","by":"Friday","title":"x"}
{"id":"J-9","event":"done","at":"2026-11-06T18:05:00Z","by":"A","proof":"p"}
""".utf8))[0]
check(straight.stage == .done && straight.ack == nil && straight.started == nil && straight.ackImplied && straight.startedImplied,"straight to done: got it + started shown with no time recorded")
print(fails == 0 ? "ALL PASS (job cards)" : "\(fails) FAILED (job cards)")
