import Foundation

// Signs of life for each crew chat, read from GitHub: owner-authored comments on the Hotline (PR #35) and issue 15, plus commits in the
// last 30 minutes on each chat's branch. Pure decision logic (CrewSignals.decide) is separate from the fetching so it can be checked offline.

struct CrewSignal { var chat: String; var date: Date; var what: String }   // chat = canonical key (CrewSignals.canon)

enum CrewSignals {
 // Every chat in meeting-room/notes/crew-roster.md that is a chat (display name, canonical key, role).
 static let roster: [(name: String,key: String,role: String)] = [
  ("LC-Manager","lc-manager","Local Claude chat on Matthew's Mac"),
  ("LC-TikTok","lc-tiktok","Local Claude chat on Matthew's Mac"),
  ("LC-Helm: build revamp (B v2)","lc-helm-build","Local Claude chat on Matthew's Mac"),
  ("LC_Helm","lc-helm","Local Claude chat on Matthew's Mac"),
  ("LC-Makeover","lc-makeover","Local Claude chat on Matthew's Mac"),
  ("LC-Trends","lc-trends","Local Claude chat on Matthew's Mac"),
  ("LC-Work","lc-work","Local Claude chat on Matthew's Mac"),
  ("LC-CrewState","lc-crewstate","Local Claude chat on Matthew's Mac"),
 ]
 // Branch -> owner key (BOARD.md / crew-roster.md).
 static let branchOwners: [(branch: String,key: String)] = [
  ("friday-phase1-chat","lc-tiktok"),("friday-phase1-crew","lc-helm-build"),
  ("friday-phase1-crewstate","lc-crewstate"),("tiktok-samples","lc-trends"),
 ]
 static let window: TimeInterval = 30 * 60

 // "Local Claude (LC-Helm: build revamp (B v2))" / "LC_Helm" / "LC-Manager" -> one key per chat.
 static func canon(_ name: String) -> String {
  var low = name.lowercased().replacingOccurrences(of:"_",with:"-").trimmingCharacters(in:.whitespaces)
  if low.hasPrefix("lc-helm") { return low.contains("build") ? "lc-helm-build" : "lc-helm" }
  if let cut = low.firstIndex(where:{ $0 == ":" || $0 == " " || $0 == "(" }) { low = String(low[..<cut]) }
  return low
 }

 // working / idle / unknown from the signals alone. `failed` = a GitHub read failed (so absence of a signal proves nothing).
 static func decide(key: String,signals: [CrewSignal],failed: Bool,now: Date) -> (state: CrewState,detail: String,since: Date?) {
  let recent = signals.filter { $0.chat == key && now.timeIntervalSince($0.date) < window && $0.date <= now.addingTimeInterval(120) }
  if let newest = recent.max(by:{ $0.date < $1.date }) {
   return (.working,"working · \(newest.what) (\(CrewData.ago(newest.date,now:now)))",newest.date)
  }
  if failed { return (.unknown,"unknown (couldn't reach GitHub)",nil) }
  let older = signals.filter { $0.chat == key }.max(by:{ $0.date < $1.date })
  return (.idle,older.map { "idle · no sign in 30 min (last: \(CrewData.ago($0.date,now:now)))" } ?? "idle · no sign in 30 min",older?.date)
 }

 // MARK: shared snapshot (read by CrewData.build, filled by refresh)
 private static let lock = NSLock()
 private static var snapshot: (signals: [CrewSignal],failed: Bool,loaded: Bool) = ([],false,false)
 private static var lastStart: Date = .distantPast
 private static var inFlight = false

 private static func store(_ r: (signals: [CrewSignal],failed: Bool,loaded: Bool)) { lock.lock(); snapshot = r; inFlight = false; lock.unlock() }
 static func current() -> (signals: [CrewSignal],failed: Bool,loaded: Bool) { lock.lock(); defer { lock.unlock() }; return snapshot }

 // Called from build(); one round (5 reads) every 6 min without a key (GitHub allows 60/h per network), every 3 min with one.
 static var token: String? = nil   // optional: a caller that already holds the GitHub key can set it (5000 reads/h instead of 60)
 static func refreshIfStale() {
  lock.lock()
  if inFlight || Date().timeIntervalSince(lastStart) < ((token ?? "").isEmpty ? 360 : 180) { lock.unlock(); return }
  inFlight = true; lastStart = Date(); lock.unlock()
  Task.detached {
   let result = await fetch(token:token)
   store(result)
  }
 }

 static func fetch(token: String?,now: Date = Date()) async -> (signals: [CrewSignal],failed: Bool,loaded: Bool) {
  let iso = ISO8601DateFormatter()
  let since = iso.string(from:now.addingTimeInterval(-window))
  var out: [CrewSignal] = []
  var failed = false
  func get(_ path: String,okMissing: Bool = false) async -> [[String:Any]]? {
   guard let req = MeetingData.api(path,token:token), let (data,resp) = try? await URLSession.shared.data(for:req),
         let code = (resp as? HTTPURLResponse)?.statusCode else { failed = true; return nil }
   if code == 404 && okMissing { return [] }
   guard code == 200, let rows = (try? JSONSerialization.jsonObject(with:data)) as? [[String:Any]] else { failed = true; return nil }
   return rows
  }
  // Hotline PR #35 (and issue 15) comments in the window, owner-authored, same tag parse as the room.
  for number in [35] {   // issue 15 comes from the room thread the app already loads
   for row in await get("/issues/\(number)/comments?per_page=100&since=\(since)") ?? [] {
    guard let body = row["body"] as? String, let user = row["user"] as? [String:Any], (user["login"] as? String) == MeetingData.trustedLogin,
          let when = iso.date(from:(row["created_at"] as? String) ?? "") else { continue }
    let parsed = MeetingData.parseMessage(body:body)
    guard let name = CrewData.agentName(parsed.author), name != "Friday" else { continue }
    out.append(CrewSignal(chat:canon(name),date:when,what:MeetingData.brief(parsed.text,limit:60)))
   }
  }
  // Commits per branch, minus anything already on master (a branch cut from master carries master's commits).
  let master = Set((await get("/commits?sha=master&since=\(since)&per_page=100") ?? []).compactMap { $0["sha"] as? String })
  for entry in branchOwners {
   for row in await get("/commits?sha=\(entry.branch)&since=\(since)&per_page=10",okMissing:true) ?? [] {
    guard let sha = row["sha"] as? String, !master.contains(sha), let commit = row["commit"] as? [String:Any],
          let who = commit["committer"] as? [String:Any], let when = iso.date(from:(who["date"] as? String) ?? "") else { continue }
    let subject = ((commit["message"] as? String) ?? "").components(separatedBy:"\n").first ?? ""
    out.append(CrewSignal(chat:entry.key,date:when,what:"commit: " + MeetingData.brief(subject,limit:60)))
   }
  }
  return (out,failed,true)
 }
}
