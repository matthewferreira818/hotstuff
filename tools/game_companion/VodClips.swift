import SwiftUI
import AppKit

// Clips from PAST streams (VODs), by tapping or by voice. Rules and Twitch calls are in VodData.swift. Uses the same Twitch login as the
// clip button (clips:edit, channel:manage:clips, editor:manage:clips, channel:manage:broadcast; sign out and in once if it was set
// up earlier). A Twitch clip is public the moment it exists, so a clip is only made when Matthew taps the button or asks Friday.
// After each clip the existing pipeline downloads it and cuts the highlight on this Mac (Clips.swift, ClipEditor.swift).
@MainActor final class VodHub: ObservableObject {
 @Published var vods: [VodRow] = []
 @Published var loading = false
 @Published var busy = false
 @Published var status = ""
 @Published var selected = ""
 @Published var atText = ""
 @Published var length = 30
 @Published var titleText = ""
 private var twitch: TwitchClips?
 private var stream: StreamHub?

 func attach(_ clips: TwitchClips,stream hub: StreamHub) {
  if twitch == nil { twitch = clips; stream = hub }
 }

 // Makes sure the channel and account ids are loaded. Returns a sentence if it can't.
 private func ready() async -> String? {
  guard let tw = twitch, tw.signedIn else { return "Twitch isn't connected yet. Sign in under Accounts." }
  guard let hub = stream else { return "The Stream page isn't ready yet." }
  if hub.channel == nil || hub.meID.isEmpty { await hub.refresh(force:true) }
  guard hub.channel != nil, !hub.meID.isEmpty else { return hub.message.isEmpty ? "I couldn't load your channel from Twitch." : hub.message }
  return nil
 }

 func load() async {
  guard !loading else { return }
  if let problem = await ready() { status = problem; return }
  guard let tw = twitch, let id = stream?.channel?.id else { return }
  loading = true
  defer { loading = false }
  do {
   let (code,json) = try await tw.call("/videos?user_id=\(id)&type=archive&first=12")
   guard code == 200 else { status = VodPlan.explain(code:code,message:json["message"] as? String); return }
   vods = VodPlan.parseVideos(json)
   if !vods.contains(where: { $0.id == selected }) { selected = vods.first?.id ?? "" }
   status = vods.isEmpty ? "No past streams found. Past streams (VODs) must be switched on in Twitch, and Twitch deletes old ones after a while." : ""
  } catch {
   status = "Couldn't reach Twitch: \(error.localizedDescription)"
  }
 }

 // MARK: making clips

 // One clip, ending at `end` seconds into the video. Returns the clip's id and a sentence about how it went.
 private func makeClip(vod: VodRow,end: Int,length: Double,title: String) async -> (id: String?,note: String) {
  guard let tw = twitch, let hub = stream, let broadcaster = hub.channel?.id else { return (nil,"Twitch isn't ready.") }
  guard let plan = VodPlan.plan(endAt:end,duration:length,vodSeconds:vod.seconds) else { return (nil,"That stream is too short for a clip.") }
  let path = VodPlan.clipPath(editor:hub.meID,broadcaster:broadcaster,vod:vod.id,offset:plan.offset,duration:plan.duration,title:title)
  do {
   let (code,json) = try await tw.call(path,method:"POST")
   guard code == 202, let id = StreamData.rows(json).first?["id"] as? String else { return (nil,VodPlan.explain(code:code,message:json["message"] as? String)) }
   // Twitch makes it in the background; check it exists before saying so.
   var exists = false
   for _ in 0..<12 {
    try await Task.sleep(nanoseconds:3_000_000_000)
    let (_,found) = try await tw.call("/clips?id=\(id)")
    if !StreamData.rows(found).isEmpty { exists = true; break }
   }
   tw.lastClipURL = "https://clips.twitch.tv/\(id)"
   return (id,exists ? "Made." : "Twitch accepted it but it isn't showing yet.")
  } catch {
   return (nil,"Couldn't make the clip: \(error.localizedDescription)")
  }
 }

