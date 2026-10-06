import Cocoa
import Security

// Twitch login for the clip account. The Client ID is public (it only names the app), so it lives in
// settings. The login tokens are secrets, so they are saved privately on this Mac (see Keychain.swift), never in Git or chat.
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
 // After each clip: download it, cut the highlight and make a wide and a tall version on this Mac (see ClipEditor.swift).
 @Published var autoEdit = UserDefaults.standard.object(forKey:"twitch.autoEdit") as? Bool ?? true { didSet { UserDefaults.standard.set(autoEdit,forKey:"twitch.autoEdit") } }
 @Published var highlightSeconds = UserDefaults.standard.object(forKey:"twitch.highlight") as? Int ?? 25 { didSet { UserDefaults.standard.set(highlightSeconds,forKey:"twitch.highlight") } }
 @Published var signedIn = TwitchTokens.isSaved
 @Published var editStatus = ""
 @Published var editing = false
 @Published var lastFolder: URL?
 @Published var status = ""
 @Published var userCode = ""
 @Published var lastClipURL = ""
 @Published var busy = false
 var lastClip = Date.distantPast
 // Called with the folder and title after a clip has been downloaded and cut (the autopilot saves a TikTok caption there).
 var onTidied: ((URL,String) -> Void)?
 // Called after the highlight is cut and before onTidied: Friday's voice-over adds its own version of the clip here (VoiceOver.swift).
 var afterEdit: ((URL,String) async -> Void)?
 var loginTask: Task<Void,Never>?
 var inFlight: Task<String,Never>?
 // clips:edit makes the clip. The two manage-clips permissions let the app download it (whichever fits the account).
 // channel:manage:broadcast lets the Stream page change the title and category and add stream markers; user:write:chat lets the chat helper post.
 static let scopes = "clips:edit channel:manage:clips editor:manage:clips channel:manage:broadcast user:write:chat"
 static let queryAllowed = CharacterSet(charactersIn:"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

 static let api = "https://api.twitch.tv/helix"
 let session = URLSession(configuration:.ephemeral)

 // MARK: sign in

 func signIn() {
  let id = clientID.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !id.isEmpty else { status = "Paste your Twitch Client ID first."; return }
  loginTask?.cancel()
  loginTask = Task {
   do {
    let start = try await form("https://id.twitch.tv/oauth2/device",["client_id":id,"scopes":TwitchClips.scopes])
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
     let reply = try await form("https://id.twitch.tv/oauth2/token",["client_id":id,"device_code":device,"grant_type":"urn:ietf:params:oauth:grant-type:device_code","scopes":TwitchClips.scopes])
     if let access = reply["access_token"] as? String {
      let saved = TwitchTokens.save(["access":access,"refresh":reply["refresh_token"] as? String ?? ""])
      signedIn = saved; userCode = ""
      status = saved ? "Signed in. The login is saved privately on this Mac." : "Signed in, but this Mac wouldn't save the login. Try again."
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

 func signOut() { loginTask?.cancel(); TwitchTokens.delete(); signedIn = false; userCode = ""; status = "Signed out. Login removed from this Mac." }

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
 func call(_ path: String,method: String = "GET",body: Data? = nil) async throws -> (Int,[String:Any]) {
  guard var tokens = TwitchTokens.load(), let access = tokens["access"] else { throw NSError(domain:"clips",code:1,userInfo:[NSLocalizedDescriptionKey:"Not signed in to Twitch."]) }
  var token = access
  for attempt in 0..<2 {
   var request = URLRequest(url:URL(string:TwitchClips.api + path)!)
   request.httpMethod = method
   request.setValue("Bearer \(token)",forHTTPHeaderField:"Authorization")
   request.setValue(clientID.trimmingCharacters(in:.whitespacesAndNewlines),forHTTPHeaderField:"Client-Id")
   if let body = body { request.httpBody = body; request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
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
 // The buddy's tool call and the app's own listening can both fire on one "clip it". The second joins the first
 // instead of making another clip.
 @discardableResult func clipNow(title: String = "") async -> String {
  if let running = inFlight { return await running.value }
  let task = Task { await self.makeClip(title:title) }
  inFlight = task
  let result = await task.value
  inFlight = nil
  return result
 }

 // How long the Twitch clip is. Twitch allows 5 to 60 seconds; the cut then trims it to the highlight.
 var clipSeconds: Int { max(30,min(60,highlightSeconds + 15)) }

 func clipPath(_ broadcasterID: String,_ title: String) -> String {
  var path = "/clips?broadcaster_id=\(broadcasterID)&duration=\(clipSeconds)"
  if !title.isEmpty, let encoded = title.addingPercentEncoding(withAllowedCharacters:TwitchClips.queryAllowed) { path += "&title=\(encoded)" }
  return path
 }

 func makeClip(title rawTitle: String) async -> String {
  let login = channel.trimmingCharacters(in:CharacterSet(charactersIn:"@ \n")).lowercased()
  guard signedIn else { return say("Not signed in to Twitch yet.") }
  guard !login.isEmpty else { return say("Type your Twitch channel name first.") }
  if Date().timeIntervalSince(lastClip) < 30 { return say("Already clipped that a moment ago.\(lastClipURL.isEmpty ? "" : " " + lastClipURL)") }
  busy = true; defer { busy = false }
  let title = String(rawTitle.trimmingCharacters(in:.whitespacesAndNewlines).prefix(100))
  do {
   let (_,who) = try await call("/users?login=\(login)")
   guard let id = (who["data"] as? [[String:Any]])?.first?["id"] as? String else { return say("Couldn't find a Twitch channel called \(login).") }
   var (code,made) = try await call(clipPath(id,title),method:"POST")
   // A title can fail Twitch's AutoMod check (a 400). Clip without it rather than lose the moment.
   if code == 400, !title.isEmpty { (code,made) = try await call(clipPath(id,""),method:"POST") }
   guard code == 202, let clipID = (made["data"] as? [[String:Any]])?.first?["id"] as? String else {
    let reason = made["message"] as? String ?? "HTTP \(code)"
    // Twitch only clips a channel that is live right now, and the channel can turn clips off.
    return say("Twitch didn't make the clip: \(reason). It only works while \(login) is live and has clips on.")
   }
   lastClip = Date()
   ClipLedger.add(clipID)
   // The clip can take several seconds to appear on Twitch; check before claiming success.
   var exists = false
   for _ in 0..<6 {
    try await Task.sleep(nanoseconds:3_000_000_000)
    let (_,found) = try await call("/clips?id=\(clipID)")
    if !((found["data"] as? [[String:Any]]) ?? []).isEmpty { exists = true; break }
   }
   lastClipURL = "https://clips.twitch.tv/\(clipID)"
   guard exists else { return say("Twitch accepted the clip but it isn't showing yet. Check \(lastClipURL) in a minute.") }
   if autoEdit { Task { await self.tidyClip(clipID:clipID,broadcasterID:id,title:title) } }
   let followUp = autoEdit ? " I'm downloading it and cutting the highlight now; the edited versions will be in the Game Companion Clips folder in a minute or two." : ""
   return say("Clip made: about \(clipSeconds) seconds of \(login). \(lastClipURL)\(followUp)")
  } catch {
   return say("Clip failed: \(error.localizedDescription)")
  }
 }

 // MARK: download and edit

 static var clipsRoot: URL { FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Movies/Game Companion Clips",isDirectory:true) }

 func clipsFolder(for title: String) -> URL {
  let stamp = DateFormatter()
  stamp.locale = Locale(identifier:"en_US_POSIX")
  stamp.dateFormat = "yyyy-MM-dd HH.mm"
  let clean = title.components(separatedBy:CharacterSet(charactersIn:"/\\:?*\"<>|")).joined().trimmingCharacters(in:.whitespaces)
  let name = clean.isEmpty ? stamp.string(from:Date()) : "\(stamp.string(from:Date())) - \(clean.prefix(60))"
  return TwitchClips.clipsRoot.appendingPathComponent(name,isDirectory:true)
 }

 // Twitch hands out a temporary download link for a clip. It needs the manage-clips permission, which a sign-in made
 // before this feature doesn't have, so a 401 here means "sign in again". Returns nil if the file isn't ready after ~30 seconds.
 func downloadLink(clipID: String,broadcasterID: String) async throws -> URL? {
  let (_,me) = try await call("/users")
  guard let editorID = (me["data"] as? [[String:Any]])?.first?["id"] as? String else {
   throw NSError(domain:"clips",code:5,userInfo:[NSLocalizedDescriptionKey:"Twitch didn't say which account is signed in."])
  }
  for _ in 0..<10 {
   let (code,reply) = try await call("/clips/downloads?broadcaster_id=\(broadcasterID)&editor_id=\(editorID)&clip_id=\(clipID)")
   if code == 401 { throw NSError(domain:"clips",code:6,userInfo:[NSLocalizedDescriptionKey:"Twitch needs one more permission to download clips. Click Sign out of Twitch, then sign in again."]) }
   if code == 403 { throw NSError(domain:"clips",code:7,userInfo:[NSLocalizedDescriptionKey:"The clip account isn't an Editor on your channel. Add it as an Editor in Twitch's Creator Dashboard (Roles), or sign in with your own account."]) }
   if code == 200, let link = ((reply["data"] as? [[String:Any]])?.first?["landscape_download_url"] as? String), let url = URL(string:link) { return url }
   try await Task.sleep(nanoseconds:3_000_000_000)
  }
  return nil
 }

 func tidyClip(clipID: String,broadcasterID: String,title: String) async {
  editing = true
  defer { editing = false }
  do {
   editStatus = "Getting the clip file from Twitch…"
   guard let link = try await downloadLink(clipID:clipID,broadcasterID:broadcasterID) else {
    editStatus = "Twitch hasn't made the clip file yet. The clip itself is fine: \(lastClipURL)"
    return
   }
   let folder = clipsFolder(for:title)
   try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
   let original = folder.appendingPathComponent("original.mp4")
   editStatus = "Downloading the clip…"
   let (temporary,response) = try await session.download(from:link)
   if let http = response as? HTTPURLResponse, http.statusCode != 200 {
    throw NSError(domain:"clips",code:8,userInfo:[NSLocalizedDescriptionKey:"Twitch's download link didn't work (code \(http.statusCode))."])
   }
   try? FileManager.default.removeItem(at:original)
   try FileManager.default.moveItem(at:temporary,to:original)
   editStatus = "Cutting the highlight…"
   let files = try await ClipEditor.tidy(original:original,folder:folder,maxLength:Double(highlightSeconds))
   lastFolder = folder
   await afterEdit?(folder,title)
   onTidied?(folder,title)
   editStatus = "Done: a \(Int(files.cut.length.rounded()))-second highlight, wide and tall, saved in Movies > Game Companion Clips > \(folder.lastPathComponent). \(files.note)".trimmingCharacters(in:.whitespaces)
   NSWorkspace.shared.activateFileViewerSelecting([files.vertical ?? files.landscape ?? original])
  } catch {
   editStatus = "Couldn't edit the clip: \(error.localizedDescription) The Twitch clip itself is fine: \(lastClipURL)"
  }
 }

 func say(_ text: String) -> String { status = text; return text }
}
