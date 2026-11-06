import Foundation

// Who is working, who is idle, who is away: worked out ONLY from things the app already reads (the room thread, the board, GitHub's public
// workflow runs and the robots' public snapshots). Nothing here is invented. A desk with no evidence says "no data". Pure logic, no UI.

enum CrewState { case working, idle, away, failing, unknown }
enum CrewKind { case chat, cloud, agent, watcher, robot, poster, friday }

struct CrewMember: Identifiable {
 var id: String
 var name: String
 var role: String
 var kind: CrewKind
 var state: CrewState
 var detail: String          // one plain line: what the evidence says
 var since: Date?            // when the state began (last post, last run) when known
 var awayUntil: Date?        // only when a room message said so
 var url: String = ""
}

enum CrewData {
 static let robotWorkflows: [(name: String,workflow: String)] = [
  ("stock-bot","Stock bot"),("stock-momentum","Stock bot (momentum)"),("stock-hot","Stock bot (hot hands)"),
  ("stock-moonshot","Stock bot (moonshot)"),("stock-moonshot-crypto","Stock bot (moonshot crypto)"),
  ("stock-quality","Stock bot - Quality Dip"),("stock-volatility","Stock bot - Volatility"),
 ]

 static let workingWindow: TimeInterval = 30 * 60      // posted in the last 30 minutes: counts as working
 static let tagForRoomAgent = ["Roxy","Grok","Cloud Claude","Browser Claude"]

 // "Local Claude (LC-Helm)" is LC-Helm; "GPT (Roxy)" is Roxy; plain "Claude" is the cloud chat.
 static func agentName(_ author: String) -> String? {
  let raw = author.trimmingCharacters(in:.whitespaces)
  let low = raw.lowercased()
  if low.isEmpty || low == "?" || low.contains("matthew") { return nil }
  if low.hasPrefix("local claude") {
   if let open = raw.firstIndex(of:"("), let close = raw.lastIndex(of:")"), open < close {
    let inner = String(raw[raw.index(after:open)..<close]).trimmingCharacters(in:.whitespaces)
    if !inner.isEmpty { return inner }
   }
   return "Local Claude"
  }
  if low.contains("gpt") || low.contains("roxy") || low.contains("carrie") { return "Roxy" }
  if low.contains("grok") { return "Grok" }
  if low.contains("friday") { return "Friday" }
  if low.contains("chrome") || low.contains("browser") { return "Browser Claude" }
  if low.contains("claude") { return "Cloud Claude" }
  return raw
 }

 static func ago(_ date: Date,now: Date = Date()) -> String {
  let s = max(0,Int(now.timeIntervalSince(date)))
  if s < 90 { return "just now" }
  if s < 3600 { return "\(s / 60) min ago" }
  if s < 86400 { return "\(s / 3600) h ago" }
  return "\(s / 86400) d ago"
 }

 // "H:MM:SS" or "Dd Hh" timer text for the side list.
 static func timer(_ seconds: TimeInterval) -> String {
  let s = max(0,Int(seconds))
  if s >= 86400 { return "\(s / 86400)d \((s % 86400) / 3600)h" }
  return String(format:"%d:%02d:%02d",s / 3600,(s % 3600) / 60,s % 60)
 }

 // A room message that says an agent is away, for example "Grok is away until Nov 11" or "Roxy back Mon Nov 9".
 static func awayUntil(for name: String,in messages: [RoomMessage],now: Date = Date()) -> Date? {
  let key = name == "Roxy" ? "(?:roxy|gpt)" : NSRegularExpression.escapedPattern(for:name.lowercased())
  let months = "(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\\.? (\\d{1,2})"
  guard let regex = try? NSRegularExpression(pattern:"\\b\(key)\\b[^.\\n]{0,70}?\\b(?:away until|back(?: on)?|returns?|out until|limit resets?)\\b[^.\\n]{0,24}?\\b\(months)",options:[.caseInsensitive]) else { return nil }
  let names = ["jan":1,"feb":2,"mar":3,"apr":4,"may":5,"jun":6,"jul":7,"aug":8,"sep":9,"oct":10,"nov":11,"dec":12]
  var calendar = Calendar(identifier:.gregorian)
  calendar.timeZone = TimeZone(identifier:"America/Moncton") ?? .current
  let year = calendar.component(.year,from:now)
  for message in messages.sorted(by:{ ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }).prefix(60) {
   guard let when = message.date, now.timeIntervalSince(when) < 12 * 86400 else { continue }
   let text = message.text as NSString
   guard let match = regex.firstMatch(in:message.text,range:NSRange(location:0,length:text.length)), match.numberOfRanges >= 3 else { continue }
   let month = names[text.substring(with:match.range(at:1)).lowercased()] ?? 0
   let day = Int(text.substring(with:match.range(at:2))) ?? 0
   guard month > 0, day > 0, let date = calendar.date(from:DateComponents(year:year,month:month,day:day,hour:6)) else { continue }
   if date > now { return date }
  }
  return nil
 }

