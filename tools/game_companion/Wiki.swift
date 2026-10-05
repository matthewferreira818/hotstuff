import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Free fact lookup for the Live buddy's lookup_game_wiki tool. Two sources, tried in order:
//  1. metabot.gg: exact tier numbers read from the game files (gear, enchantments, effects).
//  2. minecraft.wiki "Dungeons II:" pages (bosses, mobs, quests, descriptions).
// Only the words being looked up leave the Mac, never screen pictures or audio.
// Tested against both live sites on 2026-10-05 (Dungeons II is MediaWiki namespace 10014).
enum GameWiki {
 static let wikiAPI = "https://minecraft.wiki/api.php"
 static let metabotBase = "https://metabot.gg/en/minecraft-dungeons-2/"
 // Where metabot keeps each kind of page. Order matters: the first kind that has the page wins.
 static let metabotKinds = ["enchantments","effects","weapons","talismans","artifacts","armor","armor/sets"]
 static let session: URLSession = {
  let config = URLSessionConfiguration.ephemeral
  config.timeoutIntervalForRequest = 8
  config.httpAdditionalHeaders = ["User-Agent":"Mozilla/5.0 (compatible; GameCompanion/1.0; personal project)"]
  return URLSession(configuration:config)
 }()

 static func lookup(_ rawQuery: String) async -> String {
  let query = String(rawQuery.trimmingCharacters(in:.whitespacesAndNewlines).prefix(80))
  guard !query.isEmpty else { return "The search was empty. Tell the player you couldn't look it up." }
  if let found = await metabotPage(query) { return found }
  return await wikiPage(query)
 }

 // MARK: metabot.gg

 static func slug(_ name: String) -> String {
  let lowered = name.lowercased().replacingOccurrences(of:"'",with:"").replacingOccurrences(of:"\u{2019}",with:"")
  let dashed = lowered.replacingOccurrences(of:"[^a-z0-9]+",with:"-",options:.regularExpression)
  return dashed.trimmingCharacters(in:CharacterSet(charactersIn:"-"))
 }

 static func metabotPage(_ query: String) async -> String? {
  let name = slug(query)
  guard !name.isEmpty else { return nil }
  // Ask for every kind at once, then take the first kind (in the order above) that has the page.
  let results: [(Int,String,String)] = await withTaskGroup(of:(Int,String,String)?.self) { group in
   for (index,kind) in metabotKinds.enumerated() {
    group.addTask {
     guard let url = URL(string:metabotBase + kind + "/" + name),
           let (data,response) = try? await session.data(from:url),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let html = String(data:data,encoding:.utf8) else { return nil }
     let text = flattenSite(html)
     return text.count > 80 ? (index,kind,text) : nil
    }
   }
   var all: [(Int,String,String)] = []
   for await item in group { if let item = item { all.append(item) } }
   return all
  }
  guard let best = results.min(by:{ $0.0 < $1.0 }) else { return nil }
  return "MetaBot (numbers from the game files, build 1.1.1.0), \(best.1) page \"\(query)\":\n\(String(best.2.prefix(2200)))"
 }

 // Keeps the page's own content: drops menus, the app advert and the "how we source this" boxes.
 static func flattenSite(_ html: String) -> String {
  var s = html
  if let r = try? NSRegularExpression(pattern:"<main[^>]*>(.*)</main>",options:[.caseInsensitive,.dotMatchesLineSeparators]),
     let m = r.firstMatch(in:s,range:NSRange(s.startIndex...,in:s)), m.numberOfRanges > 1, let inner = Range(m.range(at:1),in:s) {
   s = String(s[inner])
  }
  let skipWords = ["MetaBot Desktop","Free · Windows","Build Planner","Download","Overwolf","DPS tier list","Farm Finder","Read More","How we source this","Data Methodology","Dakota Chinnick","Every weapon, armor","Plan your build next","Fill all 12 gear slots","All 12 gear slots","Enchantment Points & effects","Save up to 20 builds","Gear slots to plan","More Info","More info","Strategy guide"]
  let lines = textLines(s,dropping:"style|script|svg|nav|header|footer").filter { line in
   line != "Methodology" && line != "Author" && !skipWords.contains(where:{ line.contains($0) })
  }
  return lines.joined(separator:"\n")
 }

 // MARK: minecraft.wiki

 static func wikiFetch(_ items: [String:String]) async throws -> [String:Any] {
  var parts = URLComponents(string:wikiAPI)!
  parts.queryItems = items.map { URLQueryItem(name:$0.key,value:$0.value) } + [URLQueryItem(name:"format",value:"json")]
  let (data,_) = try await session.data(from:parts.url!)
  return (try JSONSerialization.jsonObject(with:data) as? [String:Any]) ?? [:]
 }

