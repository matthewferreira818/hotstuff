import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

// Dormant until MeetingHub explicitly owns one instance. No global instance, posting or credentials.
struct MeetingMonitorResponse {
 let status: Int
 let headers: [AnyHashable:Any]
 let url: URL?
 let body: Data
}
protocol MeetingMonitorTransport {
 func read(_ request: MeetingReadRequest, etag: String?) async throws -> MeetingMonitorResponse
}

final class MeetingMonitorHTTP: NSObject, MeetingMonitorTransport, URLSessionTaskDelegate, @unchecked Sendable {
 private lazy var session: URLSession = {
  let c = URLSessionConfiguration.ephemeral
  c.httpCookieStorage = nil; c.urlCredentialStorage = nil; c.urlCache = nil
  c.timeoutIntervalForRequest = 15; c.timeoutIntervalForResource = 30
  return URLSession(configuration:c,delegate:self,delegateQueue:nil)
 }()
 static func allowed(_ read: MeetingReadRequest) -> Bool {
  guard let canonical = MeetingData.monitorRead(read.source,page:read.page,perPage:read.perPage,since:read.since) else { return false }
  return read == canonical && MeetingData.isAllowedRead(read.url)
 }
 func read(_ read: MeetingReadRequest,etag: String?) async throws -> MeetingMonitorResponse {
  guard Self.allowed(read) else { throw URLError(.unsupportedURL) }
  let (data,response) = try await session.data(for:MeetingData.urlRequest(read,etag:etag))
  guard let http = response as? HTTPURLResponse, http.url == read.url else { throw URLError(.badServerResponse) }
  return MeetingMonitorResponse(status:http.statusCode,headers:http.allHeaderFields,url:http.url,body:data)
 }
 func urlSession(_ session: URLSession,task: URLSessionTask,willPerformHTTPRedirection response: HTTPURLResponse,
                 newRequest request: URLRequest,completionHandler: @escaping (URLRequest?) -> Void) {
  completionHandler(nil) // Even same-host redirects are refused; the final URL must match the generated request.
 }
 func urlSession(_ session: URLSession,task: URLSessionTask,didReceive challenge: URLAuthenticationChallenge,
                 completionHandler: @escaping (URLSession.AuthChallengeDisposition,URLCredential?) -> Void) {
  #if canImport(Darwin)
  if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
   completionHandler(.performDefaultHandling,nil); return
  }
  #endif
  completionHandler(.cancelAuthenticationChallenge,nil)
 }
 deinit { session.invalidateAndCancel() }
}

enum MeetingMonitorEventKind: String,Codable { case enabled, stopped, taskStarted, taskEnded, checked, changed, failed, reserved }
struct MeetingMonitorEvent: Codable {
 var id: String
 var at: Date
 var kind: MeetingMonitorEventKind
 var source: MeetingReadSource?
 var status: Int?
}
struct MeetingMonitorState: Codable {
 var schema = 1
 var settings = MeetingMonitorSettings()
 var budget = MeetingMonitorRequestBudget()
 var board = MeetingMonitorEndpointState()
 var comments = MeetingMonitorEndpointState()
 var cursor = MeetingMonitorCommentCursor()
 var batch: MeetingMonitorCommentBatch?
 var unread: Set<String> = []
 var events: [MeetingMonitorEvent] = []
 var manualNext: MeetingReadSource = .board
 mutating func log(_ kind: MeetingMonitorEventKind,at: Date,source: MeetingReadSource? = nil,status: Int? = nil,id: String? = nil) {
  let eventID = id ?? UUID().uuidString
  if !events.contains(where:{$0.id == eventID}) { events.append(.init(id:eventID,at:at,kind:kind,source:source,status:status)) }
  events = Array(events.suffix(200))
 }
}
protocol MeetingMonitorStorage {
 func load() throws -> MeetingMonitorState
 func save(_ state: MeetingMonitorState) throws
}