 static func build(messages: [RoomMessage],runs: [AutomationRun]?,snapshots: [String:StockRobot] = [:],fridayLive: Bool = false,now: Date = Date()) -> [CrewMember] {
  var result: [CrewMember] = []
  result.append(CrewMember(id:"Friday",name:"Friday",role:"Voice companion on Matthew's Mac",kind:.friday,state:fridayLive ? .working : .idle,detail:fridayLive ? "live session running" : "asleep until Matthew starts her",since:nil,awayUntil:nil))

  // People and agents: from the room thread.
  var last: [String:RoomMessage] = [:]
  for message in messages {
   guard let name = agentName(message.author), name != "Friday" else { continue }
   if let seen = last[name], (seen.date ?? .distantPast) >= (message.date ?? .distantPast) { continue }
   last[name] = message
  }
  var order: [String] = []
  for name in last.keys.sorted() where name.hasPrefix("LC-") || name == "Local Claude" { order.append(name) }
  for name in ["Cloud Claude","Roxy","Grok","Browser Claude"] where last[name] != nil || name != "Browser Claude" { order.append(name) }
  for name in order {
   let kind: CrewKind = (name.hasPrefix("LC-") || name == "Local Claude") ? .chat : (name == "Cloud Claude" ? .cloud : .agent)
   let role: String
   switch name {
   case "Cloud Claude": role = "Co-CEO · runs the engine, reviews and merges"
   case "Roxy": role = "Second AI · checks the work, drafts"
   case "Grok": role = "Third AI · research"
   case "Browser Claude": role = "Look-only browser helper"
   case "Local Claude": role = "Main chat on Matthew's Mac"
   default: role = "Local Claude chat on Matthew's Mac"
   }
   guard let post = last[name] else {
    result.append(CrewMember(id:name,name:name,role:role,kind:kind,state:.unknown,detail:"no room posts loaded",since:nil,awayUntil:nil))
    continue
   }
   let when = post.date
   let away = awayUntil(for:name,in:messages,now:now)
   var state = CrewState.idle
   var detail = "last post \(when.map { ago($0,now:now) } ?? "unknown")"
   if let when = when, now.timeIntervalSince(when) < workingWindow {
    state = .working
    detail = "posted \(ago(when,now:now)): " + MeetingData.brief(post.text,limit:60)
   }
   if let away = away, state != .working { state = .away; detail = "away, back \(away.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))" }
   result.append(CrewMember(id:name,name:name,role:role,kind:kind,state:state,detail:detail,since:when,awayUntil:away,url:post.url))
  }

  // Scheduled workers: from GitHub's public runs (latest run per workflow).
  func worker(_ id: String,_ name: String,_ role: String,_ kind: CrewKind,_ workflow: String) -> CrewMember {
   guard let run = runs?.first(where:{ $0.name == workflow }) else {
    if let snap = snapshots[id], let updated = snap.updated {
     return CrewMember(id:id,name:name,role:role,kind:kind,state:.idle,detail:"\(snap.paused ? "PAUSED · " : "")snapshot updated \(ago(updated,now:now)) (no workflow run in the loaded list)",since:updated,awayUntil:nil)
    }
    return CrewMember(id:id,name:name,role:role,kind:kind,state:.unknown,detail:runs == nil ? "runs not loaded" : "no recent run found",since:nil,awayUntil:nil)
   }
   if run.isRunning { return CrewMember(id:id,name:name,role:role,kind:kind,state:.working,detail:"running now",since:run.created,awayUntil:nil,url:run.url) }
   if run.isFailing { return CrewMember(id:id,name:name,role:role,kind:kind,state:.failing,detail:"last run FAILED \(run.created.map { ago($0,now:now) } ?? "")",since:run.created,awayUntil:nil,url:run.url) }
   let word = run.conclusion == "success" ? "last run ok" : "last run \(run.conclusion.isEmpty ? "ended" : run.conclusion)"
   return CrewMember(id:id,name:name,role:role,kind:kind,state:.idle,detail:"\(word) \(run.created.map { ago($0,now:now) } ?? "")",since:run.created,awayUntil:nil,url:run.url)
  }
  result.append(worker("watcher","Room watcher","Pings the room when something needs a look",.watcher,"Meeting Room ping"))
  result.append(worker("changes","Change watcher","Taps Matthew when something newsworthy happens",.watcher,"Change watcher"))
  for robot in robotWorkflows { result.append(worker(robot.name,robot.name,"Practice robot · paper money only",.robot,robot.workflow)) }
  result.append(worker("facebook","Facebook poster","Daily ECS post",.poster,"ECS daily post"))
  result.append(worker("tiktok","TikTok poster","Daily TikTok packs",.poster,"Daily TikTok packs (product + agent)"))
  result.append(worker("refresh","Refresh","Refreshes the product list every 3 days",.poster,"Refresh trending products"))
  return result
 }

 // The next scheduled product refresh: 09:00 UTC on days 1, 4, 7, ... of the month (refresh-products.yml). GitHub can run it late.
 static func nextRefresh(after now: Date = Date()) -> Date? {
  var utc = Calendar(identifier:.gregorian)
  utc.timeZone = TimeZone(identifier:"UTC") ?? .current
  for offset in 0...40 {
   guard let day = utc.date(byAdding:.day,value:offset,to:now) else { continue }
   let parts = utc.dateComponents([.year,.month,.day],from:day)
   guard let d = parts.day, (d - 1) % 3 == 0, let at = utc.date(from:DateComponents(year:parts.year,month:parts.month,day:d,hour:9)), at > now else { continue }
   return at
  }
  return nil
 }
}
