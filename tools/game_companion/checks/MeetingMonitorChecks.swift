import Foundation

// Standalone, deterministic and offline. Run on Linux BEFORE compiling this slice on the Mac:
// swiftc -parse-as-library MeetingMonitorData.swift checks/MeetingMonitorChecks.swift -o /tmp/meeting-monitor-checks
// /tmp/meeting-monitor-checks
@main struct MeetingMonitorChecks {
 static let start = Date(timeIntervalSince1970:1_800_000_000)
 static func at(_ seconds: TimeInterval) -> Date { start.addingTimeInterval(seconds) }
 static func roundTrip<T: Codable>(_ value: T) throws -> T {
  try JSONDecoder().decode(T.self,from:JSONEncoder().encode(value))
 }
 static func revision(_ id: Int64,created: TimeInterval = -100,updated: TimeInterval = -50,digest: String? = nil) -> MeetingMonitorCommentRevision {
  MeetingMonitorCommentRevision(id:id,createdAt:at(created),updatedAt:at(updated),digest:digest ?? "digest-\(id)")
 }

 static func main() throws {
  try settingsChecks()
  try budgetAndEndpointChecks()
  try cursorChecks()
  print("All Meeting Monitor checks passed (offline).")
 }

 static func settingsChecks() throws {
  var settings = MeetingMonitorSettings()
  precondition(settings.interval(access:.authenticated,now:at(0)) == nil,"Installation must default Off")
  precondition(!settings.startTask(id:"",now:at(0)) && !settings.startTask(id:"job",now:at(0),seconds:7201))
  precondition(!settings.startTask(id:"job",now:at(0),seconds:.nan) && settings.mode == .off)
  precondition(settings.startTask(id:"job",now:at(0)))
  precondition(settings.interval(access:.authenticated,now:at(1)) == 60)
  precondition(settings.interval(access:.anonymous,now:at(2)) == 300)
  let runningGeneration = settings.generation
  precondition(settings.accepts(generation:runningGeneration))
  settings.stop()
  settings = try roundTrip(settings)
  precondition(settings.mode == .off && settings.lease == nil && !settings.accepts(generation:runningGeneration),"Stop must survive relaunch and reject late results")
  precondition(!settings.completeTask(id:"job") && settings.mode == .off,"Old completion cannot re-enable monitoring")
  settings.lease = MeetingMonitorLease(taskID:"old",startedAt:at(-100),expiresAt:at(100))
  precondition(settings.interval(access:.anonymous,now:at(3)) == nil && settings.lease == nil,"Persisted Off wins over an orphaned lease")
  settings.enableHourly()
  precondition(settings.interval(access:.anonymous,now:at(4)) == 3600)
  precondition(settings.startTask(id:"job",now:at(10)))
  precondition(!settings.completeTask(id:"other") && settings.mode == .task)
  precondition(settings.completeTask(id:"job") && settings.interval(access:.authenticated,now:at(11)) == 3600)
  precondition(settings.startTask(id:"expiry",now:at(20)))
  settings = try roundTrip(settings)
  precondition(settings.interval(access:.authenticated,now:at(7219)) == 60)
  precondition(settings.interval(access:.authenticated,now:at(7220)) == 3600,"Exact expiry restores hourly without replaying missed ticks")
  precondition(settings.startTask(id:"clock",now:at(8000)))
  precondition(settings.interval(access:.authenticated,now:at(7999)) == 3600,"A backwards clock must end fast mode")
  precondition(settings.startTask(id:"clock",now:at(9000)))
  precondition(settings.interval(access:.authenticated,now:at(9001),clockChanged:true) == 3600)
  settings.mode = .task
  settings.lease = MeetingMonitorLease(taskID:"bad",startedAt:at(0),expiresAt:at(10000))
  precondition(settings.interval(access:.authenticated,now:at(9002)) == 3600,"A malformed restored lease must never extend fast mode")
 }

