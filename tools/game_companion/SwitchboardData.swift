import Foundation

// Friday's Switchboard: the rules, with no UI and no network, so checks/SwitchboardChecks.swift can test every lock offline.
// Built 2026-11-06 by LC-TikTok for LC-Manager (plan: meeting-room/notes/switchboard-plan.md; README: SWITCHBOARD.md).
//
// What it does: while the switch on the Friday page is ON, Friday reads new comments on issue 15 (the room) and PR #35 (the Hotline)
// every few minutes. A comment that passes every lock below becomes ONE headless Local Claude job on this Mac
// (`claude -p`, Matthew's normal ~/.claude/settings.json allow/deny list, cwd ~/Claude/hotstuff). Start and end are mirrored to issue 15.

// Every limit in one place (LC-Manager's lock 4).
enum SwitchboardLimits {
 static let maxRunning = 1                       // one job at a time
 static let perHour = 3                          // jobs STARTED in any rolling 60 minutes
 static let perDay = 12                          // jobs started since local midnight
 static let jobTimeout: TimeInterval = 30 * 60   // a job still running at 30 minutes is stopped
 static let killGrace: TimeInterval = 10         // after the polite stop, a hard kill
 static let pollEvery: TimeInterval = 300        // how often Friday reads the two threads while ON (Matthew: 5 min)
 static let testPollEvery: TimeInterval = 30     // test copies only (own app ID, switchboard.testFastPoll)
 static let maxAge: TimeInterval = 6 * 3600      // a comment older than this never starts a job (e.g. the Mac was off)
 static let editGrace: TimeInterval = 5          // GitHub can stamp updated_at a moment after created_at on a fresh comment
 static let logKeep = 400                        // log lines kept on disk
 static let seenKeep = 5000                      // comment ids remembered
}

// One comment as GitHub gives it (only the fields the locks need).
struct SwitchboardComment: Codable, Equatable {
 var id: Int64
 var thread: Int          // 15 = issue 15, 35 = the Hotline PR
 var login: String
 var body: String
 var createdAt: Date
 var updatedAt: Date
 var url: String
}

enum SwitchboardVerdict: Equatable {
 case ignore(String)                  // not addressed to Local Claude: remembered as seen, not logged
 case refuse(String,mirror: Bool)     // addressed to Local Claude but a lock said no: remembered, logged, mirrored if `mirror`
 case wait(String)                    // fine, but a job is running: left unseen and tried again next check
 case run
}

enum SwitchboardRules {
 static let ownerLogin = "matthewferreira818"
 static let repo = "matthewferreira818/hotstuff"
 static let roomIssue = 15
 static let hotline = 35
 static let watched: Set<Int> = [roomIssue,hotline]   // lock 1: only these two threads count
 static let tagStart = "**[Claude"
 static let tagTarget = "→ Local Claude"

 // Lock 1: the body STARTS with **[Claude and the tag (up to its first "]") contains "→ Local Claude".
 // Checking inside the tag only means a message that merely quotes the tag further down can't start a job.
 static func isTrigger(_ body: String) -> Bool {
  guard body.hasPrefix(tagStart), let close = body.firstIndex(of:"]") else { return false }
  return body[body.startIndex..<close].contains(tagTarget)
 }

 // Lock 7: hard block, checked BEFORE anything starts. Whole words, any case. Over-blocking is on purpose: a refused job
 // is cheap (the sender rewords it or Matthew does it), a wrong job isn't.
 static let blocked: [(String,[String])] = [
  ("money or payments",["money","payment","payments","pay","paid","paying","payout","paypal","stripe","invoice","invoices","refund",
                        "refunds","bank","banking","e-transfer","etransfer","interac","purchase","purchases","buy","buying","sell","selling",
                        "checkout","price","prices","pricing","credit card","debit card","card number","wire transfer","crypto","bitcoin",
                        "subscription","subscribe","billing","budget"]),
  ("logins or passwords",["password","passwords","passcode","passphrase","login","logins","log in","log into","sign in","sign-in","signin",
                          "sign up","signup","2fa","mfa","otp","verification code","api key","token","tokens","secret","secrets",
                          "credential","credentials","oauth","keychain","ssh"]),
  ("sending to a person",["email","emails","e-mail","gmail","outlook","inbox","dm","dms","direct message","sms","text message","texting",
                          "whatsapp","messenger","send to","send it to","send this to","send them","send him","send her","send a message",
                          "message him","message her","message them","call him","call her","call them","phone","outreach","cold email",
                          "linkedin message","reply to the client","contact the client","contact form"]),
  ("Moomoo",["moomoo","futu","brokerage","broker"]),
 ]

