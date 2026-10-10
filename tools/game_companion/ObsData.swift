import Foundation

// Friday's link to OBS Studio, with no Mac frameworks so the rules can be tested anywhere. Matthew's ask (2026-10-10): stream his PlayStation
// with a camera that is NOT plugged into the console, through OBS on his Mac, and let Friday work it.
// OBS has a remote-control door built in since OBS 28 (Tools > WebSocket Server Settings). It speaks "obs-websocket 5.x". Checked against the
// protocol document in github.com/obsproject/obs-websocket (docs/generated/protocol.md) on 2026-10-10: the messages (Hello 0, Identify 1,
// Identified 2, Request 6, RequestResponse 7), the login recipe, and the request and field names used below. The login recipe was also run against the
// document's own example values (password supersecretpassword) and gives the answer it shows.
// What it will and won't do: it only talks to OBS on THIS Mac (127.0.0.1), never another machine. The OBS password is a secret: it lives in a
// private file (SecretFile.swift), never in chat, the feed or the repo. Switching scenes, saving a replay and muting are free; going live or
// ending the stream needs Matthew's Allow box every single time.

enum ObsPlan {
 static let defaultPort = 4455
 static let rpcVersion = 1
 static let subprotocol = "obswebsocket.json"
 static let passwordService = "obs.websocket.password"

 // MARK: where to connect

 // The port typed in Settings. Empty means OBS's usual 4455. Anything that is not a number from 1024 to 65535 is refused.
 static func port(_ raw: String) -> Int? {
  let text = raw.trimmingCharacters(in:.whitespacesAndNewlines)
  if text.isEmpty { return defaultPort }
  guard text.count <= 5, text.allSatisfy({ $0.isASCII && $0.isNumber }), let value = Int(text), (1024...65535).contains(value) else { return nil }
  return value
 }

 // Always this Mac. There is no way to point it anywhere else.
 static func url(port: Int) -> URL? { URL(string:"ws://127.0.0.1:\(port)") }

 // MARK: the login (SHA-256 in plain Swift, so it runs and is tested on any machine)

 private static let roundConstants: [UInt32] = [
  0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
  0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
  0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
  0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
  0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
  0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
  0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
  0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
 ]

 private static func rotr(_ x: UInt32,_ n: UInt32) -> UInt32 { (x >> n) | (x << (32 - n)) }

 static func sha256(_ message: [UInt8]) -> [UInt8] {
  var state: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
  var data = message
  let bits = UInt64(message.count) * 8
  data.append(0x80)
  while data.count % 64 != 56 { data.append(0) }
  for shift in stride(from:56,through:0,by:-8) { data.append(UInt8((bits >> UInt64(shift)) & 0xff)) }
  var w = [UInt32](repeating:0,count:64)
  for chunk in stride(from:0,to:data.count,by:64) {
   for i in 0..<16 {
    let j = chunk + i * 4
    let b0 = UInt32(data[j]) << 24
    let b1 = UInt32(data[j + 1]) << 16
    let b2 = UInt32(data[j + 2]) << 8
    let b3 = UInt32(data[j + 3])
    w[i] = b0 | b1 | b2 | b3
   }
   for i in 16..<64 {
    let a15 = w[i - 15]
    let a2 = w[i - 2]
    let s0 = rotr(a15,7) ^ rotr(a15,18) ^ (a15 >> 3)
    let s1 = rotr(a2,17) ^ rotr(a2,19) ^ (a2 >> 10)
    w[i] = w[i - 16] &+ s0 &+ w[i - 7] &+ s1
   }
   var a = state[0], b = state[1], c = state[2], d = state[3]
   var e = state[4], f = state[5], g = state[6], h = state[7]
   for i in 0..<64 {
    let big1 = rotr(e,6) ^ rotr(e,11) ^ rotr(e,25)
    let choose = (e & f) ^ (~e & g)
    let temp1 = h &+ big1 &+ choose &+ roundConstants[i] &+ w[i]
    let big0 = rotr(a,2) ^ rotr(a,13) ^ rotr(a,22)
    let majority = (a & b) ^ (a & c) ^ (b & c)
    let temp2 = big0 &+ majority
    h = g; g = f; f = e
    e = d &+ temp1
    d = c; c = b; b = a
    a = temp1 &+ temp2
   }
   state[0] = state[0] &+ a; state[1] = state[1] &+ b; state[2] = state[2] &+ c; state[3] = state[3] &+ d
   state[4] = state[4] &+ e; state[5] = state[5] &+ f; state[6] = state[6] &+ g; state[7] = state[7] &+ h
  }
  var digest: [UInt8] = []
  for word in state {
   digest.append(UInt8(word >> 24))
   digest.append(UInt8((word >> 16) & 0xff))
   digest.append(UInt8((word >> 8) & 0xff))
   digest.append(UInt8(word & 0xff))
  }
  return digest
 }

