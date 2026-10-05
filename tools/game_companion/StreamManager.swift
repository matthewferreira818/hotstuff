import SwiftUI
import AppKit

// The Stream page: a friendly manager for Matthew's Twitch channel. It shows whether he is live, lets him change the title and
// category in two clicks (with saved presets), mark a moment, clip the last stretch and open the clips, and runs a go-live checklist.
// It uses the same Twitch login as the clip button (Clips.swift). Twitch doesn't let any app press "Start streaming": that stays in
// OBS or Streamlabs, and the page says so. It only changes anything when he presses Update, Mark or Clip.
@MainActor final class StreamHub: ObservableObject {
 static let presetsKey = "stream.presets"

 @Published var channel: ChannelInfo?
 @Published var meID = ""
 @Published var live: StreamLive?
 @Published var followers: Int?
 @Published var clipRows: [ClipRow] = []
 @Published var titleDraft = "" { didSet { if !syncing { touched = true } } }
 @Published var gameDraft: CategoryHit? { didSet { if !syncing { touched = true } } }
 @Published var categoryQuery = "" { didSet { searchSoon() } }
 @Published var hits: [CategoryHit] = []
 @Published var searching = false
 @Published var markerNote = ""
 @Published var presetName = ""
 @Published var presets: [StreamPreset] = StreamHub.loadPresets() {
  didSet { UserDefaults.standard.set(try? JSONEncoder().encode(presets),forKey:StreamHub.presetsKey) }
 }
 @Published var message = ""
 @Published var loading = false
 @Published var saving = false
 @Published var marking = false
 @Published var loaded = false
 // True once he has typed or picked something, so a refresh doesn't overwrite what he is working on.
 @Published var touched = false
 private var syncing = false
 private var lastRefresh = Date.distantPast
 private var twitch: TwitchClips?
 private var searchTask: Task<Void,Never>?

 // Changing the title needs the channel's own account. A separate clip account can still see the channel.
 var canEdit: Bool { channel != nil && !meID.isEmpty && channel?.id == meID }

 static func loadPresets() -> [StreamPreset] {
  guard let data = UserDefaults.standard.data(forKey:presetsKey), let list = try? JSONDecoder().decode([StreamPreset].self,from:data) else { return [] }
  return list
 }

 func attach(_ clips: TwitchClips) { if twitch == nil { twitch = clips } }

 func refresh(force: Bool = false) async {
  guard let tw = twitch, tw.signedIn, !loading else { return }
  if !force && Date().timeIntervalSince(lastRefresh) < 50 { return }
  let login = tw.channel.trimmingCharacters(in:CharacterSet(charactersIn:"@ \n")).lowercased()
  guard !login.isEmpty else { return }
  loading = true
  defer { loading = false }
  // One call at a time: if the login has expired, only one of them should refresh it.
  do {
   let (_,mine) = try await tw.call("/users")
   meID = (StreamData.rows(mine).first?["id"] as? String) ?? ""
   let (_,theirs) = try await tw.call("/users?login=\(StreamData.encoded(login))")
   guard let id = StreamData.rows(theirs).first?["id"] as? String else {
    message = "Couldn't find a Twitch channel called \(login). Check the name in Settings."
    return
   }
   let (_,streamJSON) = try await tw.call("/streams?user_id=\(id)")
   let (_,channelJSON) = try await tw.call("/channels?broadcaster_id=\(id)")
   let (_,followJSON) = try await tw.call("/channels/followers?broadcaster_id=\(id)&first=1")
   let (_,clipJSON) = try await tw.call("/clips?broadcaster_id=\(id)&first=6")
   live = StreamData.parseStream(streamJSON)
   channel = StreamData.parseChannel(channelJSON)
   followers = StreamData.parseFollowerTotal(followJSON) ?? followers
   clipRows = StreamData.parseClips(clipJSON)
   if !touched, let info = channel {
    syncing = true
    titleDraft = info.title
    gameDraft = info.gameID.isEmpty ? nil : CategoryHit(id:info.gameID,name:info.gameName)
    syncing = false
   }
   loaded = true
   lastRefresh = Date()
  } catch {
   message = "Couldn't reach Twitch: \(error.localizedDescription)"
  }
 }

