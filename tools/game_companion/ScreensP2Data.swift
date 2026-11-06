import Foundation

// Phase 2 screens (LC-Pixels), PURE logic, Foundation only so it can be checked offline (checks/screensp2_check.swift):
// what the crew chat composer posts, the memory bank file (Keep / Edit / Forget), the one Money Move line, and when Friday's DM is "thinking".
// No network and no UI here. The memory and DM files are private to this Mac: nothing in this file sends them anywhere.

enum ComposerRules {
 static let fixedTargets = ["Everyone","Claude","Friday","LC-Manager"]

 // The To: picker: the four fixed doors, then every other open Local Claude chat seen in the room (plain "LC-Name").
 static func targets(openChats: [String]) -> [String] {
  var out = fixedTargets
  let plain = openChats.map { $0.hasPrefix("Local Claude (") && $0.hasSuffix(")") ? String($0.dropFirst(14).dropLast()) : $0 }
  for name in plain.sorted(by:{ $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }) {
   if !name.isEmpty && !out.contains(where:{ $0.caseInsensitiveCompare(name) == .orderedSame }) { out.append(name) }
  }
  return out
 }

 // Always carries the arrow, so "→ Everyone" reaches the engine (it wakes LC-Manager and Friday for that).
 static func body(to target: String,text: String) -> String? {
  let words = text.trimmingCharacters(in:.whitespacesAndNewlines)
  let who = target.trimmingCharacters(in:.whitespacesAndNewlines)
  if words.isEmpty || who.isEmpty { return nil }
  return "**[Matthew → \(who)]** \(words)"
 }

 // The id GitHub gives the new comment (the shape every POST /issues/N/comments answers with).
 static func commentID(_ data: Data) -> Int? {
  guard let obj = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] else { return nil }
  return (obj["id"] as? Int) ?? (obj["id"] as? NSNumber)?.intValue
 }
}

// MARK: Friday's memory bank (Helm-Private/friday/memory.md). Format is Friday's: `### m-YYYYMMDD-NN` then tag / saved / by / important / text.

struct MemoryEntry: Identifiable, Equatable {
 var id: String
 var tag: String
 var saved: String
 var by: String
 var important: Bool
 var text: String
 var isMood: Bool { tag.lowercased() == "moods" }
}

enum MemoryBank {
 static let tags = ["About Matthew","How he talks","Likes","Decisions","Who's who","Wins","Moods","Friday's view"]

 static func lines(_ file: String) -> [String] { file.components(separatedBy:"\n") }

 // Block start lines (`### id`), in order.
 private static func starts(_ ls: [String]) -> [Int] { ls.indices.filter { ls[$0].hasPrefix("### ") } }
 private static func blockRange(_ ls: [String],id: String) -> Range<Int>? {
  let s = starts(ls)
  guard let i = s.firstIndex(where:{ ls[$0].dropFirst(4).trimmingCharacters(in:.whitespaces) == id }) else { return nil }
  return s[i]..<(i + 1 < s.count ? s[i + 1] : ls.count)
 }
 private static func value(_ ls: [String],_ r: Range<Int>,_ key: String) -> String? {
  for i in r.dropFirst() { if ls[i].hasPrefix(key + ":") { return String(ls[i].dropFirst(key.count + 1)).trimmingCharacters(in:.whitespaces) } }
  return nil
 }

 static func parse(_ file: String) -> [MemoryEntry] {
  let ls = lines(file)
  let s = starts(ls)
  var out: [MemoryEntry] = []
  for (k,start) in s.enumerated() {
   let r = start..<(k + 1 < s.count ? s[k + 1] : ls.count)
   let id = ls[start].dropFirst(4).trimmingCharacters(in:.whitespaces)
   guard !id.isEmpty, let text = value(ls,r,"text") else { continue }
   out.append(MemoryEntry(id:id,tag:value(ls,r,"tag") ?? "",saved:value(ls,r,"saved") ?? "",by:value(ls,r,"by") ?? "",
                          important:(value(ls,r,"important") ?? "no").lowercased() == "yes",text:text))
  }
  return out
 }

