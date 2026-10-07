import SwiftUI
import AppKit
import AVFoundation

// Friday's voice-over on a finished clip. The rules, prompts and Google's data shapes are in VoiceOverData.swift (tested). This file
// does the calling and the mixing on the Mac, and the card on the Stream page.
// Matthew's ask (2026-10-06): in the clip, Friday explains what's going on, how to get loot, the best ways to farm.
// Honesty rules baked in: anything about loot or farming may only come from the game's wiki pages she looked up, any sentence with a number
// the sources don't contain is dropped, the voice is an AI voice and the caption and note files say so, and nothing is posted anywhere.
// Checked against Apple's docs on 2026-10-06: AVMutableComposition.addMutableTrack(withMediaType:preferredTrackID:),
// AVMutableCompositionTrack.insertTimeRange(_:of:at:), AVMutableAudioMixInputParameters(track:), setVolume(_:at:),
// setVolumeRamp(fromStartVolume:toEndVolume:timeRange:), AVAssetExportSession.audioMix and export(to:as:), AVAssetExportPreset640x480.

enum VoiceMix {
 // A small copy of the clip (picture and sound) to send to Google for watching.
 static func shrink(_ source: URL,to destination: URL) async throws {
  let asset = AVURLAsset(url:source)
  guard let session = AVAssetExportSession(asset:asset,presetName:AVAssetExportPreset640x480) else { throw ClipEditError.noExporter }
  try? FileManager.default.removeItem(at:destination)
  try await session.export(to:destination,as:.mp4)
 }

 // The clip with her speech laid over it from `start` seconds in, and the game's own sound turned down while she talks.
 static func mix(video: URL,narration: URL,start: Double,length: Double,to destination: URL) async throws {
  let asset = AVURLAsset(url:video)
  let total = try await asset.load(.duration)
  let composition = AVMutableComposition()
  let whole = CMTimeRange(start:.zero,duration:total)
  guard let sourceVideo = try await asset.loadTracks(withMediaType:.video).first,
        let videoTrack = composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid) else {
   throw NSError(domain:"voiceover",code:1,userInfo:[NSLocalizedDescriptionKey:"The clip has no picture track."])
  }
  try videoTrack.insertTimeRange(whole,of:sourceVideo,at:.zero)
  var parameters: [AVAudioMixInputParameters] = []
  if let sourceAudio = try await asset.loadTracks(withMediaType:.audio).first,
     let gameTrack = composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) {
   try gameTrack.insertTimeRange(whole,of:sourceAudio,at:.zero)
   let duck = AVMutableAudioMixInputParameters(track:gameTrack)
   duck.setVolume(1,at:.zero)
   for step in VoiceOverPlan.ducking(start:start,length:length,clip:total.seconds) {
    duck.setVolumeRamp(fromStartVolume:step.from,toEndVolume:step.to,
                       timeRange:CMTimeRange(start:CMTime(seconds:step.at,preferredTimescale:600),duration:CMTime(seconds:step.length,preferredTimescale:600)))
   }
   parameters.append(duck)
  }
  let speech = AVURLAsset(url:narration)
  guard let speechSource = try await speech.loadTracks(withMediaType:.audio).first,
        let speechTrack = composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid) else {
   throw NSError(domain:"voiceover",code:2,userInfo:[NSLocalizedDescriptionKey:"The voice file has no sound."])
  }
  let speechLength = try await speech.load(.duration)
  let room = max(0,total.seconds - start)
  let usable = CMTime(seconds:min(speechLength.seconds,room),preferredTimescale:600)
  try speechTrack.insertTimeRange(CMTimeRange(start:.zero,duration:usable),of:speechSource,at:CMTime(seconds:start,preferredTimescale:600))
  guard let session = AVAssetExportSession(asset:composition,presetName:AVAssetExportPresetHighestQuality) else { throw ClipEditError.noExporter }
  let audioMix = AVMutableAudioMix()
  audioMix.inputParameters = parameters
  session.audioMix = audioMix
  try? FileManager.default.removeItem(at:destination)
  try await session.export(to:destination,as:.mp4)
 }
}