 private func searchSoon() {
  searchTask?.cancel()
  let query = categoryQuery.trimmingCharacters(in:.whitespacesAndNewlines)
  guard query.count >= 2, let tw = twitch, tw.signedIn else { hits = []; return }
  searchTask = Task { [weak self] in
   try? await Task.sleep(nanoseconds:400_000_000)
   guard !Task.isCancelled, let self = self else { return }
   self.searching = true
   if let (_,json) = try? await tw.call("/search/categories?query=\(StreamData.encoded(query))&first=8"), !Task.isCancelled {
    self.hits = StreamData.parseCategories(json)
   }
   self.searching = false
  }
 }

 func pick(_ hit: CategoryHit) {
  gameDraft = hit
  categoryQuery = ""
  hits = []
 }

 // Sends the title and category to Twitch. This changes the public channel, so it only runs when he presses Update.
 func save() async {
  guard canEdit, !saving else { return }
  if let problem = StreamData.titleProblem(titleDraft) { message = problem; return }
  if await push(title:titleDraft,gameID:gameDraft?.id) {
   touched = false
   await refresh(force:true)
  }
 }

 // The one place that changes the channel. Either part can be nil, so a title change leaves the category alone and the reverse.
 private func push(title: String?,gameID: String?) async -> Bool {
  guard let tw = twitch, let info = channel, canEdit, let body = StreamData.updateBody(title:title,gameID:gameID) else { return false }
  saving = true
  defer { saving = false }
  do {
   let (code,json) = try await tw.call("/channels?broadcaster_id=\(info.id)",method:"PATCH",body:body)
   if code == 204 { message = "Saved on Twitch."; return true }
   message = StreamData.explain(code:code,message:json["message"] as? String,doing:"change the title or category")
  } catch {
   message = "Couldn't reach Twitch: \(error.localizedDescription)"
  }
  return false
 }

 // A marker is a bookmark in the live stream's recording, so he can find the moment later.
 func mark() async {
  if await mark(note:markerNote) { markerNote = "" }
 }

 @discardableResult func mark(note: String) async -> Bool {
  guard let tw = twitch, let info = channel, live != nil, !marking else { return false }
  marking = true
  defer { marking = false }
  do {
   let (code,json) = try await tw.call("/streams/markers",method:"POST",body:StreamData.markerBody(userID:info.id,note:note))
   if code == 200 {
    let seconds = StreamData.rows(json).first?["position_seconds"] as? Int
    message = seconds.map { "Marked at \(StreamData.duration($0)) into the stream." } ?? "Marked."
    return true
   }
   message = StreamData.explain(code:code,message:json["message"] as? String,doing:"add a marker")
  } catch {
   message = "Couldn't reach Twitch: \(error.localizedDescription)"
  }
  return false
 }

 // MARK: Friday's voice tools
 // Each one returns a sentence Friday can say. They only run when Matthew asks out loud and has switched the tools on
 // (see Live.swift). A title or category change touches only that one part and leaves whatever he is typing on the page alone.

 // nil when the channel is loaded and ready, otherwise a sentence saying what is wrong.
 private func voiceReady(needsEdit: Bool) async -> String? {
  guard let tw = twitch, tw.signedIn else { return "Twitch isn't connected in the app yet." }
  await refresh(force:true)
  guard channel != nil else { return message.isEmpty ? "I couldn't load the channel from Twitch." : message }
  if needsEdit && !canEdit { return "This Twitch login isn't the channel's own account, so I can't change the channel. Matthew needs to sign in as the channel in Accounts." }
  return nil
 }

 func voiceStatus() async -> String {
  if let problem = await voiceReady(needsEdit:false) { return problem }
  let followerText = followers.map { ", \($0) followers" } ?? ""
  if let now = live {
   let time = now.startedAt.map { ", on air for \(StreamData.uptime(from:$0,to:Date()))" } ?? ""
   return "Live now: \"\(now.title)\", category \(now.game.isEmpty ? "none" : now.game), \(now.viewers) viewer\(now.viewers == 1 ? "" : "s")\(time)\(followerText)."
  }
  let info = channel
  return "Not live right now. The saved title is \"\(info?.title ?? "")\" and the category is \((info?.gameName.isEmpty ?? true) ? "none" : (info?.gameName ?? ""))\(followerText)."
 }

