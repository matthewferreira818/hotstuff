import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The Meeting Room board: meeting-room/BOARD.md in the public repo, shared by Claude, GPT, Friday and Matthew.
// Read-only here. The app only reads and shows it; nothing in the app edits the file. Format: see meeting-room/README.md.
//   ## Section heading
//   - [Owner] One or two sentences. Status: building

struct BoardItem: Identifiable {
 var id: String
 var owner: String      // the text inside [ ], for example "Claude" or "Claude → Matthew"; empty if none
 var text: String
 var status: String     // the words after "Status:", lowercased; empty if none
 var isDone: Bool { status.hasPrefix("done") }
}

struct BoardSection: Identifiable {
 var id: String { "\(position)-\(title)" }
 var title: String
 var items: [BoardItem]
 var position = 0       // its place in the file, so two sections with the same heading still get different ids
}

struct Board {
 var updated = ""
 var sections: [BoardSection] = []
 var raw = ""
 // Things on the table that aren't marked done.
 var openCount: Int { (sections.first { $0.title.lowercased() == "on the table" }?.items ?? []).filter { !$0.isDone }.count }
}

// One message in the room's thread (GitHub issue 15). Claude, GPT and Matthew all post through the same GitHub account, so the
// tag at the start of a message says who it is from: **[Claude → GPT]** words.
struct RoomMessage: Identifiable {
 var id: Int
 var author: String     // Claude, GPT, Matthew, or "?" when untagged
 var to: String         // who it is for, or empty
 var text: String
 var date: Date?
 var url: String
}

enum RoomPost {
 case ok
 case failed(String)
}

// What is waiting on Matthew right now: the questions put to him, the board items he owns, and recent messages for him that he
// hasn't answered. The Meeting Room opens on this so he doesn't have to scroll the whole board to find his own part.
struct MatthewNeeds {
 var questions: [BoardItem] = []
 var tasks: [BoardItem] = []
 var messages: [RoomMessage] = []
 var count: Int { questions.count + tasks.count + messages.count }
}

// A board meeting: a message that opens with "BOARD MEETING" (or "GROUP MEETING"), and everything posted after it. The crew can answer
// each other in the thread; this shows who has posted since, which is not the same as having answered the call.
struct BoardMeeting {
 var call: RoomMessage
 var replies: [RoomMessage]
 func called(_ name: String) -> Bool { MeetingData.same(call.author,name) }
 // True when this person posted anything in the thread after the call.
 func posted(_ name: String) -> Bool { replies.contains { MeetingData.same($0.author,name) } }
}

// One of the crew (Claude, GPT, Friday) on their own tab: their board items sorted into categories, and the messages they
// wrote or were sent. Empty categories are left out.
struct CrewGroup: Identifiable {
 var title: String
 var status: String     // a status word, so the page can colour the category like the status pills
 var items: [BoardItem]
 var id: String { title }
}

struct CrewView {
 var name: String
 var groups: [CrewGroup] = []
 var messages: [RoomMessage] = []
 // Everything not done: in progress, up next, waiting, blocked and questions put to Matthew.
 var open: Int { groups.filter { $0.status != "done" }.reduce(0) { $0 + $1.items.count } }
 // When this one last wrote in the room (within the part of the thread that was loaded).
 var lastPost: Date? { messages.filter { MeetingData.same($0.author,name) }.compactMap { $0.date }.max() }
}

enum MeetingData {
 static let issue = 15
 static let owner = "matthewferreira818"
 static let repo = "hotstuff"
 // Only comments from the repo owner's own account are shown. The thread is locked to people with write access, but anything
 // else that ever appeared there would not be part of the room, so it is ignored.
 static let trustedLogin = "matthewferreira818"
 static let threadPage = "https://github.com/matthewferreira818/hotstuff/issues/15"
 static let url = "https://api.github.com/repos/matthewferreira818/hotstuff/contents/meeting-room/BOARD.md?ref=master"
 static let page = "https://github.com/matthewferreira818/hotstuff/blob/master/meeting-room/BOARD.md"

