import Foundation

// One place for every keyless-or-keyed GitHub READ the Helm makes (the room thread, the board, the crew chat, the crew strip).
// Order: the Helm's saved key (if it has one) -> Matthew's own `gh` login (5000 reads/h; the same login the Switchboard uses, run with an
// argument array and no shell) -> plain keyless HTTP (60 reads/h per network, which test copies can use up). When GitHub says the free limit
// is used up (403/429 with x-ratelimit-remaining 0) the reset time is remembered so every screen can say so in plain words and retry then.
struct GHResponse {
 var status: Int
 var body: Data
 var link: String?
 var remaining: Int?
 var reset: Date?
 var via: String      // "key", "gh" or "keyless"
}

enum GitHubRead {
 nonisolated static let ghPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Claude/bin/gh").path
 nonisolated(unsafe) private static var limit: Date?
 private static let lock = NSLock()

 // When the free limit resets, if GitHub last said it was used up and that time is still ahead.
 static var limitedUntil: Date? {
  lock.lock(); defer { lock.unlock() }
  if let l = limit, l > Date() { return l }
  return nil
 }
 private static func setLimit(_ date: Date?) { lock.lock(); limit = date; lock.unlock() }

 // Pure: is this response "the free limit is used up", and until when?
 static func limitReset(status: Int,remaining: Int?,reset: Date?) -> Date? {
  guard status == 403 || status == 429, remaining == 0, let reset = reset else { return nil }
  return reset
 }

 static func clock(_ date: Date) -> String {
  let f = DateFormatter()
  f.timeZone = TimeZone(identifier:"America/Moncton") ?? .current
  f.dateFormat = "h:mm a"
  return f.string(from:date)
 }

 // The plain sentence for a used-up limit, or nil when there is no limit.
 static func limitMessage(_ until: Date? = GitHubRead.limitedUntil) -> String? {
  guard let until = until else { return nil }
  return "GitHub's free limit is used up. Trying again at \(clock(until))."
 }

 // Pure: `gh api -i` prints the status line, the headers, a blank line, then the body.
 static func parseGhOutput(_ data: Data) -> GHResponse? {
  let separators = [Data("\r\n\r\n".utf8),Data("\n\n".utf8)]
  var cut: Range<Data.Index>?
  for s in separators { if let r = data.range(of:s), cut == nil || r.lowerBound < cut!.lowerBound { cut = r } }
  guard let split = cut, let head = String(data:data[data.startIndex..<split.lowerBound],encoding:.utf8) else { return nil }
  var lines = head.components(separatedBy:"\n").map { $0.trimmingCharacters(in:.whitespacesAndNewlines) }
  guard let first = lines.first, first.hasPrefix("HTTP/"), let code = Int(first.split(separator:" ").dropFirst().first ?? "") else { return nil }
  lines.removeFirst()
  var headers: [String:String] = [:]
  for line in lines { if let i = line.firstIndex(of:":") { headers[line[..<i].lowercased()] = line[line.index(after:i)...].trimmingCharacters(in:.whitespaces) } }
  let reset = headers["x-ratelimit-reset"].flatMap { Double($0) }.map { Date(timeIntervalSince1970:$0) }
  return GHResponse(status:code,body:data[split.upperBound...],link:headers["link"],remaining:headers["x-ratelimit-remaining"].flatMap { Int($0) },reset:reset,via:"gh")
 }

 static func httpGet(_ path: String,token: String?,accept: String?) async -> GHResponse? {
  guard var request = MeetingData.api(path,token:token) else { return nil }
  if let accept = accept { request.setValue(accept,forHTTPHeaderField:"Accept") }
  guard let (data,response) = try? await URLSession.shared.data(for:request), let http = response as? HTTPURLResponse else { return nil }
  let reset = http.value(forHTTPHeaderField:"x-ratelimit-reset").flatMap { Double($0) }.map { Date(timeIntervalSince1970:$0) }
  return GHResponse(status:http.statusCode,body:data,link:http.value(forHTTPHeaderField:"Link"),remaining:http.value(forHTTPHeaderField:"x-ratelimit-remaining").flatMap { Int($0) },reset:reset,via:token == nil ? "keyless" : "key")
 }

 static func ghGet(_ path: String,accept: String?) async -> GHResponse? {
  guard FileManager.default.isExecutableFile(atPath:ghPath) else { return nil }
  let full = "repos/\(MeetingData.owner)/\(MeetingData.repo)\(path)"
  var args = ["api","-i"]
  if let accept = accept { args += ["-H","Accept: \(accept)"] }
  args.append(full)
  return await withCheckedContinuation { cont in
   DispatchQueue.global().async {
    let p = Process()
    p.executableURL = URL(fileURLWithPath:ghPath)
    p.arguments = args
    p.standardInput = FileHandle.nullDevice
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { cont.resume(returning:nil); return }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    cont.resume(returning:parseGhOutput(data))
   }
  }
 }

 // `path` is relative to the repo, like MeetingData.api: "/issues/15/comments?per_page=100".
 static func get(_ path: String,token: String?,accept: String? = nil) async -> GHResponse? {
  // Test copies only: `defaults write ... test.forceLimit -bool true` pretends GitHub's free limit is used up.
  if UserDefaults.standard.bool(forKey:"test.forceLimit") {
   setLimit(Date().addingTimeInterval(20 * 60))
   return GHResponse(status:403,body:Data(),link:nil,remaining:0,reset:limitedUntil,via:"test")
  }
  if let token = token, !token.isEmpty, let r = await httpGet(path,token:token,accept:accept), r.status == 200 { setLimit(nil); return r }
  if let r = await ghGet(path,accept:accept), r.status == 200 { setLimit(nil); return r }
  guard let r = await httpGet(path,token:nil,accept:accept) else { return nil }
  if r.status == 200 { setLimit(nil) }
  else if let until = limitReset(status:r.status,remaining:r.remaining,reset:r.reset) { setLimit(until) }
  return r
 }
}

// The room reads (board file and message thread) through the same chain, for the Meeting Room and Home.
enum RoomRead {
 static func board(token: String?) async -> Board? {
  guard let r = await GitHubRead.get("/contents/meeting-room/BOARD.md?ref=master",token:token,accept:"application/vnd.github.raw+json"), r.status == 200,
        let text = String(data:r.body,encoding:.utf8), text.contains("##") else { return nil }
  return MeetingData.parse(text)
 }

 // Newest messages of one issue or pull request thread (100 a page; the last two pages when there are more). Nil means the read failed.
 static func thread(_ issue: Int,token: String?) async -> [RoomMessage]? {
  guard let first = await GitHubRead.get("/issues/\(issue)/comments?per_page=100",token:token), first.status == 200,
        var all = MeetingData.parseMessages(first.body) else { return nil }
  if let link = first.link, let last = MeetingData.lastPage(link), last > 1 {
   var more: [RoomMessage] = []
   for page in (last > 2 ? [last - 1,last] : [last]) {
    guard let r = await GitHubRead.get("/issues/\(issue)/comments?per_page=100&page=\(page)",token:token), r.status == 200,
          let got = MeetingData.parseMessages(r.body) else { return nil }   // a missing page would leave a hole: a failed read
    more += got
   }
   all = more
  }
  return all
 }
}
