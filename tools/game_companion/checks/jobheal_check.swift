import Foundation
// Self-healing handoffs: when The Helm resends, when it hands to a backup, and the resend line's format. Run by checks/run.sh.
var fails = 0
func check(_ ok: Bool,_ name: String) { print(ok ? "PASS \(name)" : "FAIL \(name)"); if !ok { fails += 1 } }
let iso = ISO8601DateFormatter()
func t(_ s: String) -> Date { iso.date(from:"2026-11-06T\(s)Z")! }
let jobs = JobRules.fold(Data("""
{"id":"J-A","event":"assigned","at":"2026-11-06T18:00:00Z","to":"LC-Pixels","by":"Friday","title":"a"}
{"id":"J-B","event":"assigned","at":"2026-11-06T18:00:00Z","to":"LC-TikTok","by":"Friday","title":"b"}
{"id":"J-B","event":"ack","at":"2026-11-06T18:01:00Z","by":"LC-TikTok"}
{"id":"J-C","event":"assigned","at":"2026-11-06T17:00:00Z","to":"LC-Trends","by":"Friday","title":"c"}
{"id":"J-C","event":"resend","at":"2026-11-06T17:10:00Z","by":"Friday"}
{"id":"J-C","event":"resend","at":"2026-11-06T17:20:00Z","by":"Friday"}
{"id":"J-C","event":"resend","at":"2026-11-06T17:30:00Z","by":"Friday"}
""".utf8))
check(JobHeal.due(jobs,now:t("18:05:00"),lastTry:[:]).filter { $0.id != "J-C" }.isEmpty,"nothing is resent before 10 minutes")
let at11 = JobHeal.due(jobs,now:t("18:11:00"),lastTry:[:])
check(at11.contains(JobHeal.Due(id:"J-A",to:"LC-Pixels",action:.resend)),"no 'got it' after 10 minutes: resend")
check(!at11.contains { $0.id == "J-B" },"a job that got its 'got it' is never resent")
check(at11.contains(JobHeal.Due(id:"J-C",to:"LC-Trends",action:.handToBackup)),"after 3 resends with no answer: hand to the backup")
check(!JobHeal.due(jobs,now:t("18:11:00"),lastTry:["J-A":t("18:10:30")]).contains { $0.id == "J-A" },"a wake in flight isn't repeated")
let handedJobs = JobRules.fold(Data((String(decoding:try! JSONSerialization.data(withJSONObject:["id":"J-C","event":"assigned","at":"2026-11-06T17:00:00Z","to":"LC-Trends","by":"Friday","title":"c"]),as:UTF8.self) + "\n" + JobHeal.eventLine(id:"J-C",kind:"handoff",at:t("17:45:00"),to:"Friday") + "\n").utf8))
check(handedJobs.first?.handedTo == "Friday" && handedJobs.first?.handedAt != nil,"a 'handoff' line in the file is read back (who, when)")
check(JobHeal.due(handedJobs,now:t("19:00:00"),lastTry:[:]).isEmpty,"the file says it was handed: never handed again, even after a restart")
check(JobHeal.due(JobRules.fold(Data("{\"id\":\"J-D\",\"event\":\"assigned\",\"at\":\"2026-11-06T18:00:00Z\",\"to\":\"X\",\"by\":\"Friday\",\"title\":\"d\"}\n".utf8)),now:t("18:00:31"),lastTry:[:],wait:30).count == 1,"the test-copy 30-second wait works")
let line = JobHeal.eventLine(id:"J-A",kind:"resend",at:t("18:11:00"))
check(line.contains("\"event\":\"resend\"") && line.contains("\"by\":\"Friday\"") && !line.contains("title"),"the resend line is job.py's format, by Friday, no title")
check(JobRules.fold(Data((line + "\n").utf8)).isEmpty,"a resend for an unknown job is ignored by the reader")
check(JobHeal.wakeText(id:"J-A").contains("J-A") && JobHeal.wakeText(id:"J-A").contains("job.py show"),"the wake carries the job id and the command, never the title")
let later = JobRules.fold(Data((#"{"id":"J-L","event":"assigned","at":"2026-11-06T21:00:00Z","to":"LC-Work","by":"LC-Manager","title":"sat","after":"2026-11-07T13:00:00Z"}"# + "\n").utf8))
check(later.first?.after != nil,"'not before' is read from the file")
check(JobHeal.due(later,now:t("23:00:00"),lastTry:[:]).isEmpty && !JobRules.noAnswer(later[0],now:t("23:00:00")),"a job for later is not chased or flagged the night before")
check(JobHeal.due(later,now:iso.date(from:"2026-11-07T13:05:00Z")!,lastTry:[:]).isEmpty,"after its time it still gets the full 10 minutes")
check(JobHeal.due(later,now:iso.date(from:"2026-11-07T13:11:00Z")!,lastTry:[:]).count == 1,"10 minutes past its time with no 'got it': chased")
print(fails == 0 ? "ALL PASS (self-healing handoffs)" : "\(fails) FAILED (self-healing handoffs)")
