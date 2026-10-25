import Foundation

// Offline checks for the monitor read seam in MeetingData.swift. Run on any machine with Swift:
//   swiftc -parse-as-library MeetingData.swift checks/MeetingReadSeamChecks.swift -o /tmp/read-seam-checks && /tmp/read-seam-checks
@main struct MeetingReadSeamChecks {
 static var failures = 0
 static func check(_ ok: Bool,_ what: String) { if !ok { failures += 1; print("FAIL: \(what)") } }
 static let now = Date(timeIntervalSince1970:1_800_000_000)

 static func main() {
  requests()
  hintsChecks()
  linkChecks()
  resultChecks()
  if failures > 0 { print("\(failures) read seam check(s) failed."); exit(1) }
  print("All read seam checks passed (offline).")
 }

 static func requests() {
  let board = MeetingData.monitorRead(.board)!
  check(board.url.absoluteString == "https://api.github.com/repos/matthewferreira818/hotstuff/contents/meeting-room/BOARD.md?ref=master","board url")
  let c = MeetingData.monitorRead(.comments,page:3,perPage:100,since:now)!
  check(c.url.absoluteString.hasPrefix("https://api.github.com/repos/matthewferreira818/hotstuff/issues/15/comments?per_page=100&page=3&since=2027-01-15T08:00:00Z"),"comments url: \(c.url)")
  check(MeetingData.monitorRead(.comments,page:0) == nil,"page 0 refused")
  check(MeetingData.monitorRead(.comments,perPage:101) == nil,"per_page over 100 refused")
  let r = MeetingData.urlRequest(c,etag:"W/\"abc\"")
  check(r.httpMethod == "GET" && r.httpBody == nil,"GET with no body")
  check(r.value(forHTTPHeaderField:"Authorization") == nil,"never Authorization")
  check(r.httpShouldHandleCookies == false,"no cookies")
  check(r.value(forHTTPHeaderField:"If-None-Match") == "W/\"abc\"","etag passed through")
  check(MeetingData.urlRequest(c).value(forHTTPHeaderField:"If-None-Match") == nil,"no etag unless given")
  check(MeetingData.urlRequest(board).value(forHTTPHeaderField:"Accept") == "application/vnd.github.raw+json","board raw media type")
  check(MeetingData.isAllowedRead(c.url) && MeetingData.isAllowedRead(board.url),"own reads allowed")
  for bad in ["http://api.github.com/repos/matthewferreira818/hotstuff/issues/15/comments","https://evil.example/repos/matthewferreira818/hotstuff/issues/15/comments",
              "https://api.github.com/repos/matthewferreira818/hotstuff/issues/16/comments","https://api.github.com:444/repos/matthewferreira818/hotstuff/issues/15/comments",
              "https://api.github.com/repos/other/hotstuff/contents/meeting-room/BOARD.md"] {
   check(!MeetingData.isAllowedRead(URL(string:bad)),"refused: \(bad)")
  }
  check(!MeetingData.isAllowedRead(nil),"nil refused")
 }

 static func hintsChecks() {
  let h = MeetingData.hints(["Date":"Fri, 15 Jan 2027 08:00:10 GMT","Retry-After":"60","X-RateLimit-Reset":"1800000900","x-ratelimit-remaining":"42","X-Poll-Interval":"60","ETag":"W/\"e1\""],now:now)
  check(h.serverDate == now.addingTimeInterval(10),"server date \(String(describing:h.serverDate))")
  check(h.retryAfter == now.addingTimeInterval(60),"retry-after seconds")
  check(h.resetAt == Date(timeIntervalSince1970:1_800_000_900),"reset")
  check(h.remaining == 42 && h.pollInterval == 60 && h.etag == "W/\"e1\"","remaining, poll, etag")
  let far = MeetingData.hints(["Date":"Mon, 01 Jan 2001 00:00:00 GMT","Retry-After":"9999999","X-RateLimit-Reset":"9999999999"],now:now)
  check(far.serverDate == nil && far.retryAfter == nil && far.resetAt == nil,"absurd times ignored")
  let dated = MeetingData.hints(["Retry-After":"Fri, 15 Jan 2027 08:02:00 GMT"],now:now)
  check(dated.retryAfter == now.addingTimeInterval(120),"retry-after as a date")
 }

