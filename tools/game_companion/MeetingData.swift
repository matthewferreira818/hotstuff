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
 var id: String { title }
 var title: String
 var items: [BoardItem]
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
   section.items.append(makeItem(body,id:"\(section.title)-\(section.items.count)"))
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
    current = BoardSection(title:String(trimmed.dropFirst(3)).trimmingCharacters(in:.whitespaces),items:[])
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
 static func fetch() async -> Board? {
  guard let target = URL(string:url) else { return nil }
  var request = URLRequest(url:target)
  request.cachePolicy = .reloadIgnoringLocalCacheData
  request.timeoutInterval = 12
  request.setValue("application/vnd.github.raw+json",forHTTPHeaderField:"Accept")
  request.setValue("GameCompanion",forHTTPHeaderField:"User-Agent")
  guard let (data,response) = try? await URLSession.shared.data(for:request),
        (response as? HTTPURLResponse)?.statusCode == 200,
        let text = String(data:data,encoding:.utf8), text.contains("##") else { return nil }
  return parse(text)
 }
}
