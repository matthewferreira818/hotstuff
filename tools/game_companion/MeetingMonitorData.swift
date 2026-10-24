import Foundation

// Offline policy only. No transport, timers, storage, credentials or posting. The coordinator must persist a candidate
// before using it, reserve every request (including manual/retry/page/304 requests), and reject results after Stop.
enum MeetingMonitorMode: String, Codable { case off, hourly, task }

enum MeetingMonitorAccess: String, Codable {
 case anonymous, authenticated
 var taskInterval: TimeInterval { self == .authenticated ? 60 : 300 }
 var hourlyRequestLimit: Int { self == .authenticated ? 180 : 30 }
}

enum MeetingMonitorTime {
 static func valid(_ date: Date) -> Bool { date.timeIntervalSinceReferenceDate.isFinite }
 static func latest(_ dates: [Date?]) -> Date? { dates.compactMap { $0 }.filter { valid($0) }.max() }
}

struct MeetingMonitorLease: Codable, Equatable {
 var taskID: String
 var startedAt: Date
 var expiresAt: Date
 func isValid(at now: Date) -> Bool {
  let length = expiresAt.timeIntervalSince(startedAt)
  return !taskID.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && MeetingMonitorTime.valid(now)
   && MeetingMonitorTime.valid(startedAt) && MeetingMonitorTime.valid(expiresAt)
   && length > 0 && length <= 7200 && now >= startedAt && now < expiresAt
 }
}

struct MeetingMonitorSettings: Codable, Equatable {
 var mode: MeetingMonitorMode = .off
 var lease: MeetingMonitorLease?
 var generation: UInt64 = 0
 var lastObservedAt: Date?

 mutating func stop() { mode = .off; lease = nil; generation &+= 1 }
 mutating func enableHourly() { mode = .hourly; lease = nil; generation &+= 1 }

 // Called only by an explicit local task-start action, never as part of polling or restoring state.
 @discardableResult mutating func startTask(id: String,now: Date,seconds: TimeInterval = 7200) -> Bool {
  guard seconds.isFinite && seconds > 0 && seconds <= 7200 else { return false }
  let next = MeetingMonitorLease(taskID:id,startedAt:now,expiresAt:now.addingTimeInterval(seconds))
  guard next.isValid(at:now) else { return false }
  mode = .task; lease = next; lastObservedAt = now; generation &+= 1
  return true
 }

 @discardableResult mutating func completeTask(id: String) -> Bool {
  guard mode == .task, lease?.taskID == id else { return false }
  enableHourly()
  return true
 }

 // The coordinator supplies clockChanged for wall-clock/monotonic discrepancies. A backwards wall clock is also
 // detected here. A date alone cannot prove whether a forward jump was a clock change or normal sleep.
 mutating func normalize(now: Date,clockChanged: Bool = false) {
  let backwards = lastObservedAt.map { now < $0 } ?? false
  if mode == .off { lease = nil }
  else if mode == .task && (clockChanged || backwards || lease?.isValid(at:now) != true) { enableHourly() }
  if MeetingMonitorTime.valid(now) { lastObservedAt = now }
 }

 mutating func interval(access: MeetingMonitorAccess,now: Date,clockChanged: Bool = false) -> TimeInterval? {
  normalize(now:now,clockChanged:clockChanged)
  switch mode { case .off: return nil; case .hourly: return 3600; case .task: return access.taskInterval }
 }

 func accepts(generation candidate: UInt64) -> Bool { mode != .off && generation == candidate }
}

enum MeetingMonitorGate: Equatable {
 case ready
 case waitUntil(Date)
 case attention
}

struct MeetingMonitorRequestBudget: Codable, Equatable {
 // Shared across both sources and all request purposes. Changing access never clears this ledger. Future entries
 // survive a backwards clock; a reboot/crash cannot turn previously reserved requests into free capacity.
 var attempts: [Date] = []
 // GitHub token/IP rate limits apply to both endpoints and every request purpose. A successful response with zero
 // remaining capacity must also feed its normalized reset hint through recordServerLimits before body processing.
 var serverNotBefore: Date?

 mutating func recordServerLimits(retryAfter: Date? = nil,resetAt: Date? = nil) {
  let dates = [serverNotBefore,retryAfter,resetAt].compactMap { $0 }
  guard dates.allSatisfy({ MeetingMonitorTime.valid($0) }) else { serverNotBefore = .distantFuture; return }
  serverNotBefore = MeetingMonitorTime.latest([serverNotBefore,retryAfter,resetAt?.addingTimeInterval(5)])
 }

