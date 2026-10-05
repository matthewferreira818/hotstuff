import Foundation

// The pieces of the Stream page that need no Mac frameworks, so they can be tested anywhere: reading Twitch's answers and
// turning Twitch's error codes into plain words. The calls themselves are made by StreamHub (StreamManager.swift) with the
// saved Twitch login. Endpoints and permissions checked against dev.twitch.tv/docs/api/reference on 2026-10-05:
//   GET /streams            who is live, title, category, viewers, start time       (any login)
//   GET /channels           current title and category, live or not                 (any login)
//   GET /channels/followers the total follower count                                (any login; the list needs more)
//   GET /clips              the channel's clips                                     (any login)
//   GET /search/categories  find a game or category by name                         (any login)
//   PATCH /channels         change title and category                               (channel:manage:broadcast, own channel)
//   POST /streams/markers   mark a moment of a live stream                          (channel:manage:broadcast, live with VODs on)
// Nothing here starts or stops a stream: Twitch doesn't let apps do that, only the streaming software (OBS, Streamlabs) can.

struct StreamLive {
 var title: String
 var game: String
 var viewers: Int
 var startedAt: Date?
}

struct ChannelInfo {
 var id: String
 var login: String
 var name: String
 var title: String
 var gameID: String
 var gameName: String
}

struct CategoryHit: Identifiable, Equatable {
 var id: String
 var name: String
}

struct ClipRow: Identifiable {
 var id: String
 var title: String
 var url: String
 var views: Int
 var seconds: Double
 var created: Date?
}

// A saved title and category the Stream page can fill in with one click.
struct StreamPreset: Codable, Identifiable, Equatable {
 var id: String
 var name: String
 var title: String
 var gameID: String
 var gameName: String
}

enum StreamData {
 static let titleLimit = 140

 // Twitch wraps every list in {"data":[...]}.
 static func rows(_ json: [String:Any]) -> [[String:Any]] { (json["data"] as? [[String:Any]]) ?? [] }

 static func date(_ text: Any?) -> Date? {
  guard let text = text as? String else { return nil }
  return ISO8601DateFormatter().date(from:text)
 }

 // An empty list means the channel is offline, so this returns nil.
 static func parseStream(_ json: [String:Any]) -> StreamLive? {
  guard let row = rows(json).first, (row["type"] as? String ?? "live") == "live" else { return nil }
  return StreamLive(title:row["title"] as? String ?? "",game:row["game_name"] as? String ?? "",viewers:row["viewer_count"] as? Int ?? 0,startedAt:date(row["started_at"]))
 }

 static func parseChannel(_ json: [String:Any]) -> ChannelInfo? {
  guard let row = rows(json).first, let id = row["broadcaster_id"] as? String else { return nil }
  return ChannelInfo(id:id,login:row["broadcaster_login"] as? String ?? "",name:row["broadcaster_name"] as? String ?? "",title:row["title"] as? String ?? "",gameID:row["game_id"] as? String ?? "",gameName:row["game_name"] as? String ?? "")
 }

 static func parseCategories(_ json: [String:Any]) -> [CategoryHit] {
  rows(json).compactMap { row in
   guard let id = row["id"] as? String, let name = row["name"] as? String, !id.isEmpty else { return nil }
   return CategoryHit(id:id,name:name)
  }
 }

 static func parseClips(_ json: [String:Any]) -> [ClipRow] {
  rows(json).compactMap { row in
   guard let id = row["id"] as? String, let url = row["url"] as? String else { return nil }
   return ClipRow(id:id,title:row["title"] as? String ?? "(untitled)",url:url,views:row["view_count"] as? Int ?? 0,seconds:(row["duration"] as? Double) ?? Double(row["duration"] as? Int ?? 0),created:date(row["created_at"]))
  }
 }

 static func parseFollowerTotal(_ json: [String:Any]) -> Int? { json["total"] as? Int }

 // "2h 14m", "7m", "just started".
 static func uptime(from start: Date,to now: Date) -> String {
  let seconds = max(0,Int(now.timeIntervalSince(start)))
  return seconds < 60 ? "just started" : duration(seconds)
 }

 // "1h 02m" for a long stretch, "7m" for a short one.
 static func duration(_ total: Int) -> String {
  let seconds = max(0,total)
  let hours = seconds / 3600
  let minutes = (seconds % 3600) / 60
  if hours > 0 { return "\(hours)h \(minutes < 10 ? "0" : "")\(minutes)m" }
  return "\(minutes)m"
 }

 // Twitch won't take an empty title, and stops at 140 characters.
 static func titleProblem(_ raw: String) -> String? {
  let title = raw.trimmingCharacters(in:.whitespacesAndNewlines)
  if title.isEmpty { return "Type a title first. Twitch doesn't allow an empty one." }
  if title.count > titleLimit { return "That title is \(title.count) characters. Twitch's limit is \(titleLimit)." }
  return nil
 }

 // The category is only sent when one is chosen, so a title-only change never clears the category.
 static func updateBody(title: String,gameID: String?) -> Data? {
  var body: [String:Any] = ["title":title.trimmingCharacters(in:.whitespacesAndNewlines)]
  if let id = gameID, !id.isEmpty { body["game_id"] = id }
  return try? JSONSerialization.data(withJSONObject:body)
 }

 static func markerBody(userID: String,note: String) -> Data? {
  var body: [String:Any] = ["user_id":userID]
  let text = String(note.trimmingCharacters(in:.whitespacesAndNewlines).prefix(140))
  if !text.isEmpty { body["description"] = text }
  return try? JSONSerialization.data(withJSONObject:body)
 }

 static let queryAllowed = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

 static func encoded(_ text: String) -> String { text.addingPercentEncoding(withAllowedCharacters:queryAllowed) ?? "" }

 // A Twitch refusal in plain words. `doing` finishes "Couldn't ...", for example "change the title".
 static func explain(code: Int,message: String?,doing: String) -> String {
  switch code {
  case 401: return "Twitch needs one more permission to \(doing). Open Accounts, sign out of Twitch, then sign in again."
  case 403: return "Twitch won't let this account \(doing). Sign in as the account that owns the channel."
  case 404: return "Twitch couldn't \(doing). For a marker, you must be live with past broadcasts (VODs) switched on."
  case 429: return "Twitch says slow down. Try again in a minute."
  case 400:
   let reason = (message ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
   return reason.isEmpty ? "Twitch didn't accept that." : "Twitch didn't accept that: \(reason)"
  default: return "Couldn't \(doing) (Twitch answered \(code))."
  }
 }
}