// One private atomic snapshot. Payloads, validators, raw errors and headers never enter this file.
final class MeetingMonitorFileStorage: MeetingMonitorStorage {
 private let directory: URL
 private var file: URL { directory.appendingPathComponent("state.json") }
 enum StorageError: Error { case unsafePath, io, invalidState }
 init(directory: URL) throws {
  self.directory = directory
  if !FileManager.default.fileExists(atPath:directory.path) {
   try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  }
  try validate(directory,kind:S_IFDIR,mode:0o700)
 }
 private func validate(_ url: URL,kind: mode_t,mode: mode_t) throws {
  var info = stat()
  guard lstat(url.path,&info) == 0, info.st_mode & S_IFMT == kind,
        info.st_uid == getuid(), info.st_mode & 0o777 == mode else { throw StorageError.unsafePath }
 }
 func load() throws -> MeetingMonitorState {
  try validate(directory,kind:S_IFDIR,mode:0o700)
  var info = stat()
  if lstat(file.path,&info) != 0 {
   if errno == ENOENT { return MeetingMonitorState() }
   throw StorageError.io
  }
  try validate(file,kind:S_IFREG,mode:0o600)
  let s = try JSONDecoder().decode(MeetingMonitorState.self,from:Data(contentsOf:file))
  guard s.schema == 1, s.events.count <= 200 else { throw StorageError.invalidState }
  return s
 }
 func save(_ state: MeetingMonitorState) throws {
  try validate(directory,kind:S_IFDIR,mode:0o700)
  let data = try JSONEncoder().encode(state)
  let temp = directory.appendingPathComponent(UUID().uuidString + ".tmp")
  let fd = open(temp.path,O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW,0o600)
  guard fd >= 0 else { throw StorageError.io }
  defer { close(fd); unlink(temp.path) }
  try data.withUnsafeBytes { raw in
   var count = 0
   while count < raw.count {
    let n = write(fd,raw.baseAddress!.advanced(by:count),raw.count-count)
    if n < 0 && errno == EINTR { continue }
    guard n > 0 else { throw StorageError.io }; count += n
   }
  }
  guard fsync(fd) == 0, rename(temp.path,file.path) == 0 else { throw StorageError.io }
 }
}

