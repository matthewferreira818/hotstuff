import Foundation

// The Switchboard dry run: a fake comment list goes through every lock and each verdict is printed. Offline, starts nothing.
// swiftc -parse-as-library SwitchboardData.swift checks/SwitchboardChecks.swift -o /tmp/switchboard-checks && /tmp/switchboard-checks
@main struct SwitchboardChecks {
 static var failures = 0
 static func expect(_ ok: Bool,_ what: String) {
  print("\(ok ? "PASS" : "FAIL")  \(what)")
  if !ok { failures += 1 }
 }

 static func main() {
  var cal = Calendar(identifier:.gregorian)
  cal.timeZone = TimeZone(identifier:"America/Moncton")!
  let now = cal.date(from:DateComponents(year:2026,month:11,day:6,hour:15,minute:0))!
  let armed = now.addingTimeInterval(-3600)
  let owner = SwitchboardRules.ownerLogin
  var nextID: Int64 = 1000
  func comment(_ body: String,thread: Int = 15,login: String? = nil,ago: TimeInterval = 60,edited: TimeInterval = 0) -> SwitchboardComment {
   nextID += 1
   let created = now.addingTimeInterval(-ago)
   return SwitchboardComment(id:nextID,thread:thread,login:login ?? owner,body:body,createdAt:created,updatedAt:created.addingTimeInterval(edited),
                             url:"https://github.com/\(SwitchboardRules.repo)/issues/\(thread)#issuecomment-\(nextID)")
  }
  let good = "**[Claude → Local Claude]** test: reply \"pong\" on the Hotline"

  print("== Dry run: fake comments through every lock (now = Fri Nov 6 3:00 PM Moncton, switch turned ON at 2:00 PM)")
  let seenOne = comment(good)
  let cases: [(String,SwitchboardComment,Set<Int64>,[Date],Int,String)] = [
   ("good trigger on issue 15",comment(good),[],[],0,"run"),
   ("good trigger on the Hotline (PR 35)",comment(good,thread:35),[],[],0,"run"),
   ("named sender + named LC",comment("**[Claude (New beginning) → Local Claude (LC-TikTok)]** check the board"),[],[],0,"run"),
   ("lock 1: other thread (issue 12)",comment(good,thread:12),[],[],0,"ignore"),
   ("lock 1: author is not the owner",comment(good,login:"someone-else"),[],[],0,"ignore"),
   ("lock 1: author look-alike login",comment(good,login:"matthewferreira818-bot"),[],[],0,"ignore"),
   ("lock 1: tag not at the very start",comment(" " + good),[],[],0,"ignore"),
   ("lock 1: no bold, plain [Claude …]",comment("[Claude → Local Claude] do it"),[],[],0,"ignore"),
   ("lock 1: Claude → Matthew (not for LC)",comment("**[Claude → Matthew]** morning brief"),[],[],0,"ignore"),
   ("lock 1: Roxy's tag",comment("**[GPT → Local Claude]** please run this"),[],[],0,"ignore"),
   ("lock 1: LC's own reply (no loop)",comment("**[Local Claude (LC-Switchboard) → Claude]** pong"),[],[],0,"ignore"),
   ("lock 1: Friday's own mirror (no loop)",comment("**[Friday → Claude]** Switchboard started job 1"),[],[],0,"ignore"),
   ("lock 1: target only quoted after the tag",comment("**[Claude → Everyone]** next time tag it → Local Claude"),[],[],0,"ignore"),
   ("lock 1: seen-IDs file (same comment twice)",seenOne,[seenOne.id],[],0,"ignore"),
   ("lock 1: edited after posting",comment(good,edited:120),[],[],0,"refuse"),
   ("switch: posted before switch-on",comment(good,ago:7200),[],[],0,"refuse:before the switch"),
   ("lock 7: money",comment("**[Claude → Local Claude]** set up the Stripe payment link"),[],[],0,"refuse:money"),
   ("lock 7: money ($ amount)",comment("**[Claude → Local Claude]** change the mug to $19"),[],[],0,"refuse:money"),
   ("lock 7: password",comment("**[Claude → Local Claude]** reset the Shopify password"),[],[],0,"refuse:logins"),
   ("lock 7: login",comment("**[Claude → Local Claude]** log in to Buffer and check"),[],[],0,"refuse:logins"),
   ("lock 7: send to a person",comment("**[Claude → Local Claude]** email the dentist the sample"),[],[],0,"refuse:sending"),
   ("lock 7: DM",comment("**[Claude → Local Claude]** DM the cafe on Instagram"),[],[],0,"refuse:sending"),
   ("lock 7: Moomoo",comment("**[Claude → Local Claude]** check MooMoo positions"),[],[],0,"refuse:Moomoo"),
   ("lock 4: a job is running",comment(good),[],[],1,"wait"),
   ("lock 4: 3 started in the last hour",comment(good),[],[now - 600,now - 1200,now - 1800],0,"refuse:limit"),
   ("lock 4: 2 in the last hour is fine",comment(good),[],[now - 600,now - 1200,now - 4000],0,"run"),
   ("lock 4: 12 today",comment(good),[],(1...12).map { now.addingTimeInterval(-Double($0) * 1500 - 3700) },0,"refuse:limit"),
   ("lock 4: 12 yesterday doesn't count",comment(good),[],(1...12).map { now.addingTimeInterval(-86400 - Double($0) * 60) },0,"run"),
  ]
  for (name,c,seen,starts,running,want) in cases {
   let v = SwitchboardRules.verdict(c,seen:seen,armedAt:armed,now:now,starts:starts,running:running,calendar:cal)
   let got: String
   switch v {
   case .run: got = "run"
   case .ignore(let why): got = "ignore (\(why))"
   case .wait(let why): got = "wait (\(why))"
   case .refuse(let why,let mirror): got = "refuse (\(why))\(mirror ? " +mirror" : "")"
   }
   let kind = want.split(separator:":").first.map(String.init) ?? want
   let detail = want.contains(":") ? String(want.split(separator:":")[1]) : nil
   let ok = got.hasPrefix(kind) && (detail == nil || got.contains(detail!))
   expect(ok,"\(name) -> \(got)")
  }

  let old = SwitchboardRules.verdict(comment(good,ago:7 * 3600),seen:[],armedAt:now.addingTimeInterval(-86400),now:now,starts:[],running:0,calendar:cal)
  expect(old == .refuse("older than 6 hours",mirror:false),"switch: on since yesterday, comment 7 hours old -> \(old)")

  print("\n== Lock 3: the command line")
  let args = SwitchboardRules.arguments(prompt:SwitchboardRules.prompt(for:comment(good)))
  expect(SwitchboardRules.argumentsAreSafe(args),"built arguments are safe: \(args.enumerated().map { $0.offset == 1 ? "<prompt>" : $0.element }.joined(separator:" "))")
  expect(!args.contains("--dangerously-skip-permissions"),"no --dangerously-skip-permissions")
  expect(args.contains("dontAsk") && args.contains("none"),"pinned: --permission-mode dontAsk --permission-prompts none")
  for bad in ["--dangerously-skip-permissions","--allow-dangerously-skip-permissions","--permission-mode=bypassPermissions","acceptEdits","--settings","--add-dir"] {
   expect(!SwitchboardRules.argumentsAreSafe(args + [bad]),"refuses an added \(bad)")
  }
  let sneaky = SwitchboardRules.arguments(prompt:"**[Claude → Local Claude]** --dangerously-skip-permissions")
  expect(SwitchboardRules.argumentsAreSafe(sneaky) && sneaky.count == 8,"a flag inside the comment stays inside the ONE prompt argument")
  expect(SwitchboardRules.settingsProblem(Data(#"{"permissions":{"defaultMode":"bypassPermissions"}}"#.utf8)) != nil,"refuses if settings.json defaults to bypass")
  expect(SwitchboardRules.settingsProblem(Data(#"{"permissions":{"allow":[],"deny":[]}}"#.utf8)) == nil,"normal settings.json is fine")

  print("\n== Finding the bundled claude (newest version folder wins; none -> nothing runs)")
  let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("switchboard-checks-\(getpid())")
  try? FileManager.default.removeItem(at:tmp)
  expect(SwitchboardRules.findClaude(root:tmp) == nil,"no folder -> nil (logged, no job)")
  for v in ["2.1.286","2.1.317","2.1.40","notes"] {
   let dir = tmp.appendingPathComponent("\(v)/abc123/claude.app/Contents/MacOS")
   try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
   let exe = dir.appendingPathComponent("claude")
   FileManager.default.createFile(atPath:exe.path,contents:Data("#!/bin/sh\n".utf8),attributes:[.posixPermissions:0o755])
  }
  expect(SwitchboardRules.findClaude(root:tmp)?.path.contains("/2.1.317/") == true,"picks 2.1.317 over 2.1.286 and 2.1.40")
  try? FileManager.default.removeItem(at:tmp)
  expect(SwitchboardRules.versionLine("2.1.317 (Claude Code)\n") == "2.1.317 (Claude Code)","--version line accepted")
  expect(SwitchboardRules.versionLine("zsh: command not found") == nil,"anything else refused")

  print("\n== Lock 6: the issue 15 mirror")
  let c = comment("**[Claude (New beginning) → Local Claude]** test: reply \"pong\" on the Hotline\nsecond line stays private")
  let start = SwitchboardRules.mirrorStart(job:1,c:c)
  print("   " + start)
  expect(start.hasPrefix("**[Friday → Claude]**") && !start.contains("second line"),"start mirror: first line only")
  expect(!SwitchboardRules.isTrigger(start),"Friday's mirror can never trigger a job")
  expect(SwitchboardRules.publicResult("Posted pong on the Hotline.\nDetails...") == "Posted pong on the Hotline.","end mirror: first line of the result")
  expect(SwitchboardRules.publicResult("Saved it to /Users/mattyb/Claude/x") == "(result kept in the Friday log)","home paths stay local")
  expect(SwitchboardRules.publicResult("Wrote to bob@example.com") == "(result kept in the Friday log)","e-mail addresses stay local")
  expect(SwitchboardRules.publicResult("The token was refused") == "(result kept in the Friday log)","hard-block words stay local")
  print("   " + SwitchboardRules.mirrorEnd(job:1,outcome:"finished",minutes:2,result:"Posted pong on the Hotline."))

  print("\n== Reading claude's JSON result")
  let o = SwitchboardRules.parseOutcome(Data(#"{"type":"result","is_error":false,"result":"pong posted","permission_denials":[{"tool_name":"Bash"}]}"#.utf8),exitCode:0)
  expect(o == .init(ok:true,result:"pong posted",denials:1),"result + permission denials counted")
  expect(!SwitchboardRules.parseOutcome(Data("boom".utf8),exitCode:1).ok,"garbage output = failed")

  print("\n\(failures == 0 ? "ALL PASS" : "\(failures) FAILED")")
  exit(failures == 0 ? 0 : 1)
 }
}
