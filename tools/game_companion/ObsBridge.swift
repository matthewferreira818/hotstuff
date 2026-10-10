import SwiftUI
import AppKit

// Friday's link to OBS Studio on this Mac, and the OBS card on the Stream page. The rules, the messages and the login maths are in
// ObsData.swift (tested). This file does the talking on the Mac.
// Matthew's ask (2026-10-10): stream the PlayStation with a camera that is not plugged into the console, through OBS, and let Friday work it.
// How it talks: OBS has a remote-control door built in (Tools > WebSocket Server Settings). Each job opens a short connection to OBS on THIS Mac
// only (127.0.0.1), logs in, sends its requests, and hangs up, so there is nothing to keep alive and nothing to leave open.
// What she can do: look at OBS, switch scenes, save a replay, mute or unmute the mic or the game sound, and go live or end the stream.
// Going live or ending the stream needs Matthew's press on the Allow box every time; everything else is free. The OBS password is a secret kept
// in a private file (SecretFile.swift): she never sees it and it never appears in a tool result, the feed or chat.
// Checked against Apple's docs on 2026-10-10: URLSession.webSocketTask(with:protocols:), URLSessionWebSocketTask.send(_:) and receive() (async),
// cancel(with:reason:).

@MainActor final class ObsHub: ObservableObject {
 @Published var enabled = UserDefaults.standard.object(forKey:"obs.on") as? Bool ?? true { didSet { UserDefaults.standard.set(enabled,forKey:"obs.on") } }
 @Published var portText = UserDefaults.standard.string(forKey:"obs.port") ?? "" { didSet { UserDefaults.standard.set(portText,forKey:"obs.port") } }
 // True once a test against OBS has worked. Friday's OBS tools only exist while this is on and the switch is on.
 @Published var ready = UserDefaults.standard.bool(forKey:"obs.ready") { didSet { UserDefaults.standard.set(ready,forKey:"obs.ready") } }
 @Published var passwordInput = ""
 @Published var hasPassword = Keychain.exists(ObsPlan.passwordService)
 @Published var working = false
 @Published var message = ""
 @Published var snapshot: ObsPlan.Snapshot?
 // Set by the window: shows the Allow box. Going live and ending the stream wait for it.
 var approve: ((String,String) async -> Bool)?
 private var recent: [Date] = []
 private var liveChanges: [Date] = []

 var usable: Bool { enabled && ready }

 private static let notLinked = "OBS isn't linked yet. Tell the player to open the OBS card on the Stream page and press Save and test."

 private struct Job {
  var type: String
  var fields: [String:Any]? = nil
 }

 private enum Outcome {
  case ok([String:ObsPlan.Reply])
  case failed(String)
 }

 private func bytes(_ message: URLSessionWebSocketTask.Message) -> Data? {
  switch message {
  case .string(let text): return text.data(using:.utf8)
  case .data(let data): return data
  @unknown default: return nil
  }
 }

 private func savedPassword() -> String? {
  guard let data = Keychain.read(ObsPlan.passwordService), let text = String(data:data,encoding:.utf8), !text.isEmpty else { return nil }
  return text
 }