@MainActor final class VoiceOver: ObservableObject {
 // Off until Matthew switches it on: then every clip that gets cut also gets a voice-over version.
 @Published var enabled = UserDefaults.standard.object(forKey:"voiceover.on") as? Bool ?? false { didSet { UserDefaults.standard.set(enabled,forKey:"voiceover.on") } }
 @Published var focus = UserDefaults.standard.string(forKey:"voiceover.focus") ?? "" { didSet { UserDefaults.standard.set(focus,forKey:"voiceover.focus") } }
 @Published var working = false
 @Published var status = ""
 @Published var script = ""
 private var clips: TwitchClips?
 private var live: LiveBuddy?
 private var feed: FridayFeed?
 private let session = URLSession(configuration:.ephemeral)

 func attach(clips tw: TwitchClips,live buddy: LiveBuddy,feed log: FridayFeed) {
  if clips != nil { return }
  clips = tw; live = buddy; feed = log
  // Runs after each clip is cut, before its caption is written.
  tw.afterEdit = { [weak self] folder,title in await self?.autoNarrate(folder:folder,title:title) }
 }

 // True if the folder has a finished voice-over version, so the caption can say the narration is an AI voice.
 nonisolated static func hasVoiceOver(in folder: URL) -> Bool {
  [true,false].contains { FileManager.default.fileExists(atPath:folder.appendingPathComponent(VoiceOverPlan.outputName(tall:$0)).path) }
 }

 // The newest clip folder that has a cut highlight.
 func latestFolder() -> URL? {
  let fm = FileManager.default
  func usable(_ folder: URL) -> Bool {
   ["highlight-wide.mp4","highlight-tall.mp4"].contains { fm.fileExists(atPath:folder.appendingPathComponent($0).path) }
  }
  if let last = clips?.lastFolder, usable(last) { return last }
  guard let names = try? fm.contentsOfDirectory(at:TwitchClips.clipsRoot,includingPropertiesForKeys:nil) else { return nil }
  return names.filter { usable($0) }.sorted { $0.lastPathComponent > $1.lastPathComponent }.first
 }

 private func autoNarrate(folder: URL,title: String) async {
  guard enabled else { return }
  clips?.editStatus = "Highlight cut. Friday is adding her voice-over…"
  let result = await narrate(folder:folder,focus:focus)
  feed?.add("action","Voice-over: \(result)")
 }

 func narrateLatest() async {
  guard let folder = latestFolder() else { status = "There's no cut clip on this Mac yet. Make a clip first."; return }
  _ = await narrate(folder:folder,focus:focus)
 }

 // Friday's voice tool. The job takes a minute or two, so this answers at once and the result goes to the card and the feed.
 func voiceNarrate(focus spoken: String) async -> String {
  if working { return "I'm already working on a voice-over. One at a time." }
  guard let folder = latestFolder() else { return "There's no finished clip on this Mac to narrate yet. Make a clip first." }
  let words = spoken.trimmingCharacters(in:.whitespacesAndNewlines)
  Task { [weak self] in
   guard let self = self else { return }
   let result = await self.narrate(folder:folder,focus:words.isEmpty ? self.focus : words)
   self.feed?.add("action","Voice-over: \(result)")
  }
  return "On it. I'm watching the clip and writing the voice-over now. It takes a minute or two, and the new version will be in the clips folder."
 }

 // MARK: Friday's "read this link / watch this video" tool

 private var reading = false

