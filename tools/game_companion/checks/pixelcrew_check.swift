import Foundation
// Offline check of the pixel station rules (PixelCrew.swift): who walks to whom, Friday's own posts, labels, links. Run: zsh checks/run.sh
let now = Date(); var fails = 0
func check(_ n: String,_ c: Bool){ print(c ? "PASS" : "FAIL", n); if !c {fails+=1} }
func member(_ id: String,_ kind: CrewKind,_ state: CrewState = .idle) -> CrewMember { CrewMember(id:id,name:id,role:"",kind:kind,state:state,detail:"",since:nil,awayUntil:nil) }
let crew = [member("Friday",.friday),member("LC-Manager",.chat),member("LC-Helm: build revamp (B v2)",.chat),member("LC-Pixels",.chat),
            member("Cloud Claude",.cloud),member("Roxy",.agent),member("stock-bot",.robot)]
func msg(_ author: String,_ to: String,_ ago: Double,_ text: String = "hello",id: Int = Int.random(in:1...999999),source: String = "") -> RoomMessage {
 RoomMessage(id:id,author:author,to:to,text:text,date:now.addingTimeInterval(-ago),url:"u",source:source) }

check("tag 'Claude' -> Cloud Claude", PixelCrew.memberID("Claude",crew:crew) == "Cloud Claude")
check("tag 'GPT' -> Roxy", PixelCrew.memberID("GPT",crew:crew) == "Roxy")
check("tag 'Local Claude (LC-Pixels)' -> LC-Pixels", PixelCrew.memberID("Local Claude (LC-Pixels)",crew:crew) == "LC-Pixels")
check("tag 'LC-Helm build' -> long roster name", PixelCrew.memberID("Local Claude (LC-Helm build)",crew:crew) == "LC-Helm: build revamp (B v2)")
check("tag 'Everyone' -> Friday at the core", PixelCrew.memberID("Everyone",crew:crew) == "Friday")
check("tag 'Matthew' -> nobody (not on the station)", PixelCrew.memberID("Matthew",crew:crew) == nil)
check("first of several targets", PixelCrew.memberID("LC-Manager, LC-CrewState",crew:crew) == "LC-Manager")

var v = PixelCrew.visits(messages:[msg("Local Claude (LC-Pixels)","LC-Manager",300)],signals:[],crew:crew,now:now)
check("message 5 min ago -> walks to LC-Manager", v.count == 1 && v[0].from == "LC-Pixels" && v[0].to == "LC-Manager")
v = PixelCrew.visits(messages:[msg("Local Claude (LC-Pixels)","LC-Manager",20 * 60)],signals:[],crew:crew,now:now)
check("message 20 min ago -> no walk", v.isEmpty)
v = PixelCrew.visits(messages:[msg("Local Claude (LC-Pixels)","Matthew",60)],signals:[],crew:crew,now:now)
check("message to Matthew -> no walk", v.isEmpty)
v = PixelCrew.visits(messages:[msg("Local Claude (LC-Pixels)","",60)],signals:[],crew:crew,now:now)
check("untagged message -> no walk", v.isEmpty)
v = PixelCrew.visits(messages:[msg("Friday","Claude",60)],signals:[],crew:crew,now:now)
check("Friday stays at the core (no walk)", v.isEmpty)
v = PixelCrew.visits(messages:[msg("Local Claude (LC-Pixels)","LC-Pixels",60)],signals:[],crew:crew,now:now)
check("message to self -> no walk", v.isEmpty)
v = PixelCrew.visits(messages:[msg("Local Claude (LC-Pixels)","LC-Manager",500),msg("Local Claude (LC-Pixels)","Claude",100)],signals:[],crew:crew,now:now)
check("newest message wins (one walk per sender)", v.count == 1 && v[0].to == "Cloud Claude")
v = PixelCrew.visits(messages:[],signals:[CrewSignal(chat:"lc-manager",date:now.addingTimeInterval(-120),what:"gate passed",to:"LC-Pixels")],crew:crew,now:now)
check("Hotline signal with a tag -> walk", v.count == 1 && v[0].from == "LC-Manager" && v[0].to == "LC-Pixels")
v = PixelCrew.visits(messages:[],signals:[CrewSignal(chat:"lc-manager",date:now.addingTimeInterval(-120),what:"commit: x")],crew:crew,now:now)
check("commit signal (no tag) -> no walk", v.isEmpty)
v = PixelCrew.visits(messages:[msg("Claude","GPT",60)],signals:[],crew:crew,now:now)
check("cloud Claude -> Roxy walk", v.count == 1 && v[0].from == "Cloud Claude" && v[0].to == "Roxy")
v = PixelCrew.visits(messages:[msg("Local Claude (LC-Pixels)","LC-Manager",-600)],signals:[],crew:crew,now:now)
check("future-dated message ignored", v.isEmpty)

