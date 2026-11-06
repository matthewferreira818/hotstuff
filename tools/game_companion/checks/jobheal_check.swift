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
check(JobHeal.due(jobs,now:t("18:05:00"),lastTry:[:],handed:[]).filter { $0.id != "J-C" }.isEmpty,"nothing is resent before 10 minutes")
let at11 = JobHeal.due(jobs,now:t("18:11:00"),lastTry:[:],handed:[])
check(at11.contains(JobHeal.Due(id:"J-A",to:"LC-Pixels",action:.resend)),"no 'got it' after 10 minutes: resend")
check(!at11.contains { $0.id == "J-B" },"a job that got its 'got it' is never resent")
check(at11.contains(JobHeal.Due(id:"J-C",to:"LC-Trends",action:.handToBackup)),"after 3 resends with no answer: hand to the backup")
check(JobHeal.due(jobs,now:t("18:11:00"),lastTry:["J-A":t("18:10:30")],handed:["J-C"]).isEmpty,"a wake in flight isn't repeated, and a job handed to a backup isn't handed again")
let line = JobHeal.resendLine(id:"J-A",at:t("18:11:00"))
check(line.contains("\"event\":\"resend\"") && line.contains("\"by\":\"Friday\"") && !line.contains("title"),"the resend line is job.py's format, by Friday, no title")
check(JobRules.fold(Data((line + "\n").utf8)).isEmpty,"a resend for an unknown job is ignored by the reader")
check(JobHeal.wakeText(id:"J-A").contains("J-A") && JobHeal.wakeText(id:"J-A").contains("job.py show"),"the wake carries the job id and the command, never the title")
print(fails == 0 ? "ALL PASS (self-healing handoffs)" : "\(fails) FAILED (self-healing handoffs)")