 static func budgetAndEndpointChecks() throws {
  var budget = MeetingMonitorRequestBudget()
  // All callers share these reservations; successful, failed and conditional requests are equally counted.
  for _ in 0..<180 { precondition(budget.reserve(access:.authenticated,now:at(0))) }
  precondition(!budget.reserve(access:.authenticated,now:at(3599)))
  precondition(budget.nextAllowed(access:.authenticated,now:at(1)) == at(3600))
  precondition(!budget.reserve(access:.anonymous,now:at(1)),"Switching credentials must not reset spent capacity")
  precondition(budget.reserve(access:.anonymous,now:at(3600)) && budget.attempts.count == 1,"The exact rolling-window boundary releases old attempts")
  for _ in 1..<30 { precondition(budget.reserve(access:.anonymous,now:at(3600))) }
  precondition(!budget.reserve(access:.anonymous,now:at(3600)))
  precondition(budget.nextAllowed(access:.anonymous,now:at(3500)) == at(7200),"A clock rollback must retain future reservations")

  var empty = MeetingMonitorEndpointState()
  precondition(empty.receivedUnchanged(hasMatchingCache:false,now:at(0)) == .fullFetchRequired)
  precondition(empty.lastSuccessfulCheck == nil && empty.isStale(now:at(0),maximumAge:3600))
  precondition(empty.receivedUnchanged(hasMatchingCache:true,now:at(0)) == .fullFetchRequired,"A claimed cache without a local digest is insufficient")
  empty.receivedContent(digest:"board-a",now:at(0))
  let originalChange = empty.lastContentChange
  for hour in 1...24 {
   precondition(empty.receivedUnchanged(hasMatchingCache:true,now:at(Double(hour) * 3600)) == .successful)
   precondition(!empty.isStale(now:at(Double(hour) * 3600 + 10),maximumAge:3600))
  }
  precondition(empty.lastContentChange == originalChange && empty.lastSuccessfulCheck == at(86400),"A quiet room for 24 hours is healthy when checks succeed")
  empty.receivedContent(digest:"board-a",now:at(86410))
  precondition(empty.lastContentChange == originalChange)
  empty.failed(.transient,now:at(86420),budget:&budget)
  precondition(empty.lastSuccessfulCheck == at(86410) && empty.contentDigest == "board-a","Failure preserves successful cached data")
  precondition(empty.isStale(now:at(90011),maximumAge:3600))

  var failing = MeetingMonitorEndpointState()
  for (index,delay) in [60.0,120,240,480,900].enumerated() {
   failing.failed(.transient,now:at(0),budget:&budget)
   precondition(failing.nextAllowedCheck == at(delay))
   precondition(failing.requiresAttention == (index == 4))
  }
  precondition(failing.gate(budget:MeetingMonitorRequestBudget(),access:.authenticated,now:at(1000)) == .attention)
  failing.receivedContent(digest:"recovered",now:at(1000))
  precondition(failing.consecutiveFailures == 0 && !failing.requiresAttention)
  precondition(empty.consecutiveFailures == 1,"Recovering one source cannot clear the other source's failure")
  failing.failed(.inaccessible,now:at(1001),budget:&budget)
  precondition(failing.requiresAttention)
  var corruptHigh = MeetingMonitorEndpointState()
  corruptHigh.consecutiveFailures = Int.max
  corruptHigh.failed(.transient,now:at(0),budget:&budget)
  precondition(corruptHigh.consecutiveFailures == 5 && corruptHigh.requiresAttention && corruptHigh.nextAllowedCheck == at(900))
  var corruptLow = MeetingMonitorEndpointState()
  corruptLow.consecutiveFailures = Int.min
  corruptLow.failed(.transient,now:at(0),budget:&budget)
  precondition(corruptLow.consecutiveFailures == 1 && corruptLow.nextAllowedCheck == at(60),"A malformed counter cannot produce immediate retries")
  precondition(budget.serverNotBefore == nil,"Ordinary source failures must not create a shared server block")

  var limited = MeetingMonitorEndpointState()
  limited.failed(.rateLimited(retryAfter:at(86400),resetAt:at(100)),now:at(0),budget:&budget)
  precondition(budget.serverNotBefore == at(86400),"A long server Retry-After must not be capped at fifteen minutes")
  precondition(limited.gate(budget:budget,access:.anonymous,now:at(3600)) == .waitUntil(at(86400)))
  let otherEndpoint = MeetingMonitorEndpointState()
  precondition(otherEndpoint.gate(budget:budget,access:.authenticated,now:at(3600)) == .waitUntil(at(86400)),"One source's rate limit must gate the other source")
  precondition(!budget.reserve(access:.authenticated,now:at(3600)),"Manual, retry and pagination reservations must obey the shared server deadline")
  limited.receivedContent(digest:"recovered-content",now:at(3601))
  precondition(budget.serverNotBefore == at(86400),"An unrelated successful response must not clear a shared rate deadline")
  budget.recordServerLimits(resetAt:at(200))
  precondition(budget.serverNotBefore == at(86400),"Shorter response hints must not shorten the shared deadline")
  precondition(budget.reserve(access:.authenticated,now:at(86400)),"Shared server deadline permits requests at the boundary")
  var fallbackBudget = MeetingMonitorRequestBudget()
  var noHint = MeetingMonitorEndpointState()
  noHint.failed(.rateLimited(retryAfter:nil,resetAt:nil),now:at(0),budget:&fallbackBudget)
  precondition(otherEndpoint.gate(budget:fallbackBudget,access:.authenticated,now:at(0)) == .waitUntil(at(60)),"Rate limits without hints must apply the fallback to both sources")
  precondition(!fallbackBudget.reserve(access:.authenticated,now:at(59)))
  noHint.failed(.rateLimited(retryAfter:at(61),resetAt:nil),now:at(60),budget:&fallbackBudget)
  precondition(otherEndpoint.gate(budget:fallbackBudget,access:.authenticated,now:at(60)) == .waitUntil(at(180)),"A short hint cannot bypass the shared escalating fallback")
  var shortBudget = MeetingMonitorRequestBudget()
  var shortHint = MeetingMonitorEndpointState()
  shortHint.failed(.rateLimited(retryAfter:at(5),resetAt:at(-10)),now:at(0),budget:&shortBudget)
  precondition(otherEndpoint.gate(budget:shortBudget,access:.anonymous,now:at(0)) == .waitUntil(at(60)),"Short or past hints still require the minimum shared backoff")
  var responseBudget = MeetingMonitorRequestBudget()
  responseBudget.recordServerLimits(resetAt:at(100))
  responseBudget = try roundTrip(responseBudget)
  precondition(!responseBudget.reserve(access:.anonymous,now:at(104)),"A zero-remaining hint on a successful response gates the next request too")
  precondition(responseBudget.reserve(access:.anonymous,now:at(105)))
  var corruptBudget = MeetingMonitorRequestBudget()
  corruptBudget.serverNotBefore = Date(timeIntervalSinceReferenceDate:.nan)
  precondition(!corruptBudget.reserve(access:.authenticated,now:at(0)),"Malformed persisted shared deadlines must fail closed")
  corruptBudget.recordServerLimits(resetAt:at(100))
  precondition(!corruptBudget.reserve(access:.authenticated,now:at(1000)),"A new hint must not quietly repair a malformed persisted deadline")
  var reset = MeetingMonitorEndpointState()
  var resetBudget = MeetingMonitorRequestBudget()
  reset.failed(.rateLimited(retryAfter:nil,resetAt:at(100)),now:at(0),budget:&resetBudget)
  precondition(resetBudget.serverNotBefore == at(105),"Rate reset includes a safety margin")
  reset.receivedContent(digest:"same",now:at(200),serverNotBefore:at(500))
  precondition(reset.gate(budget:MeetingMonitorRequestBudget(),access:.authenticated,now:at(499)) == .waitUntil(at(500)))
  precondition(reset.gate(budget:MeetingMonitorRequestBudget(),access:.authenticated,now:at(500)) == .ready)
  var uncached = MeetingMonitorEndpointState()
  precondition(uncached.receivedUnchanged(hasMatchingCache:false,now:at(0),serverNotBefore:at(3600)) == .fullFetchRequired)
  precondition(uncached.lastSuccessfulCheck == nil && uncached.gate(budget:MeetingMonitorRequestBudget(),access:.anonymous,now:at(0)) == .waitUntil(at(3600)),"Uncached 304 must preserve the poll hint without claiming success")
  var invalidContent = MeetingMonitorEndpointState()
  invalidContent.receivedContent(digest:"",now:at(0),serverNotBefore:at(3600))
  precondition(invalidContent.lastSuccessfulCheck == nil && invalidContent.gate(budget:MeetingMonitorRequestBudget(),access:.authenticated,now:at(1)) == .waitUntil(at(3600)),"Rejected content must still obey the response poll hint")
 }

