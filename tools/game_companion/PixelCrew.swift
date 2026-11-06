import SwiftUI

// LC-Pixels (2026-11-06): the "alive" layer of the Crew station. Every motion on the station comes from a real signal the app already
// loaded: a room or Hotline post, a branch commit, a message with a "→ name" tag, a workflow run. Nothing here reads GitHub and nothing
// here is invented. Pure rules first (who visited whom, Friday's own posts, short labels, links), then the click model.

struct PixelVisit: Equatable {
 var from: String      // crew member id of the sender
 var to: String        // crew member id of the one they messaged
 var date: Date
 var what: String
}

enum PixelCrew {
 static let visitWindow: TimeInterval = 15 * 60      // a message in the last 15 minutes: the sender walks over to whoever it was for
 static let roomURL = "https://github.com/matthewferreira818/hotstuff/issues/15"
 static let hotlineURL = "https://github.com/matthewferreira818/hotstuff/pull/35"
 static let runsURL = "https://github.com/matthewferreira818/hotstuff/actions"

 // A tag name ("Claude", "GPT", "Local Claude (LC-Helm)", "LC-Manager", "Everyone") -> the id of a member on the station, or nil
 // (Matthew isn't on the station, and a name nobody owns walks nowhere). "Everyone" goes to Friday at the centre.
 static func memberID(_ tag: String,crew: [CrewMember]) -> String? {
  let first = tag.components(separatedBy:CharacterSet(charactersIn:",&+/")).first?.trimmingCharacters(in:.whitespaces) ?? ""
  let low = first.lowercased()
  if low.isEmpty { return nil }
  if ["everyone","all","crew","team","room","the crew"].contains(low) || low.hasPrefix("everyone") {
   return crew.contains { $0.id == "Friday" } ? "Friday" : nil
  }
  guard let name = CrewData.agentName(first) else { return nil }
  if let hit = crew.first(where:{ $0.id == name }) { return hit.id }
  return memberID(key:CrewSignals.canon(name),crew:crew)
 }

 // A canonical key from CrewSignals ("lc-helm-build", "cloud", "roxy") -> member id.
 static func memberID(key: String,crew: [CrewMember]) -> String? {
  crew.first(where:{ CrewSignals.canon($0.name) == key || CrewSignals.canon($0.id) == key })?.id
 }

 // Who walked to whom: the newest message per sender in the last 15 minutes, from the room/Hotline messages and the Hotline signals.
 static func visits(messages: [RoomMessage],signals: [CrewSignal],crew: [CrewMember],now: Date = Date()) -> [PixelVisit] {
  var newest: [String:PixelVisit] = [:]
  func add(_ from: String?,_ toTag: String,_ date: Date?,_ what: String) {
   guard let from = from, let date = date, now.timeIntervalSince(date) < visitWindow, date <= now.addingTimeInterval(120),
         from != "Friday", let to = memberID(toTag,crew:crew), from != to else { return }
   if let seen = newest[from], seen.date >= date { return }
   newest[from] = PixelVisit(from:from,to:to,date:date,what:what)
  }
  for m in messages where !m.to.isEmpty { add(memberID(m.author,crew:crew),m.to,m.date,MeetingData.brief(m.text,limit:60)) }
  for s in signals where !s.to.isEmpty { add(memberID(key:s.chat,crew:crew),s.to,s.date,s.what) }
  return newest.values.sorted { $0.date < $1.date }
 }

 // Friday also runs as her own Local Claude chat: a post of hers in the last 30 minutes means she's working, even with voice off.
 static func withFriday(_ crew: [CrewMember],messages: [RoomMessage],now: Date = Date()) -> [CrewMember] {
  guard let i = crew.firstIndex(where:{ $0.id == "Friday" }), crew[i].state != .working else { return crew }
  let posts = messages.filter { CrewData.agentName($0.author) == "Friday" }
  guard let post = posts.max(by:{ ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }), let when = post.date,
        now.timeIntervalSince(when) < CrewData.workingWindow, when <= now.addingTimeInterval(120) else { return crew }
  var out = crew
  out[i].state = .working
  out[i].detail = "posted \(CrewData.ago(when,now:now)): " + MeetingData.brief(post.text,limit:60)
  out[i].since = when
  out[i].url = post.url
  return out
 }

 // Room messages loaded by the Meeting Room plus the crew chat (room + Hotline), without doubles.
 static func merged(_ a: [RoomMessage],_ b: [RoomMessage]) -> [RoomMessage] {
  var seen = Set<String>()
  return (a + b).filter { seen.insert("\($0.source)#\($0.id)").inserted }
 }

 // The name under a desk: "LC-Helm: build revamp (B v2)" -> "LC-Helm build", "Practice robot stock-momentum" stays short.
 static func label(_ m: CrewMember) -> String {
  var name = m.name
  if m.kind == .chat {
   if let cut = name.firstIndex(of:":") { name = String(name[..<cut]) }
   if CrewSignals.canon(m.name) == "lc-helm-build" { name = "LC-Helm build" }
  }
  if m.kind == .robot { name = name.replacingOccurrences(of:"stock-",with:"") }
  return name.count > 14 ? String(name.prefix(13)) + "…" : name
 }

 // Where a click goes: the evidence itself when we have its link, otherwise the place the evidence lives.
 static func link(_ m: CrewMember) -> (title: String,url: String) {
  if !m.url.isEmpty {
   if m.url.contains("/actions/") { return ("Open the run on GitHub",m.url) }
   if m.url.contains("/pull/35") { return ("Open it on the Hotline",m.url) }
   return ("Open the message",m.url)
  }
  switch m.kind {
  case .robot,.poster,.watcher: return ("Open the robot runs on GitHub",runsURL)
  case .chat: return ("Open the Hotline",hotlineURL)
  default: return ("Open the room",roomURL)
  }
 }

 // One plain line for the click card.
 static func line(_ m: CrewMember,visit: PixelVisit?,crew: [CrewMember],now: Date = Date()) -> String {
  var text: String
  switch m.state {
  case .working: text = m.detail.isEmpty ? "Working right now." : m.detail
  case .idle: text = "Resting. " + (m.detail.isEmpty ? "No sign of work in the last 30 minutes." : m.detail)
  case .away: text = m.detail.isEmpty ? "Away." : m.detail.prefix(1).uppercased() + m.detail.dropFirst()
  case .failing: text = m.detail.isEmpty ? "The last run failed." : m.detail
  case .unknown: text = "No data right now" + (m.detail.isEmpty ? "." : ": " + m.detail)
  }
  if let v = visit, let to = crew.first(where:{ $0.id == v.to }) {
   text = "Messaged \(label(to)) \(CrewData.ago(v.date,now:now)): \(v.what)"
  }
  return text
 }

 // One visit loop of 20 seconds: 3 s walking over, 5 s talking at their desk, 3 s walking back, 9 s back at the own desk.
 // progress 0 = own desk, 1 = the other desk.
 static func walk(_ t: Double) -> (progress: Double,talking: Bool,walking: Bool) {
  let s = t.truncatingRemainder(dividingBy:20)
  if s < 3 { return (s / 3,false,true) }
  if s < 8 { return (1,true,false) }
  if s < 11 { return (1 - (s - 8) / 3,false,true) }
  return (0,false,false)
 }
}

// Which character is picked on the station (the app's command-line build can't use @State, so it lives here).
@MainActor final class PixelCrewModel: ObservableObject {
 static let shared = PixelCrewModel()
 @Published var selected: String?
}