 // One short visit to OBS: connect, take the hello, log in, run the jobs in order, hang up. Gives up after 10 seconds.
 private func talk(_ jobs: [Job],password: String?) async -> Outcome {
  guard let port = ObsPlan.port(portText), let url = ObsPlan.url(port:port) else {
   return .failed("The port in the OBS box has to be a number from 1024 to 65535 (OBS usually uses 4455).")
  }
  let started = Date()
  let session = URLSession(configuration:.ephemeral)
  let socket = session.webSocketTask(with:url,protocols:[ObsPlan.subprotocol])
  socket.resume()
  let watchdog = Task {
   try? await Task.sleep(nanoseconds:10_000_000_000)
   socket.cancel(with:.goingAway,reason:nil)
  }
  defer {
   watchdog.cancel()
   socket.cancel(with:.goingAway,reason:nil)
   session.finishTasksAndInvalidate()
  }
  var loggedIn = false
  var sentPassword = false
  do {
   let firstMessage = try await socket.receive()
   guard let first = bytes(firstMessage), let hello = ObsPlan.hello(first) else {
    return .failed("Something answered on that port, but it doesn't look like OBS.")
   }
   var answer: String?
   if hello.needsPassword {
    guard let word = password, !word.isEmpty, let challenge = hello.challenge, let salt = hello.salt else {
     return .failed("OBS wants a password. In OBS open Tools, WebSocket Server Settings, press Show Connect Info, and paste the password into the OBS card in the app.")
    }
    answer = ObsPlan.authentication(password:word,salt:salt,challenge:challenge)
    sentPassword = true
   }
   guard let identify = ObsPlan.identify(authentication:answer), let identifyText = String(data:identify,encoding:.utf8) else {
    return .failed("I couldn't build the login message.")
   }
   try await socket.send(.string(identifyText))
   for _ in 0..<5 {
    let next = try await socket.receive()
    if let data = bytes(next), ObsPlan.isIdentified(data) { loggedIn = true; break }
   }
   guard loggedIn else { return .failed("OBS didn't accept the login.") }
   var replies: [String:ObsPlan.Reply] = [:]
   for job in jobs {
    let id = UUID().uuidString
    guard let message = ObsPlan.request(type:job.type,id:id,fields:job.fields), let body = String(data:message,encoding:.utf8) else { continue }
    try await socket.send(.string(body))
    for _ in 0..<10 {
     let next = try await socket.receive()
     if let data = bytes(next), let found = ObsPlan.reply(data), found.id == id { replies[job.type] = found; break }
    }
   }
   return .ok(replies)
  } catch {
   if Date().timeIntervalSince(started) >= 9.5 { return .failed("OBS took too long to answer.") }
   if sentPassword && !loggedIn { return .failed(ObsPlan.closeReason(4009)) }
   return .failed(loggedIn ? "OBS stopped answering in the middle of that." : ObsPlan.unreachable)
  }
 }

 // MARK: reading what OBS says

 private func sceneNames(_ reply: ObsPlan.Reply?) -> [String] {
  guard let list = reply?.fields["scenes"] as? [[String:Any]] else { return [] }
  let ordered = list.sorted { (ObsPlan.int($0["sceneIndex"]) ?? 0) < (ObsPlan.int($1["sceneIndex"]) ?? 0) }
  return ordered.compactMap { $0["sceneName"] as? String }
 }

 private func makeSnapshot(_ replies: [String:ObsPlan.Reply]) -> ObsPlan.Snapshot {
  var shot = ObsPlan.Snapshot()
  shot.obsVersion = replies["GetVersion"]?.fields["obsVersion"] as? String ?? ""
  let stream = replies["GetStreamStatus"]?.fields ?? [:]
  shot.streaming = (stream["outputActive"] as? Bool) ?? false
  shot.reconnecting = (stream["outputReconnecting"] as? Bool) ?? false
  shot.streamMinutes = ObsPlan.minutes(milliseconds:ObsPlan.number(stream["outputDuration"]))
  shot.skippedPercent = ObsPlan.skippedPercent(skipped:ObsPlan.number(stream["outputSkippedFrames"]),total:ObsPlan.number(stream["outputTotalFrames"]))
  shot.recording = (replies["GetRecordStatus"]?.fields["outputActive"] as? Bool) ?? false
  shot.replayOn = (replies["GetReplayBufferStatus"]?.fields["outputActive"] as? Bool) ?? false
  shot.scenes = sceneNames(replies["GetSceneList"])
  shot.scene = replies["GetSceneList"]?.fields["currentProgramSceneName"] as? String ?? ""
  if let inputs = replies["GetInputList"]?.fields["inputs"] as? [[String:Any]] {
   shot.inputs = inputs.compactMap { $0["inputName"] as? String }
  }
  return shot
 }

 private static let statusJobs = [Job(type:"GetVersion"),Job(type:"GetStreamStatus"),Job(type:"GetRecordStatus"),Job(type:"GetReplayBufferStatus"),Job(type:"GetSceneList"),Job(type:"GetInputList")]

 // Asks OBS how it is. Returns the snapshot, or the plain-words reason it could not.
 private func look() async -> (ObsPlan.Snapshot?,String?) {
  switch await talk(Self.statusJobs,password:savedPassword()) {
  case .failed(let why): return (nil,why)
  case .ok(let replies):
   let shot = makeSnapshot(replies)
   snapshot = shot
   return (shot,nil)
  }
 }

