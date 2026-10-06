import Foundation

// Friday's browser tools, with no Mac frameworks so the rules can be tested anywhere. Matthew's ask (2026-10-06): "I asked her to search
// TikTok, Twitter and YouTube for references and she said she can't. I want her to be able to do anything I ask, especially something
// that easy." She had no way to open a web page; now she can open a search on a known site, or a link, in his own browser and read
// the screen (she sees every screen while live). Google Search inside her voice session is a different thing and didn't work on his
// free key (2026-10-05); this needs no key and costs nothing.
// What it will and won't open: only https pages, never an address that is a bare number or this Mac or the home network, never a link with a
// password in it, and never a page whose address says it is a bank, payment, password or login page (the same word list as her hands).

enum WebPlan {
 struct Site: Equatable {
  var key: String
  var name: String
  var template: String     // "%@" is where the search words go
 }

 static let sites: [Site] = [
  Site(key:"youtube",name:"YouTube",template:"https://www.youtube.com/results?search_query=%@"),
  Site(key:"tiktok",name:"TikTok",template:"https://www.tiktok.com/search?q=%@"),
  Site(key:"x",name:"X (Twitter)",template:"https://x.com/search?q=%@&src=typed_query"),
  Site(key:"google",name:"Google",template:"https://www.google.com/search?q=%@"),
  Site(key:"reddit",name:"Reddit",template:"https://www.reddit.com/search/?q=%@"),
  Site(key:"pinterest",name:"Pinterest",template:"https://www.pinterest.com/search/pins/?q=%@"),
  Site(key:"facebook",name:"Facebook",template:"https://www.facebook.com/search/top?q=%@"),
  Site(key:"twitch",name:"Twitch",template:"https://www.twitch.tv/search?term=%@"),
  Site(key:"wiki",name:"the Minecraft wiki",template:"https://minecraft.wiki/?search=%@")
 ]

 private static let aliases: [String:String] = [
  "twitter":"x","x.com":"x","twitter.com":"x","tweet":"x","tweets":"x","x (twitter)":"x",
  "yt":"youtube","you tube":"youtube","youtube.com":"youtube","tik tok":"tiktok","tiktok.com":"tiktok","tt":"tiktok",
  "google search":"google","web":"google","the web":"google","internet":"google","pins":"pinterest","fb":"facebook",
  "minecraft wiki":"wiki","the wiki":"wiki","minecraft.wiki":"wiki"
 ]

 static var siteNames: String { sites.map { $0.name }.joined(separator:", ") }

 static func site(_ raw: String) -> Site? {
  let word = raw.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
  let key = aliases[word] ?? word
  return sites.first { $0.key == key }
 }

 static let queryAllowed = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

 // The search words, tidied: one line, no control characters, at most 120 characters. nil if nothing is left.
 static func cleanQuery(_ raw: String) -> String? {
  let noControls = String(String.UnicodeScalarView(raw.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : $0 }))
  let squeezed = noControls.split(whereSeparator: { $0.isWhitespace }).joined(separator:" ")
  let text = String(squeezed.prefix(120)).trimmingCharacters(in:.whitespaces)
  return text.isEmpty ? nil : text
 }

 static func searchURL(site: Site,query raw: String) -> URL? {
  guard let query = cleanQuery(raw), let encoded = query.addingPercentEncoding(withAllowedCharacters:queryAllowed) else { return nil }
  return URL(string:site.template.replacingOccurrences(of:"%@",with:encoded))
 }

 enum LinkResult: Equatable {
  case ok(URL)
  case no(String)
 }

 // A web address she was asked to open (or found on screen). Adds https:// if it's missing and upgrades http to https.
 static func link(_ raw: String) -> LinkResult {
  var text = raw.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !text.isEmpty, text.count <= 500 else { return .no("That isn't a link I can open.") }
  if text.rangeOfCharacter(from:CharacterSet.whitespacesAndNewlines.union(.controlCharacters)) != nil { return .no("That link has spaces or odd characters in it, so I didn't open it.") }
  if text.lowercased().hasPrefix("http://") { text = "https://" + text.dropFirst(7) }
  else if !text.contains("://") { text = "https://" + text }
  guard let parts = URLComponents(string:text), parts.scheme?.lowercased() == "https", let host = parts.host?.lowercased(), !host.isEmpty else {
   return .no("I can only open https web pages.")
  }
  if parts.user != nil || parts.password != nil { return .no("That link has a login in it, so I didn't open it.") }
  if let port = parts.port, port != 443 { return .no("That link points at an unusual port, so I didn't open it.") }
  let numbersOnly = host.allSatisfy { $0.isNumber || $0 == "." }
  if !host.contains(".") || numbersOnly || host.contains(":") || host.hasSuffix(".local") || host.hasSuffix(".internal") || host.hasSuffix(".localhost") {
   return .no("That points at a bare address or something on this Mac or the home network, so I didn't open it.")
  }
  if let why = HandsPlan.blockedReason(owner:"",title:host + parts.path) { return .no("I won't open that: \(why).") }
  guard let url = parts.url else { return .no("I couldn't make sense of that link.") }
  return .ok(url)
 }
}