 // Reads a public web page, watches a public YouTube video, or watches the newest saved clip, and answers a question about it with Google's own
 // reader. (Matthew, 2026-10-07: "she can't analyze videos" and "she can't search links": before this she could only open a page and look at the screen.)
 // Not for TikTok, X, Instagram or Twitch videos, pages behind a login, or private videos: Google's tools can't open those, and she is told so.
 func voiceRead(source rawSource: String,question rawQuestion: String) async -> String {
  if reading { return "I'm already reading something. One at a time." }
  reading = true
  defer { reading = false }
  let source = rawSource.trimmingCharacters(in:.whitespacesAndNewlines)
  let lower = source.lowercased()
  var body: Data?
  var what = "that page"
  if !lower.contains("/") && !lower.contains(".") && (lower.isEmpty || lower.contains("clip")) {
   guard let folder = latestFolder() else { return "There's no saved clip on this Mac to watch yet." }
   let fm = FileManager.default
   let candidates = [folder.appendingPathComponent("highlight-wide.mp4"),folder.appendingPathComponent("highlight-tall.mp4")]
   guard let file = candidates.first(where:{ fm.fileExists(atPath:$0.path) }) else { return "I couldn't find the clip's video file." }
   let small = fm.temporaryDirectory.appendingPathComponent("friday-read-\(UUID().uuidString).mp4")
   defer { try? fm.removeItem(at:small) }
   do { try await VoiceMix.shrink(file,to:small) } catch { return "Couldn't prepare the clip to watch: \(error.localizedDescription)" }
   guard let video = try? Data(contentsOf:small), !video.isEmpty else { return "Couldn't read the prepared clip." }
   guard video.count <= VoiceOverPlan.maxVideoBytes else { return "That clip is too big to send to Google in one go." }
   body = VoiceOverPlan.videoBody(prompt:WebPlan.cleanQuestion(rawQuestion) + " Describe only what you can see and hear in this clip.",video:video)
   what = "your latest clip"
  } else if let youtube = WebPlan.youtubeURL(source) {
   body = WebPlan.youtubeBody(url:youtube,question:rawQuestion)
   what = "that YouTube video"
  } else {
   switch WebPlan.link(source) {
   case .no(let problem): return problem
   case .ok(let url): body = WebPlan.pageBody(url:url,question:rawQuestion); what = url.host ?? "that page"
   }
  }
  let answer = await call(body,doing:"read \(what)",timeout:240)
  guard let json = answer.json else { return answer.problem ?? "Couldn't read that." }
  guard let text = VoiceOverPlan.replyText(json) else { return "Google answered but sent back no words about \(what). It may be private, behind a login, or not something its reader can open." }
  return "From Google's reader, about \(what): " + String(text.prefix(2500)) + " (Say it came from Google's reader. It can be wrong.)"
 }

 // For a video that is playing on his screen (TikTok, X, Twitch, anything he is logged in to): a picture of every screen once a second for 5 to 40
 // seconds, studied by Google's reader. Pictures only, no sound. Google never sees the site, only what was on his screens.
 func voiceWatchScreen(seconds rawSeconds: Double?,question: String) async -> String {
  if reading { return "I'm already reading something. One at a time." }
  reading = true
  defer { reading = false }
  let count = WebPlan.watchSeconds(rawSeconds)
  var frames: [Data] = []
  var bytes = 0
  for index in 0..<count {
   let started = Date()
   guard let shot = try? await ScreenSnap.captureAll(maxWidth:1280,maxHeight:720) else { break }
   frames.append(shot.jpeg)
   bytes += shot.jpeg.count
   if bytes > 14_000_000 { break }
   let spent = Date().timeIntervalSince(started)
   if index < count - 1 && spent < 1 { try? await Task.sleep(nanoseconds:UInt64((1 - spent) * 1_000_000_000)) }
  }
  guard frames.count >= 2 else { return "I couldn't capture the screens. macOS may have forgotten the Screen Recording permission after the update: switch Game Companion off and on in Privacy & Security, Screen & System Audio Recording." }
  let answer = await call(WebPlan.screenWatchBody(question:question,frames:frames),doing:"study the screens",timeout:240)
  guard let json = answer.json else { return answer.problem ?? "Couldn't study the screens." }
  guard let text = VoiceOverPlan.replyText(json) else { return "Google sent back no words about the screens." }
  return "From Google's reader, about \(frames.count) seconds of the player's screens (pictures one second apart, no sound): " + String(text.prefix(2500)) + " (Say it came from pictures only, with no sound, so it can miss fast action and anything that was spoken.)"
 }

