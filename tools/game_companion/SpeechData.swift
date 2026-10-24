import Foundation

// What the Meeting Room says out loud, and which voice says it. Foundation-only so it can be tested here; the speaking itself is
// in MeetingVoice.swift. This reads WRITTEN words (the board and each person's last post). It is not a live call, and it never puts a
// sentence in anyone's mouth: everything the app itself writes ("GPT's last post, 3 hours ago", "2 open items are under Claude's
// name") is read by the Narrator voice, and only a person's own posted words are read in that person's voice.

struct SpeakLine: Identifiable {
 var id: Int
 var speaker: String
 var text: String
}

enum SpeechData {
 static let crew = ["Claude","GPT","Friday"]
 static let speakers = ["Claude","GPT","Friday","Matthew","Narrator"]
 static let openingLine = "Board read-out. Your Mac is reading the board's items and each person's last post aloud, in a different voice for each. It is not a live call and nobody is speaking live."
 static let closingLine = "That is everything on the board."

 struct VoiceInfo {
  var id: String
  var name: String
  var language: String
  var quality: Int
 }

 // Words that are fine to read: no markdown marks, links as "a link", file names as "a file", keys and email addresses never read,
 // arrows as "to", newlines as spaces. Long text is cut at the end of a sentence and says so.
 static func spoken(_ text: String,limit: Int = 600) -> String {
  let limit = max(limit,0)
  // The tail is cut anyway, so clip first: the cleaning rules are slow on very long unbroken text (a pasted log, a base64 blob).
  let cap = limit * 5 + 500
  let clipped = text.count > cap
  var words = clipped ? String(text.prefix(cap)) : text
  let rules: [(String,String)] = [
   (#"\b(?:github_pat_|ghp_|gho_|ghs_|sk_live_|rk_live_|sk-|AIza)[\w\-]{8,}"#,"a key"),
   (#"[\w.+\-]+@[\w\-]+\.[\w.\-]+"#,"an email address"),
   (#"\[([^\]]+)\]\((?:[^)]+)\)"#,"$1"),
   (#"https?://\S+"#,"a link"),
   (#"[\w.\-]+(?:/[\w.\-]+)+\.[A-Za-z]{1,5}"#,"a file"),
   (#"\b[\w\-]+\.(?:md|py|swift|json|yml|yaml|html|txt|command|sh|csv)\b"#,"a file"),
   (#"(?<=\w)_(?=\w)"#," "),
   (#"(?m)^[ \t]*>+"#,""),
   (#"[*_`#]+"#,""),
   (#"\s*→\s*"#," to "),
   (#"\s*\n+\s*"#," "),
   (#" {2,}"#," ")
  ]
  for (pattern,template) in rules { words = words.replacingOccurrences(of:pattern,with:template,options:.regularExpression) }
  words = words.trimmingCharacters(in:.whitespacesAndNewlines)
  guard words.count > limit || clipped else { return words }
  let cut = words.count > limit ? MeetingData.brief(words,limit:limit) : words + "…"
  return String(cut.dropLast()) + ". There is more in the room."
 }

 // Splits long speech at sentence ends into pieces of at most `max` characters, so Stop reacts quickly.
 static func chunks(_ text: String,max: Int = 350) -> [String] {
  var out: [String] = []
  var current = ""
  var sentence = ""
  func flush() { if !current.isEmpty { out.append(current); current = "" } }
  let characters = Array(text)
  for (index,character) in characters.enumerated() {
   sentence.append(character)
   if ".?!".contains(character), index + 1 == characters.count || characters[index + 1].isWhitespace {
    if current.count + sentence.count > max { flush() }
    current += sentence
    sentence = ""
   }
  }
  if !sentence.isEmpty {
   if current.count + sentence.count > max { flush() }
   current += sentence
  }
  flush()
  return out.map { $0.trimmingCharacters(in:.whitespaces) }.filter { !$0.isEmpty }
 }

 // "just now", "5 minutes ago", "3 hours ago", "4 days ago".
 static func agoWords(_ date: Date?,now: Date = Date()) -> String {
  guard let date = date else { return "a while ago" }
  let seconds = max(0,now.timeIntervalSince(date))
  func unit(_ count: Int,_ name: String) -> String { "\(count) \(name)\(count == 1 ? "" : "s") ago" }
  if seconds < 90 { return "just now" }
  if seconds < 3600 { return unit(Int(seconds / 60),"minute") }
  if seconds < 48 * 3600 { return unit(Int(seconds / 3600),"hour") }
  return unit(Int(seconds / 86400),"day")
 }

 // The text with a full stop on the end unless it already has a stop, a question mark or an exclamation mark.
 static func sentence(_ text: String) -> String {
  guard let last = text.last else { return text }
  return ".?!".contains(last) ? text : text + "."
 }

 // Which of Claude, GPT, Friday and Matthew wrote this tag (any letter case), or nil for anything else.
 static func knownSpeaker(_ author: String) -> String? {
  (crew + ["Matthew"]).first { $0.lowercased() == author.lowercased() }
 }

 // A message: the app's own header ("GPT to Everyone, 3 hours ago.") in the Narrator voice, then the person's words in theirs.
 // An untagged or oddly tagged message is read by the Narrator and says so.
 static func messageLines(_ message: RoomMessage,now: Date = Date(),firstID: Int = 0) -> [SpeakLine] {
  let known = knownSpeaker(message.author)
  let who = known ?? (message.author == "?" ? "An untagged message" : "A message tagged \(message.author)")
  let to = message.to.isEmpty ? "" : " to \(message.to)"
  let head = "\(who)\(to), \(agoWords(message.date,now:now))."
  var out = [SpeakLine(id:firstID,speaker:"Narrator",text:head)]
  for piece in chunks(spoken(message.text,limit:900)) { out.append(SpeakLine(id:firstID + out.count,speaker:known ?? "Narrator",text:piece)) }
  return out
 }

 // One crew member's report: how many items sit under their name and the first few in each category (all in the Narrator voice,
 // since the board lines were filed by whoever edits the board), then their own last post in their own voice, if there is one.
 static func crewLines(_ name: String,board: Board?,messages: [RoomMessage],now: Date = Date()) -> [(speaker: String,text: String)] {
  let crew = MeetingData.crew(name,board:board,messages:messages)
  var out: [(speaker: String,text: String)] = []
  let open = crew.open
  out.append(("Narrator",open == 0 ? "Nothing on the board is under \(name)'s name." : "\(open) open \(open == 1 ? "item is" : "items are") under \(name)'s name on the board."))
  for group in crew.groups where group.status != "done" {
   let heads = group.items.prefix(2).map { sentence(spoken($0.text,limit:110)) }
   let more = group.items.count > 2 ? " And \(group.items.count - 2) more." : ""
   out.append(("Narrator","\(group.title): \(heads.joined(separator:" "))\(more)"))
  }
  if let last = crew.messages.last(where: { $0.author.lowercased() == name.lowercased() }), case let said = spoken(last.text,limit:260), !said.isEmpty {
   out.append(("Narrator","\(name)'s last post, \(agoWords(last.date,now:now)):"))
   out.append((name,said))
  }
  return out
 }

 // One crew member's report as lines (for the Read aloud button on their tab).
 static func crewScript(_ name: String,board: Board?,messages: [RoomMessage],now: Date = Date()) -> [SpeakLine] {
  guard board != nil else { return number([("Narrator","The board has not loaded yet, so there is nothing to read.")]) }
  return number(crewLines(name,board:board,messages:messages,now:now).map { ($0.speaker,$0.text) })
 }

 // A board meeting as it happened in the thread: the call, then every reply, each message as messageLines() reads it.
 static func meetingLines(_ meeting: BoardMeeting,now: Date = Date()) -> [SpeakLine] {
  var out: [SpeakLine] = []
  for message in [meeting.call] + meeting.replies {
   for line in messageLines(message,now:now) { out.append(SpeakLine(id:out.count,speaker:line.speaker,text:line.text)) }
  }
  return out
 }

 // The whole read-out: an opening, each of Claude, GPT and Friday, then what needs Matthew. The Narrator reads everything the app wrote.
 static func meetingScript(board: Board?,messages: [RoomMessage],now: Date = Date()) -> [SpeakLine] {
  var lines: [(String,String)] = [("Narrator",openingLine)]
  guard board != nil else {
   lines.append(("Narrator","The board has not loaded yet, so there is nothing to read."))
   return number(lines)
  }
  for name in crew { for line in crewLines(name,board:board,messages:messages,now:now) { lines.append((line.speaker,line.text)) } }
  let needs = MeetingData.needs(board:board,messages:messages,now:now)
  if needs.count == 0 {
   lines.append(("Narrator","Nothing needs Matthew right now."))
  } else {
   lines.append(("Narrator","\(needs.count) \(needs.count == 1 ? "thing needs" : "things need") Matthew."))
   for item in needs.questions.prefix(3) { lines.append(("Narrator","Question: \(spoken(item.text,limit:200))")) }
   for item in needs.tasks.prefix(3) { lines.append(("Narrator","To do: \(spoken(item.text,limit:200))")) }
   for message in needs.messages.suffix(2) {
    let who = knownSpeaker(message.author) ?? (message.author == "?" ? "An untagged message" : "A message tagged \(message.author)")
    lines.append(("Narrator","\(who) wrote to you:"))
    lines.append((knownSpeaker(message.author) ?? "Narrator",spoken(message.text,limit:200)))
   }
   let shown = min(3,needs.questions.count) + min(3,needs.tasks.count) + min(2,needs.messages.count)
   if needs.count > shown { lines.append(("Narrator","The rest are in the You tab.")) }
  }
  lines.append(("Narrator",closingLine))
  return number(lines)
 }

 private static func number(_ lines: [(String,String)]) -> [SpeakLine] {
  lines.enumerated().map { SpeakLine(id:$0.offset,speaker:$0.element.0,text:$0.element.1) }
 }

 // Which built-in voice each speaker gets. Each tries its own favourites first, then the best English voice nobody has, and no two
 // speakers share one while there are enough voices.
 static let favourites: [String:[String]] = [
  "Claude":["Daniel","Oliver","Alex","Aaron","Evan"],
  "GPT":["Samantha","Ava","Allison","Nicky","Susan"],
  "Friday":["Karen","Moira","Tessa","Serena","Flo"],
  "Matthew":["Tom","Lee","Gordon","Rishi","Fred"],
  "Narrator":["Ralph","Kathy","Bruce","Fred","Junior"]
 ]

 static func assign(_ speakers: [String],voices: [VoiceInfo]) -> [String:String] {
  let english = voices.filter { $0.language.hasPrefix("en") }
  let ranked = english.sorted { $0.quality == $1.quality ? $0.name < $1.name : $0.quality > $1.quality }
  var used = Set<String>()
  var out: [String:String] = [:]
  for speaker in speakers {
   var pick: VoiceInfo?
   for favourite in favourites[speaker] ?? [] {
    pick = ranked.first { ($0.name == favourite || $0.name.hasPrefix(favourite + " ")) && !used.contains($0.id) }
    if pick != nil { break }
   }
   if pick == nil { pick = ranked.first { !used.contains($0.id) } }
   if pick == nil { pick = ranked.first }
   if let pick = pick { out[speaker] = pick.id; used.insert(pick.id) }
  }
  return out
 }

 // A small difference in pitch on top of the different voices, so they stay apart even when two voices sound alike.
 static func pitch(_ speaker: String) -> Float {
  switch speaker {
  case "Claude": return 0.95
  case "GPT": return 1.05
  case "Matthew": return 0.9
  default: return 1.0
  }
 }
}