 static func cursorChecks() throws {
  var cursor = MeetingMonitorCommentCursor()
  var baseline = cursor.beginBatch(serverCutoff:at(0))!
  for page in 1...3 {
   let first = (page - 1) * 100 + 1
   try baseline.append((first..<(first + 100)).map { revision(Int64($0)) },page:page,next:page + 1)
  }
  precondition(cursor.finishing(baseline) == nil && cursor.watermark == nil,"Partial sync cannot establish a baseline or advance its cursor")
  do {
   try baseline.append([revision(301)],page:4,next:nil)
   preconditionFailure("A fourth page in one scheduler turn must be refused")
  } catch MeetingMonitorBatchError.turnLimit { }
  baseline = try roundTrip(baseline)
  baseline.beginTurn()
  try baseline.append((301...320).map { revision(Int64($0)) },page:4,next:nil)
  let initial = cursor.finishing(baseline)!
  precondition(initial.changes.isEmpty && initial.cursor.known.count == 320,"A multi-page cold sync must not alert on history")
  cursor = try roundTrip(initial.cursor)
  precondition(cursor.baselineAt == at(0) && cursor.watermark == at(0))
  var boundary = cursor.beginBatch(serverCutoff:at(1))!
  try boundary.append([revision(401,created:0,updated:0),revision(402,created:-1,updated:0)],page:1,next:nil)
  let boundaryUpdate = cursor.finishing(boundary)!
  precondition(boundaryUpdate.changes.map { $0.id } == [401] && boundaryUpdate.changes.first?.kind == .new,"An unseen equal-second comment must not be permanently suppressed; older history stays silent")

  var batch = cursor.beginBatch(serverCutoff:at(100))!
  precondition(batch.since == at(-60))
  let oldEdit = revision(1,updated:10,digest:"edited-old-id")
  let newMessage = revision(321,created:70,updated:70)
  let afterCutoff = revision(322,created:200,updated:200)
  let historical = revision(400,created:-300,updated:60)
  try batch.append([oldEdit,newMessage,afterCutoff,historical],page:1,next:2)
  precondition(cursor.finishing(batch) == nil && cursor.watermark == at(0))
  let beforeBadPage = batch
  do {
   try batch.append([],page:3,next:nil)
   preconditionFailure("Out-of-order pages must be rejected")
  } catch MeetingMonitorBatchError.invalidPage { }
  precondition(batch == beforeBadPage,"Rejected pages must not mutate the batch")
  let sameSecondEdit = revision(2,digest:"different-content-same-timestamp")
  try batch.append([newMessage,sameSecondEdit],page:2,next:nil)
  let update = cursor.finishing(batch)!
  precondition(update.changes.map { $0.id } == [1,2,321,322])
  precondition(update.changes.map { $0.kind } == [.edited,.edited,.new,.new],"Older IDs and same-second edits are edits, not new messages")
  precondition(update.cursor.watermark == at(100),"Rows after the server cutoff must not move the watermark forward")
  precondition(update.cursor.known[400] == historical,"Historical discoveries are retained silently")
  var restoredComplete = try roundTrip(batch)
  restoredComplete.beginTurn()
  precondition(cursor.finishing(restoredComplete) == update,"A completed batch restored before adoption must replay even after a new scheduler turn")
  precondition(cursor.watermark == at(0),"Computing a candidate must not mutate the durable cursor")
  cursor = try roundTrip(update.cursor)
  precondition(cursor.finishing(batch) == nil,"A stale batch cannot overwrite a later committed cursor")
  precondition(cursor.beginBatch(serverCutoff:at(99)) == nil,"A server clock regression cannot rewind a watermark")

  var repeated = cursor.beginBatch(serverCutoff:at(300))!
  try repeated.append([oldEdit,newMessage,afterCutoff,historical,sameSecondEdit],page:1,next:nil)
  let replay = cursor.finishing(repeated)!
  precondition(replay.changes.isEmpty,"Overlapping polls cannot repeat events")
  cursor = replay.cursor
  var revisionBatch = cursor.beginBatch(serverCutoff:at(400))!
  try revisionBatch.append([revision(1,updated:5,digest:"older-response"),revision(2,digest:"another-same-second-edit"),revision(321,created:70,updated:350)],page:1,next:nil)
  let revisions = cursor.finishing(revisionBatch)!
  precondition(revisions.changes.map { $0.id } == [2])
  precondition(revisions.cursor.known[1] == oldEdit,"Late older responses must not roll a revision backwards")
  precondition(revisions.cursor.known[321]?.updatedAt == at(350),"Timestamp-only updates advance metadata without pretending content changed")
  var invalid = cursor.beginBatch(serverCutoff:at(500))!
  let beforeInvalid = invalid
  do {
   try invalid.append([revision(500,created:20,updated:10)],page:1,next:nil)
   preconditionFailure("Malformed revision metadata must reject the complete page")
  } catch MeetingMonitorBatchError.invalidRevision { }
  precondition(invalid == beforeInvalid)
  var quiet = MeetingMonitorCommentCursor().beginBatch(serverCutoff:at(0))!
  try quiet.append([],page:1,next:nil)
  precondition(MeetingMonitorCommentCursor().finishing(quiet)?.cursor.baselineAt == at(0),"An empty room is a valid silent baseline")
 }
}
