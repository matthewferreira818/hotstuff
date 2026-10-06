import Foundation

// The Friday feed: a record of what Matthew and Friday say to each other, and what she does for him (a clip, a title change).
// This file is the part with no Mac frameworks, so it can be tested anywhere. The store and the page are in FridayFeed.swift.
// The feed is a record for Matthew. Friday does not read it back, and it never leaves the Mac except when he presses Copy.

struct FeedEntry: Codable, Identifiable, Equatable {
 var id: String
 var date: Date
 var who: String      // "you", "friday" or "action"
 var text: String
}

enum FeedFormat {
 static let keepEntries = 500
 static let maxLength = 1500

 // One line of plain words: runs of spaces and line breaks become one space, and a very long message is cut.
 static func clean(_ raw: String) -> String {
  let words = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator:" ")
  return String(words.prefix(maxLength))
 }

 // Adds one message. Empty ones are skipped, the same message twice within 30 seconds counts once, and only the newest
 // `keep` messages are kept.
 static func appending(_ entries: [FeedEntry],who: String,text raw: String,now: Date = Date(),keep: Int = keepEntries) -> [FeedEntry] {
  let text = clean(raw)
  guard !text.isEmpty else { return entries }
  if let last = entries.last, last.who == who, last.text == text, now.timeIntervalSince(last.date) < 30 { return entries }
  var next = entries
  next.append(FeedEntry(id:UUID().uuidString,date:now,who:who,text:text))
  if next.count > keep { next.removeFirst(next.count - keep) }
  return next
 }

 static func name(_ who: String) -> String {
  switch who {
  case "you": return "Matthew"
  case "friday": return "Friday"
  default: return "Action"
  }
 }

 // Plain text for pasting into a chat with Claude or GPT: one line per message, oldest first.
 static func transcript(_ entries: [FeedEntry],last count: Int? = nil) -> String {
  let slice = count.map { Array(entries.suffix($0)) } ?? entries
  let stamp = DateFormatter()
  stamp.locale = Locale(identifier:"en_US_POSIX")
  stamp.dateFormat = "yyyy-MM-dd HH:mm"
  return slice.map { "[\(stamp.string(from:$0.date))] \(name($0.who)): \($0.text)" }.joined(separator:"\n")
 }

 // A short label for what a tool did, shown on the feed.
 static func actionLabel(_ tool: String) -> String {
  switch tool {
  case "clip_that": return "Clip"
  case "stream_status": return "Stream check"
  case "set_stream_title": return "Title"
  case "set_stream_category": return "Category"
  case "use_stream_preset": return "Preset"
  case "mark_moment": return "Marker"
  case "lookup_game_wiki": return "Lookup"
  case "scroll_page": return "Scroll"
  case "clip_past_moment": return "Clip from stream"
  case "clip_marked_moments": return "Marked clips"
  case "narrate_clip": return "Voice-over"
  case "tell_the_team": return "To the team"
  case "team_messages": return "Team inbox"
  case "point_at": return "Pointer"
  case "click_at": return "Click"
  case "type_text": return "Typing"
  case "press_keys": return "Keys"
  default: return "Action"
  }
 }
}
