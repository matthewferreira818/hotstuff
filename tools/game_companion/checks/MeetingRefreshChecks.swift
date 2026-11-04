import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Offline: swiftc -parse-as-library MeetingData.swift checks/MeetingRefreshChecks.swift -o /tmp/room-refresh-checks
// The session below intercepts every request. No GitHub connection, credential, or real POST is used.
final class RoomRefreshStub: URLProtocol {
 static var replies: [(Int,[String:String],Data)] = []
 static var requests: [URLRequest] = []
 override class func canInit(with request: URLRequest) -> Bool { true }
 override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
 override func startLoading() {
  precondition(request.url?.host == "api.github.com" && request.httpMethod == "GET")
  precondition(request.value(forHTTPHeaderField:"Authorization") == nil)
  Self.requests.append(request)
  precondition(!Self.replies.isEmpty)
  let reply = Self.replies.removeFirst()
  client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:reply.0,httpVersion:"HTTP/1.1",headerFields:reply.1)!,cacheStoragePolicy:.notAllowed)
  client?.urlProtocol(self,didLoad:reply.2)
  client?.urlProtocolDidFinishLoading(self)
 }
 override func stopLoading() {}
}

@main struct MeetingRefreshChecks {
 static func row(_ id: Int,_ text: String = "new message") -> [String:Any] {
  ["id":id,"body":"**[GPT → Claude]** \(text)","created_at":"2026-11-04T20:00:00Z","html_url":"https://github.com/matthewferreira818/hotstuff/issues/15#issuecomment-\(id)","user":["login":MeetingData.trustedLogin]]
 }
 static func data(_ rows: [[String:Any]]) -> Data { try! JSONSerialization.data(withJSONObject:rows) }
 static func main() async {
  precondition(RoomRefreshPolicy.interval(authenticated:true) == 5 && RoomRefreshPolicy.interval(authenticated:false) == 90)
  let since = Date(timeIntervalSince1970:1_800_000_000)
  let path = MeetingData.messageUpdatesPath(since:since)!
  let firstURL = MeetingData.api(path,token:nil)!.url!
  let query = URLComponents(url:firstURL,resolvingAgainstBaseURL:false)!.queryItems!
  precondition(firstURL.host == "api.github.com" && query.first{$0.name == "since"}?.value == ISO8601DateFormatter().string(from:since))
  precondition(MeetingData.messageUpdatesPath(since:since,page:0) == nil && MeetingData.messageUpdatesPath(since:since,page:4) == nil)
  let one = MeetingData.parseMessages(data([row(1,"old")]))!
  let newer = MeetingData.parseMessages(data([row(1,"edited"),row(2)]))!
  let merged = MeetingData.mergedMessages(one,newer)
  precondition(merged.map{$0.id} == [1,2] && merged[0].text.contains("edited"))
  // An older read can't remove a just-posted message; replaying it doesn't duplicate it.
  precondition(MeetingData.mergedMessages(merged,one).map{$0.id} == [1,2])
  precondition(MeetingData.mergedMessages(merged,newer).count == 2)
  let many = MeetingData.parseMessages(data((1...350).map{row($0)}))!
  precondition(MeetingData.mergedMessages([],many).count == 300 && MeetingData.mergedMessages([],many).first?.id == 51)
  precondition(MeetingData.postedMessage(try! JSONSerialization.data(withJSONObject:row(7)))?.id == 7)
  precondition(MeetingData.postedMessage(Data("{}".utf8)) == nil)

  let now = Date()
  precondition(MeetingData.messageReadDeadline(status:200,headers:[:],now:now) == nil)
  precondition(MeetingData.messageReadDeadline(status:200,headers:["X-Poll-Interval":"60"],now:now) == now.addingTimeInterval(60))
  precondition(MeetingData.messageReadDeadline(status:429,headers:["Retry-After":"120"],now:now) == now.addingTimeInterval(120))
  precondition(MeetingData.messageReadDeadline(status:200,headers:["X-RateLimit-Remaining":"0","X-RateLimit-Reset":String(now.addingTimeInterval(300).timeIntervalSince1970)],now:now)! >= now.addingTimeInterval(300))
  precondition(MeetingData.messageReadDeadline(status:200,headers:["X-Poll-Interval":"invalid"],now:now) == now.addingTimeInterval(60))

  let config = URLSessionConfiguration.ephemeral
  config.protocolClasses = [RoomRefreshStub.self]
  let session = URLSession(configuration:config)
  defer { session.invalidateAndCancel() }
  RoomRefreshStub.replies = [(200,["ETag":"\"v1\""],data([row(1)]))]
  let first = await MeetingData.fetchMessageUpdates(since:since,token:nil,validator:nil,session:session)
  precondition(first.messages?.map{$0.id} == [1] && first.validator?.url == firstURL.absoluteString)
  precondition(RoomRefreshStub.requests.last?.value(forHTTPHeaderField:"Cache-Control") == "no-cache")
  precondition(RoomRefreshStub.requests.last?.httpShouldHandleCookies == false)
  RoomRefreshStub.replies = [(304,[:],Data())]
  let unchanged = await MeetingData.fetchMessageUpdates(since:since,token:nil,validator:first.validator,session:session)
  precondition(unchanged.messages?.isEmpty == true && RoomRefreshStub.requests.last?.value(forHTTPHeaderField:"If-None-Match") == "\"v1\"")
  RoomRefreshStub.replies = [(200,[:],data([row(2)]))]
  _ = await MeetingData.fetchMessageUpdates(since:since.addingTimeInterval(1),token:nil,validator:first.validator,session:session)
  precondition(RoomRefreshStub.requests.last?.value(forHTTPHeaderField:"If-None-Match") == nil)

  // Even a single full page mustn't be cached: a new comment could create page 2 without changing page 1.
  RoomRefreshStub.replies = [(200,["ETag":"\"full\""],data((1...100).map{row($0)}))]
  let full = await MeetingData.fetchMessageUpdates(since:since,token:nil,validator:nil,session:session)
  precondition(full.messages?.count == 100 && full.validator == nil)
  let link = "<https://api.github.com/repos/matthewferreira818/hotstuff/issues/15/comments?per_page=100&page=2>; rel=\"last\""
  RoomRefreshStub.replies = [(200,["Link":link,"ETag":"\"page\""],data([row(1)])),(200,[:],data([row(2)]))]
  let paged = await MeetingData.fetchMessageUpdates(since:since,token:nil,validator:nil,session:session)
  precondition(paged.messages?.map{$0.id} == [1,2] && paged.validator == nil)
  precondition(URLComponents(url:RoomRefreshStub.requests.last!.url!,resolvingAgainstBaseURL:false)!.queryItems!.first{$0.name == "page"}?.value == "2")
  RoomRefreshStub.replies = [(429,["Retry-After":"120"],Data())]
  let limited = await MeetingData.fetchMessageUpdates(since:since,token:nil,validator:nil,session:session)
  precondition(limited.messages == nil && limited.notBefore! > Date().addingTimeInterval(110))
  RoomRefreshStub.replies = [(200,[:],Data("bad JSON".utf8))]
  let invalid = await MeetingData.fetchMessageUpdates(since:since,token:nil,validator:nil,session:session)
  precondition(invalid.messages == nil)
  precondition(RoomRefreshStub.replies.isEmpty)
  print("All Meeting Room refresh checks passed.")
 }
}