 static func blockReason(_ body: String) -> String? {
  let text = body.lowercased()
  if text.range(of:#"\$\s?\d"#,options:.regularExpression) != nil { return "money or payments" }
  for (reason,words) in blocked {
   for word in words {
    let escaped = NSRegularExpression.escapedPattern(for:word)
    if text.range(of:"(?<![a-z0-9])\(escaped)(?![a-z0-9])",options:.regularExpression) != nil { return reason }
   }
  }
  return nil
 }

 static func startsInLastHour(_ starts: [Date],now: Date) -> Int { starts.filter { now.timeIntervalSince($0) < 3600 && $0 <= now }.count }
 static func startsToday(_ starts: [Date],now: Date,calendar: Calendar = .current) -> Int { starts.filter { calendar.isDate($0,inSameDayAs:now) }.count }

 // Every lock, in order. `armedAt` is when the switch was last turned ON: older comments never run.
 static func verdict(_ c: SwitchboardComment,seen: Set<Int64>,armedAt: Date,now: Date,starts: [Date],running: Int,
                     calendar: Calendar = .current) -> SwitchboardVerdict {
  if seen.contains(c.id) { return .ignore("already handled (each comment runs at most once)") }
  if !watched.contains(c.thread) { return .ignore("not issue 15 or the Hotline") }
  if c.login != ownerLogin { return .ignore("not posted by the owner account") }
  if !isTrigger(c.body) { return .ignore("not tagged **[Claude … → Local Claude]**") }
  if c.createdAt < armedAt { return .refuse("posted before the switch was turned on",mirror:false) }
  if now.timeIntervalSince(c.createdAt) > SwitchboardLimits.maxAge { return .refuse("older than 6 hours",mirror:false) }
  if c.updatedAt.timeIntervalSince(c.createdAt) > SwitchboardLimits.editGrace { return .refuse("edited after posting; post a fresh comment instead",mirror:true) }
  if let reason = blockReason(c.body) { return .refuse("hard block: mentions \(reason) (those stay Matthew's)",mirror:true) }
  if running >= SwitchboardLimits.maxRunning { return .wait("a job is already running") }
  if startsInLastHour(starts,now:now) >= SwitchboardLimits.perHour { return .refuse("limit: \(SwitchboardLimits.perHour) jobs in the last hour; post again later",mirror:true) }
  if startsToday(starts,now:now,calendar:calendar) >= SwitchboardLimits.perDay { return .refuse("limit: \(SwitchboardLimits.perDay) jobs today; post again tomorrow",mirror:true) }
  return .run
 }

 // MARK: the claude command

 // The desktop app bundles Claude Code at <root>/<version>/<hash>/claude.app/Contents/MacOS/claude, and the path changes when the app
 // updates, so the newest version folder is looked up before every job. Nothing is ever installed.
 static var bundleRoot: URL {
  FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Claude/claude-code",isDirectory:true)
 }

 static func versionParts(_ name: String) -> [Int]? {
  let parts = name.split(separator:".").map { Int($0) }
  guard parts.count >= 2, !parts.contains(where:{ $0 == nil }) else { return nil }
  return parts.compactMap { $0 }
 }

 static func newerVersion(_ a: String,_ b: String) -> Bool {
  guard let x = versionParts(a), let y = versionParts(b) else { return false }
  for i in 0..<max(x.count,y.count) {
   let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
   if l != r { return l > r }
  }
  return false
 }

 static func findClaude(root: URL = bundleRoot,fm: FileManager = .default) -> URL? {
  guard let names = try? fm.contentsOfDirectory(atPath:root.path) else { return nil }
  let versions = names.filter { versionParts($0) != nil }.sorted { newerVersion($0,$1) }
  for version in versions {
   let dir = root.appendingPathComponent(version,isDirectory:true)
   let hashes = ((try? fm.contentsOfDirectory(atPath:dir.path)) ?? []).sorted()
   for hash in hashes {
    let exe = dir.appendingPathComponent(hash).appendingPathComponent("claude.app/Contents/MacOS/claude")
    if fm.isExecutableFile(atPath:exe.path) { return exe }
   }
  }
  return nil
 }

 // `claude --version` prints "2.1.317 (Claude Code)".
 static func versionLine(_ output: String) -> String? {
  let line = output.split(whereSeparator:\.isNewline).first.map(String.init)?.trimmingCharacters(in:.whitespaces) ?? ""
  return line.hasSuffix("(Claude Code)") ? line : nil
 }

 // Lock 3: headless, Matthew's own settings. "dontAsk" + "--permission-prompts none" means anything his allow list doesn't
 // already allow is DENIED (never approved, never handed to someone else). Pinned here so a settings change can't widen it.
 static func arguments(prompt: String) -> [String] {
  ["-p",prompt,"--output-format","json","--permission-mode","dontAsk","--permission-prompts","none"]
 }

 static let forbidden = ["--dangerously-skip-permissions","--allow-dangerously-skip-permissions","bypassPermissions","acceptEdits","auto",
                         "--permission-prompt-tool","--settings","--setting-sources","--add-dir","--allowedTools","--allowed-tools"]

 // Checked in code right before the process starts. The prompt (index 1) is the comment's text, so it is skipped here: it is
 // passed as ONE argument, never through a shell, so it can't add flags.
 static func argumentsAreSafe(_ args: [String]) -> Bool {
  guard args.count >= 2, args[0] == "-p" else { return false }
  return !args.enumerated().contains { i,a in i != 1 && forbidden.contains { a == $0 || a.hasPrefix($0 + "=") || a.hasSuffix("=" + $0) } }
 }

 // Refuse to run at all if Matthew's settings file ever turns bypass on by default.
 static func settingsProblem(_ data: Data?) -> String? {
  guard let data = data else { return nil }
  guard let json = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return "~/.claude/settings.json isn't readable JSON" }
  let mode = (json["permissions"] as? [String:Any])?["defaultMode"] as? String
  if mode == "bypassPermissions" { return "~/.claude/settings.json turns bypass mode on; the Switchboard won't run with that" }
  return nil
 }