var f = PixelCrew.withFriday(crew,messages:[msg("Friday","Everyone",600,"checked the robots")],now:now)
check("Friday post 10 min ago -> working", f[0].state == .working && f[0].detail.contains("checked the robots"))
f = PixelCrew.withFriday(crew,messages:[msg("Friday","Everyone",3600)],now:now)
check("Friday post 1 h ago -> stays resting", f[0].state == .idle)
f = PixelCrew.withFriday(crew,messages:[msg("Local Claude (Friday)","Claude",60)],now:now)
check("'Local Claude (Friday)' tag counts as Friday", f[0].state == .working)

let m = PixelCrew.merged([msg("A","",1,id:1),msg("B","",1,id:2)],[msg("A","",1,id:1),msg("C","",1,id:1,source:"hotline")])
check("merged drops doubles, keeps Hotline #1", m.count == 3)
check("label trims roster name", PixelCrew.label(crew[2]) == "LC-Helm build")
check("label robot", PixelCrew.label(crew[6]) == "bot")
check("link: robot without run -> runs page", PixelCrew.link(crew[6]).url.hasSuffix("/actions"))
check("link: chat without post -> Hotline", PixelCrew.link(crew[1]).url.hasSuffix("/pull/35"))
check("walk loop: there, talk, back, home", PixelCrew.walk(1.5).walking && PixelCrew.walk(5).talking && PixelCrew.walk(9.5).walking && PixelCrew.walk(15).progress == 0)
let line = PixelCrew.line(crew[3],visit:PixelVisit(from:"LC-Pixels",to:"LC-Manager",date:now.addingTimeInterval(-120),what:"hi"),crew:crew,now:now)
check("click line names the visit: \(line)", line.hasPrefix("Messaged LC-Manager 2 min ago"))
// Board bug (11-06): the old station showed chats "away, back Nov 9" (Roxy's date). A chat is never away because a line mentions Roxy's return.
let roomLines = [msg("Local Claude (LC-Manager)","Everyone",300,"LC-Manager here: Roxy back Mon Nov 9, Grok away until Nov 11"),msg("GPT","Claude",86400,"Roxy back Mon Nov 9")]
let built = CrewData.build(messages:roomLines,runs:[],now:now)
check("no chat is away from Roxy's date", !built.contains { $0.kind == .chat && ($0.state == .away || $0.awayUntil != nil) })
check("Roxy herself is away until Nov 9", built.first(where:{ $0.id == "Roxy" })?.state == .away)