 // MARK: talking to Google

 private func call(_ body: Data?,doing: String,timeout: Double) async -> (json: [String:Any]?,problem: String?) {
  guard let key = GeminiKey.load(), !key.isEmpty else { return (nil,"No Google key is saved yet. Add it under Accounts.") }
  guard let body = body else { return (nil,"Couldn't put the request together.") }
  var request = URLRequest(url:URL(string:VoiceOverPlan.endpoint)!,timeoutInterval:timeout)
  request.httpMethod = "POST"
  request.setValue(key,forHTTPHeaderField:"x-goog-api-key")
  request.setValue("application/json",forHTTPHeaderField:"Content-Type")
  request.httpBody = body
  do {
   let (data,response) = try await session.data(for:request)
   let code = (response as? HTTPURLResponse)?.statusCode ?? 0
   let json = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
   guard code == 200 else { return (nil,VoiceOverPlan.explain(code:code,message:VoiceOverPlan.errorMessage(json),doing:doing)) }
   return (json,nil)
  } catch {
   return (nil,"Couldn't reach Google to \(doing): \(error.localizedDescription)")
  }
 }

 // Her words in her voice (the one she uses live), as a WAV file's bytes and how long it plays.
 private func speak(_ words: String) async -> (wav: Data?,seconds: Double,problem: String?) {
  var voice = live?.voice ?? "Kore"
  var answer = await call(VoiceOverPlan.speechBody(script:words,voice:voice),doing:"make the voice",timeout:120)
  // If Google doesn't have that voice name for speech, try a standard one rather than give up.
  if answer.json == nil, voice != "Kore", (answer.problem ?? "").contains("didn't accept") {
   voice = "Kore"
   answer = await call(VoiceOverPlan.speechBody(script:words,voice:voice),doing:"make the voice",timeout:120)
  }
  guard let json = answer.json else { return (nil,0,answer.problem) }
  guard let audio = VoiceOverPlan.replyAudio(json) else { return (nil,0,"Google answered without any sound.") }
  let wav = VoiceOverPlan.asWAV(audio)
  guard let seconds = VoiceOverPlan.wavSeconds(wav), seconds > 0.5 else { return (nil,0,"Google's voice file wasn't readable.") }
  return (wav,seconds,nil)
 }

 // MARK: the whole job