 private func finish(_ made: [(id: String,title: String)]) async {
  guard let tw = twitch, let broadcaster = stream?.channel?.id, tw.autoEdit else { return }
  for item in made { await tw.tidyClip(clipID:item.id,broadcasterID:broadcaster,title:item.title) }
 }

 // From the form on the Stream page.
 func clipFromForm() async {
  guard !busy else { return }
  if let problem = await ready() { status = problem; return }
  guard let vod = vods.first(where: { $0.id == selected }) else { status = "Pick a past stream first."; return }
  guard let at = VodPlan.parseClock(atText) else { status = "Type the time the clip should end at, like 1:12:30 or 45m."; return }
  busy = true
  defer { busy = false }
  status = "Asking Twitch for the clip…"
  let result = await makeClip(vod:vod,end:at,length:Double(length),title:titleText)
  guard let id = result.id else { status = result.note; return }
  status = "\(result.note) https://clips.twitch.tv/\(id)"
  await finish([(id,titleText)])
 }

 // Every marker he dropped during that stream becomes a clip (at most 8 a run).
 func clipMarked(_ vod: VodRow) async -> String {
  guard !busy else { return "Already working on clips." }
  if let problem = await ready() { status = problem; return problem }
  guard let tw = twitch else { return "Twitch isn't ready." }
  busy = true
  defer { busy = false }
  status = "Looking for your markers in “\(vod.title)”…"
  var markers: [VodMarker] = []
  do {
   let (code,json) = try await tw.call("/streams/markers?video_id=\(vod.id)&first=100")
   guard code == 200 else { let why = VodPlan.explain(code:code,message:json["message"] as? String); status = why; return why }
   markers = VodPlan.parseMarkers(json)
  } catch {
   let why = "Couldn't reach Twitch: \(error.localizedDescription)"
   status = why
   return why
  }
  guard !markers.isEmpty else {
   status = "No markers in that stream. Mark moments while you stream (the Mark it button, or tell Friday \"mark that\")."
   return status
  }
  let chosen = Array(markers.prefix(VodPlan.maxPerBatch))
  var made: [(id: String,title: String)] = []
  var problems: [String] = []
  for (index,marker) in chosen.enumerated() {
   let title = marker.note.isEmpty ? "Moment \(index + 1) at \(VodPlan.clock(marker.seconds))" : marker.note
   status = "Clip \(index + 1) of \(chosen.count): \(title)…"
   let result = await makeClip(vod:vod,end:VodPlan.markerEnd(marker.seconds,vodSeconds:vod.seconds),length:VodPlan.defaultClip,title:title)
   if let id = result.id { made.append((id,title)) } else { problems.append(result.note) }
   try? await Task.sleep(nanoseconds:2_000_000_000)
  }
  let extra = markers.count > chosen.count ? " (the first \(chosen.count) of \(markers.count) markers)" : ""
  status = made.isEmpty ? (problems.first ?? "No clips were made.") : "Made \(made.count) clip\(made.count == 1 ? "" : "s")\(extra). Cutting the highlights on this Mac next; they land in Movies > Game Companion Clips."
  let summary = status
  await finish(made)
  return summary
 }

 // MARK: Friday's voice tools. Each returns a sentence she can say.

 private func pick(_ which: String) async -> (vod: VodRow?,problem: String?) {
  if vods.isEmpty { await load() }
  if vods.isEmpty { return (nil,status.isEmpty ? "I couldn't find any past streams." : status) }
  guard let vod = VodPlan.pickVod(vods,which:which) else { return (nil,"I couldn't tell which stream you mean. Say latest, or a number from the list on the Stream page.") }
  return (vod,nil)
 }

 func voiceClip(video: String,at: String,seconds: Double?,title: String) async -> String {
  let chosen = await pick(video)
  guard let vod = chosen.vod else { return chosen.problem ?? "I couldn't find that stream." }
  guard let end = VodPlan.parseClock(at) else { return "I need the time in the stream the clip should end at, like 1:12:30 or 45 minutes." }
  guard !busy else { return "I'm already making clips. Give me a minute." }
  busy = true
  defer { busy = false }
  let name = title.trimmingCharacters(in:.whitespacesAndNewlines)
  let result = await makeClip(vod:vod,end:end,length:seconds ?? VodPlan.defaultClip,title:name)
  guard let id = result.id else { status = result.note; return result.note }
  status = "\(result.note) https://clips.twitch.tv/\(id)"
  Task { await self.finish([(id,name)]) }
  return "Made a clip of \(vod.title) ending at \(VodPlan.clock(end)). It's public on Twitch now, and I'm cutting the highlight on your Mac."
 }

