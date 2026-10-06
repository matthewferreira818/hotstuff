import Foundation

// Friday's voice-over on a finished clip: the rules and the data shapes, with no Mac frameworks so they can be tested anywhere.
// Matthew's ask (2026-10-06): in the clip, Friday explains what's going on, how to get loot, the best ways to farm.
// How it works (VoiceOver.swift does the calling):
//  1. A small copy of the clip (picture and sound) goes to Google's Gemini, which says what happens in it and names the items, enemies and
//     areas it can clearly read or hear.
//  2. Those names are looked up on the game's wiki (Wiki.swift). Anything about getting loot or farming may ONLY come from those pages.
//  3. A short script is written from just those two sources, and every sentence with a number the sources don't contain is dropped.
//  4. Gemini's voice speaks it, in the voice Friday uses live, and the speech is mixed over the clip with the game sound turned down.
// Endpoints and shapes checked against ai.google.dev/gemini-api/docs (video-understanding, speech-generation) on 2026-10-06:
//   POST /v1beta/interactions, header x-goog-api-key. Video can be sent inline when the whole request is under 20 MB.
//   Text answers: steps[].content[].text where the step type is "model_output". Speech: model gemini-3.8-flash-tts, response_format audio,
//   generation_config.speech_config [{voice}], answered as base64 audio/wav (a 44 byte RIFF header, 24 kHz 16 bit mono).
// The voice-over is an AI voice, and the files and caption say so.

struct VoiceOverview: Equatable {
 var summary: String
 var named: [String]
 var game: String
}

struct DuckStep: Equatable {
 var at: Double
 var length: Double
 var from: Float
 var to: Float
}

enum VoiceOverPlan {
 static let model = "gemini-3.8-flash"
 static let speechModel = "gemini-3.8-flash-tts"
 static let endpoint = "https://generativelanguage.googleapis.com/v1beta/interactions"
 static let wordsPerSecond = 2.3         // a steady explainer pace
 static let leadIn = 0.8                 // seconds of the clip before she starts
 static let tail = 1.0                   // seconds kept quiet at the end
 static let minClipSeconds = 8.0         // shorter than this isn't worth narrating
 static let maxVideoBytes = 14_000_000   // the small copy sent for watching; Google's inline limit is 20 MB for the whole request
 static let maxNamed = 3
 static let duckVolume: Float = 0.22     // how loud the game and his own voice are while she talks
 static let fadeDown = 0.3
 static let fadeUp = 0.6
 static let style = "upbeat, clear and friendly, like a gaming explainer short, at a steady pace"

 // MARK: how much she can say

 static func available(clipSeconds: Double) -> Double { max(0,clipSeconds - leadIn - tail) }

 static func wordBudget(clipSeconds: Double) -> Int { Int(available(clipSeconds:clipSeconds) * wordsPerSecond) }

 static func wordCount(_ text: String) -> Int { text.split(whereSeparator: { $0.isWhitespace }).count }

 // MARK: cleaning and checking the script

 // Plain words to speak: no markdown, hashtags, emoji or quote marks.
 static func clean(_ raw: String) -> String {
  let kept = raw.replacingOccurrences(of:"\n",with:" ")
   .split(whereSeparator: { $0.isWhitespace })
   .map(String.init)
   .filter { !$0.hasPrefix("#") }
   .joined(separator:" ")
  var text = ""
  for scalar in kept.unicodeScalars where !scalar.properties.isEmojiPresentation && scalar.value != 0xFE0F {
   if "*_`\"\u{201C}\u{201D}".unicodeScalars.contains(scalar) { continue }
   text.unicodeScalars.append(scalar)
  }
  return text.split(whereSeparator: { $0.isWhitespace }).joined(separator:" ")
 }

 static func sentences(_ text: String) -> [String] {
  var result: [String] = []
  var current = ""
  let chars = Array(text)
  for (index,character) in chars.enumerated() {
   current.append(character)
   guard ".!?".contains(character) else { continue }
   let atEnd = index + 1 >= chars.count
   if atEnd || chars[index + 1] == " " || chars[index + 1] == "\n" {
    let line = current.trimmingCharacters(in:.whitespacesAndNewlines)
    if !line.isEmpty { result.append(line) }
    current = ""
   }
  }
  let rest = current.trimmingCharacters(in:.whitespacesAndNewlines)
  if !rest.isEmpty { result.append(rest) }
  return result
 }