 // Returns a sentence about how it went. Never posts or uploads the result anywhere.
 func narrate(folder: URL,focus rawFocus: String) async -> String {
  if working { return "I'm already working on a voice-over." }
  working = true
  script = ""
  defer { working = false }
  func finish(_ text: String) -> String { status = text; return text }
  let fm = FileManager.default
  let wide = folder.appendingPathComponent("highlight-wide.mp4")
  let tall = folder.appendingPathComponent("highlight-tall.mp4")
  let haveWide = fm.fileExists(atPath:wide.path)
  let haveTall = fm.fileExists(atPath:tall.path)
  guard haveWide || haveTall else { return finish("There's no cut highlight in \(folder.lastPathComponent) to narrate.") }
  let source = haveWide ? wide : tall
  let length = ((try? await AVURLAsset(url:source).load(.duration).seconds) ?? 0)
  guard length >= VoiceOverPlan.minClipSeconds else { return finish("That clip is only \(Int(length)) seconds, too short for a voice-over.") }

  // 1. She watches it.
  status = "Friday is watching the clip…"
  let small = fm.temporaryDirectory.appendingPathComponent("friday-watch-\(UUID().uuidString).mp4")
  defer { try? fm.removeItem(at:small) }
  do { try await VoiceMix.shrink(source,to:small) } catch { return finish("Couldn't make the small copy to send to Google: \(error.localizedDescription)") }
  guard let video = try? Data(contentsOf:small), !video.isEmpty else { return finish("Couldn't read the small copy of the clip.") }
  guard video.count <= VoiceOverPlan.maxVideoBytes else { return finish("That clip is too big to send to Google in one go (\(video.count / 1_000_000) MB even after shrinking).") }
  let watched = await call(VoiceOverPlan.videoBody(prompt:VoiceOverPlan.overviewPrompt,video:video),doing:"watch the clip",timeout:240)
  guard let watchedJSON = watched.json else { return finish(watched.problem ?? "Couldn't watch the clip.") }
  guard let overviewText = VoiceOverPlan.replyText(watchedJSON), let overview = VoiceOverPlan.parseOverview(overviewText) else {
   return finish("Google answered, but I couldn't make sense of what it saw. Try again.")
  }

  // 2. She looks up what she saw on the game's wiki. Tips can only come from these pages.
  status = "Checking the game wiki for \(overview.named.isEmpty ? "anything she can name" : overview.named.joined(separator:", "))…"
  var facts: [String] = []
  var pages: [String] = []
  for name in overview.named {
   let found = await GameWiki.lookup(name)
   if VoiceOverPlan.isFound(lookup:found) { facts.append(String(found.prefix(1500))); pages.append(name) }
  }

  // 3. She writes it, and only what the sources back up is kept.
  status = "Friday is writing the voice-over…"
  let budget = VoiceOverPlan.wordBudget(clipSeconds:length)
  let wrote = await call(VoiceOverPlan.textBody(prompt:VoiceOverPlan.scriptPrompt(summary:overview.summary,facts:facts,focus:rawFocus,words:budget)),doing:"write the voice-over",timeout:120)
  guard let wroteJSON = wrote.json else { return finish(wrote.problem ?? "Couldn't write the voice-over.") }
  guard let draft = VoiceOverPlan.replyText(wroteJSON) else { return finish("Google sent back no words. Try again.") }
  let vetted = VoiceOverPlan.vetted(VoiceOverPlan.clean(draft),sources:[overview.summary] + facts)
  var lines = VoiceOverPlan.fit(vetted.kept,words:budget)
  guard !lines.isEmpty else {
   return finish("I couldn't write a voice-over I can stand behind for that clip: what she wrote had numbers or claims I couldn't check. Nothing was changed.")
  }

  // 4. She says it. If it runs too long for the clip, fewer sentences and once more.
  status = "Friday is recording the voice-over…"
  var spoken = await speak(lines.joined(separator:" "))
  let room = VoiceOverPlan.available(clipSeconds:length)
  if spoken.wav != nil, spoken.seconds > room {
   let words = VoiceOverPlan.wordCount(lines.joined(separator:" "))
   let fewer = Int(Double(words) * room / spoken.seconds * 0.95)
   lines = VoiceOverPlan.fit(lines,words:fewer)
   if lines.isEmpty { return finish("The voice-over came out too long for the clip and I couldn't shorten it. Nothing was changed.") }
   spoken = await speak(lines.joined(separator:" "))
  }
  let words = lines.joined(separator:" ")
  script = words
  let note = VoiceOverPlan.scriptFile(script:words,named:overview.named,wikiPages:pages,game:overview.game)
  guard let wav = spoken.wav else {
   try? note.write(to:folder.appendingPathComponent("voiceover-draft.txt"),atomically:true,encoding:.utf8)
   return finish("I wrote the voice-over but couldn't make the voice: \(spoken.problem ?? "no sound came back"). The words are saved in \(folder.lastPathComponent)/voiceover-draft.txt.")
  }
  let wavURL = folder.appendingPathComponent("voiceover.wav")
  guard (try? wav.write(to:wavURL)) != nil else { return finish("Couldn't save the voice file in \(folder.lastPathComponent).") }

  // 5. She talks over the clip, with the game turned down while she does.
  status = "Putting the voice-over on the clip…"
  var made: [String] = []
  var problems: [String] = []
  for (exists,isTall,url) in [(haveTall,true,tall),(haveWide,false,wide)] where exists {
   let out = folder.appendingPathComponent(VoiceOverPlan.outputName(tall:isTall))
   do { try await VoiceMix.mix(video:url,narration:wavURL,start:VoiceOverPlan.leadIn,length:spoken.seconds,to:out); made.append(out.lastPathComponent) }
   catch { problems.append("\(isTall ? "tall" : "wide") version: \(error.localizedDescription)") }
  }
  guard !made.isEmpty else { return finish("I made the voice but couldn't put it on the clip: \(problems.joined(separator:"; ")).") }
  try? note.write(to:folder.appendingPathComponent("voiceover-script.txt"),atomically:true,encoding:.utf8)
  let tips = pages.isEmpty ? "There are no tips in it, because the wiki had nothing on what she could name." : "Anything about loot or farming came from the wiki pages for \(pages.joined(separator:", "))."
  let dropped = vetted.dropped.isEmpty ? "" : " She left out \(vetted.dropped.count) sentence\(vetted.dropped.count == 1 ? "" : "s") with numbers she couldn't back up."
  return finish("Voice-over done: \(made.joined(separator:" and ")) in \(folder.lastPathComponent). \(tips)\(dropped)\(problems.isEmpty ? "" : " Problem: \(problems.joined(separator:"; ")).")")
 }
}