 func voiceSetTitle(_ raw: String) async -> String {
  if let problem = StreamData.titleProblem(raw) { return problem }
  if let problem = await voiceReady(needsEdit:true) { return problem }
  let title = raw.trimmingCharacters(in:.whitespacesAndNewlines)
  guard await push(title:title,gameID:nil) else { return message }
  await refresh(force:true)
  return "Done. The stream title is now: \(title)."
 }

 func voiceSetCategory(_ raw: String) async -> String {
  let query = raw.trimmingCharacters(in:.whitespacesAndNewlines)
  if query.count < 2 { return "I need the name of the game or category." }
  if let problem = await voiceReady(needsEdit:true) { return problem }
  guard let tw = twitch, let (_,json) = try? await tw.call("/search/categories?query=\(StreamData.encoded(query))&first=8") else { return "I couldn't search Twitch's categories just now." }
  switch StreamData.chooseCategory(StreamData.parseCategories(json),query:query) {
  case .none: return "Twitch has no category matching \"\(query)\". Nothing was changed."
  case .ask(let names): return "Nothing was changed. Twitch has several close matches: \(names.joined(separator:", ")). Ask which one is meant."
  case .use(let hit):
   guard await push(title:nil,gameID:hit.id) else { return message }
   await refresh(force:true)
   return "Done. The category is now \(hit.name)."
  }
 }

 func voicePreset(_ raw: String) async -> String {
  if presets.isEmpty { return "There are no saved presets yet. Matthew can save one on the Stream page." }
  let wanted = raw.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
  guard !wanted.isEmpty, let preset = presets.first(where: { $0.name.lowercased() == wanted }) ?? presets.first(where: { $0.name.lowercased().contains(wanted) }) else {
   return "I couldn't find that preset. The saved ones are: \(presets.map { $0.name }.joined(separator:", "))."
  }
  if let problem = await voiceReady(needsEdit:true) { return problem }
  guard await push(title:preset.title,gameID:preset.gameID.isEmpty ? nil : preset.gameID) else { return message }
  await refresh(force:true)
  return "Done. Used the \(preset.name) preset: \"\(preset.title)\"\(preset.gameName.isEmpty ? "" : ", category \(preset.gameName)")."
 }

 func voiceMark(_ note: String) async -> String {
  if let problem = await voiceReady(needsEdit:false) { return problem }
  guard live != nil else { return "You're not live right now, so Twitch can't take a marker." }
  if await mark(note:note) { return message }
  return "Twitch didn't take the marker. Past broadcasts (VODs) must be switched on in Twitch."
 }

 func savePreset() {
  let name = presetName.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !name.isEmpty, StreamData.titleProblem(titleDraft) == nil else { message = "Type a title above and a name for the preset first."; return }
  var next = presets
  next.removeAll { $0.name.lowercased() == name.lowercased() }
  next.append(StreamPreset(id:UUID().uuidString,name:name,title:titleDraft.trimmingCharacters(in:.whitespacesAndNewlines),gameID:gameDraft?.id ?? "",gameName:gameDraft?.name ?? ""))
  presets = next
  presetName = ""
  message = "Saved the preset \"\(name)\". Click it any time to fill in the title and category."
 }

 func use(_ preset: StreamPreset) {
  titleDraft = preset.title
  gameDraft = preset.gameID.isEmpty ? nil : CategoryHit(id:preset.gameID,name:preset.gameName)
 }

 func remove(_ preset: StreamPreset) { presets.removeAll { $0.id == preset.id } }
}