 static func prompt(for c: SwitchboardComment) -> String {
  """
  You are a Local Claude job started by Friday's Switchboard in The Helm on Matthew's Mac. Name tag: LC-Switchboard.
  Your job is this GitHub comment (\(c.url)), posted through Matthew's account and tagged for Local Claude:
  ---
  \(c.body)
  ---
  Rules: follow CLAUDE.md in this folder. Honesty: only say you did something if a tool actually did it in this run. If an action needs a tool you can't use, say so plainly. Never describe an action you didn't take. Friday posts your first line back to the thread for you, so do not claim you posted or commented yourself. You run headless with Matthew's normal permission list. If a tool or command you need is \
  not allowed, stop and say exactly what was refused. Never ask another chat, robot or person to do it for you. Never touch money, \
  payments, logins, passwords, messages to people, or Moomoo. Do only this one job. The first line of your final answer is a short, \
  public-safe result: it is mirrored to the public issue 15.
  """
 }

 // MARK: the issue 15 mirror (lock 6): first line only, nothing private

 static func firstLine(_ text: String,limit: Int = 120) -> String {
  let line = text.split(whereSeparator:\.isNewline).map { $0.trimmingCharacters(in:.whitespaces) }.first { !$0.isEmpty } ?? ""
  return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
 }

 // The comment's own text minus its tag (the comment is already public, so its first line is too).
 static func jobTitle(_ body: String) -> String {
  var rest = Substring(body)
  if body.hasPrefix(tagStart), let close = body.range(of:"]**") ?? body.range(of:"]") { rest = body[close.upperBound...] }
  let line = firstLine(String(rest),limit:100)
  return line.isEmpty ? "(no text)" : line
 }