 // Starts the batch and answers right away: it takes a minute or more, and Friday's tool answer shouldn't wait that long.
 func voiceMarked(video: String) async -> String {
  let chosen = await pick(video)
  guard let vod = chosen.vod else { return chosen.problem ?? "I couldn't find that stream." }
  guard !busy else { return "I'm already making clips. Give me a minute." }
  Task { _ = await self.clipMarked(vod) }
  return "On it. I'm clipping the moments you marked in \(vod.title), up to \(VodPlan.maxPerBatch). You'll see them on the Stream page and in your clips folder in a minute or two."
 }
}

extension CompanionInterfaceView {
 var hubStreamVods: some View {
  VStack(alignment:.leading,spacing:14) {
   HStack(spacing:10) {
    Text("Clip from my past streams").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
    if vods.loading || vods.busy { ProgressView().controlSize(.small) }
    Spacer()
    Button { Task { await vods.load() } } label: { Label("Load my streams",systemImage:"arrow.clockwise") }
     .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12))).disabled(vods.loading || vods.busy)
   }
   Text("Pick a past stream, then clip the moments you marked or type a time. A clip is public on Twitch the moment it's made. The app then downloads it and cuts the highlight on this Mac. Twitch deletes old streams after a while, so clip soon.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.6))
   if vods.vods.isEmpty {
    Text(vods.status.isEmpty ? "Press Load my streams." : vods.status).font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.55))
   } else {
    VStack(spacing:8) {
     ForEach(Array(vods.vods.prefix(6).enumerated()),id:\.element.id) { index,vod in
      HStack(spacing:10) {
       Button { vods.selected = vod.id } label: { Image(systemName:vods.selected == vod.id ? "largecircle.fill.circle" : "circle").foregroundStyle(vods.selected == vod.id ? Noir.crimsonLight : Color.white.opacity(0.4)) }.buttonStyle(.plain)
       VStack(alignment:.leading,spacing:2) {
        Text("\(index + 1). \(vod.title)").font(.system(size:13.5,weight:.medium,design:.rounded)).foregroundStyle(Color.white).lineLimit(1)
        Text("\(vod.created.map { hubAgo($0) } ?? "") · \(VodPlan.clock(vod.seconds)) long · \(vod.views) view\(vod.views == 1 ? "" : "s")").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
       }
       Spacer()
       Button { Task { _ = await vods.clipMarked(vod) } } label: { Label("Clip my marked moments",systemImage:"bookmark.fill") }
        .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12))).disabled(vods.busy)
       Button { hubOpen(vod.url) } label: { Image(systemName:"arrow.up.right") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
      }
      .padding(10)
      .background(RoundedRectangle(cornerRadius:12,style:.continuous).fill(Color.white.opacity(vods.selected == vod.id ? 0.07 : 0.03)))
     }
    }
    HStack(spacing:10) {
     hubField("Clip ends at (1:12:30 or 45m)",text:$vods.atText).frame(maxWidth:230)
     Picker("Length",selection:$vods.length) { Text("15 s").tag(15); Text("30 s").tag(30); Text("45 s").tag(45); Text("60 s").tag(60) }.pickerStyle(.segmented).labelsHidden().frame(width:200)
     hubField("Title",text:$vods.titleText)
     Button { Task { await vods.clipFromForm() } } label: { Label("Make clip",systemImage:"scissors") }
      .buttonStyle(PillButtonStyle(tint:HubColor.violet)).disabled(vods.busy || vods.selected.isEmpty)
    }
    if !vods.status.isEmpty { Text(vods.status).font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.75)).textSelection(.enabled) }
   }
  }
  .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
 }
}
