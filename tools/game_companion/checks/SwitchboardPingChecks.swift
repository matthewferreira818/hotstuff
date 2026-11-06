import Foundation

// Phase 2 engine checks: ping routing, loop guards, cooldown/caps, the wake text (never the message), the DM files. Offline.
// swiftc -parse-as-library MeetingData.swift SwitchboardData.swift FridayBrainData.swift SwitchboardPingData.swift checks/SwitchboardPingChecks.swift -o /tmp/ping-checks && /tmp/ping-checks
@main struct SwitchboardPingChecks {
 static var failures = 0
 static func expect(_ ok: Bool,_ what: String) { print("\(ok ? "PASS" : "FAIL")  \(what)"); if !ok { failures += 1 } }

 static func main() {
  var cal = Calendar(identifier:.gregorian); cal.timeZone = TimeZone(identifier:"America/Moncton")!
  let now = cal.date(from:DateComponents(year:2026,month:11,day:6,hour:9,minute:0))!
  let armed = now.addingTimeInterval(-3600)
  var nextID: Int64 = 7000
  func msg(_ body: String,thread: Int = 15,login: String = SwitchboardRules.ownerLogin,ago: TimeInterval = 30) -> SwitchboardComment {
   nextID += 1
   let t = now.addingTimeInterval(-ago)
   return SwitchboardComment(id:nextID,thread:thread,login:login,body:body,createdAt:t,updatedAt:t,url:"https://github.com/matthewferreira818/hotstuff/issues/15#issuecomment-\(nextID)")
  }
  func routeOf(_ c: SwitchboardComment) -> PingRoute { PingRules.route(c,now:now,armedAt:armed) }
  func desc(_ r: PingRoute) -> String { switch r { case .none(let w): return "none (\(w))"; case .wake(let n): return "wake \(n)"; case .hotlinePointer: return "hotline pointer" } }

  print("== Room ping routing table (issue 15, owner account)")
  let table: [(String,SwitchboardComment,PingRoute?,String)] = [
   ("named LC, Local Claude (…) form",msg("**[Claude (New beginning) → Local Claude (LC-Manager)]** hello"),.wake(["LC-Manager"]),""),
   ("named LC, bare name",msg("**[Matthew → LC-TikTok]** hello"),.wake(["LC-TikTok"]),""),
   ("underscore name keeps its spelling",msg("**[Matthew → LC_Manager]** hello"),.wake(["LC_Manager"]),""),
   ("→ Friday",msg("**[Matthew → Friday]** hello"),.wake(["Friday"]),""),
   ("→ Friday from an LC chat",msg("**[Local Claude (LC-Manager) → Friday]** hello"),.wake(["Friday"]),""),
   ("→ LC-Pixels",msg("**[Claude → Local Claude (LC-Pixels)]** hello"),.wake(["LC-Pixels"]),""),
   ("→ Everyone from Matthew wakes LC-Manager + Friday only",msg("**[Matthew → Everyone]** morning"),.wake(["LC-Manager","Friday"]),""),
   ("→ Everyone from Claude does NOT wake anyone",msg("**[Claude → Everyone]** fyi"),nil,"Everyone"),
   ("→ Everyone from an LC chat does NOT wake anyone",msg("**[Local Claude (LC-Helm) → Everyone]** fyi"),nil,"Everyone"),
   ("→ Claude = one pointer on the Hotline",msg("**[Local Claude (LC-TikTok) → Claude]** question"),.hotlinePointer,""),
   ("→ Claude (New beginning) = pointer",msg("**[Matthew → Claude (New beginning)]** question"),.hotlinePointer,""),
   ("loop guard: Friday's own line",msg("**[Friday → LC-Manager]** hello"),nil,"Friday"),
   ("loop guard: Friday's own line to Everyone",msg("**[Friday → Everyone]** hello"),nil,"Friday"),
   ("loop guard: the Switchboard's receipt",msg("**[Friday (LC-Switchboard) → Claude]** Switchboard relayed comment 1 to LC-Manager: delivered."),nil,"receipt"),
   ("loop guard: a ping pointer itself",msg("**[Friday (LC-Switchboard) → Claude]** new room message for you: https://x"),nil,"receipt"),
   ("not to its own sender",msg("**[Local Claude (LC-TikTok) → LC-TikTok]** note to self"),nil,"own sender"),
   ("→ Matthew is not a ping",msg("**[Claude → Matthew]** brief"),nil,"not addressed"),
   ("→ GPT / Roxy / Grok are not LC chats",msg("**[Claude → GPT]** draft please"),nil,"not addressed"),
   ("plain → Local Claude is job territory, not a ping",msg("**[Claude → Local Claude]** do a thing"),nil,"not addressed"),
   ("→ Local Claude chats is not a name",msg("**[Claude → Local Claude chats]** hi"),nil,"not addressed"),
   ("no tag at all",msg("just words"),nil,"tag"),
   ("not the owner account",msg("**[Matthew → Friday]** hello",login:"someone-else"),nil,"owner"),
   ("the Hotline is never a ping source",msg("**[Claude → Local Claude (LC-Manager)]** hello",thread:35),nil,"not the room"),
   ("posted before the switch went on",msg("**[Matthew → Friday]** hello",ago:7200),nil,"before"),
   ("older than 6 hours",PingRules.route(msg("**[Matthew → Friday]** hello",ago:7 * 3600),now:now,armedAt:now.addingTimeInterval(-86400)) == .none("older than 6 hours") ? msg("x") : msg("**[Matthew → Friday]** y"),nil,""),
  ]
  for (name,c,want,why) in table {
   let got = routeOf(c)
   if name == "older than 6 hours" { expect(PingRules.route(msg("**[Matthew → Friday]** hello",ago:7 * 3600),now:now,armedAt:now.addingTimeInterval(-86400)) == .none("older than 6 hours"),"older than 6 hours is no ping"); continue }
   if let w = want { expect(got == w,"\(name) -> \(desc(got))") }
   else { if case .none(let reason) = got { expect(reason.lowercased().contains(why.lowercased()),"\(name) -> \(desc(got))") } else { expect(false,"\(name) -> \(desc(got)) (should be none)") } }
  }

  print("\n== Cooldown (2 min per chat) and caps")
  expect(PingRules.gate(chat:"LC-Manager",now:now,last:[:],sent:[],calendar:cal) == .go,"first wake goes")
  expect(PingRules.gate(chat:"LC-Manager",now:now,last:["lcmanager":now.addingTimeInterval(-60)],sent:[],calendar:cal) == .cooldown,"same chat 60 s later: cooldown")
  expect(PingRules.gate(chat:"LC_Manager",now:now,last:["lcmanager":now.addingTimeInterval(-60)],sent:[],calendar:cal) == .cooldown,"underscore spelling shares the cooldown")
  expect(PingRules.gate(chat:"LC-Manager",now:now,last:["lcmanager":now.addingTimeInterval(-121)],sent:[],calendar:cal) == .go,"same chat after 2 min: goes")
  expect(PingRules.gate(chat:"Friday",now:now,last:["lcmanager":now.addingTimeInterval(-10)],sent:[],calendar:cal) == .go,"a different chat is not blocked by someone else's cooldown")
  expect(PingRules.gate(chat:"Friday",now:now,last:[:],sent:(1...30).map { now.addingTimeInterval(-Double($0) * 60) },calendar:cal) == .hourCap,"30 wakes in the last hour: hour cap")
  expect(PingRules.gate(chat:"Friday",now:now,last:[:],sent:(1...29).map { now.addingTimeInterval(-Double($0) * 60) },calendar:cal) == .go,"29 in the hour: goes")

  print("\n== The wake text is a link, never the message")
  let secret = "SECRET-BODY-123 please keep this out of every wake, log and receipt"
  let c = msg("**[Claude → Local Claude (LC-Manager)]** \(secret)")
  let w = PingRules.wakeText(link:c.url)
  expect(w == "new room message for you: \(c.url)" && !w.contains("SECRET-BODY"),"wake text = 'new room message for you: <link>' and has none of the message: \(w)")
  expect(!PingRules.pointerText(link:c.url).contains("SECRET-BODY") && PingRules.pointerText(link:c.url).hasPrefix("**[Friday (LC-Switchboard) → Claude]**"),"Hotline pointer carries only the link, under Friday's tag")
  expect(!PingRules.wakePrompt(name:"LC-Manager",message:w).contains("SECRET-BODY"),"the relay prompt for a wake never sees the message")
  expect(PingRules.route(msg(PingRules.pointerText(link:c.url)),now:now,armedAt:armed) == .none("Friday's own line or a receipt"),"the pointer line can't ping anyone (no loop)")
  let args = PingRules.wakeArguments(name:"LC-Manager",message:w)
  expect(PingRules.wakeArgumentsAreSafe(args),"wake command line is safe: \(args.enumerated().map { $0.offset == 1 ? "<prompt>" : ($0.element.hasPrefix("{") ? "<settings>" : $0.element) }.joined(separator:" "))")
  expect(args.contains("--tools") && args[args.firstIndex(of:"--tools")! + 1] == "ToolSearch,ListAgents,SendMessage","a wake has only ToolSearch, ListAgents, SendMessage")
  expect(!PingRules.wakeArgumentsAreSafe(Array(args.prefix(args.count - 2))),"a wake without the hooks-off setting is refused")
  expect(!PingRules.wakeArgumentsAreSafe(args + ["--dangerously-skip-permissions"]),"a wake with a bypass flag is refused")
  expect(!args.contains("--model"),"Haiku setting OFF: wakes carry no --model")
  let hw = PingRules.wakeArguments(name:"LC-Manager",message:w,light:true)
  expect(PingRules.wakeArgumentsAreSafe(hw) && hw[hw.firstIndex(of:"--model")! + 1] == "haiku" && !PingRules.wakeArgumentsAreSafe(hw.map { $0 == "haiku" ? "sonnet" : $0 }),"Haiku setting ON: wakes run on Haiku; any other model is refused")
  expect(args.contains(SwitchboardRules.noTranscript) && !PingRules.wakeArgumentsAreSafe(args.filter { $0 != SwitchboardRules.noTranscript }),"a wake carries --no-session-persistence and is refused without it")

  print("\n== Delivery proof for a wake (same parser as a Hotline relay)")
  func stream(_ to: String,_ message: String,ok: Bool) -> Data {
   func j(_ o: [String: Any]) -> String { String(decoding:try! JSONSerialization.data(withJSONObject:o),as:UTF8.self) }
   let lines = [j(["type":"assistant","message":["content":[["type":"tool_use","id":"L","name":"ListAgents","input":[:]]]]]),
                j(["type":"user","message":["content":[["type":"tool_result","tool_use_id":"L","content":"Peer sessions (2):\n  LC_Manager [aa11]  ·  idle\n  Friday [bb22]  ·  idle\n"]]]]),
                j(["type":"assistant","message":["content":[["type":"tool_use","id":"S","name":"SendMessage","input":["to":to,"message":message]]]]]),
                j(["type":"user","message":["content":[["type":"tool_result","tool_use_id":"S","content":ok ? #"{"success":true}"# : "error"]]]]),
                j(["type":"result","is_error":false,"result":"DELIVERED","num_turns":3])]
   return Data(lines.joined(separator:"\n").utf8)
  }
  expect(SwitchboardRules.parseRelay(stream("LC_Manager",w,ok:true),target:"LC-Manager",expected:w).delivered,"wake to LC-Manager: delivered only on success:true, right chat, verbatim text")
  expect(!SwitchboardRules.parseRelay(stream("Friday",w,ok:true),target:"LC-Manager",expected:w).delivered,"sent to the wrong chat: not delivered")
  expect(!SwitchboardRules.parseRelay(stream("LC_Manager",w + " extra",ok:true),target:"LC-Manager",expected:w).delivered,"text changed: not delivered")
  let closed = SwitchboardRules.parseRelay(Data(#"{"type":"result","is_error":false,"result":"NOT DELIVERED: Friday isn't open","num_turns":2}"#.utf8),target:"Friday",expected:w)
  expect(!closed.delivered && !closed.unproven,"chat not open: not delivered, not 'unconfirmed'")

  print("\n== Results the screen shows")
  let ok = PingResult(id:1,at:now,targets:["LC-Manager":"delivered"])
  expect(ok.allOK && ok.badge == "pinged ✓ LC-Manager","delivered -> \(ok.badge)")
  let mixed = PingResult(id:2,at:now,targets:["Friday":"not open","LC-Manager":"delivered"])
  expect(!mixed.allOK && mixed.badge == "pinged ✗ Friday (not open) · pinged ✓ LC-Manager","mixed -> \(mixed.badge)")
  let ptr = PingResult(id:3,at:now,targets:[:],pointer:"posted")
  expect(ptr.allOK && ptr.badge == "pinged ✓ cloud Claude","pointer posted -> \(ptr.badge)")
  expect(!PingResult(id:4,at:now,targets:["LC-Manager":"cooldown"]).allOK,"a cooldown skip is shown as ✗ (skipped)")
  let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
  let json = String(decoding:try! enc.encode(ok),as:UTF8.self)
  expect(!json.contains("SECRET") && json.contains("\"targets\""),"a stored result holds names and outcomes only")

  print("\n== Friday-and-me DM files")
  expect(PingRules.dmWakeText == "new DM, read ~/Claude/friday-dm/inbox.jsonl","DM wake text is the fixed sentence")
  let dmText = "TOP-SECRET-DM my private words"
  guard let made = DMRules.inboxLine(text:dmText,now:now) else { expect(false,"inboxLine built"); return }
  expect(made.line.contains("TOP-SECRET-DM") && !made.line.contains("\n"),"the inbox line (a private file) holds the message on one line")
  expect(!PingRules.dmWakeText.contains("TOP-SECRET-DM") && !PingRules.wakePrompt(name:"Friday",message:PingRules.dmWakeText).contains("TOP-SECRET-DM"),"the DM wake text and its relay prompt NEVER contain the message")
  let back = DMRules.lines(Data((made.line + "\n").utf8),as:DMIn.self)
  expect(back.count == 1 && back[0].text == dmText && back[0].id == made.id,"inbox line round-trips {id, at, text}")
  expect(made.line.contains("\"id\"") && made.line.contains("\"at\"") && made.line.contains("\"text\""),"inbox shape is {id, at, text}")
  let out = DMOut(id:"r1",replyTo:made.id,at:now,text:"hi back")
  let outLine = DMRules.line(out) ?? ""
  expect(outLine.contains("\"replyTo\"") && DMRules.lines(Data(outLine.utf8),as:DMOut.self) == [out],"outbox shape is {id, replyTo, at, text} and round-trips")
  expect(DMRules.inboxLine(text:"   \n ",now:now) == nil,"an empty DM is not written")
  expect((DMRules.inboxLine(text:String(repeating:"x",count:25000),now:now).map { DMRules.lines(Data($0.line.utf8),as:DMIn.self)[0].text.count } ?? 0) == DMRules.maxTextCount,"a very long DM is capped at \(DMRules.maxTextCount) characters")
  expect(DMRules.inboxLine(text:"line one\nline two",now:now).map { !$0.line.contains("\n") && DMRules.lines(Data($0.line.utf8),as:DMIn.self)[0].text == "line one\nline two" } ?? false,"a multi-line DM stays one JSONL line")
  let status = ["a": DMStatus(id:"a",at:now,state:"woken")]
  let inbox = [DMIn(id:"a",at:now,text:"x"),DMIn(id:"b",at:now,text:"y")]
  expect(DMRules.unhandled(inbox:inbox,status:status).map { $0.id } == ["b"],"only DMs without a status still need a wake")
  expect(DMRules.note(for:DMStatus(id:"b",at:now,state:"closed")) == "Friday's chat is closed — open it to talk","closed chat: the screen note is exactly 'Friday's chat is closed — open it to talk'")
  expect(DMRules.note(for:DMStatus(id:"b",at:now,state:"woken")) == nil,"woken: no note")
  expect(Set((1...50).map { _ in DMRules.newID() }).count > 40,"ids are unique")

  print("\n== Forgiving chat-name matching (LC-Pixels vs the open chat LC-Pixel)")
  typealias NM = SwitchboardRules.NameMatch
  let listing = ["LC_Manager [2d9a46]","LC-Pixel [aa1111]","LC-Helm: build revamp (B v2) [e4bf1e]","Friday [bb2222]","LC-TikTok [0830bd]","LC-Trends [ac175c]"]
  expect(NM.resolve("LC-Pixels",listed:listing) == .one("LC-Pixel"),"LC-Pixels = LC-Pixel (trailing s)")
  expect(NM.resolve("LC-Pixel",listed:listing) == .one("LC-Pixel"),"LC-Pixel = LC-Pixel")
  expect(NM.resolve("lc pixels",listed:listing) == .one("LC-Pixel"),"spaces and case don't matter: 'lc pixels'")
  expect(NM.resolve("LC-Manager",listed:listing) == .one("LC_Manager"),"LC-Manager = LC_Manager")
  expect(NM.resolve("LC_Manager",listed:listing) == .one("LC_Manager"),"LC_Manager = LC_Manager")
  expect(NM.resolve("LC-Helm build",listed:listing) == .one("LC-Helm: build revamp (B v2)"),"'LC-Helm build' = 'LC-Helm: build revamp (B v2)' (unique short name)")
  expect(NM.resolve("LC-Helm: build",listed:listing) == .one("LC-Helm: build revamp (B v2)"),"colon and spaces ignored")
  expect(NM.resolve("friday",listed:listing) == .one("Friday"),"friday = Friday")
  expect(NM.resolve("LC-Hel",listed:listing) == .many(["LC-Helm: build revamp (B v2)"]) || NM.resolve("LC-Hel",listed:listing) == .one("LC-Helm: build revamp (B v2)"),"a 5-letter prefix finds the one chat")
  let two = listing + ["LC-Helm: design [cc3333]"]
  expect(NM.resolve("LC-Helm",listed:two) == .many(["LC-Helm: build revamp (B v2)","LC-Helm: design"]),"two candidates = refuse, never guess: \(NM.resolve("LC-Helm",listed:two))")
  expect(NM.resolve("LC-Nobody",listed:listing) == .none(closest:nil),"no match = not open")
  expect(NM.resolve("LC-Trend",listed:listing) == .one("LC-Trends"),"the other direction of the trailing s")
  expect(NM.resolve("LC-Pixelz",listed:listing) == .none(closest:"LC-Pixel"),"no match names the closest chat")
  expect(NM.resolve("lc",listed:listing) == .none(closest:nil),"'lc' alone is too short to match everyone")
  expect(NM.resolve("LC-TikTok",listed:listing + ["LC-TikTok [dd4444]"]) == .many(["LC-TikTok","LC-TikTok"]),"the same name twice = refuse")
  expect(NM.strip("LC-Helm: build revamp (B v2) [e4bf1e]") == "LC-Helm: build revamp (B v2)","the [ref] is not part of the name")
  expect(PingRules.gate(chat:"LC-Pixels",now:now,last:["lcpixel":now.addingTimeInterval(-30)],sent:[],calendar:cal) == .cooldown,"LC-Pixels and LC-Pixel share one cooldown")
  expect(PingRules.chatName("Local Claude (LC-Pixels)") == "LC-Pixels" && PingRules.chatName("LC Pixels") == "LC Pixels","tag targets 'LC-Pixels' and 'LC Pixels' are chat names")
  expect(PingRules.route(msg("**[Matthew → Local Claude (LC-Pixels)]** roll call"),now:now,armedAt:armed) == .wake(["LC-Pixels"]),"the roll call to LC-Pixels still routes to a wake")
  // the delivery proof under forgiving matching
  func send(_ to: String,_ list: String,_ text: String,reply: String = #"{"success":true}"#) -> Data {
   func j(_ o: [String: Any]) -> String { String(decoding:try! JSONSerialization.data(withJSONObject:o),as:UTF8.self) }
   return Data([j(["type":"assistant","message":["content":[["type":"tool_use","id":"L","name":"ListAgents","input":[:]]]]]),
                j(["type":"user","message":["content":[["type":"tool_result","tool_use_id":"L","content":"Peer sessions:\n" + list]]]]),
                j(["type":"assistant","message":["content":[["type":"tool_use","id":"S","name":"SendMessage","input":["to":to,"message":text]]]]]),
                j(["type":"user","message":["content":[["type":"tool_result","tool_use_id":"S","content":reply]]]]),
                j(["type":"result","is_error":false,"result":"DELIVERED","num_turns":3])].joined(separator:"\n").utf8)
  }
  let listText = listing.map { "  \($0)  ·  idle" }.joined(separator:"\n")
  expect(SwitchboardRules.parseRelay(send("LC-Pixel",listText,"hi"),target:"LC-Pixels",expected:"hi").delivered,"target LC-Pixels, sent to the open LC-Pixel: delivered")
  expect(SwitchboardRules.parseRelay(send("LC-Helm: build revamp (B v2)",listText,"hi"),target:"LC-Helm build",expected:"hi").delivered,"short name delivered to a chat whose name has spaces and a colon")
  expect(!SwitchboardRules.parseRelay(send("Friday",listText,"hi"),target:"LC-Pixels",expected:"hi").delivered,"sent to the wrong chat: not delivered")
  let amb = SwitchboardRules.parseRelay(send("LC-Helm: design",listText + "\n  LC-Helm: design [cc3333]  ·  idle","hi"),target:"LC-Helm",expected:"hi")
  expect(!amb.delivered && amb.unproven,"two chats match but it sent anyway: UNPROVEN, not 'delivered'")
  func noSend(_ list: String,_ final: String) -> Data {
   func j(_ o: [String: Any]) -> String { String(decoding:try! JSONSerialization.data(withJSONObject:o),as:UTF8.self) }
   return Data([j(["type":"assistant","message":["content":[["type":"tool_use","id":"L","name":"ListAgents","input":[:]]]]]),
                j(["type":"user","message":["content":[["type":"tool_result","tool_use_id":"L","content":"Peer sessions:\n" + list]]]]),
                j(["type":"result","is_error":false,"result":final,"num_turns":2])].joined(separator:"\n").utf8)
  }
  let none = SwitchboardRules.parseRelay(noSend(listText,"NOT DELIVERED: x"),target:"LC-Pixelz",expected:"hi")
  expect(!none.delivered && none.detail == "LC-Pixelz isn't open (closest: LC-Pixel)","none = 'isn't open (closest: <name>)' decided by the app, not the model: \(none.detail)")
  let many = SwitchboardRules.parseRelay(noSend(listText + "\n  LC-Helm: design [cc3333]  ·  idle","NOT DELIVERED"),target:"LC-Helm",expected:"hi")
  expect(!many.delivered && many.detail.contains("more than one chat matches"),"two candidates = refused with both names: \(many.detail)")
  expect(SwitchboardRules.relayPrompt(for:msg("**[Claude → Local Claude (LC-Pixels)]** x",thread:35),name:"LC-Pixels").contains("LC-Pixels\" = \"LC-Pixel\""),"the relay prompt teaches the same matching rules")

  print("\n== Closed chat: hand off at once, keep one copy (no retry loop)")
  expect(PingRules.backups(for:"LC-Pixels") == ["Friday","LC-Manager"],"closed chat -> Friday first, LC-Manager second")
  expect(PingRules.backups(for:"Friday") == ["LC-Manager"],"Friday closed -> LC-Manager")
  expect(PingRules.backups(for:"friday") == ["LC-Manager"],"friday (any spelling) closed -> LC-Manager")
  expect(PingRules.handOffText(chat:"LC-Pixels",original:"new room message for LC-Pixels: https://x") == "for LC-Pixels, whose chat is closed; handle it or reassign: new room message for LC-Pixels: https://x","hand-off label is exactly 'for <name>, whose chat is closed; handle it or reassign: …'")
  let hl = PingRules.hotlineLine(chat:"LC-Pixels",backup:"Friday",ref:"room message 123")
  expect(hl == "**[Friday (LC-Switchboard) → Claude]** LC-Pixels is closed; Friday has it (room message 123)." && !SwitchboardRules.isTrigger(hl) && SwitchboardRules.relayTarget(hl) == nil,"one Hotline line per hand-off, under Friday's tag, can't trigger a job or relay")
  expect(PingRules.hotlineLine(chat:"LC-Pixels",backup:nil,ref:"x").contains("nobody else could take it"),"no backup open: the Hotline line says so")
  expect(PingRules.route(msg(hl),now:now,armedAt:armed) == .none("Friday's own line or a receipt"),"the hand-off line can't ping anyone (no loop)")
  let h = PingRules.Held(id:"1-lcpixel",chat:"LC-Pixels",text:"new room message for LC-Pixels: https://x",origin:1,since:now)
  expect(!PingRules.heldDue(h,now:now.addingTimeInterval(14 * 60)) && PingRules.heldDue(h,now:now.addingTimeInterval(15 * 60)),"the held copy is probed every 15 minutes, not sooner")
  var tried = h; tried.lastTry = now.addingTimeInterval(20 * 60)
  expect(!PingRules.heldDue(tried,now:now.addingTimeInterval(30 * 60)) && PingRules.heldDue(tried,now:now.addingTimeInterval(36 * 60)),"after a try the next probe is 15 minutes later")
  expect(!PingRules.heldExpired(h,now:now.addingTimeInterval(11 * 3600)) && PingRules.heldExpired(h,now:now.addingTimeInterval(13 * 3600)),"a held copy is dropped after 12 hours")
  expect(PingRules.heldText(h).contains("held for you since") && PingRules.heldText(h).hasSuffix(h.text),"the late delivery says it was held, then gives the same text")
  let handed = PingResult(id:5,at:now,targets:["LC-Pixel":"handed to Friday"])
  expect(handed.badge == "LC-Pixel closed → Friday has it" && handed.handedOff && !handed.allOK,"crew chat shows '<name> closed → Friday has it': \(handed.badge)")
  expect(PingResult(id:6,at:now,targets:["LC-Pixel":"closed"]).badge == "LC-Pixel closed, and nobody could take it","nobody could take it is shown plainly")
  let later = PingResult(id:7,at:now,targets:["LC-Pixel":"delivered later"])
  expect(later.badge == "pinged ✓ LC-Pixel (when it reopened)","delivered when it reopened: \(later.badge)")
  let wakeBack = PingRules.wakeArguments(name:"Friday",message:PingRules.handOffText(chat:"LC-Pixels",original:"new room message for LC-Pixels: https://x"))
  expect(PingRules.wakeArgumentsAreSafe(wakeBack),"a hand-off wake uses the same locked-down command line")


  print("\n== Room pings only after switch-on, and never repeated after a relaunch (fix 2026-11-06)")
  func roomAt(_ id: Int64,_ t: Date) -> SwitchboardComment {
   SwitchboardComment(id:id,thread:15,login:SwitchboardRules.ownerLogin,body:"**[Matthew → Friday]** hello",createdAt:t,updatedAt:t,url:"https://github.com/matthewferreira818/hotstuff/issues/15#issuecomment-\(id)")
  }
  func wakes(_ r: [(comment: SwitchboardComment,route: PingRoute)]) -> [Int64] { r.compactMap { if case .wake = $0.route { return $0.comment.id }; return nil } }
  let onAt = now
  var ledger = RoomPingLedger()
  expect(wakes(ledger.pass([roomAt(9001,onAt.addingTimeInterval(-60))],now:onAt)).isEmpty,"never armed: nothing pings")
  ledger = RoomPingLedger(); ledger.arm(now:onAt)
  let old2h = roomAt(9101,onAt.addingTimeInterval(-2 * 3600)), new10s = roomAt(9102,onAt.addingTimeInterval(10))
  let first = ledger.pass([old2h,new10s],now:onAt.addingTimeInterval(30))
  expect(!wakes(first).contains(9101),"a message 2 h before switch-on = no wake")
  expect(wakes(first) == [9102],"a message 10 s after switch-on = wake")
  expect(wakes(ledger.pass([old2h,new10s],now:onAt.addingTimeInterval(90))).isEmpty,"the next check doesn't wake again (seen)")
  // relaunch with the ON state kept: the ledger is saved and loaded like state.json
  let saved = try! JSONEncoder().encode(ledger)
  var reloaded = try! JSONDecoder().decode(RoomPingLedger.self,from:saved)
  let relaunchAt = onAt.addingTimeInterval(3 * 3600)
  let whileClosed = roomAt(9103,onAt.addingTimeInterval(3600))     // posted while the app was quit (switch still ON on disk)
  reloaded.relaunch(stillOn:true,now:relaunchAt)
  let afterRelaunch = reloaded.pass([old2h,new10s,whileClosed],now:relaunchAt.addingTimeInterval(20))
  expect(wakes(afterRelaunch).isEmpty,"relaunch with the same ON state = no repeat wakes, and nothing posted while the app was closed")
  expect(reloaded.seen.contains(9102) && reloaded.seen.contains(9103),"seen ids survive the relaunch")
  let freshAfter = roomAt(9104,relaunchAt.addingTimeInterval(15))
  expect(wakes(reloaded.pass([freshAfter],now:relaunchAt.addingTimeInterval(40))) == [9104],"after a relaunch, a new message still wakes")
  var offLaunch = RoomPingLedger(); offLaunch.relaunch(stillOn:false,now:relaunchAt)
  expect(offLaunch.armedAt == .distantFuture,"a launch with the switch OFF arms nothing")
  // the old 7-message case: armed hours ago, messages posted while closed, app relaunched still ON
  var stale = RoomPingLedger(); stale.arm(now:onAt.addingTimeInterval(-5 * 3600))
  let seven = (0..<7).map { roomAt(9200 + Int64($0),onAt.addingTimeInterval(-Double($0 + 1) * 1800)) }
  stale.relaunch(stillOn:true,now:onAt)
  expect(wakes(stale.pass(seven,now:onAt.addingTimeInterval(30))).isEmpty,"the 12:44 case (7 old messages, relaunched while ON) wakes nobody")
  expect(stale.since(now:onAt) == onAt.addingTimeInterval(-60),"GitHub is asked only from the arming time (minus a minute)")

  print("\n\(failures == 0 ? "ALL PASS" : "\(failures) FAILED")")
  exit(failures == 0 ? 0 : 1)
 }
}
