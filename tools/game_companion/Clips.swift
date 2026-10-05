import Cocoa
import Security

// Twitch login for the clip account. The Client ID is public (it only names the app), so it lives in
// settings. The login tokens are secrets, so they live in the macOS Keychain, never in files or chat.
enum TwitchTokens {
 static let service = "GameCompanion.TwitchTokens"
 // "Signed in?" never asks for a password. Reading the tokens can, so that happens once per run (see Keychain.swift).
 static var isSaved: Bool { Keychain.exists(service) }
 static func load() -> [String:String]? {
  guard let data = Keychain.read(service) else { return nil }
  return (try? JSONSerialization.jsonObject(with:data)) as? [String:String]
 }
 static func save(_ tokens: [String:String]) -> Bool {
  guard let data = try? JSONSerialization.data(withJSONObject:tokens) else { return false }
  return Keychain.write(service,data)
 }
 static func delete() { Keychain.remove(service) }
}

// Makes Twitch clips of Matthew's stream from a separate "clip" Twitch account (or his own; whichever
// account he approves in the browser). Twitch's Create Clip call grabs the last ~30 seconds of a LIVE
// channel and posts the clip on Twitch right away, so it only ever runs when he clicks the button
// or asks the buddy out loud, and never more than once every 30 seconds.
// Sign-in uses Twitch's Device Code flow (no client secret needed): the app shows a code, Matthew
// approves it on twitch.tv in his browser. Docs: dev.twitch.tv/docs/authentication/getting-tokens-oauth
// and dev.twitch.tv/docs/api/reference#create-clip (checked 2026-10-05).
@MainActor final class TwitchClips: ObservableObject {
 @Published var clientID = UserDefaults.standard.string(forKey:"twitch.clientID") ?? "" { didSet { UserDefaults.standard.set(clientID,forKey:"twitch.clientID") } }
 @Published var channel = UserDefaults.standard.string(forKey:"twitch.channel") ?? "" { didSet { UserDefaults.standard.set(channel,forKey:"twitch.channel") } }
 // Off until Matthew ticks it: lets the live buddy make a clip when he says "clip that".
 @Published var voiceClips = UserDefaults.standard.object(forKey:"twitch.voice") as? Bool ?? false { didSet { UserDefaults.standard.set(voiceClips,forKey:"twitch.voice") } }
 @Published var signedIn = TwitchTokens.isSaved
 @Published var status = ""
 @Published var userCode = ""
 @Published var lastClipURL = ""
 @Published var busy = false
 var lastClip = Date.distantPast
 var loginTask: Task<Void,Never>?

 static let api = "https://api.twitch.tv/helix"
 let session = URLSession(configuration:.ephemeral)

 // MARK: sign in

 func signIn() {
  let id = clientID.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !id.isEmpty else { status = "Paste your Twitch Client ID first."; return }
  loginTask?.cancel()
  loginTask = Task {
   do {
    let start = try await form("https://id.twitch.tv/oauth2/device",["client_id":id,"scopes":"clips:edit"])
    guard let device = start["device_code"] as? String, let code = start["user_code"] as? String, let link = start["verification_uri"] as? String else {
     status = "Twitch didn't start the sign-in: \(start["message"] as? String ?? "unknown reason")"; return
    }
    userCode = code
    let wait = start["interval"] as? Double ?? 5
    let deadline = Date().addingTimeInterval(start["expires_in"] as? Double ?? 1800)
    status = "A Twitch page is opening. Log in as the CLIP account, type the code \(code) if it asks, and click Authorize."
    if let url = URL(string:link) { NSWorkspace.shared.open(url) }
    while Date() < deadline && !Task.isCancelled {
     try await Task.sleep(nanoseconds:UInt64(wait*1_000_000_000))
     let reply = try await form("https://id.twitch.tv/oauth2/token",["client_id":id,"device_code":device,"grant_type":"urn:ietf:params:oauth:grant-type:device_code","scopes":"clips:edit"])
     if let access = reply["access_token"] as? String {
      let saved = TwitchTokens.save(["access":access,"refresh":reply["refresh_token"] as? String ?? ""])
      signedIn = saved; userCode = ""
      status = saved ? "Signed in. Tokens are in your Mac's Keychain." : "Signed in, but the Keychain wouldn't save the login. Try again."
      return
     }
     // "authorization_pending" just means he hasn't clicked Authorize yet.
     let message = (reply["message"] as? String ?? "").lowercased()
     if !message.contains("pending") { status = "Twitch said: \(reply["message"] as? String ?? "sign-in failed")"; userCode = ""; return }
    }
    userCode = ""
    if !Task.isCancelled { status = "Sign-in timed out. Click Sign in again." }
   } catch is CancellationError {
   } catch {
    userCode = ""; status = "Couldn't reach Twitch: \(error.localizedDescription)"
   }
  }
 }

