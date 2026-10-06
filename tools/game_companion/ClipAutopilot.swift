import SwiftUI
import AppKit

// Clip autopilot (Matthew's choice, 2026-10-05): while the app is open and he has switched it on, Friday makes clips without being asked,
// from three sources: (1) after a stream ends, every moment he marked (VodClips.swift); (2) exciting moments she notices live from the
// sound of his own voice, at most 3 a stream and 5 minutes apart; (3) his viewers' best clips from the last week, 2 each run, one run
// every 6 hours. Clips are public on Twitch the moment they exist, so every source is capped and every action is written to the log
// below and to the Friday feed. Each finished clip gets a TikTok caption saved next to it (tiktok-caption.txt). Rules and tests:
// AutopilotData.swift. It is off until he switches it on, and it stops when the window closes.

// The clips the app has already made or handled, so the viewers' source never re-picks one.
enum ClipLedger {
 private static let key = "autopilot.handled"
 static var ids: [String] { UserDefaults.standard.stringArray(forKey:key) ?? [] }
 static func add(_ id: String) { UserDefaults.standard.set(AutopilotPlan.appendHandled(ids,id),forKey:key) }
}

@MainActor final class ClipAutopilot: ObservableObject {
 @Published var enabled = UserDefaults.standard.object(forKey:"autopilot.on") as? Bool ?? false {
  didSet {
   UserDefaults.standard.set(enabled,forKey:"autopilot.on")
   if enabled { begin(); note("Autopilot is on") } else { pause(); note("Autopilot is off") }
  }
 }
 @Published var fromMarkers = UserDefaults.standard.object(forKey:"autopilot.markers") as? Bool ?? true { didSet { UserDefaults.standard.set(fromMarkers,forKey:"autopilot.markers") } }
 @Published var fromLive = UserDefaults.standard.object(forKey:"autopilot.live") as? Bool ?? true { didSet { UserDefaults.standard.set(fromLive,forKey:"autopilot.live") } }
 @Published var fromViewers = UserDefaults.standard.object(forKey:"autopilot.viewers") as? Bool ?? true { didSet { UserDefaults.standard.set(fromViewers,forKey:"autopilot.viewers") } }
 @Published var log: [String] = []
 @Published var working = false

 private var clips: TwitchClips?
 private var stream: StreamHub?
 private var vods: VodHub?
 private var live: LiveBuddy?
 private var feed: FridayFeed?
 private var loop: Task<Void,Never>?
 private var hype = HypeDetector()
 private var liveCount = 0
 private var lastLiveClip: Date?
 private var wasLive = false
 private var offlineChecks = 0
 private var endedAt: Date?
 private var streamStart: Date?
 private var lastSlow = Date.distantPast
 private var lastViewerRun = Date.distantPast
 private var handledVods = Set(UserDefaults.standard.stringArray(forKey:"autopilot.vods") ?? [])

 func attach(clips tw: TwitchClips,stream hub: StreamHub,vods list: VodHub,live buddy: LiveBuddy,feed log: FridayFeed) {
  guard clips == nil else { return }
  clips = tw; stream = hub; vods = list; live = buddy; feed = log
  tw.onTidied = { [weak self] folder,title in self?.writePack(folder:folder,title:title) }
  if enabled { begin() }
 }

 private func note(_ text: String) {
  let stamp = Date().formatted(date:.omitted,time:.shortened)
  log.insert("\(stamp) · \(text)",at:0)
  if log.count > 12 { log.removeLast(log.count - 12) }
  feed?.add("action","Autopilot: \(text)")
 }

 func begin() {
  guard loop == nil else { return }
  loop = Task { [weak self] in
   while !Task.isCancelled {
    guard let self = self, self.enabled else { return }
    await self.tick()
    try? await Task.sleep(nanoseconds:250_000_000)
   }
  }
 }

 // Stops the loop without changing the switch (used when the window closes).
 func pause() {
  loop?.cancel()
  loop = nil
 }

 private func tick() async {
  guard let tw = clips, tw.signedIn, let hub = stream else { return }
  let now = Date()
  // Fast: his voice while he streams and Friday is listening.
  if fromLive, let buddy = live, buddy.running, hub.liveNow {
   let level = buddy.micLevel * max(0,1 - now.timeIntervalSince(buddy.micLevelAt) * 5)
   if hype.feed(level:level,dt:0.25), AutopilotPlan.canClipLive(count:liveCount,lastClip:lastLiveClip,now:now), !tw.busy {
    liveCount += 1
    lastLiveClip = now
    note("Exciting moment (\(liveCount) of \(AutopilotPlan.liveCapPerStream) this stream), clipping it")
    Task { [weak self] in
     let result = await tw.clipNow(title:"")
     self?.note(String(result.prefix(140)))
    }
   }
  }
  // Slow: every 20 seconds, watch for the stream starting and ending, and the viewers' clips.
  if now.timeIntervalSince(lastSlow) >= 20 {
   lastSlow = now
   await slow(now)
  }
 }