 static func parse(_ text: String) -> Board {
  var board = Board()
  board.raw = text
  var sections: [BoardSection] = []
  var current: BoardSection?
  var lastItemText: String?
  func closeItem() {
   guard var section = current, let body = lastItemText else { return }
   section.items.append(makeItem(body,id:"\(section.position)-\(section.title)-\(section.items.count)"))
   current = section
   lastItemText = nil
  }
  for line in text.components(separatedBy:"\n") {
   let trimmed = line.trimmingCharacters(in:.whitespaces)
   if trimmed.hasPrefix("_Last updated:") {
    board.updated = trimmed.trimmingCharacters(in:CharacterSet(charactersIn:"_ ")).replacingOccurrences(of:"Last updated:",with:"").trimmingCharacters(in:.whitespaces)
   } else if trimmed.hasPrefix("## ") {
    closeItem()
    if let section = current { sections.append(section) }
    current = BoardSection(title:String(trimmed.dropFirst(3)).trimmingCharacters(in:.whitespaces),items:[],position:sections.count)
   } else if trimmed.hasPrefix("- "), current != nil {
    closeItem()
    lastItemText = String(trimmed.dropFirst(2))
   } else if !trimmed.isEmpty, lastItemText != nil, line.hasPrefix(" ") {
    lastItemText = (lastItemText ?? "") + " " + trimmed   // an indented line continues the item above
   }
  }
  closeItem()
  if let section = current { sections.append(section) }
  board.sections = sections
  return board
 }

 // "[Claude → Matthew] Some words. Status: waiting" becomes owner, text and status.
 static func makeItem(_ body: String,id: String) -> BoardItem {
  var rest = body.trimmingCharacters(in:.whitespaces)
  var owner = ""
  if rest.hasPrefix("["), let close = rest.firstIndex(of:"]") {
   owner = String(rest[rest.index(after:rest.startIndex)..<close]).trimmingCharacters(in:.whitespaces)
   rest = String(rest[rest.index(after:close)...]).trimmingCharacters(in:.whitespaces)
  }
  var status = ""
  if let range = rest.range(of:"Status:",options:.backwards) {
   status = String(rest[range.upperBound...]).trimmingCharacters(in:CharacterSet(charactersIn:". ")).lowercased()
   rest = String(rest[..<range.lowerBound]).trimmingCharacters(in:.whitespaces)
  }
  return BoardItem(id:id,owner:owner,text:rest,status:status)
 }

 // The tag at the start: **[Claude → GPT]** words, or **[Matthew]** words. Anything after a "---" line (the Claude footer) is dropped.
 static func parseMessage(body: String) -> (author: String,to: String,text: String) {
  var text = body.replacingOccurrences(of:"\r\n",with:"\n")
  if let footer = text.range(of:"\n---\n") { text = String(text[..<footer.lowerBound]) }
  text = text.trimmingCharacters(in:.whitespacesAndNewlines)
  var author = "?"
  var to = ""
  if text.hasPrefix("**["), let close = text.range(of:"]**") {
   let tag = String(text[text.index(text.startIndex,offsetBy:3)..<close.lowerBound])
   let parts = tag.components(separatedBy:"→").map { $0.trimmingCharacters(in:.whitespaces) }
   author = parts.first.flatMap { $0.isEmpty ? nil : $0 } ?? "?"
   if parts.count > 1 { to = parts[1] }
   text = String(text[close.upperBound...]).trimmingCharacters(in:.whitespacesAndNewlines)
  }
  return (author,to,text)
 }

 static func parseMessages(_ data: Data) -> [RoomMessage]? {
  guard let rows = (try? JSONSerialization.jsonObject(with:data)) as? [[String:Any]] else { return nil }
  let iso = ISO8601DateFormatter()
  return rows.compactMap { row in
   guard let id = row["id"] as? Int, let body = row["body"] as? String,
         let user = row["user"] as? [String:Any], (user["login"] as? String) == trustedLogin else { return nil }
   let parsed = parseMessage(body:body)
   return RoomMessage(id:id,author:parsed.author,to:parsed.to,text:parsed.text,date:iso.date(from:(row["created_at"] as? String) ?? ""),url:(row["html_url"] as? String) ?? "")
  }
 }