 static func linkChecks() {
  let p1 = MeetingData.monitorRead(.comments,page:1,perPage:100,since:now)!
  let good = "<\(MeetingData.monitorRead(.comments,page:2,perPage:100,since:now)!.url.absoluteString)>; rel=\"next\", <https://api.github.com/repos/matthewferreira818/hotstuff/issues/15/comments?per_page=100&page=5>; rel=\"last\""
  let n = MeetingData.nextRead(after:p1,link:good)
  check(n.ok && n.next?.page == 2 && n.next?.since == now,"next page accepted")
  check(MeetingData.nextRead(after:p1,link:nil).ok && MeetingData.nextRead(after:p1,link:nil).next == nil,"no link, no next")
  let lastOnly = "<https://api.github.com/repos/matthewferreira818/hotstuff/issues/15/comments?per_page=100&page=1>; rel=\"prev\""
  check(MeetingData.nextRead(after:p1,link:lastOnly).next == nil,"no rel=next")
  for bad in ["<https://evil.example/repos/matthewferreira818/hotstuff/issues/15/comments?per_page=100&page=2>; rel=\"next\"",
              "<https://api.github.com/repos/matthewferreira818/hotstuff/issues/15/comments?per_page=100&page=9>; rel=\"next\"",
              "<https://api.github.com/repos/matthewferreira818/hotstuff/issues/15/comments?per_page=100&page=2&extra=1>; rel=\"next\"",
              "garbage; rel=\"next\""] {
   check(!MeetingData.nextRead(after:p1,link:bad).ok,"bad link refused: \(bad)")
  }
 }

 static func comment(_ id: Int,login: String = "matthewferreira818",body: String = "**[Claude → GPT]** hi") -> [String:Any] {
  ["id":id,"body":body,"user":["login":login],"created_at":"2027-01-15T07:00:00Z","updated_at":"2027-01-15T07:30:00Z","html_url":"https://github.com/x"]
 }

 static func resultChecks() {
  let c = MeetingData.monitorRead(.comments,page:1,perPage:2)!
  let body = try! JSONSerialization.data(withJSONObject:[comment(1),comment(2,login:"someone-else")])
  guard case let .comments(rows,next,full,hints) = MeetingData.readResult(c,status:200,headers:["ETag":"\"x\""],finalURL:c.url,body:body,now:now) else { check(false,"comments parse"); return }
  check(rows.count == 1 && rows[0].id == 1 && rows[0].message.author == "Claude" && rows[0].message.to == "GPT","only the owner's comments, tags parsed")
  check(rows[0].updatedAt.timeIntervalSince(rows[0].createdAt) == 1800,"updated_at kept")
  check(full && next == nil && hints.etag == "\"x\"","full page, no next, etag")
  let edited = try! JSONSerialization.data(withJSONObject:[comment(1,body:"**[Claude → GPT]** hi, edited")])
  if case let .comments(e,_,_,_) = MeetingData.readResult(c,status:200,headers:[:],finalURL:c.url,body:edited,now:now) { check(e[0].digest != rows[0].digest,"edit changes the digest") }
  check(MeetingData.digest(Data("abc".utf8)) == MeetingData.digest(Data("abc".utf8)) && MeetingData.digest(Data("abc".utf8)) == "e71fa2190541574b","digest is stable FNV-1a")
  if case let .rejected(why,_,h) = MeetingData.readResult(c,status:200,headers:["Retry-After":"30"],finalURL:c.url,body:Data("not json".utf8),now:now) {
   check(why == .badPayload && h.retryAfter == now.addingTimeInterval(30),"bad payload keeps hints")
  } else { check(false,"bad payload rejected") }
  if case .unchanged = MeetingData.readResult(c,status:304,headers:[:],finalURL:c.url,body:Data(),now:now) {} else { check(false,"304 unchanged") }
  if case let .rejected(why,_,_) = MeetingData.readResult(c,status:200,headers:[:],finalURL:URL(string:"https://evil.example/x"),body:body,now:now) { check(why == .wrongHost,"wrong host") } else { check(false,"wrong host rejected") }
  let board = MeetingData.monitorRead(.board)!
  if case let .rejected(why,_,_) = MeetingData.readResult(c,status:200,headers:[:],finalURL:board.url,body:body,now:now) { check(why == .redirected,"redirect to the other resource") } else { check(false,"redirect rejected") }
  if case let .rejected(why,status,_) = MeetingData.readResult(c,status:403,headers:[:],finalURL:c.url,body:Data(),now:now) { check(why == .badStatus && status == 403,"403 is a bad status") } else { check(false,"403 rejected") }
  let text = "_Last updated: x_\n\n## On the table\n- [GPT] A thing. Status: building\n"
  if case let .board(b,d,_) = MeetingData.readResult(board,status:200,headers:[:],finalURL:board.url,body:Data(text.utf8),now:now) {
   check(b.openCount == 1 && d == MeetingData.digest(Data(text.utf8)),"board parsed with digest")
  } else { check(false,"board parse") }
 }
}