 // Rewrites one block's lines in place (keeps the id and every other line), or nil when the id isn't there.
 private static func setLine(_ ls: inout [String],_ r: Range<Int>,_ key: String,_ val: String) {
  if let i = r.dropFirst().first(where:{ ls[$0].hasPrefix(key + ":") }) { ls[i] = "\(key): \(val)" }
 }
 private static func oneLine(_ s: String) -> String {
  s.components(separatedBy:.newlines).joined(separator:" ").trimmingCharacters(in:.whitespaces)
 }

 // Keep = important: yes.
 static func keep(_ file: String,id: String) -> String? {
  var ls = lines(file)
  guard let r = blockRange(ls,id:id) else { return nil }
  setLine(&ls,r,"important","yes")
  return ls.joined(separator:"\n")
 }

 // Edit = new text (one line) and optionally a new tag; the id stays. An empty text is refused (that is Forget's job).
 static func edit(_ file: String,id: String,text: String,tag: String? = nil) -> String? {
  var ls = lines(file)
  guard let r = blockRange(ls,id:id) else { return nil }
  let t = oneLine(text)
  if t.isEmpty { return nil }
  setLine(&ls,r,"text",t)
  if let tag = tag, tags.contains(tag) { setLine(&ls,r,"tag",tag) }
  return ls.joined(separator:"\n")
 }

 // Forget = the whole block is deleted (with one blank line after it). Everything above the first `### ` is left alone.
 static func forget(_ file: String,id: String) -> String? {
  var ls = lines(file)
  guard let r = blockRange(ls,id:id) else { return nil }
  var end = r.upperBound
  if end < ls.count && end > r.lowerBound && ls[end - 1].trimmingCharacters(in:.whitespaces).isEmpty { end = r.upperBound }   // the blank separator already sits inside the block
  ls.removeSubrange(r.lowerBound..<end)
  return ls.joined(separator:"\n")
 }
}

// MARK: One Money Move (Helm-Private/friday/money-move.md): the newest `## YYYY-MM-DD` section, with `move:` and `why:` lines.

struct MoneyMove: Equatable { var date: String; var move: String; var why: String }

enum MoneyMoveFile {
 static func latest(_ file: String) -> MoneyMove? {
  let ls = file.components(separatedBy:"\n")
  var best: MoneyMove? = nil
  var i = 0
  while i < ls.count {
   if ls[i].hasPrefix("## ") {
    let head = ls[i].dropFirst(3)
    let date = String(head.prefix(10))
    var move = "", why = ""
    var j = i + 1
    while j < ls.count && !ls[j].hasPrefix("## ") {
     if ls[j].hasPrefix("move:") { move = String(ls[j].dropFirst(5)).trimmingCharacters(in:.whitespaces) }
     if ls[j].hasPrefix("why:") { why = String(ls[j].dropFirst(4)).trimmingCharacters(in:.whitespaces) }
     j += 1
    }
    let looksLikeDate = date.count == 10 && date.dropFirst(4).hasPrefix("-") && Int(date.prefix(4)) != nil
    if looksLikeDate && !move.isEmpty && (best == nil || date > best!.date) { best = MoneyMove(date:date,move:move,why:why) }
    i = j
   } else { i += 1 }
  }
  return best
 }

 // "Friday, Nov 6" for the "as of" line.
 static func asOf(_ date: String) -> String {
  let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.timeZone = TimeZone(identifier:"America/Moncton")
  guard let d = f.date(from:date) else { return date }
  let out = DateFormatter(); out.dateFormat = "EEEE, MMM d"; out.timeZone = TimeZone(identifier:"America/Moncton")
  return out.string(from:d)
 }
}

// MARK: Friday & me: is she still working on the newest message of his?

enum DMScreenRules {
 // Thinking = his newest message has no reply yet and the engine hasn't said her chat is closed or the wake failed.
 static func thinking(lastSentID: String?,repliedTo: Set<String>,state: String?) -> Bool {
  guard let id = lastSentID, !repliedTo.contains(id) else { return false }
  return !["closed","failed"].contains(state ?? "")
 }
}
