import Foundation

// Clips from PAST streams (VODs): the pure parts, with no Mac frameworks so they can be tested anywhere. Twitch calls checked against
// dev.twitch.tv/docs/api/reference on 2026-10-05:
//   GET  /videos?user_id=&type=archive&first=     the channel's past streams (type archive); duration like "3h12m5s"
//   GET  /streams/markers?video_id=               the markers dropped during that stream (channel:manage:broadcast)
//   POST /videos/clips?editor_id=&broadcaster_id=&vod_id=&vod_offset=&duration=&title=
//        makes a clip from a past stream (editor:manage:clips or channel:manage:clips). vod_offset is where the clip ENDS, in
//        seconds from the start of the video; it must be at least the duration; duration 5 to 60; title is required.
// A Twitch clip is public the moment it exists, so these only run when Matthew asks.

struct VodRow: Identifiable, Equatable {
 var id: String
 var title: String
 var created: Date?
 var seconds: Int
 var views: Int
 var url: String
}

struct VodMarker: Equatable {
 var id: String
 var seconds: Int
 var note: String
}

enum VodPlan {
 static let minClip = 5.0
 static let maxClip = 60.0
 static let defaultClip = 30.0
 // How many moments one "clip my marked moments" run will clip, so one tap can't flood the channel with clips.
 static let maxPerBatch = 8
 // A marker is the moment he noticed something, so the clip runs up to a few seconds AFTER it.
 static let afterMarker = 8

 static func parseVideos(_ json: [String:Any]) -> [VodRow] {
  StreamData.rows(json).compactMap { row in
   guard let id = row["id"] as? String, let url = row["url"] as? String else { return nil }
   return VodRow(id:id,title:row["title"] as? String ?? "(untitled)",created:StreamData.date(row["created_at"]),seconds:parseDuration(row["duration"] as? String ?? "") ?? 0,views:row["view_count"] as? Int ?? 0,url:url)
  }
 }

 static func parseMarkers(_ json: [String:Any]) -> [VodMarker] {
  var found: [VodMarker] = []
  for user in StreamData.rows(json) {
   for video in (user["videos"] as? [[String:Any]]) ?? [] {
    for marker in (video["markers"] as? [[String:Any]]) ?? [] {
     guard let id = marker["id"] as? String, let at = marker["position_seconds"] as? Int else { continue }
     found.append(VodMarker(id:id,seconds:at,note:(marker["description"] as? String) ?? ""))
    }
   }
  }
  return found.sorted { $0.seconds < $1.seconds }
 }

 // "3h12m5s", "45m10s", "30s". nil if it is not that shape.
 static func parseDuration(_ text: String) -> Int? {
  let clean = text.lowercased().replacingOccurrences(of:" ",with:"")
  guard !clean.isEmpty, let regex = try? NSRegularExpression(pattern:"^(?:(\\d+)h)?(?:(\\d+)m)?(?:(\\d+)s)?$") else { return nil }
  let range = NSRange(clean.startIndex..<clean.endIndex,in:clean)
  guard let match = regex.firstMatch(in:clean,options:[],range:range) else { return nil }
  func part(_ i: Int) -> Int {
   guard let r = Range(match.range(at:i),in:clean) else { return 0 }
   return Int(clean[r]) ?? 0
  }
  let total = part(1) * 3600 + part(2) * 60 + part(3)
  return total > 0 ? total : nil
 }

 // 3725 becomes "1:02:05"; 125 becomes "2:05".
 static func clock(_ seconds: Int) -> String {
  let s = max(0,seconds)
  let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
  return h > 0 ? String(format:"%d:%02d:%02d",h,m,sec) : String(format:"%d:%02d",m,sec)
 }

 // What Matthew or Friday might say for a time in a stream: "1:12:30", "72:30", "45", "1h12m", "12 minutes". A bare number is seconds.
 static func parseClock(_ text: String) -> Int? {
  var clean = text.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
  guard !clean.isEmpty else { return nil }
  if clean.contains(":") {
   let parts = clean.split(separator:":",omittingEmptySubsequences:false).map { Int($0.trimmingCharacters(in:.whitespaces)) }
   guard parts.count <= 3, !parts.contains(where: { $0 == nil }) else { return nil }
   let values = parts.compactMap { $0 }
   guard values.allSatisfy({ $0 >= 0 }) else { return nil }
   return values.reduce(0) { $0 * 60 + $1 }
  }
  if let plain = Int(clean) { return plain >= 0 ? plain : nil }
  for (word,short) in [("hours","h"),("hour","h"),("hrs","h"),("hr","h"),("minutes","m"),("minute","m"),("mins","m"),("min","m"),("seconds","s"),("second","s"),("secs","s"),("sec","s")] {
   clean = clean.replacingOccurrences(of:word,with:short)
  }
  return parseDuration(clean)
 }

 // Where the clip ends and how long it is, kept inside what Twitch allows and inside the video. nil if the video is too short.
 static func plan(endAt: Int,duration: Double,vodSeconds: Int) -> (offset: Int,duration: Double)? {
  let length = min(maxClip,max(minClip,duration))
  guard vodSeconds >= Int(length.rounded(.up)) else { return nil }
  let end = min(vodSeconds,max(endAt,Int(length.rounded(.up))))
  return (end,length)
 }

 static func markerEnd(_ marker: Int,vodSeconds: Int) -> Int { min(vodSeconds,marker + afterMarker) }

 // "latest" (or nothing), a number from the list (1 is the newest), or part of a stream's title.
 static func pickVod(_ vods: [VodRow],which raw: String) -> VodRow? {
  let want = raw.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
  if want.isEmpty || ["latest","last","newest","recent","most recent","last stream","latest stream"].contains(want) { return vods.first }
  if let n = Int(want), n >= 1, n <= vods.count { return vods[n - 1] }
  return vods.first { $0.title.lowercased().contains(want) }
 }

 static func clipPath(editor: String,broadcaster: String,vod: String,offset: Int,duration: Double,title: String) -> String {
  let name = String(title.trimmingCharacters(in:.whitespacesAndNewlines).prefix(100))
  let shown = name.isEmpty ? "Moment" : name
  return "/videos/clips?editor_id=\(editor)&broadcaster_id=\(broadcaster)&vod_id=\(vod)&vod_offset=\(offset)&duration=\(duration)&title=\(StreamData.encoded(shown))"
 }

 static func explain(code: Int,message: String?) -> String {
  switch code {
  case 401: return "Twitch needs a permission this login doesn't have. Open Accounts, sign out of Twitch, then sign in again."
  case 403: return "Twitch won't allow this clip: clips may be limited to followers or subscribers, switched off, or this account isn't allowed to clip your channel (a separate clip account must be made an Editor)."
  case 404: return "Twitch can't find that video. Past streams are deleted after a while, so it may have expired."
  case 429: return "Twitch says slow down. Try again in a minute."
  case 400:
   let reason = (message ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
   return reason.isEmpty ? "Twitch didn't accept that clip." : "Twitch didn't accept that clip: \(reason)"
  default: return "Couldn't make the clip (Twitch answered \(code))."
  }
 }
}
