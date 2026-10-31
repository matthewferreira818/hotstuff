import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Offline, no app launch: swiftc -parse-as-library MeetingData.swift MeetingMonitorData.swift MeetingMonitor.swift
// checks/MeetingMonitorCoordinatorChecks.swift -o /tmp/monitor-checks && /tmp/monitor-checks
final class TestClock {
 var now = Date(timeIntervalSince1970:1_800_000_000)
 var tick: TimeInterval = 0
 func advance(_ seconds: TimeInterval) { now = now.addingTimeInterval(seconds); tick += seconds }
}
final class MemoryMonitorStore: MeetingMonitorStorage {
 var value = MeetingMonitorState()
 var fail = false
 var saves = 0
 func load() throws -> MeetingMonitorState { value }
 func save(_ state: MeetingMonitorState) throws {
  if fail { throw CocoaError(.fileWriteOutOfSpace) }; value = state; saves += 1
 }
}
actor FakeMonitorTransport: MeetingMonitorTransport {
 var reads: [MeetingReadRequest] = []
 var etags: [String?] = []
 var responses: [MeetingMonitorResponse] = []
 var waiting: CheckedContinuation<MeetingMonitorResponse,Error>?
 var delayed = false
 let store: MemoryMonitorStore
 var reservedBeforeRead = true
 init(_ store: MemoryMonitorStore) { self.store = store }
 func enqueue(_ responses: [MeetingMonitorResponse]) { self.responses += responses }
 func delay() { delayed = true }
 func count() -> Int { reads.count }
 func release(_ response: MeetingMonitorResponse) { delayed = false; waiting?.resume(returning:response); waiting = nil }
 func read(_ request: MeetingReadRequest,etag: String?) async throws -> MeetingMonitorResponse {
  reads.append(request); etags.append(etag)
  reservedBeforeRead = reservedBeforeRead && store.value.budget.attempts.count >= reads.count
  if delayed { return try await withCheckedThrowingContinuation { waiting = $0 } }
  guard !responses.isEmpty else { throw URLError(.notConnectedToInternet) }
  return responses.removeFirst()
 }
}
@main struct MeetingMonitorCoordinatorChecks {
 static var failures = 0
 static func check(_ value: Bool,_ label: String) { if !value { failures += 1; print("FAIL: \(label)") } }
 static func monitor(_ store: MemoryMonitorStore,_ net: FakeMonitorTransport,_ c: TestClock) throws -> MeetingMonitor {
  try MeetingMonitor(transport:net,storage:store,clock:{c.now},uptime:{c.tick})
 }
 static func response(_ source: MeetingReadSource,_ clock: TestClock,status: Int = 200,page: Int = 1,since: Date? = nil,
                      body: String? = nil,extra: [String:String] = [:]) -> MeetingMonitorResponse {
  let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT:0); f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
  var h: [AnyHashable:Any] = ["Date":f.string(from:clock.now)]
  for (k,v) in extra { h[k] = v }
  return .init(status:status,headers:h,url:MeetingData.monitorRead(source,page:page,since:since)!.url,
               body:Data((body ?? (source == .board ? "## On the table\n- [GPT] Test. Status: waiting" : "[]")).utf8))
 }
 static func row(_ id: Int,_ date: Date,_ body: String = "private-test-body") -> String {
  let d = MeetingData.sinceText(date)
  return "{\"id\":\(id),\"body\":\"\(body)\",\"user\":{\"login\":\"matthewferreira818\"},\"created_at\":\"\(d)\",\"updated_at\":\"\(d)\"}"
 }
 static func main() async throws {
  try await presentationAndManualSource()
  try await offAndStop()
  try await pagination()
  try await limitsAndStorage()
  try await cachingAndLease()
  try privateFile()
  if failures > 0 { print("\(failures) coordinator checks failed"); exit(1) }
  print("All coordinator checks passed (offline).")
 }
 static func presentationAndManualSource() async throws {
  let s = MemoryMonitorStore(), c = TestClock(); let n = FakeMonitorTransport(s), m = try monitor(s,n,c)
  var updates = await m.updates().makeAsyncIterator()
  let initial = await updates.next()
  check(initial?.state.settings.mode == .off && initial?.commentsLoaded == false,"observer starts Off with unloaded messages")
  await n.enqueue([response(.comments,c,body:"[\(row(7,c.now))]")])
  await m.refresh(.manual,source:.comments)
  let loaded = await updates.next()
  check(await n.count() == 1,"explicit comments refresh uses only one request")
  check(loaded?.messages.first?.id == 7 && loaded?.commentsLoaded == true && loaded?.busy == false,"observer receives payload after durable commit")
  check(loaded?.state.settings.mode == .off,"observing and manual refresh do not enable monitor")
  let restart = try monitor(s,n,c)
  let restored = await restart.presentation()
  check(restored.state.comments.lastSuccessfulCheck != nil && !restored.commentsLoaded && restored.messages.isEmpty,"restart distinguishes saved check timestamp from missing payload")
  await n.delay()
  let pending = Task { await m.refresh(.manual,source:.board) }
  while await n.count() < 2 { await Task.yield() }
  let inFlight = await updates.next()
  check(inFlight?.busy == true,"observer shows real in-flight work")
  await m.stop()
  await n.release(response(.board,c)); await pending.value
  let stopped = await updates.next()
  check(stopped?.state.settings.mode == .off && stopped?.board == nil && stopped?.busy == false,"Stop publishes Off and rejects late payload")
  s.fail = true; await m.refresh(.manual)
  let failed = await updates.next()
  check(failed?.storageFailed == true,"observer exposes persistence failure")
 }
 static func offAndStop() async throws {
  let s = MemoryMonitorStore(), c = TestClock(); let n = FakeMonitorTransport(s), m = try monitor(s,n,c)
  await m.startScheduler(); await m.refresh(.automatic)
  check(await n.count() == 0,"Off blocks automatic startup")
  await n.enqueue([response(.board,c)])
  await m.refresh(.manual)
  check(await n.count() == 1,"manual Off one request")
  check(await m.snapshot().settings.mode == .off,"manual remains Off")
  await n.delay()
  let pending = Task { await m.refresh(.manual) }
  while await n.count() < 2 { await Task.yield() }
  await m.refresh(.manual)
  check(await n.count() == 2,"overlap single flight")
  await m.stop()
  let stopped = await m.snapshot()
  await n.release(response(.comments,c,body:"[\(row(1,c.now))]")); await pending.value
  check(await m.snapshot().cursor == stopped.cursor,"late response cannot advance cursor")
  check(await m.snapshot().events.count == stopped.events.count,"late response cannot log success")
  let restarted = try monitor(s,n,c); await restarted.refresh(.automatic)
  check(await n.count() == 2,"restart retains Stop")
  check(await n.reservedBeforeRead,"reservation saved before dispatch")
 }
 static func pagination() async throws {
  let s = MemoryMonitorStore(), c = TestClock(); let n = FakeMonitorTransport(s), m = try monitor(s,n,c)
  _ = await m.startFast()
  var replies = [response(.board,c)]
  for page in 1...3 {
   let next = MeetingData.monitorRead(.comments,page:page+1)!.url.absoluteString
   replies.append(response(.comments,c,page:page,body:"[\(row(page,c.now.addingTimeInterval(-10)))]",extra:["Link":"<\(next)>; rel=\"next\""]))
  }
  await n.enqueue(replies); await m.refresh(.automatic)
  check(await n.count() == 4,"one board plus three pages max")
  check(await m.snapshot().cursor.watermark == nil,"partial batch does not advance watermark")
  check(await m.snapshot().batch?.nextPage == 4,"continuation persisted")
  check(await m.snapshot().unread.isEmpty,"baseline quiet")
  let restart = try monitor(s,n,c); c.advance(300)
  await n.enqueue([response(.board,c),response(.comments,c,page:4,body:"[\(row(4,c.now.addingTimeInterval(-310)))]")])
  await restart.refresh(.automatic)
  let baseline = await restart.snapshot()
  check(baseline.cursor.known.count == 4 && baseline.batch == nil,"restart completes baseline without gaps")
  check(baseline.unread.isEmpty,"full baseline still quiet")
  c.advance(300)
  await n.enqueue([response(.board,c),response(.comments,c,since:baseline.cursor.watermark!.addingTimeInterval(-60),body:"[\(row(5,c.now))]")])
  await restart.refresh(.automatic)
  check(await restart.snapshot().unread == ["comment:5:new"],"new revision unread once")
  let encoded = String(data:try JSONEncoder().encode(await restart.snapshot()),encoding:.utf8)!
  check(!encoded.contains("private-test-body") && !encoded.contains("ETag"),"persistence excludes payloads and headers")
 }
 static func limitsAndStorage() async throws {
  let s = MemoryMonitorStore(), c = TestClock(); let n = FakeMonitorTransport(s), m = try monitor(s,n,c)
  await n.enqueue([response(.board,c,status:429,extra:["Retry-After":"600"])])
  await m.refresh(.manual); await m.refresh(.manual)
  check(await n.count() == 1,"server backoff applies to manual")
  _ = await m.startFast(); await m.refresh(.automatic)
  check(await n.count() == 1,"server backoff shared across both sources")
  let z = MemoryMonitorStore(); let zn = FakeMonitorTransport(z), zm = try monitor(z,zn,c)
  await zn.enqueue([response(.board,c,extra:["X-RateLimit-Remaining":"0"])])
  await zm.refresh(.manual); await zm.refresh(.manual)
  check(await zn.count() == 1,"zero remaining without reset fails closed")
  let s2 = MemoryMonitorStore(); s2.value.budget.attempts = Array(repeating:c.now,count:30)
  let n2 = FakeMonitorTransport(s2), m2 = try monitor(s2,n2,c)
  await m2.refresh(.manual); check(await n2.count() == 0,"anonymous 30 request cap")
  let s3 = MemoryMonitorStore(); let n3 = FakeMonitorTransport(s3), m3 = try monitor(s3,n3,c)
  s3.fail = true; await m3.refresh(.manual)
  let diskFailed = await m3.storageFailed
  check(await n3.count() == 0 && diskFailed,"storage failure blocks dispatch")
  let s4 = MemoryMonitorStore(); let n4 = FakeMonitorTransport(s4), m4 = try monitor(s4,n4,c)
  await n4.enqueue([response(.board,c)]); await m4.refresh(.manual); await n4.delay()
  let pending = Task { await m4.refresh(.manual) }
  while await n4.count() < 2 { await Task.yield() }
  s4.fail = true; await n4.release(response(.comments,c,body:"[\(row(1,c.now))]")); await pending.value
  check(await m4.snapshot().cursor.watermark == nil,"failed result persistence preserves cursor")
  check(await m4.storageFailed,"failed result persistence pauses")
  for bad in ["https://evil.example/x","https://api.github.com/repos/matthewferreira818/hotstuff/issues/15/comments?evil=1"] {
   let r = MeetingReadRequest(source:.comments,page:1,perPage:100,since:nil,url:URL(string:bad)!)
   check(!MeetingMonitorHTTP.allowed(r),"strict canonical transport URL")
  }
 }
 static func cachingAndLease() async throws {
  let s = MemoryMonitorStore(), c = TestClock(); let n = FakeMonitorTransport(s), m = try monitor(s,n,c)
  _ = await m.startFast(seconds:600)
  await n.enqueue([response(.board,c,extra:["ETag":"test"]),response(.comments,c)])
  await m.refresh(.automatic); c.advance(300)
  let since = await m.snapshot().cursor.watermark!.addingTimeInterval(-60)
  await n.enqueue([response(.board,c,status:304),response(.comments,c,since:since)])
  await m.refresh(.automatic)
  check(await m.snapshot().board.lastSuccessfulCheck == c.now,"304 refreshes success timestamp")
  check(await n.etags[2] == "test","validator only with memory payload")
  c.advance(301); await m.refresh(.automatic)
  check(await m.snapshot().settings.mode == .hourly,"lease expires to hourly")
  let restart = try monitor(s,n,c)
  await n.enqueue([response(.board,c,status:304)])
  await restart.refresh(.manual)
  check(await n.etags.last! == nil,"restart has no memory validator")
  check(await restart.snapshot().board.lastSuccessfulCheck != c.now,"uncached 304 is not success")
  var state = MeetingMonitorState()
  for _ in 0..<250 { state.log(.checked,at:c.now) }
  check(state.events.count == 200,"audit capped at 200")
 }
 static func privateFile() throws {
  let dir = FileManager.default.temporaryDirectory.appendingPathComponent("helm-monitor-test-" + UUID().uuidString)
  defer { try? FileManager.default.removeItem(at:dir) }
  let file = try MeetingMonitorFileStorage(directory:dir)
  var s = try file.load(); s.settings.stop(); try file.save(s)
  check(try file.load().settings.mode == .off,"private file roundtrip")
  let attr = try FileManager.default.attributesOfItem(atPath:dir.appendingPathComponent("state.json").path)
  check((attr[.posixPermissions] as? NSNumber)?.intValue == 0o600,"file owner only")
  try Data("corrupt".utf8).write(to:dir.appendingPathComponent("state.json"))
  do { _ = try file.load(); check(false,"corrupt state must not reset budget") } catch {}
 }
}
