import Foundation

// What the Meeting Room says out loud, and which voice says it. Foundation-only so it can be tested here; the speaking itself is
// in MeetingVoice.swift. This reads WRITTEN words (the board and each person's last post) in a different built-in Mac voice for
// Claude, GPT, Friday and Matthew. It is not a live call, and it never makes up a sentence for anyone: lines about a person's board
// items are written in the third person ("GPT has two items open"), and only their own last post is read as their words.

struct SpeakLine: Identifiable {
 var id: Int
 var speaker: String
 var text: String
}

enum SpeechData {
 static let speakers = ["Claude","GPT","Friday","Matthew"]
 static let crew = ["Claude","GPT","Friday"]
 static let openingLine = "Group meeting. Your Mac is reading the room out loud, one voice each. These are the board's words and each person's last post, not a live call."

 struct VoiceInfo {
  var id: String
  var name: String
  var language: String
  var quality: Int
 }

 // Words that are fine to read: no markdown marks, links as "a link", file names as "a file", arrows as "to", newlines as spaces.
 // Long text is cut at the end of a sentence and says so.
 static func spoken(_ text: String,limit: Int = 600) -> String {
  var words = text
  let rules: [(String,String)] = [
   (#"\[([^\]]+)\]\((?:[^)]+)\)"#,"$1"),
   (#"https?://\S+"#,"a link"),
   (#"[\w.\-]+(?:/[\w.\-]+)+\.[A-Za-z]{1,5}"#,"a file"),
   (#"\b[\w\-]+\.(?:md|py|swift|json|yml|yaml|html|txt|command|sh|csv)\b"#,"a file"),
   (#"[*_`#>]+"#,""),
   (#"\s*→\s*"#," to "),
   (#"\s*\n+\s*"#," "),
   (#" {2,}"#," ")
  ]
  for (pattern,template) in rules { words = words.replacingOccurrences(of:pattern,with:template,options:.regularExpression) }
  words = words.trimmingCharacters(in:.whitespacesAndNewlines)
  guard words.count > limit else { return words }
  let cut = MeetingData.brief(words,limit:limit)
  return String(cut.dropLast()) + ". There is more in the room."
 }

 // Splits long speech at sentence ends into pieces of at most `max` characters, so Stop reacts quickly.
 static func chunks(_ text: String,max: Int = 350) -> [String] {
  var out: [String] = []
  var current = ""
  var sentence = ""
  func flush() { if !current.isEmpty { out.append(current); current = "" } }
  for character in text {
   sentence.append(character)
   if ".?!".contains(character) {
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

 // A message, read by its author's voice: who it was to, when, and the words.
 static func messageLines(_ message: RoomMessage,now: Date = Date(),firstID: Int = 0) -> [SpeakLine] {
  let author = speakers.contains(message.author) ? message.author : "Claude"
  let to = message.to.isEmpty ? "" : " to \(message.to)"
  let head = "\(message.author)\(to), \(agoWords(message.date,now:now))."
  let body = chunks(spoken(message.text,limit:900))
  return ([head] + body).enumerated().map { SpeakLine(id:firstID + $0.offset,speaker:author,text:$0.element) }
 }

 // One crew member's report, in their voice: how many items are open and the first few in each category (third person, from the
 // board), then their own last post in the thread, if there is one.
 static func crewLines(_ name: String,board: Board?,messages: [RoomMessage],now: Date = Date()) -> [String] {
  let crew = MeetingData.crew(name,board:board,messages:messages)
  var out: [String] = []
  out.append(crew.open == 0 ? "\(name) has nothing open on the board." : "\(name) has \(crew.open) open on the board.")
  for group in crew.groups where group.status != "done" {
   let heads = group.items.prefix(2).map { spoken($0.text,limit:110) }
   let more = group.items.count > 2 ? ", and \(group.items.count - 2) more" : ""
   out.append("\(group.title): \(heads.joined(separator:". "))\(more).")
  }
  if let last = crew.messages.last(where: { $0.author.lowercased() == name.lowercased() }) {
   out.append("Last post \(agoWords(last.date,now:now)): \(spoken(last.text,limit:260))")
  }
  return out
 }

 // One crew member's report as lines in their voice (for the Hear Claude / Hear GPT / Hear Friday buttons).
 static func crewScript(_ name: String,board: Board?,messages: [RoomMessage],now: Date = Date()) -> [SpeakLine] {
  guard board != nil else { return number([(name,"The board has not loaded yet, so there is nothing to read.")]) }
  return number(crewLines(name,board:board,messages:messages,now:now).map { (name,$0) })
 }

 // A board meeting as it happened in the thread: the call, then every reply, each in its author's voice.
 static func meetingLines(_ meeting: BoardMeeting,now: Date = Date()) -> [SpeakLine] {
  var out: [SpeakLine] = []
  for message in [meeting.call] + meeting.replies {
   for line in messageLines(message,now:now) { out.append(SpeakLine(id:out.count,speaker:line.speaker,text:line.text)) }
  }
  return out
 }

 // The whole meeting: an opening, each of Claude, GPT and Friday in their own voice, then what needs Matthew.
 static func meetingScript(board: Board?,messages: [RoomMessage],now: Date = Date()) -> [SpeakLine] {
  var lines: [(String,String)] = [("Claude",openingLine)]
  guard board != nil else {
   lines.append(("Claude","The board has not loaded yet, so there is nothing to read."))
   return number(lines)
  }
  for name in crew { for sentence in crewLines(name,board:board,messages:messages,now:now) { lines.append((name,sentence)) } }
  let needs = MeetingData.needs(board:board,messages:messages,now:now)
  if needs.count == 0 {
   lines.append(("Claude","Matthew, nothing needs you right now."))
  } else {
   lines.append(("Claude","Matthew, \(needs.count) \(needs.count == 1 ? "thing needs" : "things need") you."))
   for item in needs.questions.prefix(3) { lines.append(("Claude","Question: \(spoken(item.text,limit:200))")) }
   for item in needs.tasks.prefix(3) { lines.append(("Claude","To do: \(spoken(item.text,limit:200))")) }
   let shown = min(3,needs.questions.count) + min(3,needs.tasks.count)
   if needs.count > shown { lines.append(("Claude","The rest are in the You tab.")) }
  }
  lines.append(("Claude","That is the meeting."))
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
  "Matthew":["Tom","Fred","Lee","Gordon","Rishi"]
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