extension CompanionInterfaceView {
 var hubStream: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:18) {
    hubStreamHeader
    if !clips.signedIn {
     hubStreamConnect
    } else if clips.channel.trimmingCharacters(in:.whitespaces).isEmpty {
     VStack(alignment:.leading,spacing:12) {
      Text("Which channel is yours?").font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
      Text("Type just the name (the part after twitch.tv/).").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.6))
      hubField("your channel name",text:$clips.channel).frame(maxWidth:340)
      Button { Task { await stream.refresh(force:true) } } label: { Label("Load my channel",systemImage:"arrow.clockwise") }.buttonStyle(PillButtonStyle())
     }
     .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
    } else if !stream.loaded {
     if stream.loading { ProgressView().controlSize(.large).frame(maxWidth:.infinity).padding(40) }
     else {
      VStack(spacing:10) {
       Text("Couldn't load your channel yet").font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
       if !stream.message.isEmpty { Text(stream.message).font(.system(size:13,design:.rounded)).foregroundStyle(Color.white.opacity(0.6)) }
       Button { Task { await stream.refresh(force:true) } } label: { Label("Try again",systemImage:"arrow.clockwise") }.buttonStyle(PillButtonStyle())
      }
      .frame(maxWidth:.infinity).padding(30).hubCard()
     }
    } else {
     hubStreamStatus
     if !stream.canEdit { hubStreamWrongAccount }
     hubStreamEditor
     HStack(alignment:.top,spacing:14) {
      hubStreamActions
      hubStreamChecklist
     }
     hubStreamClips
    }
    if !stream.message.isEmpty {
     Text(stream.message).font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.75)).textSelection(.enabled)
    }
    Text("Twitch doesn't let any app press Start Streaming for you; that stays in OBS or Streamlabs. Nothing on this page changes your channel until you press Update, Mark or Clip.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
  .onAppear { stream.attach(clips); Task { await stream.refresh() } }
 }

 var hubStreamHeader: some View {
  HStack(spacing:10) {
   hubPill("TWITCH · YOUR CHANNEL",tint:HubColor.violet)
   Spacer()
   Button { hubOpen(hubTwitchDashboard) } label: { Label("Twitch Stream Manager",systemImage:"arrow.up.right.square") }
    .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   Button { Task { await stream.refresh(force:true) } } label: { Label(stream.loading ? "Refreshing…" : "Refresh",systemImage:"arrow.clockwise") }
    .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    .disabled(stream.loading || !clips.signedIn)
  }
 }

 var hubStreamLogin: String { clips.channel.trimmingCharacters(in:CharacterSet(charactersIn:"@ \n")).lowercased() }
 var hubTwitchDashboard: String { hubStreamLogin.isEmpty ? "https://dashboard.twitch.tv/" : "https://dashboard.twitch.tv/u/\(hubStreamLogin)/stream-manager" }
 func hubOpen(_ link: String) { if let url = URL(string:link) { NSWorkspace.shared.open(url) } }

 var hubStreamConnect: some View {
  VStack(alignment:.leading,spacing:12) {
   Text("Connect Twitch first").font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
   Text("This page uses the same Twitch login as the clip button. Sign in once and it shows whether you're live, lets you change your title and category, and lists your clips. If you signed in before this page existed, sign out and in once more so Twitch can give the new permission.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.6))
   VStack(alignment:.leading,spacing:10) { clipSettings }
  }
  .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
 }

 var hubStreamStatus: some View {
  VStack(alignment:.leading,spacing:14) {
   HStack(spacing:10) {
    if let now = stream.live {
     hubPill("LIVE NOW",tint:Noir.crimsonLight)
     Text(now.title.isEmpty ? "(no title)" : now.title).font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(Color.white).lineLimit(2)
    } else {
     hubPill("OFFLINE",tint:HubColor.slate)
     Text("Not streaming right now").font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
    }
    Spacer()
   }
   LazyVGrid(columns:[GridItem(.adaptive(minimum:200),spacing:14)],spacing:14) {
    if let now = stream.live {
     hubStat("Watching now","\(now.viewers)","viewers",tint:Color.white)
     if let start = now.startedAt {
      TimelineView(.periodic(from:Date(),by:30)) { timeline in
       hubStat("On air for",StreamData.uptime(from:start,to:timeline.date),"since \(start.formatted(date:.omitted,time:.shortened))",tint:Color.white)
      }
     }
     hubStat("Category",now.game.isEmpty ? "None" : now.game,"live category",tint:Color.white)
    } else {
     hubStat("Category",stream.channel?.gameName.isEmpty == false ? (stream.channel?.gameName ?? "") : "None","what you last streamed",tint:Color.white)
    }
    hubStat("Followers",stream.followers.map { $0.formatted() } ?? "—","total",tint:HubColor.violet)
   }
  }
  .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
 }

 var hubStreamWrongAccount: some View {
  HStack(alignment:.top,spacing:12) {
   Image(systemName:"exclamationmark.triangle.fill").foregroundStyle(HubColor.amber)
   Text("You're signed in to Twitch as a different account than \(stream.channel?.name ?? hubStreamLogin). You can see your channel here, but changing the title or category needs the channel's own account. Sign out in Accounts and sign in as \(stream.channel?.name ?? hubStreamLogin) to turn those on.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.75))
  }
  .padding(16).frame(maxWidth:.infinity,alignment:.leading).hubCard()
 }

 func hubField(_ placeholder: String,text: Binding<String>) -> some View {
  TextField(placeholder,text:text).textFieldStyle(.plain)
   .font(.system(size:14,design:.rounded))
   .padding(.horizontal,14).padding(.vertical,10)
   .background(RoundedRectangle(cornerRadius:12,style:.continuous).fill(Color.white.opacity(0.07)))
   .overlay(RoundedRectangle(cornerRadius:12,style:.continuous).stroke(Color.white.opacity(0.10),lineWidth:1))
 }

 func hubChip(_ text: String,selected: Bool = false,tint: Color = Color.white.opacity(0.12),action: @escaping () -> Void) -> some View {
  Button(action:action) {
   Text(text).font(.system(size:12.5,weight:.medium,design:.rounded)).foregroundStyle(Color.white).lineLimit(1)
    .padding(.horizontal,12).padding(.vertical,7)
    .background(Capsule().fill(selected ? Noir.crimson : tint))
  }
  .buttonStyle(.plain)
 }

 var hubStreamEditor: some View {
  VStack(alignment:.leading,spacing:14) {
   Text("Title and category").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
   VStack(alignment:.leading,spacing:6) {
    HStack {
     Text("Stream title").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.55))
     Spacer()
     Text("\(stream.titleDraft.count)/\(StreamData.titleLimit)").font(.system(size:11.5,design:.rounded)).foregroundStyle(stream.titleDraft.count > StreamData.titleLimit ? Noir.crimsonLight : Color.white.opacity(0.4))
    }
    hubField("What are you streaming?",text:$stream.titleDraft)
   }
   VStack(alignment:.leading,spacing:8) {
    HStack(spacing:8) {
     Text("Category").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.55))
     if let game = stream.gameDraft { hubPill(game.name.uppercased(),tint:HubColor.violet) } else { Text("none chosen").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.4)) }
    }
    HStack(spacing:8) {
     hubField("Search a game or category",text:$stream.categoryQuery)
     if stream.searching { ProgressView().controlSize(.small) }
    }
    if !stream.hits.isEmpty {
     LazyVGrid(columns:[GridItem(.adaptive(minimum:150),spacing:8)],alignment:.leading,spacing:8) {
      ForEach(stream.hits) { hit in hubChip(hit.name) { stream.pick(hit) } }
     }
    }
   }
   VStack(alignment:.leading,spacing:8) {
    Text("Presets").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.55))
    if stream.presets.isEmpty {
     Text("Save a title and category you use often, then fill it in with one click.").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
    } else {
     LazyVGrid(columns:[GridItem(.adaptive(minimum:150),spacing:8)],alignment:.leading,spacing:8) {
      ForEach(stream.presets) { preset in
       hubChip(preset.name,tint:HubColor.violet.opacity(0.35)) { stream.use(preset) }
        .help("\(preset.title)\(preset.gameName.isEmpty ? "" : " · \(preset.gameName)")")
        .contextMenu { Button("Delete this preset",role:.destructive) { stream.remove(preset) } }
      }
     }
     Text("Right-click a preset to delete it.").font(.system(size:11,design:.rounded)).foregroundStyle(Color.white.opacity(0.35))
    }
    HStack(spacing:8) {
     hubField("Name for a new preset",text:$stream.presetName).frame(maxWidth:260)
     Button { stream.savePreset() } label: { Label("Save as preset",systemImage:"plus") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    }
   }
   HStack(spacing:12) {
    Button { Task { await stream.save() } } label: { Label(stream.saving ? "Updating…" : "Update on Twitch",systemImage:"arrow.up.circle.fill") }
     .buttonStyle(PillButtonStyle())
     .disabled(!stream.canEdit || stream.saving || !stream.touched)
    if stream.touched {
     Button { stream.touched = false; Task { await stream.refresh(force:true) } } label: { Label("Undo my edits",systemImage:"arrow.uturn.backward") }
      .buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    }
    Text("This changes your public channel right away, live or not.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
   }
  }
  .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
 }

 var hubStreamActions: some View {
  VStack(alignment:.leading,spacing:12) {
   Text("While you're live").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
   VStack(alignment:.leading,spacing:6) {
    Text("Mark this moment").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.55))
    hubField("Optional note, like \"clutch win\"",text:$stream.markerNote)
    Button { Task { await stream.mark() } } label: { Label(stream.marking ? "Marking…" : "Mark it",systemImage:"bookmark.fill") }
     .buttonStyle(PillButtonStyle())
     .disabled(stream.live == nil || stream.marking)
    Text("A bookmark in your stream's recording, so you can find the moment later. Needs past broadcasts switched on in Twitch.").font(.system(size:11,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
   }
   Divider().overlay(Color.white.opacity(0.1))
   VStack(alignment:.leading,spacing:6) {
    Button { Task { await clips.clipNow() } } label: { Label(clips.busy ? "Clipping…" : "Clip the last moments",systemImage:"scissors") }
     .buttonStyle(PillButtonStyle(tint:HubColor.violet))
     .disabled(stream.live == nil || clips.busy)
    Text("Makes a public Twitch clip, then cuts the highlight on this Mac. The same as the clip button on the Game page.").font(.system(size:11,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
   }
   HStack(spacing:8) {
    Button { hubOpen("https://www.twitch.tv/\(hubStreamLogin)") } label: { Label("My channel",systemImage:"tv") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
    Button { hubOpen("https://dashboard.twitch.tv/u/\(hubStreamLogin)/content/clips") } label: { Label("My clips",systemImage:"film") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
   }
  }
  .padding(18).frame(maxWidth:.infinity,minHeight:300,alignment:.topLeading).hubCard()
 }

 func hubCheck(_ ok: Bool,_ text: String,_ fix: String) -> some View {
  HStack(alignment:.top,spacing:10) {
   Image(systemName:ok ? "checkmark.circle.fill" : "circle").foregroundStyle(ok ? HubColor.green : Color.white.opacity(0.35))
   VStack(alignment:.leading,spacing:2) {
    Text(text).font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(ok ? 0.9 : 0.75))
    if !ok { Text(fix).font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.45)) }
   }
  }
 }

 var hubStreamChecklist: some View {
  VStack(alignment:.leading,spacing:12) {
   Text("Before you go live").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
   hubCheck(clips.signedIn,"Twitch is connected","Sign in under Accounts.")
   hubCheck(!stream.titleDraft.trimmingCharacters(in:.whitespaces).isEmpty && !stream.touched,"Title is saved on Twitch","Type a title and press Update.")
   hubCheck(stream.gameDraft != nil && !stream.touched,"Category is saved on Twitch","Search a game and press Update.")
   hubCheck(live.hasKey,"Friday has her Google key","Add it in Settings.")
   hubCheck(c.sharing,"A game window is chosen for Friday","Press Choose window on the Game page.")
   hubCheck(clips.voiceClips,"\"Clip it\" by voice is on","Tick it in Settings before starting Friday.")
   hubCheck(clips.voiceStream,"Friday can run this page by voice","Tick it in Settings before starting Friday.")
   hubCheck(stream.live != nil,"You're live on Twitch","Start streaming in OBS or Streamlabs.")
  }
  .padding(18).frame(maxWidth:.infinity,minHeight:300,alignment:.topLeading).hubCard()
 }

 var hubStreamClips: some View {
  VStack(alignment:.leading,spacing:12) {
   Text("Latest clips").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
   if stream.clipRows.isEmpty {
    Text("No clips found on your channel yet.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
   } else {
    ForEach(stream.clipRows) { clip in
     HStack(spacing:12) {
      Image(systemName:"film.fill").foregroundStyle(HubColor.violet)
      VStack(alignment:.leading,spacing:2) {
       Text(clip.title).font(.system(size:13.5,weight:.medium,design:.rounded)).foregroundStyle(Color.white).lineLimit(1)
       Text("\(Int(clip.seconds.rounded())) s · \(clip.views) view\(clip.views == 1 ? "" : "s") · \(hubAgo(clip.created))").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
      }
      Spacer()
      Button { hubOpen(clip.url) } label: { Label("Open",systemImage:"arrow.up.right") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12)))
     }
    }
   }
  }
  .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()
 }
}