 private func allow() -> Bool {
  let now = Date()
  guard ObsPlan.underLimit(recent,now:now,window:60,max:20) else { return false }
  recent.append(now)
  recent = Array(recent.suffix(40))
  return true
 }

 private static let tooBusy = "I've been talking to OBS a lot this minute, so I'm pausing. Ask me again in a minute."

 // MARK: the Save and test button, and the Stream page buttons

 func saveAndTest() async {
  let typed = passwordInput.trimmingCharacters(in:.whitespacesAndNewlines)
  working = true
  defer { working = false }
  switch await talk(Self.statusJobs,password:typed.isEmpty ? savedPassword() : typed) {
  case .failed(let why):
   ready = false
   message = why
  case .ok(let replies):
   if !typed.isEmpty {
    guard Keychain.write(ObsPlan.passwordService,Data(typed.utf8)) else { message = "OBS answered, but I couldn't save the password on this Mac."; return }
    hasPassword = true
    passwordInput = ""
   }
   let shot = makeSnapshot(replies)
   snapshot = shot
   ready = true
   message = "Connected to OBS\(shot.obsVersion.isEmpty ? "" : " \(shot.obsVersion)"). I can see \(shot.scenes.count) scene\(shot.scenes.count == 1 ? "" : "s"). Friday can work OBS now (the switch above)."
  }
 }

 func check() async {
  working = true
  defer { working = false }
  let (shot,problem) = await look()
  if let shot = shot { message = ObsPlan.describe(shot) } else { message = problem ?? "I couldn't check OBS." }
 }

 func forgetPassword() {
  Keychain.remove(ObsPlan.passwordService)
  hasPassword = false
  ready = false
  snapshot = nil
  message = "Password removed. Press Save and test to link OBS again."
 }

 func switchTo(_ scene: String) async {
  working = true
  defer { working = false }
  message = await setScene(scene)
 }

 func saveReplayNow() async {
  working = true
  defer { working = false }
  message = await replay(action:"save")
 }

 // MARK: what Friday can do (each returns words for her to say)

 func voiceStatus() async -> String {
  guard usable else { return Self.notLinked }
  guard allow() else { return Self.tooBusy }
  let (shot,problem) = await look()
  if let shot = shot { return ObsPlan.describe(shot) }
  return problem ?? ObsPlan.unreachable
 }

 func voiceScene(_ spoken: String) async -> String {
  guard usable else { return Self.notLinked }
  guard allow() else { return Self.tooBusy }
  return await setScene(spoken)
 }

 private func setScene(_ spoken: String) async -> String {
  switch await talk([Job(type:"GetSceneList")],password:savedPassword()) {
  case .failed(let why): return why
  case .ok(let replies):
   let names = sceneNames(replies["GetSceneList"])
   if names.isEmpty { return "OBS has no scenes yet. Make a scene in OBS first (the + under Scenes)." }
   switch ObsPlan.pick(spoken,from:names) {
   case .none: return "OBS has no scene called “\(spoken)”. Its scenes are: " + names.prefix(12).map { "“\($0)”" }.joined(separator:", ") + ". Ask the player which one they meant."
   case .several(let matches): return "More than one scene fits “\(spoken)”: " + matches.prefix(8).map { "“\($0)”" }.joined(separator:", ") + ". Ask the player which one."
   case .one(let name):
    switch await talk([Job(type:"SetCurrentProgramScene",fields:["sceneName":name])],password:savedPassword()) {
    case .failed(let why): return why
    case .ok(let done):
     guard let reply = done["SetCurrentProgramScene"] else { return "OBS didn't confirm the switch." }
     if !reply.ok { return ObsPlan.failure(reply,doing:"switching scenes") }
     if var shot = snapshot { shot.scene = name; snapshot = shot }
     return "Switched OBS to the scene “\(name)”."
    }
   }
  }
 }

 func voiceReplay(_ action: String) async -> String {
  guard usable else { return Self.notLinked }
  guard allow() else { return Self.tooBusy }
  return await replay(action:action)
 }

