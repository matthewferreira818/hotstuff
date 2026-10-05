import Foundation

// The rules and the arithmetic behind Friday's hands and her view of all the screens, with no Mac frameworks so they can be tested
// anywhere. Matthew's choices (2026-10-05): she can click, type and press keys when he tells her to; anything that could SEND or BUY
// (pressing Return, a Send or Pay style button, a checkout page) needs him to press Allow on a box first; and she sees every screen
// while live. The off-limits list below is a safety net, not a guarantee: it matches words in the app
// name and the window title, so it can miss a page whose title doesn't say what it is.

enum HandsPlan {
 static let maxTyped = 300

 // MARK: where things are (all in "desk" points: the top-left of the main screen is 0,0, y grows downward)

 static func union(_ rects: [CGRect]) -> CGRect? {
  guard var result = rects.first else { return nil }
  for rect in rects.dropFirst() { result = result.union(rect) }
  return result
 }

 // One picture of every screen side by side, laid out the way the screens sit on the desk, shrunk to fit `maxWidth` x `maxHeight`.
 static func layout(_ frames: [CGRect],maxWidth: Double,maxHeight: Double) -> (union: CGRect,scale: Double,width: Int,height: Int)? {
  guard let area = union(frames), area.width > 0, area.height > 0 else { return nil }
  let scale = min(1,min(maxWidth / Double(area.width),maxHeight / Double(area.height)))
  return (area,scale,max(1,Int((Double(area.width) * scale).rounded())),max(1,Int((Double(area.height) * scale).rounded())))
 }

 // Where one screen goes inside that picture. Drawing code puts its origin at the bottom-left, so y is flipped.
 static func canvasRect(for frame: CGRect,union area: CGRect,scale: Double,canvasHeight: Int) -> CGRect {
  let x = Double(frame.minX - area.minX) * scale
  let top = Double(frame.minY - area.minY) * scale
  let h = Double(frame.height) * scale
  return CGRect(x:x,y:Double(canvasHeight) - top - h,width:Double(frame.width) * scale,height:h)
 }

 // A spot Friday names (0 to 1000 across the picture, left to right and top to bottom) turned into a spot on the desk.
 static func desk(_ nx: Double,_ ny: Double,in area: CGRect) -> CGPoint {
  let fx = min(max(nx,0),1000) / 1000
  let fy = min(max(ny,0),1000) / 1000
  return CGPoint(x:area.minX + area.width * CGFloat(fx),y:area.minY + area.height * CGFloat(fy))
 }

 // MARK: what she may type and press

 // Plain text only: up to `maxTyped` characters, line breaks allowed, no other control characters. nil means refuse.
 static func cleanTyped(_ raw: String) -> String? {
  let text = raw.replacingOccurrences(of:"\r\n",with:"\n").replacingOccurrences(of:"\r",with:"\n")
  guard !text.isEmpty, text.count <= maxTyped else { return nil }
  for scalar in text.unicodeScalars where scalar.value < 32 && scalar != "\n" { return nil }
  if text.unicodeScalars.contains(where: { $0.value == 127 }) { return nil }
  return text
 }

 struct KeyPress: Equatable {
  var code: UInt16
  var modifiers: [String]    // any of "cmd", "shift", "opt", "ctrl"
  var label: String          // for the Allow box, for example "⌘⇧T"
 }

 private static let codes: [String:UInt16] = [
  "a":0,"s":1,"d":2,"f":3,"h":4,"g":5,"z":6,"x":7,"c":8,"v":9,"b":11,"q":12,"w":13,"e":14,"r":15,"y":16,"t":17,
  "1":18,"2":19,"3":20,"4":21,"6":22,"5":23,"=":24,"9":25,"7":26,"-":27,"8":28,"0":29,"]":30,"o":31,"u":32,"[":33,
  "i":34,"p":35,"l":37,"j":38,"'":39,"k":40,";":41,"\\":42,",":43,"/":44,"n":45,"m":46,".":47,"`":50,
  "return":36,"enter":36,"tab":48,"space":49,"delete":51,"backspace":51,"escape":53,"esc":53,
  "left":123,"right":124,"down":125,"up":126,"pageup":116,"pagedown":121,"home":115,"end":119
 ]
 private static let modifierNames: [String:String] = ["cmd":"cmd","command":"cmd","shift":"shift","opt":"opt","option":"opt","alt":"opt","ctrl":"ctrl","control":"ctrl"]