 static func wikiPage(_ query: String) async -> String {
  do {
   let found = try await wikiFetch(["action":"query","list":"search","srsearch":query,"srnamespace":"10014","srlimit":"4"])
   let hits = ((found["query"] as? [String:Any])?["search"] as? [[String:Any]])?.compactMap { $0["title"] as? String } ?? []
   guard let top = hits.first else { return "Neither MetaBot nor the Minecraft wiki has a Dungeons II page matching \"\(query)\". Tell the player you couldn't find it, and don't guess." }
   let page = try await wikiFetch(["action":"parse","page":top,"prop":"text","redirects":"1","disablelimitreport":"1","disableeditsection":"1"])
   guard let html = ((page["parse"] as? [String:Any])?["text"] as? [String:Any])?["*"] as? String else { return "The wiki page \"\(top)\" came back empty. Tell the player you couldn't check it." }
   var reply = "Minecraft wiki page \"\(top)\" (a wiki, so numbers shown as X% are unfilled placeholders):\n" + excerpt(flattenWiki(html),around:query)
   if hits.count > 1 { reply += "\n\nOther wiki pages that matched: " + hits.dropFirst().joined(separator:"; ") + ". Search again with one of those names if the player needs it." }
   return reply
  } catch {
   return "The lookup failed (\(error.localizedDescription)). Tell the player you couldn't check it."
  }
 }

 // Page heads are mostly infobox. If the page is long and the search word sits further down, keep the head plus the part around the word.
 static func excerpt(_ text: String, around query: String) -> String {
  let limit = 1800
  guard text.count > limit else { return text }
  let head = String(text.prefix(600))
  if let hit = text.range(of:query,options:.caseInsensitive) {
   let at = text.distance(from:text.startIndex,to:hit.lowerBound)
   if at > 600 {
    let start = max(600,at - 300)
    let from = text.index(text.startIndex,offsetBy:start)
    return head + "\n…\n" + String(text[from...].prefix(limit - 650))
   }
  }
  return String(text.prefix(limit))
 }

 // Wiki HTML to short plain text: picture data, contents list, history, gallery and navigation are dropped.
 static func flattenWiki(_ html: String) -> String {
  var lines = textLines(html,dropping:"style|script",linksBreakLines:false)
  if let stop = lines.firstIndex(where: { ["History","Gallery","Navigation","References"].contains($0) }) { lines = Array(lines[..<stop]) }
  var kept: [String] = []
  var depth = 0
  for line in lines {
   // The page carries its picture data as a block of JSON that starts on a line holding only "{".
   if depth > 0 || line == "{" {
    depth += line.filter { $0 == "{" }.count - line.filter { $0 == "}" }.count
    continue
   }
   if line == "Contents" { continue }
   if line.count < 40, line.range(of:"^[0-9]+(\\.[0-9]+)* [A-Za-z' ]+$",options:.regularExpression) != nil { continue }
   kept.append(line)
  }
  return kept.joined(separator:"\n")
 }

 // MARK: shared

 // HTML to trimmed non-empty lines. Table cells are joined with " | " so rows stay readable.
 static func textLines(_ html: String, dropping blocks: String, linksBreakLines: Bool = true) -> [String] {
  var s = html
  func sub(_ pattern: String, _ with: String) {
   guard let r = try? NSRegularExpression(pattern:pattern,options:[.caseInsensitive,.dotMatchesLineSeparators]) else { return }
   s = r.stringByReplacingMatches(in:s,range:NSRange(s.startIndex...,in:s),withTemplate:with)
  }
  sub("<(\(blocks))[^>]*>.*?</\\1>","")
  sub("<sup[^>]*reference[^>]*>.*?</sup>","")
  sub("</t[dh]>"," | ")
  sub("</?(br|p|tr|li|h[1-6]|div|table|ul|ol|dd|dt|section\(linksBreakLines ? "|button|a" : ""))[^>]*>","\n")
  sub("<[^>]+>","")
  return decode(s).components(separatedBy:"\n")
   .map { $0.trimmingCharacters(in:.whitespaces) }
   .map { $0.hasSuffix("|") ? String($0.dropLast()).trimmingCharacters(in:.whitespaces) : $0 }
   .filter { !$0.isEmpty }
 }

 static func decode(_ text: String) -> String {
  var out = text
  // Numeric entities like &#32; or &#x27;
  if let r = try? NSRegularExpression(pattern:"&#(x?)([0-9a-fA-F]+);") {
   for m in r.matches(in:out,range:NSRange(out.startIndex...,in:out)).reversed() {
    guard let whole = Range(m.range,in:out), let marker = Range(m.range(at:1),in:out), let digits = Range(m.range(at:2),in:out),
          let code = UInt32(out[digits],radix:out[marker].isEmpty ? 10 : 16), let scalar = Unicode.Scalar(code) else { continue }
    out.replaceSubrange(whole,with:String(Character(scalar)))
   }
  }
  for (code,plain) in [("&nbsp;"," "),("&lt;","<"),("&gt;",">"),("&quot;","\""),("&amp;","&")] {
   out = out.replacingOccurrences(of:code,with:plain)
  }
  return out
 }
}