 private func slow(_ now: Date) async {
  guard let hub = stream else { return }
  await hub.refresh()
  let freshCheck = Date().timeIntervalSince(hub.lastRefresh) < 90
  if hub.liveNow {
   offlineChecks = 0
   if !wasLive {
    wasLive = true
    streamStart = now
    liveCount = 0
    lastLiveClip = nil
    hype = HypeDetector()
    endedAt = nil
    note("Stream started")
   }
  } else if wasLive && freshCheck {
   // Only a successful check that says offline counts, and it has to say so three times (about a minute), so a network blip
   // can't look like the end of a stream.
   offlineChecks += 1
   if offlineChecks >= 3 {
    wasLive = false
    endedAt = now
    note("Stream ended")
   }
  }
  if let ended = endedAt, now.timeIntervalSince(ended) >= 90 {
   endedAt = nil
   if fromMarkers { await runMarkers() }
  }
  if fromViewers && now.timeIntervalSince(lastViewerRun) >= 6 * 3600 {
   lastViewerRun = now
   await runViewers()
  }
 }

 // MARK: the three sources

 private func runMarkers() async {
  guard let list = vods else { return }
  await list.load()
  guard let vod = list.vods.first else { note("No past stream found to clip"); return }
  guard !handledVods.contains(vod.id) else { note("Already clipped “\(vod.title)”"); return }
  handledVods.insert(vod.id)
  UserDefaults.standard.set(Array(handledVods).suffix(60).map { $0 },forKey:"autopilot.vods")
  working = true
  defer { working = false }
  let summary = await list.clipMarked(vod)
  note("Marked moments in “\(vod.title)”: \(summary)")
 }

 func runViewers() async {
  guard let tw = clips, let hub = stream, tw.signedIn else { return }
  if hub.channel == nil { await hub.refresh(force:true) }
  guard let channel = hub.channel?.id else { note("Couldn't check viewers' clips: channel not loaded"); return }
  working = true
  defer { working = false }
  let since = ISO8601DateFormatter().string(from:Date().addingTimeInterval(-AutopilotPlan.viewerWindowDays * 86_400))
  do {
   let (code,json) = try await tw.call("/clips?broadcaster_id=\(channel)&started_at=\(since)&first=40")
   guard code == 200 else { note("Couldn't check viewers' clips (Twitch answered \(code))"); return }
   let picks = AutopilotPlan.pickViewerClips(StreamData.parseClips(json),handled:Set(ClipLedger.ids),now:Date())
   if picks.isEmpty { note("No new viewer clips worth taking"); return }
   for clip in picks {
    ClipLedger.add(clip.id)
    note("Viewer clip: \(clip.title) (\(clip.views) view\(clip.views == 1 ? "" : "s"))")
    if tw.autoEdit { await tw.tidyClip(clipID:clip.id,broadcasterID:channel,title:clip.title) }
   }
  } catch {
   note("Couldn't check viewers' clips: \(error.localizedDescription)")
  }
 }

 // MARK: the TikTok caption

 // Called after every finished clip, whoever asked for it.
 func writePack(folder: URL,title: String) {
  let text = TikTokPack.caption(title:title,game:stream?.channel?.gameName ?? "",voiceOver:VoiceOver.hasVoiceOver(in:folder))
  try? text.write(to:folder.appendingPathComponent("tiktok-caption.txt"),atomically:true,encoding:.utf8)
  note("Ready for TikTok: \(folder.lastPathComponent)")
 }
}

extension CompanionInterfaceView {
 var hubStreamAutopilot: some View {
  VStack(alignment:.leading,spacing:12) {
   HStack(spacing:10) {
    Text("Clip autopilot").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
    hubPill(autopilot.enabled ? "ON" : "OFF",tint:autopilot.enabled ? HubColor.green : HubColor.slate)
    if autopilot.working { ProgressView().controlSize(.small) }
    Spacer()
    Toggle("",isOn:$autopilot.enabled).labelsHidden().toggleStyle(.switch)
   }
   Text("While this app is open, Friday makes clips without being asked. Clips are public on Twitch the moment they're made. Each finished clip gets a TikTok caption saved next to it.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.6))
   Toggle("After a stream: clip every moment I marked (up to \(VodPlan.maxPerBatch))",isOn:$autopilot.fromMarkers).font(.system(size:13,design:.rounded))
   Toggle("While I stream: clip exciting moments from the sound of my voice (up to \(AutopilotPlan.liveCapPerStream) a stream, 5 minutes apart)",isOn:$autopilot.fromLive).font(.system(size:13,design:.rounded))
   Toggle("Every 6 hours: take my viewers' best clips from the last week (up to \(AutopilotPlan.viewerClipsPerRun) a time)",isOn:$autopilot.fromViewers).font(.system(size:13,design:.rounded))
   HStack(spacing:10) {
    Button { Task { await autopilot.runViewers() } } label: { Label("Check viewers' clips now",systemImage:"person.2.fill") }
     .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12))).disabled(autopilot.working || !clips.signedIn)
    Button {
     try? FileManager.default.createDirectory(at:TwitchClips.clipsRoot,withIntermediateDirectories:true)
     NSWorkspace.shared.open(TwitchClips.clipsRoot)
    } label: { Label("Open the clips folder",systemImage:"folder") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   }
   if !autopilot.log.isEmpty {
    VStack(alignment:.leading,spacing:4) {
     ForEach(Array(autopilot.log.enumerated()),id:\.offset) { _,line in
      Text(line).font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.6)).lineLimit(2).textSelection(.enabled)
     }
    }
   }
   Text("The live source only hears your voice while Friday is running and you're live, and it can misjudge: a loud laugh isn't always a highlight. Turn a source off if it makes clips you don't want.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
  }
  .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
 }
}
