import Foundation

// Clip autopilot: the pure rules, with no Mac frameworks so they can be tested anywhere. Matthew's choice (2026-10-05): Friday may pick
// moments to clip without being asked, from three sources: the moments he marked (after each stream), exciting moments she notices
// live, and his viewers' best clips. Clips are public on Twitch the moment they exist, so every source has a hard cap.

enum AutopilotPlan {
 static let liveCapPerStream = 3          // live "exciting moment" clips in one stream
 static let liveGapSeconds = 300.0        // at least this long between two live clips
 static let viewerClipsPerRun = 2         // viewers' clips picked per run (one run every 6 hours at most)
 static let minViewerViews = 3            // a viewer clip needs at least this many views to count
 static let viewerWindowDays = 7.0
 static let ledgerLimit = 500

 // Which viewer clips to pick: recent, enough views, not already handled, best first, at most `limit`.
 static func pickViewerClips(_ clips: [ClipRow],handled: Set<String>,now: Date,limit: Int = viewerClipsPerRun,minViews: Int = minViewerViews) -> [ClipRow] {
  let cutoff = now.addingTimeInterval(-viewerWindowDays * 86_400)
  return Array(clips
   .filter { !handled.contains($0.id) && $0.views >= minViews && ($0.created ?? .distantPast) >= cutoff }
   .sorted { $0.views != $1.views ? $0.views > $1.views : ($0.created ?? .distantPast) > ($1.created ?? .distantPast) }
   .prefix(limit))
 }

 // Keeps a list of handled ids from growing forever: newest `limit` kept, no repeats.
 static func appendHandled(_ ids: [String],_ id: String,limit: Int = ledgerLimit) -> [String] {
  var next = ids.filter { $0 != id }
  next.append(id)
  return next.count > limit ? Array(next.suffix(limit)) : next
 }

 // A live clip may be made when autopilot has room left in this stream and the last one was long enough ago.
 static func canClipLive(count: Int,lastClip: Date?,now: Date) -> Bool {
  if count >= liveCapPerStream { return false }
  if let last = lastClip, now.timeIntervalSince(last) < liveGapSeconds { return false }
  return true
 }
}

// Notices an exciting moment from the sound of Matthew's own voice: a clear jump above how loud he normally is, held for a
// moment. Feed it the mic level (0 to 1) about every 0.2 seconds. It says true once per burst and then waits for him to calm down.
struct HypeDetector {
 var baseline = 0.06
 private var above = 0.0
 private var calm = 0.0
 private var armed = true
 static let holdSeconds = 0.8
 static let calmSeconds = 2.0
 static let floor = 0.45          // never fire below this level, however quiet the room is
 static let jump = 2.8            // and at least this many times his normal level

 mutating func feed(level raw: Double,dt: Double) -> Bool {
  let level = min(1,max(0,raw.isFinite ? raw : 0))
  let threshold = max(Self.floor,baseline * Self.jump)
  if level < threshold {
   // normal talking: learn how loud that is (slowly, so a burst doesn't raise it)
   baseline += (min(level,0.35) - baseline) * min(1,dt / 20)
   baseline = max(0.02,baseline)
   above = 0
   calm += dt
   if calm >= Self.calmSeconds { armed = true }
   return false
  }
  calm = 0
  above += dt
  if armed && above >= Self.holdSeconds {
   armed = false
   return true
  }
  return false
 }
}

// The caption saved next to each finished clip, ready to paste into TikTok. Only words that are true: the clip's own title and
// hashtags about the game it is from. No claims, no "link in bio".
enum TikTokPack {
 static func hashtags(game: String) -> [String] {
  let lower = game.lowercased()
  var tags: [String] = []
  if lower.contains("minecraft") { tags.append("#minecraft") }
  if lower.contains("dungeons") { tags.append("#minecraftdungeons") }
  return tags + ["#gaming","#twitch","#fyp"]
 }

 static func cleanTitle(_ raw: String) -> String {
  let words = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator:" ")
  return String(words.prefix(90))
 }

 static func caption(title raw: String,game: String) -> String {
  let title = cleanTitle(raw)
  let head = title.isEmpty || title.lowercased().hasPrefix("moment") ? "Clutch moment" : title
  return head + " 🔥\n\n" + hashtags(game:game).joined(separator:" ") + "\n"
 }
}