 private func replay(action: String) async -> String {
  let word = action.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
  if word == "start" {
   switch await talk([Job(type:"StartReplayBuffer")],password:savedPassword()) {
   case .failed(let why): return why
   case .ok(let done):
    guard let reply = done["StartReplayBuffer"] else { return "OBS didn't confirm." }
    if !reply.ok { return ObsPlan.failure(reply,doing:"turning on the replay buffer") + " The replay buffer also has to be switched on in OBS: Settings, Output, Replay Buffer." }
    return "The replay buffer is on. From now on a highlight can be saved at any moment."
   }
  }
  switch await talk([Job(type:"GetReplayBufferStatus"),Job(type:"GetLastReplayBufferReplay")],password:savedPassword()) {
  case .failed(let why): return why
  case .ok(let first):
   let on = (first["GetReplayBufferStatus"]?.fields["outputActive"] as? Bool) ?? false
   if !on { return "The replay buffer is off, so there is nothing to save yet. Offer to turn it on (obs_replay with action start); it also has to be enabled in OBS under Settings, Output, Replay Buffer." }
   let before = first["GetLastReplayBufferReplay"]?.fields["savedReplayPath"] as? String ?? ""
   switch await talk([Job(type:"SaveReplayBuffer")],password:savedPassword()) {
   case .failed(let why): return why
   case .ok(let done):
    guard let reply = done["SaveReplayBuffer"] else { return "OBS didn't confirm the save." }
    if !reply.ok { return ObsPlan.failure(reply,doing:"saving the replay") }
    try? await Task.sleep(nanoseconds:1_500_000_000)
    if case .ok(let after) = await talk([Job(type:"GetLastReplayBufferReplay")],password:savedPassword()),
       let path = after["GetLastReplayBufferReplay"]?.fields["savedReplayPath"] as? String, !path.isEmpty, path != before {
     return "Saved the last moments as a replay file: \((path as NSString).lastPathComponent), in OBS's recording folder."
    }
    return "Asked OBS to save the last moments. The file appears in OBS's recording folder in a second or two."
   }
  }
 }

 func voiceMute(_ source: String,muted: Bool) async -> String {
  guard usable else { return Self.notLinked }
  guard allow() else { return Self.tooBusy }
  var name = ""
  switch ObsPlan.muteTarget(source) {
  case .named(let given):
   guard let clean = ObsPlan.cleanName(given) else { return "Which sound should I \(muted ? "mute" : "unmute")? Say its name in OBS, for example the mic or the game sound." }
   name = clean
  case .mic, .desktop:
   let wantMic: Bool
   if case .mic = ObsPlan.muteTarget(source) { wantMic = true } else { wantMic = false }
   switch await talk([Job(type:"GetSpecialInputs")],password:savedPassword()) {
   case .failed(let why): return why
   case .ok(let done):
    let key = wantMic ? "mic1" : "desktop1"
    guard let found = done["GetSpecialInputs"]?.fields[key] as? String, !found.isEmpty else {
     return "OBS has no source set as the \(wantMic ? "mic" : "desktop audio"). Ask the player for the exact name of the sound source in OBS, or check OBS to list them."
    }
    name = found
   }
  }
  switch await talk([Job(type:"SetInputMute",fields:["inputName":name,"inputMuted":muted])],password:savedPassword()) {
  case .failed(let why): return why
  case .ok(let done):
   guard let reply = done["SetInputMute"] else { return "OBS didn't confirm." }
   if !reply.ok { return ObsPlan.failure(reply,doing:"changing the sound") }
   return "\(muted ? "Muted" : "Unmuted") “\(name)” in OBS."
  }
 }