 func nextAllowed(access: MeetingMonitorAccess,now: Date) -> Date? {
  guard MeetingMonitorTime.valid(now), attempts.allSatisfy({ MeetingMonitorTime.valid($0) }),
        serverNotBefore.map({ MeetingMonitorTime.valid($0) }) ?? true else { return .distantFuture }
  let live = attempts.filter { $0 > now.addingTimeInterval(-3600) }.sorted()
  let local: Date? = live.count >= access.hourlyRequestLimit ? live[live.count - access.hourlyRequestLimit].addingTimeInterval(3600) : nil
  let server = serverNotBefore.flatMap { $0 > now ? $0 : nil }
  return MeetingMonitorTime.latest([local,server])
 }

 // Persist this mutated value before dispatch. Do not undo a reservation when a request fails or is cancelled.
 @discardableResult mutating func reserve(access: MeetingMonitorAccess,now: Date) -> Bool {
  guard nextAllowed(access:access,now:now) == nil else { return false }
  attempts.removeAll { $0 <= now.addingTimeInterval(-3600) }
  attempts.append(now)
  return true
 }
}

enum MeetingMonitorFailure {
 case transient
 case rateLimited(retryAfter: Date?,resetAt: Date?)
 case inaccessible
}

enum MeetingMonitorUnchangedResult: Equatable { case successful, fullFetchRequired }

struct MeetingMonitorEndpointState: Codable, Equatable {
 var lastSuccessfulCheck: Date?
 var lastContentChange: Date?
 var contentDigest: String?
 var nextAllowedCheck: Date?
 var consecutiveFailures = 0
 var requiresAttention = false

 mutating func receivedContent(digest: String,now: Date,serverNotBefore: Date? = nil) {
  nextAllowedCheck = MeetingMonitorTime.latest([nextAllowedCheck,serverNotBefore])
  guard MeetingMonitorTime.valid(now), !digest.isEmpty else { return }
  if contentDigest != digest { lastContentChange = now }
  contentDigest = digest
  succeeded(now:now,serverNotBefore:serverNotBefore)
 }

 // Matching cache means the same endpoint URL, representation, validator and a usable local snapshot. A naked 304
 // is not a successful check. The subsequent full fetch still passes the shared budget and endpoint gate.
 mutating func receivedUnchanged(hasMatchingCache: Bool,now: Date,serverNotBefore: Date? = nil) -> MeetingMonitorUnchangedResult {
  nextAllowedCheck = MeetingMonitorTime.latest([nextAllowedCheck,serverNotBefore])
  guard hasMatchingCache, contentDigest != nil, MeetingMonitorTime.valid(now) else { return .fullFetchRequired }
  succeeded(now:now,serverNotBefore:serverNotBefore)
  return .successful
 }

 private mutating func succeeded(now: Date,serverNotBefore: Date?) {
  lastSuccessfulCheck = now; consecutiveFailures = 0; requiresAttention = false
  nextAllowedCheck = MeetingMonitorTime.latest([serverNotBefore])
 }

 mutating func failed(_ failure: MeetingMonitorFailure,now: Date,budget: inout MeetingMonitorRequestBudget) {
  if case let .rateLimited(retryAfter,resetAt) = failure { budget.recordServerLimits(retryAfter:retryAfter,resetAt:resetAt) }
  guard MeetingMonitorTime.valid(now) else { requiresAttention = true; return }
  consecutiveFailures = min(max(consecutiveFailures,0),4) + 1
  if case .inaccessible = failure { requiresAttention = true; return }
  let delay = min(60 * pow(2,Double(consecutiveFailures - 1)),900)
  let deadline = now.addingTimeInterval(delay)
  if case .rateLimited = failure { budget.recordServerLimits(retryAfter:deadline) }
  nextAllowedCheck = MeetingMonitorTime.latest([nextAllowedCheck,deadline])
  if consecutiveFailures >= 5 { requiresAttention = true }
 }

 func gate(budget: MeetingMonitorRequestBudget,access: MeetingMonitorAccess,now: Date) -> MeetingMonitorGate {
  guard !requiresAttention, MeetingMonitorTime.valid(now) else { return .attention }
  let deadline = MeetingMonitorTime.latest([nextAllowedCheck,budget.nextAllowed(access:access,now:now)])
  if let deadline = deadline, deadline > now { return .waitUntil(deadline) }
  return .ready
 }

 // Content can stay unchanged indefinitely. Freshness is about successful checks, never the age of the last change.
 func isStale(now: Date,maximumAge: TimeInterval) -> Bool {
  guard MeetingMonitorTime.valid(now), maximumAge.isFinite, maximumAge >= 0,
        let success = lastSuccessfulCheck, MeetingMonitorTime.valid(success), now >= success else { return true }
  return now.timeIntervalSince(success) > maximumAge
 }
}

struct MeetingMonitorCommentRevision: Codable, Equatable {
 var id: Int64
 var createdAt: Date
 var updatedAt: Date
 // Stable raw-content digest supplied by transport; never Swift hashValue and never a message body.
 var digest: String
 var isValid: Bool {
  id > 0 && !digest.isEmpty && MeetingMonitorTime.valid(createdAt) && MeetingMonitorTime.valid(updatedAt) && updatedAt >= createdAt
 }
}