 // OBS's recipe: secret = base64(sha256(password + salt)); answer = base64(sha256(secret + challenge)). Both hashes are the raw 32 bytes.
 static func authentication(password: String,salt: String,challenge: String) -> String {
  let secret = Data(sha256(Array((password + salt).utf8))).base64EncodedString()
  return Data(sha256(Array((secret + challenge).utf8))).base64EncodedString()
 }

 // MARK: the messages

 static func int(_ value: Any?) -> Int? {
  if let n = value as? Int { return n }
  if let n = value as? Double, n.isFinite { return Int(n) }
  if let n = value as? NSNumber { return n.intValue }
  return nil
 }

 static func number(_ value: Any?) -> Double? {
  if let n = value as? Double { return n }
  if let n = value as? Int { return Double(n) }
  if let n = value as? NSNumber { return n.doubleValue }
  return nil
 }

 static func object(_ data: Data) -> [String:Any]? { (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] }

 static func opcode(_ data: Data) -> Int? { int(object(data)?["op"]) }

 struct Hello: Equatable {
  var obsVersion: String
  var socketVersion: String
  var rpc: Int
  var challenge: String?
  var salt: String?
  var needsPassword: Bool { challenge != nil && salt != nil }
 }

 // OBS speaks first: {"op":0,"d":{"obsStudioVersion":"..","obsWebSocketVersion":"..","rpcVersion":1,"authentication":{"challenge":"..","salt":".."}}}
 // There is no "authentication" part when OBS has no password set.
 static func hello(_ data: Data) -> Hello? {
  guard let top = object(data), int(top["op"]) == 0, let body = top["d"] as? [String:Any] else { return nil }
  var found = Hello(obsVersion:body["obsStudioVersion"] as? String ?? "",socketVersion:body["obsWebSocketVersion"] as? String ?? "",rpc:int(body["rpcVersion"]) ?? 1,challenge:nil,salt:nil)
  if let auth = body["authentication"] as? [String:Any], let challenge = auth["challenge"] as? String, let salt = auth["salt"] as? String {
   found.challenge = challenge
   found.salt = salt
  }
  return found
 }

 // Our answer. eventSubscriptions 0 means "send me no events", so nothing but our own answers ever arrives.
 static func identify(authentication: String?) -> Data? {
  var body: [String:Any] = ["rpcVersion":rpcVersion,"eventSubscriptions":0]
  if let answer = authentication { body["authentication"] = answer }
  let message: [String:Any] = ["op":1,"d":body]
  return try? JSONSerialization.data(withJSONObject:message)
 }

 static func isIdentified(_ data: Data) -> Bool { opcode(data) == 2 }

 static func request(type: String,id: String,fields: [String:Any]? = nil) -> Data? {
  var body: [String:Any] = ["requestType":type,"requestId":id]
  if let fields = fields, !fields.isEmpty { body["requestData"] = fields }
  let message: [String:Any] = ["op":6,"d":body]
  return try? JSONSerialization.data(withJSONObject:message)
 }

 struct Reply {
  var id: String
  var type: String
  var ok: Bool
  var code: Int
  var comment: String
  var fields: [String:Any]
 }

 static func reply(_ data: Data) -> Reply? {
  guard let top = object(data), int(top["op"]) == 7, let body = top["d"] as? [String:Any],
        let id = body["requestId"] as? String, let status = body["requestStatus"] as? [String:Any] else { return nil }
  let code = int(status["code"]) ?? 0
  let ok = (status["result"] as? Bool) ?? (code == 100)
  return Reply(id:id,type:body["requestType"] as? String ?? "",ok:ok,code:code,comment:status["comment"] as? String ?? "",fields:body["responseData"] as? [String:Any] ?? [:])
 }

 // MARK: plain words for what went wrong

 static let unreachable = "I couldn't reach OBS. Is OBS open, and is its remote-control door switched on (in OBS: Tools, then WebSocket Server Settings, tick Enable WebSocket server)? If you changed the port there, it has to match the port in the app."

 static func closeReason(_ code: Int) -> String {
  switch code {
  case 4009: return "OBS says the password is wrong. In OBS open Tools, WebSocket Server Settings, press Show Connect Info, and paste the password into the app again."
  case 4010: return "This OBS speaks a different version of the remote-control language than the app does. Updating OBS usually fixes it."
  case 4011: return "OBS ended the session."
  default: return "OBS hung up on me (code \(code))."
  }
 }

 static func failure(_ reply: Reply,doing: String) -> String {
  let note = reply.comment.trimmingCharacters(in:.whitespacesAndNewlines)
  switch reply.code {
  case 207: return "OBS isn't ready yet. Give it a few seconds and ask again."
  case 600: return "OBS couldn't find that\(note.isEmpty ? "" : " (\(note))")."
  case 604: return "OBS can't do that right now\(note.isEmpty ? "" : ": \(note)")."
  default: return note.isEmpty ? "OBS said no to \(doing) (code \(reply.code))." : "OBS said no to \(doing): \(note)"
  }
 }

 // MARK: names the player says