 // A list line: the text as it is when short, otherwise the end of the last sentence that fits (if that leaves a useful amount),
 // otherwise cut at a word. A cut line ends with "…", which is how the page knows there is more to open.
 static let briefLimit = 140

 static func oneLine(_ text: String) -> String {
  text.replacingOccurrences(of:"\n",with:" ").trimmingCharacters(in:.whitespacesAndNewlines)
 }

 // True when brief() would cut the text, which is when the page offers to open the rest.
 static func isCut(_ text: String,limit: Int? = nil) -> Bool { oneLine(text).count > (limit ?? briefLimit) }

 // The names shown in the Meeting Room. The tags stay Claude, GPT, Friday and Matthew (the board and the thread are public and the
 // tags are how the app files things), but Matthew picks what each is called on screen. Roxy is GPT's name since 2026-10-24.
 static let displayNames: [String:String] = ["GPT":"Roxy"]
 static func display(_ name: String) -> String { displayNames[name] ?? name }

 // A tag can carry a nickname, as in "GPT (Roxy)" or "Carrie (GPT)". This maps any such tag to Claude, GPT, Friday or Matthew, or nil
 // for anyone else ("Chrome Claude" is a different helper, so it is not Claude).
 static func canonical(_ raw: String) -> String? {
  let text = raw.lowercased()
  if text.contains("matthew") { return "Matthew" }
  if text.contains("gpt") || text.contains("roxy") || text.contains("carrie") { return "GPT" }
  if text.contains("friday") { return "Friday" }
  if text.contains("claude") && !text.contains("chrome") { return "Claude" }
  return nil
 }

 // True when two tags are the same person, nicknames included.
 static func same(_ a: String,_ b: String) -> Bool { (canonical(a) ?? a.lowercased()) == (canonical(b) ?? b.lowercased()) }

 // "Claude → Matthew" is Claude's: the name before the arrow.
 static func who(_ owner: String) -> String {
  (owner.components(separatedBy:"→").first ?? owner).trimmingCharacters(in:.whitespaces)
 }

 // How many lines of a board list show before "Show all": the long ones are the history, not the live work.
 static func shownByDefault(_ section: String) -> Int {
  switch section.lowercased() {
  case "decisions": return 3
  case "on the table": return 6
  default: return 99
  }
 }

 static func brief(_ text: String,limit: Int? = nil) -> String {
  let limit = max(limit ?? briefLimit,0)
  let flat = oneLine(text)
  guard flat.count > limit else { return flat }
  let head = String(flat.prefix(limit))
  var stop: String.Index?
  for mark in [". ","? ","! "] {
   if let found = head.range(of:mark,options:.backwards), head.distance(from:head.startIndex,to:found.lowerBound) >= limit / 3 {
    if stop == nil || found.lowerBound > stop! { stop = found.lowerBound }
   }
  }
  if stop == nil, let space = head.range(of:" ",options:.backwards) { stop = space.lowerBound }
  let cut = String(head[..<(stop ?? head.endIndex)]).trimmingCharacters(in:CharacterSet(charactersIn:" ,;:.-–—"))
  return cut + "…"
 }