 // Going live and ending the stream are public, so both wait for the Allow box. At most 2 changes in 2 minutes.
 func voiceStream(_ action: String) async -> String {
  guard usable else { return Self.notLinked }
  guard allow() else { return Self.tooBusy }
  let word = action.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
  guard word == "start" || word == "stop" else { return "Say whether to start or stop the stream." }
  guard ObsPlan.underLimit(liveChanges,now:Date(),window:120,max:2) else { return "I already changed the stream twice in the last two minutes, so I'm not doing it again. Check OBS yourself." }
  guard let ask = approve else { return "I can't show the Allow box right now, so I didn't touch the stream." }
  let (shot,problem) = await look()
  guard let current = shot else { return problem ?? ObsPlan.unreachable }
  if word == "start" {
   if current.streaming { return "OBS is already live." }
   guard await ask("Go live on Twitch?",ObsPlan.goLiveDetail(scene:current.scene)) else { return "The player didn't press Allow, so I did NOT go live." }
  } else {
   if !current.streaming { return "OBS isn't streaming, so there is nothing to end." }
   guard await ask("End the live stream?",ObsPlan.stopDetail) else { return "The player didn't press Allow, so I did NOT end the stream." }
  }
  liveChanges.append(Date())
  switch await talk([Job(type:word == "start" ? "StartStream" : "StopStream")],password:savedPassword()) {
  case .failed(let why): return why
  case .ok(let done):
   guard let reply = done[word == "start" ? "StartStream" : "StopStream"] else { return "OBS didn't confirm." }
   if !reply.ok { return ObsPlan.failure(reply,doing:word == "start" ? "going live" : "ending the stream") }
   return word == "start" ? "OBS started streaming. It can take 10 to 20 seconds to show up on Twitch." : "OBS ended the stream."
  }
 }
}

// MARK: the OBS card on the Stream page

extension CompanionInterfaceView {
 var hubStreamObs: some View {
  VStack(alignment:.leading,spacing:12) {
   HStack(spacing:10) {
    Text("OBS (your streaming program)").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
    hubPill(obs.ready ? "LINKED" : "NOT LINKED",tint:obs.ready ? HubColor.green : HubColor.slate)
    if obs.working { ProgressView().controlSize(.small) }
    Spacer()
    Text("Friday can work OBS").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.55))
    Toggle("",isOn:$obs.enabled).labelsHidden().toggleStyle(.switch)
   }
   Text("OBS is the free program that puts your game, your camera and your voice into one picture and sends it to Twitch. Link it here and Friday can see how it is doing, switch scenes, save a replay, mute the mic and, only when you press Allow, go live or end the stream. It all stays on this Mac.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.65))
   VStack(alignment:.leading,spacing:4) {
    Text("1. Install OBS Studio from obsproject.com (it is free).").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.75))
    Text("2. In OBS open Tools, then WebSocket Server Settings. Tick Enable WebSocket server, then press Show Connect Info.").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.75))
    Text("3. Paste the server password below and press Save and test. If OBS shows no password, leave the box empty.").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.75))
   }
   HStack(spacing:10) {
    SecureField(obs.hasPassword ? "Password saved (paste a new one to replace it)" : "OBS server password",text:$obs.passwordInput).noirField()
    TextField("port (4455)",text:$obs.portText).noirField().frame(width:110)
   }
   HStack(spacing:10) {
    Button { Task { await obs.saveAndTest() } } label: { Label("Save and test",systemImage:"checkmark.seal") }
     .buttonStyle(PillButtonStyle()).disabled(obs.working)
    Button { Task { await obs.check() } } label: { Label("Check OBS",systemImage:"arrow.clockwise") }
     .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12))).disabled(obs.working || !obs.ready)
    Button { Task { await obs.saveReplayNow() } } label: { Label("Save a replay",systemImage:"gobackward.30") }
     .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12))).disabled(obs.working || !obs.ready)
    Button { if let url = URL(string:"https://obsproject.com/") { NSWorkspace.shared.open(url) } } label: { Label("Get OBS",systemImage:"arrow.up.right.square") }
     .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    if obs.hasPassword {
     Button { obs.forgetPassword() } label: { Label("Forget password",systemImage:"xmark.circle") }
      .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    }
   }
   if let shot = obs.snapshot, !shot.scenes.isEmpty {
    Text("Scenes (press one to switch OBS to it)").font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(Color.white.opacity(0.6))
    ScrollView(.horizontal) {
     HStack(spacing:8) {
      ForEach(shot.scenes,id:\.self) { name in
       Button { Task { await obs.switchTo(name) } } label: { Text(name) }
        .buttonStyle(PillButtonStyle(tint:name == shot.scene ? Noir.crimson : Color.white.opacity(0.12))).disabled(obs.working)
      }
     }
    }
    .scrollIndicators(.hidden)
   }
   if !obs.message.isEmpty {
    Text(obs.message).font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.75)).textSelection(.enabled)
   }
   Text("The password is saved in a private file on this Mac, never in the app's feed or in chat. Friday talks only to the OBS on this Mac. Going live or ending the stream always waits for your press on the Allow box.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.45))
  }
  .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
 }
}