 static func normal(_ raw: String) -> String {
  var text = raw.lowercased().split(whereSeparator:{ $0.isWhitespace }).joined(separator:" ")
  if text.hasSuffix(" scene") { text = String(text.dropLast(6)) }
  return text.trimmingCharacters(in:.whitespaces)
 }

 // A name sent on to OBS: no control characters, no more than 100 characters, something left after trimming.
 static func cleanName(_ raw: String) -> String? {
  let scalars = raw.unicodeScalars.filter { !CharacterSet.controlCharacters.contains($0) }
  let text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in:.whitespacesAndNewlines)
  guard !text.isEmpty, text.count <= 100 else { return nil }
  return text
 }

 enum Pick: Equatable {
  case one(String)
  case several([String])
  case none
 }

 // Which scene the player means: the exact name first, then a name that starts with the words, then one that contains them.
 static func pick(_ spoken: String,from names: [String]) -> Pick {
  let want = normal(spoken)
  guard !want.isEmpty else { return .none }
  func decide(_ found: [String]) -> Pick? {
   if found.count == 1 { return .one(found[0]) }
   return found.count > 1 ? .several(found) : nil
  }
  if let answer = decide(names.filter { normal($0) == want }) { return answer }
  if let answer = decide(names.filter { normal($0).hasPrefix(want) }) { return answer }
  if let answer = decide(names.filter { normal($0).contains(want) }) { return answer }
  return .none
 }

 enum MuteTarget: Equatable {
  case mic
  case desktop
  case named(String)
 }

 static func muteTarget(_ raw: String) -> MuteTarget {
  let word = normal(raw)
  let mics: Set<String> = ["mic","microphone","my mic","my microphone","mic/aux","mic aux","voice"]
  let desktops: Set<String> = ["desktop","desktop audio","game","game audio","game sound","computer","computer audio","system audio"]
  if mics.contains(word) { return .mic }
  if desktops.contains(word) { return .desktop }
  return .named(raw.trimmingCharacters(in:.whitespacesAndNewlines))
 }

 // MARK: what she tells the player about OBS

 struct Snapshot {
  var obsVersion = ""
  var streaming = false
  var reconnecting = false
  var streamMinutes = 0
  var skippedPercent = 0.0
  var recording = false
  var replayOn = false
  var scene = ""
  var scenes: [String] = []
  var inputs: [String] = []
 }

 static func minutes(milliseconds: Double?) -> Int {
  guard let ms = milliseconds, ms.isFinite, ms > 0 else { return 0 }
  return Int(ms / 60000)
 }

 static func duration(_ total: Int) -> String {
  if total < 1 { return "under a minute" }
  if total < 60 { return total == 1 ? "1 minute" : "\(total) minutes" }
  let hours = total / 60
  let rest = total % 60
  let first = hours == 1 ? "1 hour" : "\(hours) hours"
  return rest == 0 ? first : "\(first) \(rest) minute\(rest == 1 ? "" : "s")"
 }

 static func skippedPercent(skipped: Double?,total: Double?) -> Double {
  guard let skipped = skipped, let total = total, total >= 300, skipped >= 0 else { return 0 }
  return skipped / total * 100
 }

 static func describe(_ s: Snapshot) -> String {
  var parts: [String] = []
  if s.streaming {
   parts.append(s.reconnecting ? "OBS is streaming but it is reconnecting to Twitch right now" : "OBS is LIVE, on air for \(duration(s.streamMinutes))")
   if s.skippedPercent >= 1 { parts.append("it is dropping about \(Int(s.skippedPercent.rounded()))% of frames, so the stream may stutter")  }
  } else {
   parts.append("OBS is open but NOT streaming")
  }
  if s.recording { parts.append("it is recording to a file") }
  parts.append(s.replayOn ? "the replay buffer is on, so a highlight can be saved" : "the replay buffer is off")
  if !s.scene.isEmpty { parts.append("the current scene is “\(s.scene)”") }
  var text = parts.joined(separator:"; ") + "."
  if !s.scenes.isEmpty { text += " Scenes: " + s.scenes.prefix(12).map { "“\($0)”" }.joined(separator:", ") + "." }
  if !s.inputs.isEmpty { text += " Audio and video sources: " + s.inputs.prefix(12).map { "“\($0)”" }.joined(separator:", ") + "." }
  return text
 }

 // What the Allow box says. Going live is public the moment it starts.
 static func goLiveDetail(scene: String) -> String {
  scene.isEmpty ? "OBS will start streaming to your channel. Everything on your OBS screen becomes public right away." : "OBS will start streaming to your channel on the “\(scene)” scene. Everything on your OBS screen becomes public right away."
 }

 static let stopDetail = "OBS will end your live stream now. Viewers will see it stop."

 // At most `max` of these in the last `window` seconds. Used to keep her from hammering OBS.
 static func underLimit(_ times: [Date],now: Date,window: TimeInterval,max: Int) -> Bool {
  times.filter { now.timeIntervalSince($0) < window }.count < max
 }
}