actor MeetingMonitor {
 enum Origin { case automatic, manual }
 private let transport: MeetingMonitorTransport
 private let storage: MeetingMonitorStorage
 private let clock: () -> Date
 private let uptime: () -> TimeInterval
 private var lastClock: (Date,TimeInterval)?
 private var state: MeetingMonitorState
 private(set) var storageFailed = false
 private(set) var boardPayload: Board?
 private(set) var messages: [Int64:RoomMessage] = [:]
 private var boardETag: String?
 private var active: Task<MeetingMonitorResponse,Error>?
 private var timer: Task<Void,Never>?
 private var busy = false
 // Separate in-memory generation also invalidates callbacks if saving Stop fails.
 private var generation: UInt64 = 0
 init(transport: MeetingMonitorTransport,storage: MeetingMonitorStorage,
      clock: @escaping () -> Date = Date.init,uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) throws {
  self.transport = transport; self.storage = storage; self.clock = clock; self.uptime = uptime
  state = try storage.load()
 }
 func snapshot() -> MeetingMonitorState { state }
 @discardableResult private func commit(_ next: MeetingMonitorState) -> Bool {
  do { try storage.save(next); state = next; return true }
  catch { storageFailed = true; timer?.cancel(); timer = nil; active?.cancel(); return false }
 }
 private func invalidate() { generation &+= 1; timer?.cancel(); timer = nil; active?.cancel() }
 func stop() {
  invalidate()
  var next = state; next.settings.stop(); next.log(.stopped,at:clock())
  if !commit(next) { state.settings.stop() } // fail closed for this process; caller must display storageFailed
 }
 @discardableResult func enableHourly() -> Bool {
  guard !storageFailed else { return false }
  invalidate(); var next = state; next.settings.enableHourly(); next.log(.enabled,at:clock())
  return commit(next)
 }
 @discardableResult func startFast(seconds: TimeInterval = 7200) -> Bool {
  guard !storageFailed else { return false }
  var next = state
  guard next.settings.startTask(id:UUID().uuidString,now:clock(),seconds:seconds) else { return false }
  invalidate(); next.log(.taskStarted,at:clock()); return commit(next)
 }
 func completeTask() {
  guard let id = state.settings.lease?.taskID else { return }
  var next = state; guard next.settings.completeTask(id:id) else { return }
  invalidate(); next.log(.taskEnded,at:clock()); _ = commit(next)
 }
 func markRead() { guard !storageFailed else { return }; var next = state; next.unread = []; _ = commit(next) }
 // Integration may call this once after explicit enable or startup. Off never starts a timer.
 func startScheduler() {
  guard timer == nil, !storageFailed, state.settings.mode != .off else { return }
  timer = Task { [weak self] in
   while !Task.isCancelled {
    guard let self else { return }
    await self.refresh(.automatic)
    do { try await Task.sleep(nanoseconds:60_000_000_000) } catch { return }
   }
  }
 }
 private func normalize() -> Bool {
  let now = clock(), tick = uptime()
  let changed = lastClock.map { abs(now.timeIntervalSince($0.0) - (tick - $0.1)) > 5 } ?? false
  lastClock = (now,tick)
  var next = state; let prior = next.settings.mode
  next.settings.normalize(now:now,clockChanged:changed)
  if prior != next.settings.mode { next.log(.taskEnded,at:now) }
  return commit(next)
 }
 // All callers share this single-flight path. Manual Off consumes exactly one request, never creates a timer.
 func refresh(_ origin: Origin) async {
  guard !busy, !storageFailed else { return }
  guard normalize(), origin == .manual || state.settings.mode != .off else { return }
  busy = true; let run = generation
  defer { busy = false; active = nil }
  if origin == .manual {
   _ = await fetch(state.manualNext,run:run,manual:true)
   return
  }
  _ = await fetch(.board,run:run,manual:false)
  guard run == generation, !storageFailed else { return }
  for _ in 0..<3 {
   guard await fetch(.comments,run:run,manual:false), run == generation, !storageFailed, state.batch != nil else { break }
  }
  if run == generation, !storageFailed, state.batch != nil {
   var next = state
   next.comments.nextAllowedCheck = MeetingMonitorTime.latest([next.comments.nextAllowedCheck,clock().addingTimeInterval(300)])
   _ = commit(next)
  }
 }
 private func fetch(_ source: MeetingReadSource,run: UInt64,manual: Bool) async -> Bool {
  guard run == generation, !storageFailed, normalize(), run == generation,
        manual || state.settings.mode != .off else { return false }
  let now = clock()
  let endpoint = source == .board ? state.board : state.comments
  guard endpoint.gate(budget:state.budget,access:.anonymous,now:now) == .ready else { return false }
  let interval: TimeInterval = state.settings.mode == .task ? 300 : 3600
  if !manual, !(source == .comments && state.batch != nil),
     let last = endpoint.lastSuccessfulCheck, now.timeIntervalSince(last) < interval { return false }
  let page = source == .comments ? state.batch?.nextPage ?? 1 : 1
  let since = source == .comments ? state.batch?.since ?? state.cursor.watermark?.addingTimeInterval(-60) : nil
  guard let read = MeetingData.monitorRead(source,page:page,since:since), MeetingMonitorHTTP.allowed(read) else { return false }
  var reserved = state
  guard reserved.budget.reserve(access:.anonymous,now:now) else { return false }
  if manual { reserved.manualNext = source == .board ? .comments : .board }
  reserved.log(.reserved,at:now,source:source)
  guard commit(reserved) else { return false }
  let etag = source == .board && boardPayload != nil ? boardETag : nil
  let transport = self.transport
  let task = Task { try await transport.read(read,etag:etag) }; active = task
  let response: MeetingMonitorResponse
  do { response = try await task.value }
  catch {
   guard run == generation, !storageFailed else { return false }
   var next = state; var e = source == .board ? next.board : next.comments
   e.failed(.transient,now:clock(),budget:&next.budget)
   if source == .board { next.board = e } else { next.comments = e }
   next.log(.failed,at:clock(),source:source); _ = commit(next); return false
  }
  guard run == generation, !storageFailed, normalize(), run == generation,
        manual || state.settings.mode != .off else { return false }
  let finished = clock()
  var next = state
  var e = source == .board ? next.board : next.comments
  let hints = MeetingData.hints(response.headers,now:finished)
  next.budget.recordServerLimits(retryAfter:hints.retryAfter,resetAt:hints.remaining == 0 ? hints.resetAt : nil)
  // A present but unusable server deadline is not permission to retry immediately.
  let headerNames = Set(response.headers.keys.compactMap { ($0 as? String)?.lowercased() })
  if (headerNames.contains("retry-after") && hints.retryAfter == nil)
      || (hints.remaining == 0 && hints.resetAt == nil) {
   next.budget.recordServerLimits(retryAfter:.distantFuture)
  }
  let poll: Date? = headerNames.contains("x-poll-interval") && hints.pollInterval == nil
   ? .distantFuture : hints.pollInterval.map { finished.addingTimeInterval($0) }
  e.nextAllowedCheck = MeetingMonitorTime.latest([e.nextAllowedCheck,poll])
  let result: MeetingReadResult = response.url == read.url
   ? MeetingData.readResult(read,status:response.status,headers:response.headers,finalURL:response.url,body:response.body,now:finished)
   : .rejected(.redirected,status:response.status,hints:hints)
  var payload: Board?
  var rows: [MeetingReadComment] = []
  var successful = false
  switch result {
  case let .board(board,digest,_):
   if e.contentDigest != nil && e.contentDigest != digest {
    let id = "board:\(digest)"; next.unread.insert(id); next.log(.changed,at:finished,source:source,id:id)
   }
   e.receivedContent(digest:digest,now:finished,serverNotBefore:poll); payload = board; successful = true
  case let .comments(comments,continuation,_,_):
   do {
    var batch: MeetingMonitorCommentBatch
    if let existing = next.batch { batch = existing }
    else {
     guard let cutoff = hints.serverDate, let fresh = next.cursor.beginBatch(serverCutoff:cutoff) else { throw MeetingMonitorBatchError.invalidPage }
     batch = fresh
    }
    // The enclosing refresh owns the three-page turn limit; persisted batches resume on a later turn.
    batch.beginTurn()
    try batch.append(comments.map { .init(id:$0.id,createdAt:$0.createdAt,updatedAt:$0.updatedAt,digest:$0.digest) },page:page,next:continuation?.page)
    if continuation == nil {
     guard let update = next.cursor.finishing(batch) else { throw MeetingMonitorBatchError.invalidPage }
     next.cursor = update.cursor; next.batch = nil
     for change in update.changes { next.unread.insert(change.eventID); next.log(.changed,at:finished,source:source,id:change.eventID) }
     e.receivedContent(digest:MeetingData.digest(try JSONEncoder().encode(next.cursor.version)),now:finished,serverNotBefore:poll)
    } else { next.batch = batch }
    e.consecutiveFailures = 0; e.requiresAttention = false
    rows = comments; successful = true
   } catch { e.failed(.transient,now:finished,budget:&next.budget) }
  case .unchanged:
   successful = source == .board && e.receivedUnchanged(hasMatchingCache:boardPayload != nil && etag != nil,now:finished,serverNotBefore:poll) == .successful
   if !successful { boardETag = nil; e.failed(.transient,now:finished,budget:&next.budget) }
  case .rejected:
   let limited = response.status == 429 || (response.status == 403 && (hints.remaining == 0 || hints.retryAfter != nil))
   let failure: MeetingMonitorFailure = limited ? .rateLimited(retryAfter:hints.retryAfter,resetAt:hints.resetAt)
    : ([401,403,404].contains(response.status) ? .inaccessible : .transient)
   e.failed(failure,now:finished,budget:&next.budget)
  }
  if source == .board { next.board = e } else { next.comments = e }
  next.log(successful ? .checked : .failed,at:finished,source:source,status:response.status)
  guard commit(next) else { return false }
  if let payload { boardPayload = payload; boardETag = hints.etag }
  for row in rows { messages[row.id] = row.message }
  return successful
 }
}
