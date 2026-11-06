import Foundation
import Darwin

// The crew station's link to the ACTUAL chats running on this Mac (LC-Pixels, 2026-11-06, Matthew: "they need to be connected to actual
// working bots"). Claude Code keeps one small registry file per running session in ~/.claude/sessions/<pid>.json with its name and
// whether it is "busy" (mid-task) or "idle", and when that last changed. We read ONLY those .json files, and only four fields
// (pid, name, status, statusUpdatedAt); the .key files next to them are secrets and are never opened. A file whose process has ended is ignored.
//
// What it changes on the station: an open chat that is busy = typing at its desk with a real RUN timer; open and idle = asleep at its desk;
// a Local Claude chat that is NOT open (and showed no work in the last 30 min) gets no desk, and the list names it as closed.
// If the folder can't be read, nothing changes (the station falls back to room posts and commits).

struct LiveSession: Equatable {
 var pid: Int32
 var name: String
 var busy: Bool
 var since: Date        // when it became busy / idle
}

enum LiveSessions {
 static var folder: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions",isDirectory:true) }

 static func parse(_ data: Data) -> LiveSession? {
  guard let o = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any],
        let pid = (o["pid"] as? NSNumber)?.int32Value,
        let raw = o["name"] as? String else { return nil }
  let name = raw.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !name.isEmpty else { return nil }
  let ms = (o["statusUpdatedAt"] as? NSNumber)?.doubleValue ?? (o["updatedAt"] as? NSNumber)?.doubleValue ?? 0
  return LiveSession(pid:pid,name:name,busy:(o["status"] as? String) == "busy",since:Date(timeIntervalSince1970:ms / 1000))
 }

 static func alive(_ pid: Int32) -> Bool { pid > 0 && (kill(pid,0) == 0 || errno == EPERM) }

 // nil when the registry can't be read at all (then the station keeps its old behaviour).
 static func read() -> [LiveSession]? {
  guard let files = try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) else { return nil }
  return files.filter { $0.pathExtension == "json" }
   .compactMap { (try? Data(contentsOf:$0)).flatMap(parse) }
   .filter { alive($0.pid) }
   .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
 }

 // "LC-CrewState: crew strip shows who's really working" -> "LC-CrewState", "LC_Helm" -> "LC-Helm".
 static func shortName(_ name: String) -> String {
  var n = name
  if let cut = n.firstIndex(of:":") { n = String(n[..<cut]) }
  if n.hasPrefix("LC_") { n = "LC-" + n.dropFirst(3) }
  return n.trimmingCharacters(in:.whitespaces)
 }

 static func timer(_ since: Date,now: Date) -> String {
  let s = max(0,Int(now.timeIntervalSince(since)))
  return s < 3600 ? String(format:"%d:%02d",s / 60,s % 60) : String(format:"%d:%02d:%02d",s / 3600,(s / 60) % 60,s % 60)
 }

 static let busyPrefix = "busy right now"

 // Merges the live sessions into the crew. Returns the crew to show and the names of Local Claude chats that are closed.
 static func apply(_ sessions: [LiveSession]?,to crew: [CrewMember],now: Date = Date()) -> (crew: [CrewMember],closed: [String]) {
  guard let sessions = sessions else { return (crew,[]) }
  var out = crew
  var open = Set<String>()
  for s in sessions {
   let key = CrewSignals.canon(s.name)
   let idleFor = CrewData.ago(s.since,now:now)
   if key == "friday" {
    if let i = out.firstIndex(where:{ $0.kind == .friday }) {
     open.insert(out[i].id)
     if s.busy { out[i].state = .working; out[i].detail = "\(busyPrefix): her chat on this Mac is mid-task"; out[i].since = s.since }
     else if out[i].state != .working { out[i].detail = "her chat is open on this Mac, idle since \(idleFor)" }
    }
    continue
   }
   // A cloud-tagged member whose newest post is "[Claude (NB2)]" IS the open NB2 session: one desk, not two.
   if let i = out.firstIndex(where:{ $0.kind == .cloud && $0.alias.map { CrewSignals.canon($0) == key } == true }) {
    open.insert(out[i].id)
    out[i].name = shortName(s.name)
    if s.busy { out[i].state = .working; out[i].detail = "\(busyPrefix): its chat on this Mac is mid-task"; out[i].since = s.since }
    else if out[i].state != .working { out[i].state = .idle; out[i].detail = "chat open on this Mac, idle since \(idleFor)"; out[i].since = s.since }
    continue
   }
   if let i = out.firstIndex(where:{ $0.kind == .chat && CrewSignals.canon($0.name) == key }) {
    open.insert(out[i].id)
    if s.busy { out[i].state = .working; out[i].detail = "\(busyPrefix): its chat on this Mac is mid-task"; out[i].since = s.since }
    else if out[i].state != .working { out[i].state = .idle; out[i].detail = "chat open on this Mac, idle since \(idleFor)"; out[i].since = s.since }
   } else {
    let n = shortName(s.name)
    out.append(CrewMember(id:"live:" + key,name:n,role:"Local Claude chat",kind:.chat,state:s.busy ? .working : .idle,
                          detail:s.busy ? "\(busyPrefix): its chat on this Mac is mid-task" : "chat open on this Mac, idle since \(idleFor)",
                          since:s.since,awayUntil:nil))
    open.insert("live:" + key)
   }
  }
  // A Local Claude chat with no open session is closed, unless it showed real work in the last 30 minutes (then it keeps its desk).
  var closed: [String] = []
  out.removeAll { m in
   guard m.kind == .chat, !open.contains(m.id), m.state != .working, m.state != .failing else { return false }
   closed.append(PixelCrew.label(m)); return true
  }
  return (out,closed)
 }
}

// Re-reads the registry every few seconds while the station is on screen.
@MainActor final class LiveSessionsModel: ObservableObject {
 static let shared = LiveSessionsModel()
 @Published private(set) var sessions: [LiveSession]? = LiveSessions.read()
 private var loop: Task<Void,Never>?

 func start() {
  guard loop == nil else { return }
  loop = Task { [weak self] in
   while !Task.isCancelled {
    try? await Task.sleep(nanoseconds:4_000_000_000)
    let fresh = await Task.detached { LiveSessions.read() }.value
    if fresh != self?.sessions { self?.sessions = fresh }
   }
  }
 }
}