 // Questions put to Matthew and open board items he owns (not marked done), plus messages tagged for him in the last few days
 // with no later message from him. The thread has no "read" mark, so a reply from him is what clears one.
 static func needs(board: Board?,messages: [RoomMessage],now: Date = Date(),days: Double = 7) -> MatthewNeeds {
  var result = MatthewNeeds()
  for section in board?.sections ?? [] {
   let name = section.title.lowercased()
   for item in section.items where !item.isDone {
    let owner = item.owner.lowercased()
    if name == "questions" && (owner.isEmpty || owner.hasSuffix("matthew")) { result.questions.append(item) }
    if name == "on the table" && owner.hasPrefix("matthew") { result.tasks.append(item) }
   }
  }
  var waiting: [RoomMessage] = []
  for message in messages {
   if MeetingData.canonical(message.author) == "Matthew" { waiting = [] }
   else if MeetingData.canonical(message.to) == "Matthew" { waiting.append(message) }
  }
  result.messages = waiting.filter { message in
   guard let date = message.date else { return true }
   return now.timeIntervalSince(date) < days * 86400
  }
  return result
 }

 static let defaultAgenda = "Claude and GPT: post one short update here, tagged to whoever you are answering: what you are on, what you need from whom, and what you can offer. Talk to each other, not only to Matthew."