// Live sessions (~/.claude/sessions): the station shows the chats actually open on this Mac.
let reg = Data(#"{"pid":123,"name":"LC-CrewState: crew strip","status":"busy","statusUpdatedAt":1793957236254,"sessionId":"x"}"#.utf8)
let parsed = LiveSessions.parse(reg)
check("registry file -> name, busy, since", parsed?.name == "LC-CrewState: crew strip" && parsed?.busy == true && parsed?.pid == 123)
check("a file with no name is skipped", LiveSessions.parse(Data(#"{"pid":5,"status":"idle"}"#.utf8)) == nil)
check("short name cuts at ':' and fixes LC_", LiveSessions.shortName("LC-CrewState: crew strip") == "LC-CrewState" && LiveSessions.shortName("LC_Helm") == "LC-Helm")
let liveCrew = [member("Friday",.friday),member("LC-Manager",.chat),member("LC-Pixels",.chat),member("LC-Work",.chat,.working),member("stock-bot",.robot)]
let sess = [LiveSession(pid:1,name:"LC-Pixels",busy:true,since:now.addingTimeInterval(-90)),LiveSession(pid:2,name:"NB2",busy:false,since:now.addingTimeInterval(-600)),
            LiveSession(pid:3,name:"Friday",busy:true,since:now)]
let lm = LiveSessions.apply(sess,to:liveCrew,now:now)
check("busy chat -> working with the busy line", lm.crew.first(where:{ $0.id == "LC-Pixels" }).map { $0.state == .working && $0.detail.hasPrefix(LiveSessions.busyPrefix) } ?? false)
check("an open chat not in the room gets a desk", lm.crew.contains { $0.name == "NB2" && $0.state == .idle && $0.kind == .chat })
check("closed chat with no recent work leaves the station", !lm.crew.contains { $0.id == "LC-Manager" } && lm.closed == ["LC-Manager"])
check("closed chat that committed in the last 30 min keeps its desk", lm.crew.contains { $0.id == "LC-Work" })
check("Friday's busy chat makes her working", lm.crew.first(where:{ $0.kind == .friday })?.state == .working)
check("robots are untouched", lm.crew.contains { $0.id == "stock-bot" })
check("no registry -> nothing changes", LiveSessions.apply(nil,to:liveCrew,now:now).crew.count == liveCrew.count)
check("RUN timer format", LiveSessions.timer(now.addingTimeInterval(-125),now:now) == "2:05")

// A room tag "Claude (NB2)" and the open NB2 session are one desk.
var cloudNB2 = member("Cloud Claude",.cloud,.idle); cloudNB2.alias = "NB2"
let dup = LiveSessions.apply([LiveSession(pid:9,name:"NB2",busy:true,since:now)],to:[member("Friday",.friday),cloudNB2],now:now)
check("Claude (NB2) room tag + NB2 session = one desk, named NB2 and working", dup.crew.filter { $0.name == "NB2" || $0.id == "Cloud Claude" }.count == 1 && dup.crew.first(where:{ $0.id == "Cloud Claude" })?.name == "NB2" && dup.crew.first(where:{ $0.id == "Cloud Claude" })?.state == .working)
var cloudWork = member("Cloud Claude",.cloud,.idle); cloudWork.alias = "Work"
let nodup = LiveSessions.apply([LiveSession(pid:9,name:"NB2",busy:false,since:now)],to:[cloudWork],now:now)
check("Claude (Work) tag is not the NB2 session: cloud desk stays, NB2 gets its own", nodup.crew.count == 2 && nodup.crew.first(where:{ $0.id == "Cloud Claude" })?.name == "Cloud Claude")
check("tagAlias", CrewData.tagAlias("Claude (NB2)") == "NB2" && CrewData.tagAlias("Claude") == nil)
let qs = [BoardItem(id:"q1",owner:"",text:"(none open: the October questions went to the archive on 11-05)",status:""),
          BoardItem(id:"q2",owner:"Claude → Matthew",text:"CONFIRM: send the pilot offer to Maplehurst?",status:""),
          BoardItem(id:"q3",owner:"",text:"None open.",status:"")]
check("placeholder board lines are not questions waiting on Matthew", PixelCrew.realQuestions(qs).map { $0.id } == ["q2"])
exit(fails == 0 ? 0 : 1)
