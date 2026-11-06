import Foundation

// READ BUDGET (keyless GitHub limit = 60 reads/hour per network, shared by the whole app): crew chat ~48/h (4 per 5 min), room + board +
// runs: see MeetingRoom/VentureData; THIS file: 1 read per 6 min = 10/h without a key. Net: keep this at 1 read per round, never more.
// The key (if the app holds one for the Meeting Room) is NOT reachable from here; a caller that has it sets CrewSignals.token. No new key.

// Signs of life for each crew chat, read from GitHub: owner-authored comments on the Hotline (PR #35) and issue 15, plus commits in the
// last 30 minutes on each chat's branch. Pure decision logic (CrewSignals.decide) is separate from the fetching so it can be checked offline.

struct CrewSignal { var chat: String; var date: Date; var what: String; var to: String = "" }   // chat = canonical key (CrewSignals.canon); to = the tag's "→ name" (Hotline posts), used by the pixel station

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
  ("LC-Pixels","lc-pixels","Local Claude chat on Matthew's Mac"),
 ]
 // Branch -> owner key (BOARD.md / crew-roster.md).
 static let branchOwners: [(branch: String,key: String)] = [
  ("friday-phase1-chat","lc-tiktok"),("friday-phase1-crew","lc-helm-build"),
  ("friday-phase1-crewstate","lc-crewstate"),("tiktok-samples","lc-trends"),("pixel-agents","lc-pixels"),
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
  if failed { return (.unknown,"unknown (\(GitHubRead.limitMessage() ?? "couldn't reach GitHub"))",nil) }
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

 // Called from build(); ONE read per round: every 6 min without a key (10/h), every 3 min with one.
 static var token: String? = nil   // optional: a caller that already holds the GitHub key can set it (5000 reads/h instead of 60)
 static func refreshIfStale() {
  lock.lock()
  if inFlight || (GitHubRead.limitedUntil != nil && token == nil && !FileManager.default.isExecutableFile(atPath:GitHubRead.ghPath)) || Date().timeIntervalSince(lastStart) < ((token ?? "").isEmpty ? 360 : 180) { lock.unlock(); return }
  inFlight = true; lastStart = Date(); lock.unlock()
  Task.detached {
   let result = await fetch(token:token)
   store(result)
  }
 }

 // Parse GitHub's repo events feed (ONE read): owner-authored IssueCommentEvents on #35 (Hotline) in the window, and PushEvents to a
 // branch we own. Pure, so it can be checked offline. The feed can lag (often under a minute, sometimes longer): fine for a 30-min window.
 static func parseEvents(_ data: Data,now: Date) -> [CrewSignal]? {
  guard let rows = (try? JSONSerialization.jsonObject(with:data)) as? [[String:Any]] else { return nil }
  let iso = ISO8601DateFormatter()
  var out: [CrewSignal] = []
  for row in rows {
   guard let type = row["type"] as? String, let when = iso.date(from:(row["created_at"] as? String) ?? ""),
         now.timeIntervalSince(when) < window, let payload = row["payload"] as? [String:Any] else { continue }
   if type == "IssueCommentEvent" {
    guard let issue = payload["issue"] as? [String:Any], (issue["number"] as? Int) == 35,
          let comment = payload["comment"] as? [String:Any], let body = comment["body"] as? String,
          let user = comment["user"] as? [String:Any], (user["login"] as? String) == MeetingData.trustedLogin else { continue }
    let parsed = MeetingData.parseMessage(body:body)
    guard let name = CrewData.agentName(parsed.author), name != "Friday" else { continue }
    out.append(CrewSignal(chat:canon(name),date:when,what:MeetingData.brief(parsed.text,limit:60),to:parsed.to))
   } else if type == "PushEvent" {
    guard let ref = payload["ref"] as? String, ref.hasPrefix("refs/heads/"),
          let owner = branchOwners.first(where:{ $0.branch == String(ref.dropFirst(11)) }) else { continue }
    let commits = (payload["commits"] as? [[String:Any]]) ?? []
    let subject = ((commits.last?["message"] as? String) ?? "").components(separatedBy:"\n").first ?? ""
    out.append(CrewSignal(chat:owner.key,date:when,what:"commit: " + MeetingData.brief(subject.isEmpty ? "push" : subject,limit:60)))
   }
  }
  return out
 }

 static func fetch(token: String?,now: Date = Date()) async -> (signals: [CrewSignal],failed: Bool,loaded: Bool) {
  guard let r = await GitHubRead.get("/events?per_page=100",token:token), r.status == 200, let signals = parseEvents(r.body,now:now) else { return ([],true,true) }
  return (signals,false,true)
 }
}