 private static let spelledNumbers = ["two","three","four","five","six","seven","eight","nine","ten","eleven","twelve","fifteen","twenty","thirty","forty","fifty","hundred","thousand","percent","twice","double","triple","half"]
 private static let digitPattern = try! NSRegularExpression(pattern:"\\d+(?:[.,]\\d+)?",options:[])

 // Keeps only the sentences whose numbers appear in the sources (what she saw, and the wiki pages). A number she can't back up
 // is something she could have made up, so that whole sentence goes. Spelled-out amounts ("twenty percent") are held to the same rule.
 static func vetted(_ script: String,sources: [String]) -> (kept: [String],dropped: [String]) {
  let pool = sources.joined(separator:"\n").lowercased()
  var kept: [String] = []
  var dropped: [String] = []
  for sentence in sentences(script) {
   let lower = sentence.lowercased()
   var ok = true
   let range = NSRange(lower.startIndex..<lower.endIndex,in:lower)
   for match in digitPattern.matches(in:lower,options:[],range:range) {
    if let found = Range(match.range,in:lower), !pool.contains(String(lower[found])) { ok = false }
   }
   let tokens = Set(lower.split(whereSeparator: { !$0.isLetter }).map(String.init))
   for word in spelledNumbers where tokens.contains(word) && !pool.contains(word) { ok = false }
   if ok { kept.append(sentence) } else { dropped.append(sentence) }
  }
  return (kept,dropped)
 }

 // As many whole sentences from the start as fit in `words`.
 static func fit(_ lines: [String],words: Int) -> [String] {
  var total = 0
  var result: [String] = []
  for line in lines {
   let count = wordCount(line)
   if total + count > words { break }
   total += count
   result.append(line)
  }
  return result
 }

 // MARK: what Gemini says it saw

