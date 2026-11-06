import Foundation
let now = Date(); var fails = 0
func check(_ n: String,_ c: Bool){ print(c ? "PASS" : "FAIL", n); if !c {fails+=1} }
let k="lc-tiktok"
var r = CrewSignals.decide(key:k,signals:[CrewSignal(chat:k,date:now.addingTimeInterval(-600),what:"Hotline post words")],failed:false,now:now)
check("post 10 min ago -> working: \(r.detail)", r.state == .working && r.detail.contains("Hotline post words"))
r = CrewSignals.decide(key:k,signals:[CrewSignal(chat:k,date:now.addingTimeInterval(-300),what:"commit: fix thing")],failed:false,now:now)
check("commit 5 min ago -> working: \(r.detail)", r.state == .working && r.detail.contains("commit: fix thing"))
r = CrewSignals.decide(key:k,signals:[CrewSignal(chat:k,date:now.addingTimeInterval(-2400),what:"old")],failed:false,now:now)
check("nothing in 40 min -> idle: \(r.detail)", r.state == .idle)
r = CrewSignals.decide(key:k,signals:[],failed:true,now:now)
check("fetch failure -> unknown: \(r.detail)", r.state == .unknown && r.detail.contains("couldn't reach GitHub"))
r = CrewSignals.decide(key:k,signals:[CrewSignal(chat:k,date:now.addingTimeInterval(-2400),what:"old")],failed:true,now:now)
check("old signal + failure -> unknown (no old value)", r.state == .unknown)
r = CrewSignals.decide(key:k,signals:[CrewSignal(chat:"lc-work",date:now.addingTimeInterval(-60),what:"x")],failed:false,now:now)
check("other chat's signal ignored -> idle", r.state == .idle)
check("canon", CrewSignals.canon("LC-Helm: build revamp (B v2)")=="lc-helm-build" && CrewSignals.canon("LC_Helm")=="lc-helm" && CrewSignals.canon("LC-TikTok")=="lc-tiktok")
func ev(_ t: String,_ ago: Double,_ payload: String) -> String { "{\"type\":\"\(t)\",\"created_at\":\"\(ISO8601DateFormatter().string(from:now.addingTimeInterval(-ago)))\",\"payload\":\(payload)}" }
func cm(_ n: Int,_ login: String,_ body: String) -> String { "{\"issue\":{\"number\":\(n)},\"comment\":{\"body\":\"\(body)\",\"user\":{\"login\":\"\(login)\"}}}" }
func push(_ ref: String) -> String { "{\"ref\":\"\(ref)\",\"commits\":[{\"message\":\"Add typed chat\\n\\nbody\"}]}" }
func parse(_ evs: [String]) -> [CrewSignal] { CrewSignals.parseEvents(("[" + evs.joined(separator:",") + "]").data(using:.utf8)!,now:now) ?? [] }
var p = parse([ev("PushEvent",120,push("refs/heads/friday-phase1-chat"))])
check("PushEvent friday-phase1-chat -> LC-TikTok working", p.count==1 && CrewSignals.decide(key:"lc-tiktok",signals:p,failed:false,now:now).state == .working && p[0].what == "commit: Add typed chat")
p = parse([ev("IssueCommentEvent",300,cm(35,"matthewferreira818","**[Local Claude (LC-Trends) → Claude]** report ready"))])
check("IssueCommentEvent #35 tagged LC-Trends -> working", p.count==1 && CrewSignals.decide(key:"lc-trends",signals:p,failed:false,now:now).state == .working)
check("non-owner comment ignored", parse([ev("IssueCommentEvent",60,cm(35,"someoneelse","**[Local Claude (LC-Trends) → Claude]** hi"))]).isEmpty)
check("Friday line ignored", parse([ev("IssueCommentEvent",60,cm(35,"matthewferreira818","**[Friday → Everyone]** hello"))]).isEmpty)
check("push to master ignored", parse([ev("PushEvent",60,push("refs/heads/master"))]).isEmpty)
check("comment on another issue ignored", parse([ev("IssueCommentEvent",60,cm(99,"matthewferreira818","**[Local Claude (LC-Trends) → Claude]** x"))]).isEmpty)
check("event older than 30 min ignored", parse([ev("PushEvent",2400,push("refs/heads/tiktok-samples"))]).isEmpty)
check("garbage feed -> nil (becomes unknown)", CrewSignals.parseEvents("nope".data(using:.utf8)!,now:now) == nil)
exit(fails == 0 ? 0 : 1)