enum MeetingMonitorCommentChangeKind: String, Codable { case new, edited }

struct MeetingMonitorCommentChange: Codable, Equatable {
 var id: Int64
 var kind: MeetingMonitorCommentChangeKind
 var eventID: String
}

enum MeetingMonitorBatchError: Error, Equatable { case invalidPage, turnLimit, invalidRevision }

struct MeetingMonitorCommentBatch: Codable, Equatable {
 var baseVersion: UInt64
 var since: Date?
 // A validated server timestamp anchored at the first response. Never move this to a later row's updated_at.
 var cutoff: Date
 var nextPage: Int? = 1
 var pagesThisTurn = 0
 var hasReadPage = false
 var staged: [Int64:MeetingMonitorCommentRevision] = [:]

 // A scheduler turn can fetch at most three pages. Resuming does not change since/cutoff or advance the cursor.
 mutating func beginTurn() { pagesThisTurn = 0 }

 mutating func append(_ revisions: [MeetingMonitorCommentRevision],page: Int,next: Int?) throws {
  guard pagesThisTurn >= 0 && pagesThisTurn < 3 else { throw MeetingMonitorBatchError.turnLimit }
  guard page > 0, nextPage == page, next.map({ $0 > page }) ?? true else { throw MeetingMonitorBatchError.invalidPage }
  guard revisions.allSatisfy({ $0.isValid }) else { throw MeetingMonitorBatchError.invalidRevision }
  for revision in revisions {
   if let prior = staged[revision.id], prior.updatedAt > revision.updatedAt { continue }
   staged[revision.id] = revision
  }
  nextPage = next; pagesThisTurn += 1; hasReadPage = true
 }
}

struct MeetingMonitorCursorUpdate: Equatable {
 var cursor: MeetingMonitorCommentCursor
 var changes: [MeetingMonitorCommentChange]
}

struct MeetingMonitorCommentCursor: Codable, Equatable {
 var version: UInt64 = 0
 var baselineAt: Date?
 var watermark: Date?
 // Keep comment dedupe independently of the later 200-event audit retention; dropping old IDs makes old edits look new.
 var known: [Int64:MeetingMonitorCommentRevision] = [:]

 func beginBatch(serverCutoff: Date) -> MeetingMonitorCommentBatch? {
  guard MeetingMonitorTime.valid(serverCutoff), watermark.map({ serverCutoff >= $0 }) ?? true else { return nil }
  return MeetingMonitorCommentBatch(baseVersion:version,since:watermark?.addingTimeInterval(-60),cutoff:serverCutoff)
 }

 // Return a new candidate only for a complete batch. Persist snapshot/cursor/events together before adopting it;
 // failure leaves this cursor unchanged and replay produces identical event IDs. No notification decision lives here.
 func finishing(_ batch: MeetingMonitorCommentBatch) -> MeetingMonitorCursorUpdate? {
  guard batch.baseVersion == version, batch.nextPage == nil, batch.hasReadPage,
        batch.since == watermark?.addingTimeInterval(-60), MeetingMonitorTime.valid(batch.cutoff),
        watermark.map({ batch.cutoff >= $0 }) ?? true, batch.staged.values.allSatisfy({ $0.isValid }) else { return nil }
  var candidate = self
  var changes: [MeetingMonitorCommentChange] = []
  for revision in batch.staged.values.sorted(by:{ $0.id < $1.id }) {
   let prior = known[revision.id]
   if let prior = prior, prior.updatedAt > revision.updatedAt { continue }
   candidate.known[revision.id] = revision
   guard let baseline = baselineAt else { continue } // the entire first complete sync is a silent baseline
   let kind: MeetingMonitorCommentChangeKind
   if let prior = prior {
    guard prior.digest != revision.digest else { continue }
    kind = .edited
   } else {
    // GitHub timestamps have second precision. An unseen ID equal to the baseline second may have arrived after
    // the baseline response: count it as new to avoid a permanent miss. Equal-second history is ambiguous and may
    // therefore also count once; strictly older historical discoveries stay silent.
    guard revision.createdAt >= baseline else { continue }
    kind = .new
   }
   let event: String
   if kind == .new { event = "comment:\(revision.id):new" }
   else {
    let stamp = String(revision.updatedAt.timeIntervalSince1970.bitPattern,radix:16)
    event = "comment:\(revision.id):edit:\(stamp):\(revision.digest.utf8.count):\(revision.digest)"
   }
   changes.append(MeetingMonitorCommentChange(id:revision.id,kind:kind,eventID:event))
  }
  candidate.baselineAt = baselineAt ?? batch.cutoff
  candidate.watermark = batch.cutoff
  candidate.version &+= 1
  return MeetingMonitorCursorUpdate(cursor:candidate,changes:changes)
 }
}