 // The first answer is a small JSON object; models sometimes wrap it in a code fence or add a sentence around it.
 static func parseOverview(_ text: String) -> VoiceOverview? {
  guard let open = text.firstIndex(of:"{"), let close = text.lastIndex(of:"}"), open < close else { return nil }
  let slice = String(text[open...close])
  guard let data = slice.data(using:.utf8), let json = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return nil }
  let summary = ((json["what_happens"] as? String) ?? "").trimmingCharacters(in:.whitespacesAndNewlines)
  guard !summary.isEmpty else { return nil }
  var seen = Set<String>()
  var named: [String] = []
  for raw in (json["named"] as? [Any]) ?? [] {
   guard let text = raw as? String else { continue }
   let name = String(text.trimmingCharacters(in:.whitespacesAndNewlines).prefix(60))
   if name.isEmpty || seen.contains(name.lowercased()) { continue }
   seen.insert(name.lowercased())
   named.append(name)
   if named.count == maxNamed { break }
  }
  return VoiceOverview(summary:summary,named:named,game:((json["game"] as? String) ?? "").trimmingCharacters(in:.whitespacesAndNewlines))
 }

 // A wiki lookup (Wiki.swift) that found nothing says so in words aimed at Friday.
 static func isFound(lookup: String) -> Bool {
  !lookup.contains("Tell the player you couldn't") && !lookup.hasPrefix("The lookup failed")
 }

 // MARK: Google's answers

 private static func contentItems(_ json: [String:Any]) -> [[String:Any]] {
  var items: [[String:Any]] = []
  for step in (json["steps"] as? [[String:Any]]) ?? [] {
   let type = step["type"] as? String ?? "model_output"
   guard type == "model_output" else { continue }
   items.append(contentsOf:(step["content"] as? [[String:Any]]) ?? [])
  }
  return items
 }

 // The text of an answer, from the new "interactions" shape, with the older candidates shape as a fallback.
 static func replyText(_ json: [String:Any]) -> String? {
  var parts = contentItems(json).filter { ($0["type"] as? String ?? "text") == "text" }.compactMap { $0["text"] as? String }
  if parts.isEmpty, let direct = json["output_text"] as? String { parts = [direct] }
  if parts.isEmpty, let candidate = (json["candidates"] as? [[String:Any]])?.first,
     let list = (candidate["content"] as? [String:Any])?["parts"] as? [[String:Any]] {
   parts = list.compactMap { $0["text"] as? String }
  }
  let text = parts.joined(separator:"\n").trimmingCharacters(in:.whitespacesAndNewlines)
  return text.isEmpty ? nil : text
 }

 // The last audio block of an answer.
 static func replyAudio(_ json: [String:Any]) -> Data? {
  var blobs = contentItems(json).filter { ($0["type"] as? String) == "audio" }.compactMap { $0["data"] as? String }
  if blobs.isEmpty, let candidate = (json["candidates"] as? [[String:Any]])?.first,
     let list = (candidate["content"] as? [String:Any])?["parts"] as? [[String:Any]] {
   blobs = list.compactMap { ($0["inlineData"] as? [String:Any])?["data"] as? String }
  }
  guard let last = blobs.last, let data = Data(base64Encoded:last), !data.isEmpty else { return nil }
  return data
 }

 static func errorMessage(_ json: [String:Any]) -> String? {
  if let error = json["error"] as? [String:Any] { return error["message"] as? String }
  return json["message"] as? String
 }

 // A Google refusal in plain words. `doing` finishes "Couldn't ...", for example "watch the clip".
 static func explain(code: Int,message: String?,doing: String) -> String {
  let reason = String((message ?? "").trimmingCharacters(in:.whitespacesAndNewlines).prefix(160))
  switch code {
  case 400: return reason.isEmpty ? "Google didn't accept the request to \(doing)." : "Google didn't accept the request to \(doing): \(reason)"
  case 401, 403: return "Google refused the saved key when I tried to \(doing). The key may be wrong, or the free plan may not include this. Check the key in Accounts."
  case 404: return "Google doesn't know the model I use to \(doing) (it may have been renamed)."
  case 429: return "Google's free limit is used up for now, so I couldn't \(doing). The free allowance resets daily; try again later."
  case 500...599: return "Google had a problem when I tried to \(doing). Try again in a minute."
  default: return "Couldn't \(doing) (Google answered \(code))."
  }
 }

 // MARK: requests

 static func videoBody(prompt: String,video: Data) -> Data? {
  let input: [[String:Any]] = [["type":"text","text":prompt],["type":"video","data":video.base64EncodedString(),"mime_type":"video/mp4"]]
  return try? JSONSerialization.data(withJSONObject:["model":model,"input":input] as [String:Any])
 }

 static func textBody(prompt: String) -> Data? {
  let input: [[String:Any]] = [["type":"text","text":prompt]]
  return try? JSONSerialization.data(withJSONObject:["model":model,"input":input] as [String:Any])
 }

 static func speechBody(script: String,voice: String) -> Data? {
  let annotation: [String:Any] = ["type":"speech_metadata","style":style]
  let content: [String:Any] = ["type":"text","text":script,"annotations":[annotation]]
  let turn: [String:Any] = ["type":"user_input","content":[content]]
  let body: [String:Any] = [
   "model":speechModel,
   "input":[turn],
   "response_format":["type":"audio"],
   "generation_config":["speech_config":[["voice":voice]]]
  ]
  return try? JSONSerialization.data(withJSONObject:body)
 }

 // MARK: the prompts

 static let overviewPrompt = "You are watching a short clip, with sound, from a video game player's Twitch stream. Reply with ONLY a JSON object, no markdown: {\"game\": \"the game's name if you can tell, otherwise empty\", \"what_happens\": \"3 to 5 plain sentences about what happens in the clip, in order, including anything the player says that matters\", \"named\": [\"up to 3 names of items, enemies, bosses, areas or mechanics that are clearly readable on screen or clearly said out loud\"]}. Describe only what you can see or hear. Never guess a name you cannot read or hear."

 // What she is asked to cover. Matthew's words if he gave any, otherwise the default he asked for.
 static func focusClause(_ raw: String) -> String {
  let own = String(raw.replacingOccurrences(of:"\n",with:" ").trimmingCharacters(in:.whitespacesAndNewlines).prefix(120))
  if own.isEmpty { return "If FACTS explain how to get an item shown here or how to farm something shown here, work one useful tip in." }
  return "The player asked you to cover: \(own). Cover it ONLY as far as FACTS allow."
 }

 static func scriptPrompt(summary: String,facts: [String],focus: String,words: Int) -> String {
  let factText = facts.isEmpty ? "(none found)" : facts.joined(separator:"\n---\n")
  return "Write the voice-over for a short vertical gaming clip. The speaker is Friday, the player's AI companion, narrating over the footage; viewers will know it is an AI voice. Style: upbeat, plain, spoken, like a gaming explainer short. Length: at most \(words) words, in whole sentences, starting right away with what is happening. RULES: 1) Say what is going on using ONLY WHAT_HAPPENS. 2) \(focusClause(focus)) If FACTS has nothing useful, give no tip at all and say nothing about how to get loot or how to farm. 3) Never state a number, percentage, drop chance, level or location that is not written in WHAT_HAPPENS or FACTS. 4) No hashtags, no emoji, no 'link in bio', no promises, no claims about the channel. Reply with only the words to speak.\n\nWHAT_HAPPENS:\n\(summary)\n\nFACTS (from the game's wiki):\n\(factText)"
 }

 // MARK: the speech file

 static func wavFromPCM(_ pcm: Data,sampleRate: Int = 24_000) -> Data {
  var out = Data()
  func u32(_ value: Int) { var v = UInt32(truncatingIfNeeded:value).littleEndian; out.append(Data(bytes:&v,count:4)) }
  func u16(_ value: Int) { var v = UInt16(truncatingIfNeeded:value).littleEndian; out.append(Data(bytes:&v,count:2)) }
  out.append(contentsOf:Array("RIFF".utf8)); u32(36 + pcm.count)
  out.append(contentsOf:Array("WAVE".utf8)); out.append(contentsOf:Array("fmt ".utf8)); u32(16)
  u16(1); u16(1); u32(sampleRate); u32(sampleRate * 2); u16(2); u16(16)
  out.append(contentsOf:Array("data".utf8)); u32(pcm.count)
  out.append(pcm)
  return out
 }

 // Google answers with a WAV file; if it ever sends bare 24 kHz samples instead, wrap them.
 static func asWAV(_ data: Data) -> Data {
  data.starts(with:Array("RIFF".utf8)) ? data : wavFromPCM(data)
 }

 // How long a WAV file plays, read from its header. nil if it isn't a readable WAV.
 static func wavSeconds(_ data: Data) -> Double? {
  let bytes = [UInt8](data)
  guard bytes.count > 44, bytes[0...3].elementsEqual(Array("RIFF".utf8)) else { return nil }
  func u32(_ at: Int) -> Int { at + 4 <= bytes.count ? Int(bytes[at]) | Int(bytes[at + 1]) << 8 | Int(bytes[at + 2]) << 16 | Int(bytes[at + 3]) << 24 : 0 }
  var byteRate = 0
  var at = 12
  while at + 8 <= bytes.count {
   let name = String(decoding:bytes[at..<(at + 4)],as:UTF8.self)
   let size = u32(at + 4)
   if name == "fmt " { byteRate = u32(at + 16) }   // the chunk body starts 8 bytes in; byte rate is 8 bytes into the body
   if name == "data" {
    // A streamed file can say 0 or "everything": then it runs to the end of the file.
    let length = (size == 0 || size == 0xFFFF_FFFF || at + 8 + size > bytes.count) ? bytes.count - (at + 8) : size
    return byteRate > 0 ? Double(length) / Double(byteRate) : nil
   }
   at += 8 + size + (size % 2)
  }
  return nil
 }

 // MARK: mixing it into the clip

 // Volume changes for the game's own sound (and his voice in it): full, down while she talks, back up after. All times in seconds.
 static func ducking(start: Double,length: Double,clip: Double) -> [DuckStep] {
  guard clip > 0, length > 0, start >= 0, start < clip else { return [] }
  var steps: [DuckStep] = []
  let downAt = max(0,start - fadeDown)
  steps.append(DuckStep(at:downAt,length:max(0.05,start - downAt),from:1,to:duckVolume))
  let end = min(start + length,clip)
  let upLength = min(fadeUp,clip - end)
  if upLength >= 0.05 { steps.append(DuckStep(at:end,length:upLength,from:duckVolume,to:1)) }
  return steps
 }

 static func outputName(tall: Bool) -> String { tall ? "highlight-tall-voiceover.mp4" : "highlight-wide-voiceover.mp4" }

 // The note saved next to the clip: the words, what they came from, and that the voice is an AI.
 static func scriptFile(script: String,named: [String],wikiPages: [String],game: String) -> String {
  var lines = ["Voice-over (written and spoken by Friday, an AI voice; made by Gemini from this clip):","",script,""]
  lines.append("What she looked at: the clip's picture and sound" + (game.isEmpty ? "." : " (\(game)).") )
  if !named.isEmpty { lines.append("Names she picked out: " + named.joined(separator:", ") + ".") }
  lines.append(wikiPages.isEmpty ? "Game facts used: none (no wiki page found, so there are no tips in it)." : "Game facts used, from the game's wiki: " + wikiPages.joined(separator:", ") + ".")
  lines.append("Sentences with a number she couldn't back up were removed.")
  return lines.joined(separator:"\n") + "\n"
 }
}