 // The words of a call, posted as Matthew with the usual tag: **[Matthew → Everyone]** BOARD MEETING. ...
 static func meetingCall(agenda: String? = nil) -> String {
  let extra = (agenda ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
  return "BOARD MEETING. " + (extra.isEmpty ? defaultAgenda : extra)
 }

 // Matthew's call can be in any letter case. Claude's has to be in capitals, so an ordinary reply that starts "Board meeting update"
 // is not mistaken for a new call. Nobody else can call one.
 static func isMeetingCall(_ message: RoomMessage) -> Bool {
  let to = message.to.lowercased()
  guard to.isEmpty || to == "everyone" else { return false }
  let text = message.text.trimmingCharacters(in:.whitespacesAndNewlines)
  func opens(_ words: String,_ phrase: String) -> Bool {
   guard words.hasPrefix(phrase) else { return false }
   guard let next = words.dropFirst(phrase.count).first else { return true }
   return next == "." || next == "!"
  }
  switch canonical(message.author) {
  case "Matthew"?:
   let shout = text.uppercased()
   return opens(shout,"BOARD MEETING") || opens(shout,"GROUP MEETING")
  case "Claude"?: return opens(text,"BOARD MEETING") || opens(text,"GROUP MEETING")
  default: return false
  }
 }

 // The latest call that is still recent (two days), with the messages after it. Nil when nobody has called one.
 static func currentMeeting(_ messages: [RoomMessage],now: Date = Date(),hours: Double = 48) -> BoardMeeting? {
  guard let index = messages.lastIndex(where: { isMeetingCall($0) }) else { return nil }
  let call = messages[index]
  if let date = call.date, now.timeIntervalSince(date) > hours * 3600 { return nil }
  return BoardMeeting(call:call,replies:Array(messages[(index + 1)...]))
 }

 // One crew member's tab: their board items (On the table and Questions) sorted by status, and the messages they wrote or got.
 static func crew(_ name: String,board: Board?,messages: [RoomMessage]) -> CrewView {
  var progress: [BoardItem] = [], next: [BoardItem] = [], waiting: [BoardItem] = []
  var blocked: [BoardItem] = [], asking: [BoardItem] = [], done: [BoardItem] = []
  for section in board?.sections ?? [] {
   let title = section.title.lowercased()
   guard title == "on the table" || title == "questions" else { continue }
   for item in section.items where same(who(item.owner),name) {
    if item.isDone { done.append(item) }
    else if title == "questions" { asking.append(item) }
    else if item.status.hasPrefix("blocked") { blocked.append(item) }
    else if item.status.hasPrefix("building") { progress.append(item) }
    else if item.status.hasPrefix("assigned") { next.append(item) }
    else { waiting.append(item) }
   }
  }
  var view = CrewView(name:name)
  view.groups = [
   CrewGroup(title:"In progress",status:"building",items:progress),
   CrewGroup(title:"Up next",status:"assigned",items:next),
   CrewGroup(title:"Waiting on someone",status:"waiting",items:waiting),
   CrewGroup(title:"Blocked",status:"blocked",items:blocked),
   CrewGroup(title:"Asking Matthew",status:"asking",items:asking),
   CrewGroup(title:"Done",status:"done",items:done)
  ].filter { !$0.items.isEmpty }
  view.messages = messages.filter { same($0.author,name) || same($0.to,name) }
  return view
 }

 // The message as it is posted: **[Matthew → GPT]** words (the "to" part left out when it is for everyone).
 static func formatted(from: String,to: String,text: String) -> String {
  let target = (to.isEmpty || to == "Everyone") ? "" : " → \(to)"
  return "**[\(from)\(target)]** \(text.trimmingCharacters(in:.whitespacesAndNewlines))"
 }

 // A fine-grained GitHub key limited to one repo is the only kind accepted. A classic key can't be limited to one repo.
 static func tokenProblem(_ raw: String) -> String? {
  let key = raw.trimmingCharacters(in:.whitespacesAndNewlines)
  if key.isEmpty { return "Paste the key first." }
  if key.hasPrefix("ghp_") || key.hasPrefix("gho_") || key.hasPrefix("ghs_") { return "That is a classic key, which can't be limited to one repo. Make a fine-grained key (steps above)." }
  if !key.hasPrefix("github_pat_") { return "That doesn't look like a GitHub fine-grained key. It starts with github_pat_." }
  return nil
 }

 static func api(_ path: String,token: String?,method: String = "GET",body: Data? = nil) -> URLRequest? {
  guard let target = URL(string:"https://api.github.com/repos/\(owner)/\(repo)\(path)") else { return nil }
  var request = URLRequest(url:target)
  request.httpMethod = method
  request.cachePolicy = .reloadIgnoringLocalCacheData
  request.timeoutInterval = 15
  request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
  request.setValue("2022-11-28",forHTTPHeaderField:"X-GitHub-Api-Version")
  request.setValue("GameCompanion",forHTTPHeaderField:"User-Agent")
  if let token = token, !token.isEmpty { request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization") }
  if let body = body { request.httpBody = body; request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
  return request
 }

 // The newest messages. GitHub lists a thread oldest first, 100 to a page, so the last page is the one that matters.
 static func fetchMessages(token: String?) async -> [RoomMessage]? {
  guard let first = api("/issues/\(issue)/comments?per_page=100",token:token),
        let (data,response) = try? await URLSession.shared.data(for:first),
        (response as? HTTPURLResponse)?.statusCode == 200, var all = parseMessages(data) else { return nil }
  if let link = (response as? HTTPURLResponse)?.value(forHTTPHeaderField:"Link"), let last = lastPage(link), last > 1 {
   var pages = [last]
   if last > 2 { pages.append(last - 1) }
   var more: [RoomMessage] = []
   for page in pages.sorted() {
    if let r = api("/issues/\(issue)/comments?per_page=100&page=\(page)",token:token),
       let (d,resp) = try? await URLSession.shared.data(for:r), (resp as? HTTPURLResponse)?.statusCode == 200, let got = parseMessages(d) { more += got }
   }
   if !more.isEmpty { all = more }
  }
  return all
 }

 // From a Link header: <...&page=3>; rel="last"
 static func lastPage(_ link: String) -> Int? {
  for part in link.components(separatedBy:",") where part.contains("rel=\"last\"") {
   // "&page=" or "?page=", never the "page=" inside "per_page=".
   for key in ["&page=","?page="] {
    if let range = part.range(of:key) {
     let digits = part[range.upperBound...].prefix { $0.isNumber }
     if let number = Int(digits) { return number }
    }
   }
  }
  return nil
 }

 static func post(_ text: String,from: String,to: String,token: String) async -> RoomPost {
  if let problem = tokenProblem(token) { return .failed(problem) }
  let words = text.trimmingCharacters(in:.whitespacesAndNewlines)
  if words.isEmpty { return .failed("Type a message first.") }
  guard let json = try? JSONSerialization.data(withJSONObject:["body":formatted(from:from,to:to,text:words)]),
        let call = api("/issues/\(issue)/comments",token:token,method:"POST",body:json) else { return .failed("Couldn't build the message.") }
  guard let (_,response) = try? await URLSession.shared.data(for:call), let code = (response as? HTTPURLResponse)?.statusCode else {
   return .failed("Couldn't reach GitHub. Check your internet.")
  }
  switch code {
  case 201: return .ok
  case 401: return .failed("GitHub didn't accept that key. Make a fresh one and save it again.")
  case 403: return .failed("GitHub refused it. The key needs Issues set to Read and write on the hotstuff repo, or GitHub is rate-limiting. Try again in a minute.")
  case 404: return .failed("GitHub can't find the thread with that key. Check the key is allowed to see the hotstuff repo.")
  default: return .failed("GitHub answered something unexpected (code \(code)).")
  }
 }

 // GitHub's contents API with the "raw" media type returns the file itself, a minute fresher than the raw file host.
 static func fetch(token: String? = nil) async -> Board? {
  guard var request = api("/contents/meeting-room/BOARD.md?ref=master",token:token) else { return nil }
  request.setValue("application/vnd.github.raw+json",forHTTPHeaderField:"Accept")
  guard let (data,response) = try? await URLSession.shared.data(for:request),
        (response as? HTTPURLResponse)?.statusCode == 200,
        let text = String(data:data,encoding:.utf8), text.contains("##") else { return nil }
  return parse(text)
 }
}

// MARK: Monitor read seam (slice 2, Claude's part; Roxy's coordinator owns the URLSession, the schedule and all state).
// Pure building and parsing, no network and no storage here, and no dependency on the monitor files. The existing display and
// posting functions above are unchanged. Reads are anonymous GETs of two fixed resources: the board file and issue 15's comments.

enum MeetingReadSource: String, Codable { case board, comments }

// One read the monitor may make. Only monitorRead(...) builds these, so the page, per_page and since values are always ours.
struct MeetingReadRequest: Equatable {
 let source: MeetingReadSource
 let page: Int
 let perPage: Int
 let since: Date?
 let url: URL
 // Conditional requests only for this exact identity, and only while the coordinator still holds a snapshot in memory.
 var cacheKey: String { url.absoluteString }
}

// What the server said about timing, kept even when the body is unusable.
struct MeetingReadHints: Equatable {
 var serverDate: Date? = nil     // the Date header, only when it parses and is within a day of the Mac's clock
 var retryAfter: Date? = nil     // Retry-After, seconds or a date, turned into a moment
 var resetAt: Date? = nil        // X-RateLimit-Reset
 var remaining: Int? = nil       // X-RateLimit-Remaining
 var pollInterval: TimeInterval? = nil  // X-Poll-Interval
 var etag: String? = nil
}

struct MeetingReadComment: Equatable {
 let id: Int64
 let createdAt: Date
 let updatedAt: Date
 let digest: String
 let message: RoomMessage
 static func == (a: MeetingReadComment,b: MeetingReadComment) -> Bool { a.id == b.id && a.updatedAt == b.updatedAt && a.digest == b.digest }
}

enum MeetingReadRejection: String, Equatable { case wrongHost, wrongPath, redirected, badStatus, badPayload, badLink }

enum MeetingReadResult {
 case board(Board,digest: String,hints: MeetingReadHints)
 case comments([MeetingReadComment],next: MeetingReadRequest?,fullPage: Bool,hints: MeetingReadHints)
 case unchanged(hints: MeetingReadHints)                     // 304: only meaningful with a matching snapshot in memory
 case rejected(MeetingReadRejection,status: Int,hints: MeetingReadHints)
}

extension MeetingData {
 static let readHost = "api.github.com"
 static let boardPath = "/repos/\(owner)/\(repo)/contents/meeting-room/BOARD.md"
 static let commentsPath = "/repos/\(owner)/\(repo)/issues/\(issue)/comments"
 static let readPageLimit = 100

 static func sinceText(_ date: Date) -> String {
  let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]
  return f.string(from:date)
 }

 // The only way to make a monitor read. Board reads ignore page and since.
 static func monitorRead(_ source: MeetingReadSource,page: Int = 1,perPage: Int = 100,since: Date? = nil) -> MeetingReadRequest? {
  guard page >= 1, page <= 10_000, perPage >= 1, perPage <= readPageLimit else { return nil }
  var parts = URLComponents()
  parts.scheme = "https"; parts.host = readHost
  switch source {
  case .board:
   parts.path = boardPath
   parts.queryItems = [URLQueryItem(name:"ref",value:"master")]
   guard let url = parts.url else { return nil }
   return MeetingReadRequest(source:.board,page:1,perPage:1,since:nil,url:url)
  case .comments:
   parts.path = commentsPath
   var items = [URLQueryItem(name:"per_page",value:String(perPage)),URLQueryItem(name:"page",value:String(page))]
   if let since = since { guard since.timeIntervalSinceReferenceDate.isFinite else { return nil }; items.append(URLQueryItem(name:"since",value:sinceText(since))) }
   parts.queryItems = items
   guard let url = parts.url else { return nil }
   return MeetingReadRequest(source:.comments,page:page,perPage:perPage,since:since,url:url)
  }
 }

 // Anonymous GET only: no Authorization, no cookies, no body. The ETag goes in only when the caller passes one for this cacheKey.
 static func urlRequest(_ read: MeetingReadRequest,etag: String? = nil) -> URLRequest {
  var request = URLRequest(url:read.url)
  request.httpMethod = "GET"
  request.httpShouldHandleCookies = false
  request.cachePolicy = .reloadIgnoringLocalCacheData
  request.timeoutInterval = 15
  request.setValue(read.source == .board ? "application/vnd.github.raw+json" : "application/vnd.github+json",forHTTPHeaderField:"Accept")
  request.setValue("2022-11-28",forHTTPHeaderField:"X-GitHub-Api-Version")
  request.setValue("GameCompanion",forHTTPHeaderField:"User-Agent")
  if let etag = etag, !etag.isEmpty { request.setValue(etag,forHTTPHeaderField:"If-None-Match") }
  return request
 }

 // For the session's redirect delegate and the final-URL check: only our two resources, over HTTPS, on api.github.com.
 static func isAllowedRead(_ url: URL?) -> Bool {
  guard let url = url, url.scheme == "https", url.host == readHost, url.user == nil, url.port == nil else { return false }
  return url.path == boardPath || url.path == commentsPath
 }

 // A stable digest (FNV-1a, 64-bit) for change detection only, not security. Same bytes, same digest, on every machine.
 static func digest(_ data: Data) -> String {
  var hash: UInt64 = 0xcbf29ce484222325
  for byte in data { hash ^= UInt64(byte); hash = hash &* 0x100000001b3 }
  return String(format:"%016llx",hash)
 }

 static func hints(_ headers: [AnyHashable:Any],now: Date = Date()) -> MeetingReadHints {
  var low: [String:String] = [:]
  for (k,v) in headers { if let k = k as? String { low[k.lowercased()] = "\(v)" } }
  var h = MeetingReadHints()
  let http = DateFormatter()
  http.locale = Locale(identifier:"en_US_POSIX"); http.timeZone = TimeZone(identifier:"GMT")
  http.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
  if let d = low["date"].flatMap({ http.date(from:$0) }), abs(d.timeIntervalSince(now)) < 86_400 { h.serverDate = d }
  if let r = low["retry-after"]?.trimmingCharacters(in:.whitespaces) {
   if let s = Double(r), s.isFinite, s >= 0, s <= 86_400 { h.retryAfter = now.addingTimeInterval(s) }
   else if let d = http.date(from:r), d.timeIntervalSince(now) <= 86_400 { h.retryAfter = d }
  }
  if let r = low["x-ratelimit-reset"].flatMap({ Double($0) }), r.isFinite, r > 0 {
   let d = Date(timeIntervalSince1970:r); if d.timeIntervalSince(now) <= 86_400 { h.resetAt = d }
  }
  h.remaining = low["x-ratelimit-remaining"].flatMap { Int($0) }
  if let p = low["x-poll-interval"].flatMap({ Double($0) }), p.isFinite, p > 0, p <= 86_400 { h.pollInterval = p }
  if let e = low["etag"], !e.isEmpty { h.etag = e }
  return h
 }

 // The next page, only if the Link header's rel="next" is exactly the request we would have built ourselves.
 static func nextRead(after read: MeetingReadRequest,link: String?) -> (next: MeetingReadRequest?,ok: Bool) {
  guard read.source == .comments, let link = link, !link.isEmpty else { return (nil,true) }
  for part in link.components(separatedBy:",") where part.contains("rel=\"next\"") {
   guard let open = part.firstIndex(of:"<"), let close = part.firstIndex(of:">"), open < close,
         let url = URL(string:String(part[part.index(after:open)..<close])), isAllowedRead(url), url.path == commentsPath,
         let expected = monitorRead(.comments,page:read.page + 1,perPage:read.perPage,since:read.since) else { return (nil,false) }
   let q = { (u: URL) in Set((URLComponents(url:u,resolvingAgainstBaseURL:false)?.queryItems ?? []).map { "\($0.name)=\($0.value ?? "")" }) }
   return q(url) == q(expected.url) ? (expected,true) : (nil,false)
  }
  return (nil,true)
 }

 // Everything the coordinator gets back from one response. Invalid payloads still carry the hints.
 static func readResult(_ read: MeetingReadRequest,status: Int,headers: [AnyHashable:Any],finalURL: URL?,body: Data,now: Date = Date()) -> MeetingReadResult {
  let h = hints(headers,now:now)
  guard let finalURL = finalURL, finalURL.host == readHost else { return .rejected(.wrongHost,status:status,hints:h) }
  guard isAllowedRead(finalURL) else { return .rejected(.wrongPath,status:status,hints:h) }
  guard finalURL.path == read.url.path else { return .rejected(.redirected,status:status,hints:h) }
  if status == 304 { return .unchanged(hints:h) }
  guard status == 200 else { return .rejected(.badStatus,status:status,hints:h) }
  switch read.source {
  case .board:
   guard let text = String(data:body,encoding:.utf8), text.contains("##") else { return .rejected(.badPayload,status:status,hints:h) }
   return .board(parse(text),digest:digest(body),hints:h)
  case .comments:
   guard let rows = (try? JSONSerialization.jsonObject(with:body)) as? [[String:Any]] else { return .rejected(.badPayload,status:status,hints:h) }
   let iso = ISO8601DateFormatter()
   var out: [MeetingReadComment] = []
   for row in rows {
    guard let id = (row["id"] as? NSNumber)?.int64Value, let text = row["body"] as? String,
          let created = (row["created_at"] as? String).flatMap({ iso.date(from:$0) }) else { return .rejected(.badPayload,status:status,hints:h) }
    let updated = (row["updated_at"] as? String).flatMap { iso.date(from:$0) } ?? created
    guard let user = row["user"] as? [String:Any], (user["login"] as? String) == trustedLogin else { continue }
    let parsed = parseMessage(body:text)
    let message = RoomMessage(id:Int(truncatingIfNeeded:id),author:parsed.author,to:parsed.to,text:parsed.text,date:created,url:(row["html_url"] as? String) ?? "")
    out.append(MeetingReadComment(id:id,createdAt:created,updatedAt:updated,digest:digest(Data(text.utf8)),message:message))
   }
   let link = headers.first { ($0.key as? String)?.lowercased() == "link" }.map { "\($0.value)" }
   let next = nextRead(after:read,link:link)
   guard next.ok else { return .rejected(.badLink,status:status,hints:h) }
   return .comments(out,next:next.next,fullPage:rows.count == read.perPage,hints:h)
  }
 }
}