 // "cmd+t", "cmd+shift+4", "enter", "escape", "down". nil if it is not a key combination we know.
 static func parseKeys(_ spec: String) -> KeyPress? {
  let parts = spec.lowercased().replacingOccurrences(of:" ",with:"").split(separator:"+",omittingEmptySubsequences:true).map(String.init)
  guard let keyName = parts.last, let code = codes[keyName] else { return nil }
  var mods: [String] = []
  for name in parts.dropLast() {
   guard let mod = modifierNames[name] else { return nil }
   if !mods.contains(mod) { mods.append(mod) }
  }
  let order = ["ctrl","opt","shift","cmd"]
  mods.sort { (order.firstIndex(of:$0) ?? 9) < (order.firstIndex(of:$1) ?? 9) }
  let symbols = ["ctrl":"⌃","opt":"⌥","shift":"⇧","cmd":"⌘"]
  let shown = keyName.count == 1 ? keyName.uppercased() : keyName.capitalized
  return KeyPress(code:code,modifiers:mods,label:mods.compactMap { symbols[$0] }.joined() + shown)
 }

 // Combinations that quit apps, log out, or throw things away. Refused even if Matthew would press Allow.
 static func blockedCombo(_ press: KeyPress) -> String? {
  let mods = Set(press.modifiers)
  let isQ = press.code == 12
  if mods.contains("cmd") && isQ { return "quitting an app or logging out" }
  if mods.contains("cmd") && mods.contains("opt") && press.code == 53 { return "force quitting apps" }
  if mods.contains("cmd") && press.code == 51 { return "moving things to the Trash" }
  return nil
 }

 // MARK: where she may not act

 private static let offLimits: [(words: [String],why: String)] = [
  (["moomoo","futu","wealthsimple","questrade","interactive brokers","brokerage"],"that's a trading or money app"),
  (["bank","banking","rbc ","scotiabank","bmo ","cibc","desjardins","tangerine","paypal","interac","stripe","porkbun"],"that looks like a bank, payment or domain account"),
  (["password","1password","bitwarden","lastpass","keychain","passkey"],"that's a password page"),
  (["sign in","log in","login","sign-in","log-in"],"that looks like a login page"),
  (["system settings","system preferences","activity monitor"],"that's a system settings window"),
  (["game companion"],"that's my own app, and she must not change her own switches"),
  (["terminal","iterm","ghostty","warp","kitty"],"that's a command line, and a typed command could do real damage")
 ]

 // nil when the window is fine to act in. `owner` is the app's name, `title` the window's title.
 static func blockedReason(owner: String,title: String) -> String? {
  let haystack = (owner + " | " + title).lowercased()
  for rule in offLimits where rule.words.contains(where: { haystack.contains($0) }) { return rule.why }
  return nil
 }

 // MARK: what could send or buy something (these need his Allow, and she is told to ask him out loud too)

 private static let riskyPattern = try! NSRegularExpression(pattern:"\\b(send|submit|post|publish|buy|pay|purchase|checkout|check out|place order|order|confirm|subscribe|donate|tip|transfer|withdraw|delete|remove|reply|tweet|share|book|reserve|apply|upload|sign up|register|accept|agree|bid|invoice|trade|sell)\\b",options:[.caseInsensitive])
 private static let riskyWindowPattern = try! NSRegularExpression(pattern:"\\b(checkout|check out|payment|billing|cart|basket|order|invoice|purchase|confirm|subscription)\\b",options:[.caseInsensitive])

 private static func matches(_ regex: NSRegularExpression,_ text: String) -> Bool {
  regex.firstMatch(in:text,options:[],range:NSRange(text.startIndex..<text.endIndex,in:text)) != nil
 }

 // What she says she is clicking ("Send button") or what the button under the pointer is called.
 static func riskyIntent(_ text: String) -> Bool { !text.isEmpty && matches(riskyPattern,text) }

 // A window whose title says it is a checkout, payment, cart or order page: everything done there needs Allow.
 static func riskyWindow(title: String) -> Bool { !title.isEmpty && matches(riskyWindowPattern,title) }

 // 13 to 19 digits with only spaces or dashes between them: it looks like a card number, so she won't type it.
 static func looksLikeCardNumber(_ text: String) -> Bool {
  let digits = text.filter { $0.isNumber }
  let others = text.filter { !$0.isNumber && $0 != " " && $0 != "-" }
  return digits.count >= 13 && digits.count <= 19 && others.isEmpty
 }

 // Pressing Return or Enter is how most things get sent, so it always needs Allow.
 static func needsAllow(_ press: KeyPress) -> Bool { press.code == 36 }
}