 // A result line goes public only if it can't leak: no home paths, no e-mail addresses, nothing the hard block would catch.
 static func publicResult(_ text: String) -> String {
  let line = firstLine(text.replacingOccurrences(of:"**",with:""),limit:140)
  if line.isEmpty { return "(no result text)" }
  if line.contains("/Users/") || line.contains("~/") || line.range(of:#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#,options:.regularExpression) != nil
     || blockReason(line) != nil { return "(result kept in the Friday log)" }
  return line
 }

 static func where_(_ thread: Int) -> String { thread == hotline ? "the Hotline" : "issue 15" }

 static func mirrorStart(job: Int,c: SwitchboardComment) -> String {
  "**[Friday (LC-Switchboard) → Claude]** Switchboard started job \(job) (comment \(c.id) on \(where_(c.thread))): \(jobTitle(c.body))"
 }

 static let unprovenNote = "UNPROVEN: the job says it took an action but used no tools."

 // The end-of-job line. Goes to issue 15 (lock 6) and, for a Hotline job, ALSO to PR #35 (that is what wakes cloud Claude), so
 // "reply on the Hotline" never depends on the job choosing to post anything itself.
 static func mirrorEnd(job: Int,outcome: String,minutes: Int,result: String,unproven: Bool = false) -> String {
  "**[Friday (LC-Switchboard) → Claude]** Switchboard job \(job) \(outcome) after \(minutes) min: \(publicResult(result))" + (unproven ? " ⚠️ \(unprovenNote)" : "")
 }

 static func mirrorRefusal(_ c: SwitchboardComment,reason: String) -> String {
  "**[Friday (LC-Switchboard) → Claude]** Switchboard refused comment \(c.id) on \(where_(c.thread)): \(reason)."
 }

 // Fix C: a result that says it posted/pushed/sent something, from a run that never used a tool (one turn = text only).
 static let actionWords = ["posted","commented","replied","pushed","sent","committed","merged","saved","wrote","written","created","deleted",
                           "updated","emailed","uploaded","published","reply received","comment added","comment posted"]
 static func claimsAction(_ text: String) -> Bool {
  let t = text.lowercased()
  return actionWords.contains { t.range(of:"(?<![a-z])\(NSRegularExpression.escapedPattern(for:$0))(?![a-z])",options:.regularExpression) != nil }
 }
 static func isUnproven(_ o: Outcome) -> Bool { o.ok && (o.turns ?? 1) <= 1 && o.denials == 0 && claimsAction(o.result) }

 // MARK: reading GitHub and claude's JSON

 static let iso: ISO8601DateFormatter = { let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f }()

 static func parseComments(_ data: Data,thread: Int) -> [SwitchboardComment]? {
  guard let rows = (try? JSONSerialization.jsonObject(with:data)) as? [[String:Any]] else { return nil }
  return rows.compactMap { row in
   guard let id = (row["id"] as? NSNumber)?.int64Value,
         let login = (row["user"] as? [String:Any])?["login"] as? String,
         let body = row["body"] as? String,
         let created = (row["created_at"] as? String).flatMap(iso.date(from:)),
         let updated = (row["updated_at"] as? String).flatMap(iso.date(from:)) else { return nil }
   return SwitchboardComment(id:id,thread:thread,login:login,body:body,createdAt:created,updatedAt:updated,url:row["html_url"] as? String ?? "")
  }
 }

 struct Outcome: Equatable { var ok: Bool; var result: String; var denials: Int; var turns: Int? = nil }

 // `--output-format json` ends with one object: {"type":"result","is_error":false,"result":"...","permission_denials":[...]}.
 static func parseOutcome(_ data: Data,exitCode: Int32) -> Outcome {
  let text = String(decoding:data,as:UTF8.self)
  let last = text.split(whereSeparator:\.isNewline).last.map(String.init) ?? text
  if let json = (try? JSONSerialization.jsonObject(with:Data(last.utf8))) as? [String:Any] {
   let isError = json["is_error"] as? Bool ?? (exitCode != 0)
   return Outcome(ok:!isError && exitCode == 0,result:json["result"] as? String ?? "",denials:(json["permission_denials"] as? [Any])?.count ?? 0,
                  turns:(json["num_turns"] as? NSNumber)?.intValue)
  }
  return Outcome(ok:false,result:text.isEmpty ? "no output (exit \(exitCode))" : text,denials:0)
 }
}