extension CompanionInterfaceView {
 var hubStreamVoiceOver: some View {
  VStack(alignment:.leading,spacing:12) {
   HStack(spacing:10) {
    Text("Friday's voice-over").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
    hubPill(voiceover.enabled ? "ON" : "OFF",tint:voiceover.enabled ? HubColor.green : HubColor.slate)
    if voiceover.working { ProgressView().controlSize(.small) }
    Spacer()
    Toggle("",isOn:$voiceover.enabled).labelsHidden().toggleStyle(.switch)
   }
   Text("After a clip is cut, Friday watches it, looks up the items and enemies she can name on the game wiki, and records a voice-over in her own voice: what's going on, plus how to get the loot or farm it, but only where the wiki says so. You get a second version of each clip with her voice on it (the game turned down while she talks) and the words in a text file. Nothing is posted anywhere.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.65))
   TextField("What should she cover? (for example: how to get this loot, best way to farm it)",text:$voiceover.focus).noirField()
   HStack(spacing:10) {
    Button { Task { await voiceover.narrateLatest() } } label: { Label("Add a voice-over to my latest clip",systemImage:"waveform.badge.mic") }
     .buttonStyle(PillButtonStyle()).disabled(voiceover.working || !live.hasKey)
    Button {
     try? FileManager.default.createDirectory(at:TwitchClips.clipsRoot,withIntermediateDirectories:true)
     NSWorkspace.shared.open(TwitchClips.clipsRoot)
    } label: { Label("Open the clips folder",systemImage:"folder") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   }
   if !voiceover.status.isEmpty {
    Text(voiceover.status).font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.75)).textSelection(.enabled)
   }
   if !voiceover.script.isEmpty {
    Text("“\(voiceover.script)”").font(.system(size:12.5,design:.rounded)).foregroundStyle(Noir.crimsonLight).textSelection(.enabled)
   }
   Text("To do this, a small copy of the clip (picture and sound) and the words she writes go to Google with your free Gemini key; Google's free tier may use that data to improve its products. If the free plan doesn't include Google's voice maker, she says so and the words are still saved. The voice is an AI, and the TikTok caption says so. She can get things wrong, so listen before you post it.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.45))
  }
  .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
 }
}