 func signOut() { loginTask?.cancel(); TwitchTokens.delete(); signedIn = false; userCode = ""; status = "Signed out. Login removed from the Keychain." }

 // POSTs form fields and returns Twitch's JSON, whatever the status code (errors carry a "message").
 func form(_ url: String,_ fields: [String:String]) async throws -> [String:Any] {
  var request = URLRequest(url:URL(string:url)!)
  request.httpMethod = "POST"
  request.setValue("application/x-www-form-urlencoded",forHTTPHeaderField:"Content-Type")
  var parts = URLComponents(); parts.queryItems = fields.map { URLQueryItem(name:$0.key,value:$0.value) }
  request.httpBody = parts.percentEncodedQuery?.data(using:.utf8)
  let (data,_) = try await session.data(for:request)
  return (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
 }

 // MARK: clipping

 // Calls Twitch with the saved login. If the token has expired, refreshes it once and retries.
 func call(_ path: String,method: String = "GET") async throws -> (Int,[String:Any]) {
  guard var tokens = TwitchTokens.load(), let access = tokens["access"] else { throw NSError(domain:"clips",code:1,userInfo:[NSLocalizedDescriptionKey:"Not signed in to Twitch."]) }
  var token = access
  for attempt in 0..<2 {
   var request = URLRequest(url:URL(string:TwitchClips.api + path)!)
   request.httpMethod = method
   request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
   request.setValue(clientID.trimmingCharacters(in:.whitespacesAndNewlines),forHTTPHeaderField:"Client-Id")
   let (data,response) = try await session.data(for:request)
   let code = (response as? HTTPURLResponse)?.statusCode ?? 0
   if code == 401 && attempt == 0, let refresh = tokens["refresh"], !refresh.isEmpty {
    let fresh = try await form("https://id.twitch.tv/oauth2/token",["client_id":clientID.trimmingCharacters(in:.whitespacesAndNewlines),"grant_type":"refresh_token","refresh_token":refresh])
    guard let newAccess = fresh["access_token"] as? String else { signOut(); throw NSError(domain:"clips",code:2,userInfo:[NSLocalizedDescriptionKey:"Twitch login expired. Click Sign in again."]) }
    tokens = ["access":newAccess,"refresh":fresh["refresh_token"] as? String ?? refresh]
    _ = TwitchTokens.save(tokens); token = newAccess
    continue
   }
   return (code,(try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:])
  }
  throw NSError(domain:"clips",code:3,userInfo:[NSLocalizedDescriptionKey:"Twitch kept refusing the login."])
 }

 // Returns a sentence the buddy can read out, and also sets the on-screen status.
 @discardableResult func clipNow() async -> String {
  let login = channel.trimmingCharacters(in:CharacterSet(charactersIn:"@ \n")).lowercased()
  guard signedIn else { return say("Not signed in to Twitch yet.") }
  guard !login.isEmpty else { return say("Type your Twitch channel name first.") }
  guard !busy else { return say("Already making a clip.") }
  if Date().timeIntervalSince(lastClip) < 30 { return say("A clip was made less than 30 seconds ago. Wait a moment.") }
  busy = true; defer { busy = false }
  do {
   let (_,who) = try await call("/users?login=\(login)")
   guard let id = (who["data"] as? [[String:Any]])?.first?["id"] as? String else { return say("Couldn't find a Twitch channel called \(login).") }
   let (code,made) = try await call("/clips?broadcaster_id=\(id)",method:"POST")
   guard code == 202, let clipID = (made["data"] as? [[String:Any]])?.first?["id"] as? String else {
    let reason = made["message"] as? String ?? "HTTP \(code)"
    // Twitch only clips a channel that is live right now, and the channel can turn clips off.
    return say("Twitch didn't make the clip: \(reason). It only works while \(login) is live and has clips on.")
   }
   lastClip = Date()
   // The clip can take several seconds to appear on Twitch; check before claiming success.
   var exists = false
   for _ in 0..<6 {
    try await Task.sleep(nanoseconds:3_000_000_000)
    let (_,found) = try await call("/clips?id=\(clipID)")
    if !((found["data"] as? [[String:Any]]) ?? []).isEmpty { exists = true; break }
   }
   lastClipURL = "https://clips.twitch.tv/\(clipID)"
   return say(exists ? "Clip made: the last ~30 seconds of \(login). \(lastClipURL)" : "Twitch accepted the clip but it isn't showing yet. Check \(lastClipURL) in a minute.")
  } catch {
   return say("Clip failed: \(error.localizedDescription)")
  }
 }

 func say(_ text: String) -> String { status = text; return text }
}
