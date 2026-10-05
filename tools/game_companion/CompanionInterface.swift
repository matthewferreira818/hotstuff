import Cocoa
import SwiftUI
import AVFoundation
import Combine

struct CompanionInterfaceView: View {
 @StateObject var c = Companion()
 @StateObject var live = LiveBuddy()
 @StateObject var clips = TwitchClips()
 @StateObject var hub = HubModel()
 @Namespace var railNamespace
 @StateObject var stocks = StockHub()
 @StateObject var ventures = VentureHub()
 @StateObject var sales = SalesHub()
 @StateObject var meeting = MeetingHub()
 @StateObject var stream = StreamHub()
 @StateObject var feed = FridayFeed()
 @StateObject var chat = ChatHub()
 @StateObject var hands = FridayHands()
 @StateObject var corner = FridayCornerController()
 @StateObject var conversation = ConversationStore(fileURL:DesignPreview.enabled ? URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("GameCompanion-DesignPreviewMemory.json") : nil,load: !DesignPreview.enabled)
 private let heartbeat = Timer.publish(every:60,on:.main,in:.common).autoconnect()
 let refreshTick = Timer.publish(every:300,on:.main,in:.common).autoconnect()
 let pageTick = Timer.publish(every:60,on:.main,in:.common).autoconnect()
 @Environment(\.accessibilityReduceMotion) var reduceMotion
 var body: some View {
  hubShell
  .frame(minWidth:960,idealWidth:1100,maxWidth:.infinity,minHeight:660,idealHeight:760,maxHeight:.infinity)
  .background(NoirBackground())
  .preferredColorScheme(.dark)
  .tint(Noir.crimson)
  .groupBoxStyle(NoirCard())
  .focusEffectDisabled()
  .onAppear { Keychain.migrateLegacy([GeminiKey.service,TwitchTokens.service,MeetingHub.tokenService,SalesHub.service]); c.conversation = conversation; live.conversation = conversation; live.clips = clips; live.stream = stream; live.feed = feed; live.chat = chat; live.hands = hands; live.meeting = meeting; hands.attach(live); chat.attach(clips,stream:stream,feed:feed); stream.attach(clips); corner.attach(live); Task { await stocks.refresh(); await ventures.refresh(force:true); await sales.refresh(force:true); await meeting.refresh(force:true) } }
  .onReceive(pageTick) { _ in Task { await hubRefreshVisible() } }
  .onReceive(refreshTick) { _ in Task { await stocks.refresh(); await ventures.refresh(); await sales.refresh(); await meeting.refresh() } }
  .onDisappear { stopAll() }
  .onChange(of:conversation.page) { _,page in
   c.handsFree = false; c.stopMic(); c.cancelResponse(); c.automatic = false; c.history.removeAll(); c.reply = ""; c.input = ""; c.unloadModel()
   if page == 2 { conversation.stopInitiative(); live.clearSession() }
  }
  .onChange(of:c.tab) { _,_ in stopAll() }
  .onReceive(heartbeat) { _ in
   // Never starts an engine or warms a local model just to ask a question.
   if !DesignPreview.enabled && live.running && live.ready && !live.search && !live.wiki && Date() > live.speakingUntil && conversation.claimInitiative() {
    live.sendSuggestion(conversation.initiativePrompt)
   }
  }
  .sheet(isPresented:$c.showPanel) { panel }
 }

 // The main screen: Friday's orb in the middle, a few round buttons underneath, everything else behind Settings.
 func fridayStage(orb: CGFloat) -> some View {
  VStack(spacing:0) {
   modePill
   Spacer(minLength:0)
   orbSection(orb)
   captions
   Spacer(minLength:0)
   if c.showKeyboard { composer.padding(.bottom,12) }
   seesRow
   controlBar
   HStack(spacing:6) { Image(systemName:"lock.shield"); Text(conversation.memoryEnabled ? "Reviewed notes saved locally · chats and images not saved" : "Memory off · chats and images not saved by this app") }
    .font(.system(size:10,design:.rounded)).foregroundStyle(Color.white.opacity(0.35)).padding(.top,14)
  }
  .padding(.horizontal,28).padding(.vertical,20)
 }

 // Says which brain is on. While Google Live runs it says so plainly, because the screen and mic are being shared.
 var modePill: some View {
  HStack {
   HStack(spacing:7) {
    Circle().fill(c.tab == 0 && live.running ? Noir.crimsonLight : Color.white.opacity(0.3)).frame(width:7,height:7)
    Text(c.tab == 0 ? (live.running ? "LIVE · WINDOW + MIC SHARED WITH GOOGLE" : "GOOGLE LIVE") : "ON THIS MAC").font(.system(size:10,weight:.semibold,design:.rounded)).tracking(1.2)
   }
   .foregroundStyle(Color.white.opacity(c.tab == 0 && live.running ? 0.85 : 0.5))
   .padding(.horizontal,12).padding(.vertical,7)
   .background(Capsule().fill(Color.white.opacity(0.07)))
   Spacer()
  }
 }

 // Friday in the middle: a crimson orb that shows what she is doing right now.
 func orbSection(_ orb: CGFloat) -> some View {
  TimelineView(.animation(minimumInterval:1.0/30.0)) { timeline in
   let state = orbState(at:timeline.date)
   VStack(spacing:4) {
    FridayOrb(state:state,t:timeline.date.timeIntervalSinceReferenceDate,level:orbLevel(at:timeline.date),size:orb,animated:!reduceMotion)
    Text("Friday").font(.system(size:26,weight:.light,design:.rounded)).tracking(8).foregroundStyle(Color.white.opacity(0.92))
    Text(DesignPreview.enabled ? "Review draft · connections disabled" : stateLabel(state)).font(.system(size:11,weight:.medium,design:.rounded)).tracking(2).textCase(.uppercase).foregroundStyle(state == .off ? Color.white.opacity(0.4) : Noir.crimsonLight)
   }
   .frame(maxWidth:.infinity)
  }
 }

 // What she heard, what she is saying, and the status line (which is where problems like "Choose a window first" show up).
 var captions: some View {
  VStack(spacing:8) {
   Text(c.tab == 0 ? live.status : c.status).font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.55)).multilineTextAlignment(.center).lineLimit(3)
   if c.tab == 0 && !live.heard.isEmpty { Text(live.heard).font(.system(size:14,design:.rounded)).foregroundStyle(Color.white.opacity(0.5)).multilineTextAlignment(.center).lineLimit(2) }
   if !clips.status.isEmpty { Text(clips.status).font(.system(size:12,design:.rounded)).foregroundStyle(Noir.crimsonLight.opacity(0.9)).multilineTextAlignment(.center).lineLimit(3).textSelection(.enabled) }
   if !clips.lastClipURL.isEmpty { Button("Open last clip") { if let url = URL(string:clips.lastClipURL) { NSWorkspace.shared.open(url) } }.buttonStyle(.plain).font(.system(size:12,weight:.semibold,design:.rounded)).foregroundStyle(Noir.crimsonLight) }
   if !currentReply.isEmpty { Text(currentReply).font(.system(size:17,design:.rounded)).foregroundStyle(Color.white.opacity(0.92)).multilineTextAlignment(.center).lineLimit(6).textSelection(.enabled) }
  }
  .frame(maxWidth:.infinity,minHeight:120,alignment:.top)
  .padding(.horizontal,10).padding(.top,6)
 }

 // A small look at the last picture she was sent, so what leaves the Mac is never a mystery.
 @ViewBuilder var seesRow: some View {
  if c.tab == 0, let seen = live.lastSeen {
   HStack(spacing:10) {
    Image(nsImage:seen).resizable().scaledToFit().frame(height:44).clipShape(RoundedRectangle(cornerRadius:6,style:.continuous))
    Text("Friday sees this · \(live.picturesSent) sent").font(.system(size:11,design:.rounded)).foregroundStyle(Color.white.opacity(0.45))
    Spacer()
   }
   .padding(.bottom,10)
  }
 }

 var controlBar: some View {
  HStack(spacing:18) {
   Button { c.choose() } label: { Image(systemName:"rectangle.on.rectangle") }.buttonStyle(OrbButtonStyle(diameter:54,filled:c.sharing)).disabled(DesignPreview.enabled).help("Choose the game window")
   Button { c.showKeyboard.toggle() } label: { Image(systemName:"keyboard") }.buttonStyle(OrbButtonStyle(diameter:54,filled:c.showKeyboard)).help("Type instead of talking")
   Button { mainAction() } label: { Image(systemName:mainIcon) }.buttonStyle(OrbButtonStyle(diameter:76,filled:true)).disabled(DesignPreview.enabled).help(c.tab == 0 ? (live.running ? "Stop the live session" : "Start the live session") : "Talk")
   if clips.signedIn {
    Button { Task { await clips.clipNow() } } label: { Image(systemName:"scissors") }.buttonStyle(OrbButtonStyle(diameter:54)).disabled(clips.busy).help("Clip the last 30 seconds")
   }
   Button { c.showPanel = true } label: { Image(systemName:"slider.horizontal.3") }.buttonStyle(OrbButtonStyle(diameter:54)).help("Settings and more")
   Button { stopAll() } label: { Image(systemName:"xmark") }.buttonStyle(OrbButtonStyle(diameter:54)).help("Stop everything")
  }
 }
 var mainIcon: String {
  if c.tab == 0 { return live.running ? "stop.fill" : "waveform" }
  return c.listening ? "mic.slash.fill" : "mic.fill"
 }
 // Never greyed out: if the key or window is missing, live.start says so in the status line.
 func mainAction() {
  if c.tab == 0 {
   if live.running { live.stop() } else { c.stopMic(); c.cancelResponse(); live.start(filter:c.filter,notes:conversation.page == 0 ? c.gameNotes : "") }
  } else {
   c.mic()
  }
 }

 // Everything the old screen had, now in a panel: the three views, window picker, keys, switches, memory.
 var panel: some View {
  VStack(alignment:.leading,spacing:14) {
   HStack {
    Text("Settings & more").font(.system(size:18,weight:.semibold,design:.rounded))
    Spacer()
    Button("Done") { c.showPanel = false }.buttonStyle(.borderedProminent).controlSize(.small)
   }
   Picker("View",selection:$conversation.page) { Text("Game").tag(0); Text("Conversation").tag(1); Text("Memory & topics").tag(2) }.pickerStyle(.segmented).labelsHidden()
   ScrollView {
    VStack(alignment:.leading,spacing:16) {
     if conversation.page == 0 { gamePage }
     else if conversation.page == 1 { conversationPage }
     else { memoryPage }
    }.frame(maxWidth:.infinity,alignment:.leading)
   }.scrollIndicators(.hidden)
  }
  .padding(.horizontal,26).padding(.vertical,18).frame(width:620,height:720)
  .background(NoirBackground())
  .preferredColorScheme(.dark)
  .tint(Noir.crimson)
  .groupBoxStyle(NoirCard())
  .focusEffectDisabled()
  .alert("Delete saved memory and topics?",isPresented:$conversation.deleteConfirmation) {
   Button("Cancel",role:.cancel) {}
   Button("Delete",role:.destructive) { stopAll(); conversation.deleteAll() }
  } message: { Text("This removes the reviewed notes and topic queue from this Mac. Copies already sent to Google cannot be recalled by this app.") }
 }
 // Google Live: asleep until started, then listening while you talk, thinking just after, speaking while her audio plays.
 // On this Mac: the same, from the local engine.
 func orbState(at now: Date) -> OrbState {
  if c.tab == 0 {
   guard live.running else { return .off }
   guard live.ready else { return .thinking }
   if now < live.speakingUntil { return .speaking }
   if live.status.hasPrefix("Looking up") { return .thinking }
   let since = now.timeIntervalSince(live.lastVoice)
   if since < 1.2 { return .listening }
   if since < 6 { return .thinking }
   return .idle
  }
  if c.speaker.isSpeaking { return .speaking }
  if c.listening { return .listening }
  if c.busy { return .thinking }
  return .idle
 }
 // 0 to 1: how loud the sound is right now, from the mic or from her voice.
 func orbLevel(at now: Date) -> Double {
  if c.tab == 0 {
   let voice = live.voiceLevel * max(0,1 - now.timeIntervalSince(live.voiceLevelAt) * 5)
   let mic = live.micLevel * max(0,1 - now.timeIntervalSince(live.micLevelAt) * 5)
   return min(1,max(voice,mic))
  }
  // The local engine has no level meter, so speaking gets a gentle pulse.
  if c.speaker.isSpeaking { return 0.45 + 0.25 * sin(now.timeIntervalSinceReferenceDate * 9) }
  return c.listening ? 0.25 : 0
 }
 func stateLabel(_ state: OrbState) -> String {
  switch state {
  case .off: return "Asleep"
  case .idle: return c.tab == 0 ? "Watching" : "Ready"
  case .listening: return "Listening"
  case .thinking: return "Thinking"
  case .speaking: return "Speaking"
  }
 }
 func stopAll() { conversation.stopInitiative(); live.clearSession(); c.stop(); chat.stop() }
 @ViewBuilder var engineChoice: some View {
  Picker("Conversation mode",selection:$c.tab) { Text("On this Mac").tag(1); Text("Google Live").tag(0) }.pickerStyle(.segmented).disabled(live.running || c.busy)
  Text(c.tab == 0 ? "Google Live sends microphone audio, selected-window frames and messages to Google when started. Check your account's free-tier limits before use." : "On this Mac uses your existing Ollama model. A 4B model can slow an 8 GB Mac.").font(.caption).foregroundStyle(.secondary)
 }
 @ViewBuilder var gamePage: some View {
  engineChoice
  GroupBox {
   HStack { VStack(alignment:.leading,spacing:5) { Label("Game window",systemImage:"rectangle.on.rectangle").font(.headline); Text(c.sharing ? (c.screenVerified ? "Access verified" : "Selected · not yet tested") : "No window shared").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button("Choose window") { c.choose() }.disabled(DesignPreview.enabled); Button("Stop sharing") { live.stop(); c.stopScreen() }.disabled(!c.sharing) }
  }
  if c.tab == 0 {
   HStack { Button(live.running ? "Stop live session" : "Start live session",systemImage:live.running ? "stop.circle" : "play.circle") { if live.running { live.stop() } else { c.stopMic(); c.cancelResponse(); live.start(filter:c.filter,notes:conversation.page == 0 ? c.gameNotes : "") } }.buttonStyle(.borderedProminent).disabled(DesignPreview.enabled || !live.hasKey || !c.sharing); Text(live.hasKey ? "Google key saved on this Mac" : "Add your key in Settings").font(.caption).foregroundStyle(.secondary) }
  } else {
   HStack { Button(c.listening ? "Stop microphone" : "Listen",systemImage:"mic") { c.mic() }.disabled(DesignPreview.enabled || c.busy || !c.voiceReady); Text(c.voiceReady ? "Local voice available" : "Local speech unavailable").font(.caption).foregroundStyle(.secondary) }
  }
  replyCard
  composer
  DisclosureGroup("Settings",isExpanded:$conversation.settingsOpen) {
   VStack(alignment:.leading,spacing:14) {
    TextField("Game notes and build context",text:$c.gameNotes)
    Text("Game notes are saved as a setting and sent as context in Google Live.").font(.caption).foregroundStyle(.secondary)
    HStack { Button("Test screen access · no AI") { c.testScreenAccess() }.disabled(DesignPreview.enabled || !c.sharing || c.busy); Button("Screen permission settings") { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!) }.disabled(DesignPreview.enabled) }
    if c.tab == 0 { googleSettings } else { localSettings }
   }.padding(.top,10)
  }
 }
 @ViewBuilder var replyCard: some View {
  GroupBox {
   VStack(alignment:.leading,spacing:10) {
    Text(c.tab == 0 ? live.status : c.status).font(.caption).foregroundStyle(.secondary)
    if c.tab == 0, let seen = live.lastSeen {
     HStack(spacing:10) {
      Image(nsImage:seen).resizable().scaledToFit().frame(height:68).clipShape(RoundedRectangle(cornerRadius:6))
      Text("What the buddy saw last · \(live.picturesSent) pictures sent. This preview stays in memory only.").font(.caption).foregroundStyle(.secondary)
     }
    }
    if c.tab == 0 && !live.heard.isEmpty { Text("You: \(live.heard)").font(.callout).foregroundStyle(.secondary) }
    Text(currentReply.isEmpty ? "Your companion's reply will appear here." : currentReply).font(.body).textSelection(.enabled).frame(maxWidth:.infinity,alignment:.leading).frame(minHeight:90,alignment:.topLeading)
   }
  }
 }
 var currentReply: String { c.tab == 0 ? live.said : c.reply }
 @ViewBuilder var composer: some View {
  HStack { TextField("What would you like to talk about?",text:c.tab == 0 ? $live.typed : $c.input).noirField().onSubmit { sendMessage() }; Button("Send",systemImage:"arrow.up.circle.fill") { sendMessage() }.disabled(DesignPreview.enabled || c.busy || (c.tab == 0 && !live.running)) }
 }
 func sendMessage() { if c.tab == 0 { live.sendTyped() } else { c.ask(c.input) } }
 func askReflection(_ text:String) { if c.tab == 0 { live.typed = text; live.sendTyped() } else { c.ask(text) } }
 @ViewBuilder var conversationPage: some View {
  engineChoice
  if c.tab == 0 {
   HStack { Button(live.running ? "Stop live conversation" : "Start live conversation",systemImage:live.running ? "stop.circle" : "play.circle") { if live.running { live.stop() } else { c.stopMic(); c.cancelResponse(); live.start(filter:c.filter,notes:"") } }.buttonStyle(.borderedProminent).disabled(DesignPreview.enabled || !live.hasKey || !c.sharing) }
   Text(live.running ? "This live session shares your chosen game window and microphone with Google. Stop all ends sharing." : "Choose a window on the Game view before starting a live conversation. Local conversation works without sharing a screen.").font(.caption).foregroundStyle(.secondary)
  } else {
   HStack { Button(c.listening ? "Stop microphone" : "Listen",systemImage:"mic") { c.mic() }.disabled(DesignPreview.enabled || c.busy || !c.voiceReady); Text("Local conversation does not capture the game window.").font(.caption).foregroundStyle(.secondary) }
  }
  Text("A companion with its own reasoning").font(.title3.bold())
  Text("Explore ideas, challenge a conclusion, or ask what changed its reasoning. Reflections describe generated reasoning and uncertainty; they do not establish subjective feelings or consciousness.").font(.callout).foregroundStyle(.secondary)
  Toggle("Reflective conversation",isOn:$conversation.reflective).disabled(live.running)
  HStack { Button("Reflect on our conversation") { askReflection("Reflect briefly on our current conversation: what conclusion seems strongest, what is uncertain, and what new evidence would change it? Do not claim actual feelings.") }; Button("Suggest something to explore") { askReflection(conversation.initiativePrompt) } }.disabled(DesignPreview.enabled || c.busy || (c.tab == 0 && !live.running))
  replyCard
  composer
  if !currentReply.isEmpty { Button("Review this as a topic") { conversation.proposalTitle = String(currentReply.prefix(180)); conversation.proposalPurpose = "Discuss this idea and agree on a plan before any research or building."; conversation.page = 2 } }
  GroupBox("Initiative · your choice") {
   VStack(alignment:.leading,spacing:9) {
    Toggle("Occasional questions and proposals",isOn:Binding(get:{ conversation.initiativeEnabled },set:{ conversation.enableInitiative($0) }))
    HStack { Text("At most once every"); Slider(value:$conversation.intervalMinutes,in:10...60,step:5); Text("\(Int(conversation.intervalMinutes)) minutes").monospacedDigit() }
    Text("Local mode may add a question to a reply when due; it never starts extra inference in the background. Google Live can ask during an already-running session when both lookup tools are off. Stop all turns initiative off.").font(.caption).foregroundStyle(.secondary)
    Text("A proposal is a request for your decision. This app does not execute new research, watch videos, download, build or spend after approval. Gameplay fact lookup still follows the existing Google Search setting.").font(.caption).foregroundStyle(.secondary)
   }
  }
 }
 @ViewBuilder var memoryPage: some View {
  Text("Remember what you choose").font(.title3.bold())
  Toggle("Save reviewed notes and topics on this Mac",isOn:Binding(get:{ conversation.memoryEnabled },set:{ conversation.enableMemory($0) }))
  Toggle("Include saved memory in Google Live",isOn:$conversation.shareMemoryWithGoogle).disabled(!conversation.memoryEnabled || live.running)
  Text("Memory is optional. Only the notes and topics you review here are saved; transcripts, audio and screen images are not. Allowing Google memory sharing sends those notes as cloud context when the next live session starts. Deleting local notes cannot erase cloud copies.").font(.caption).foregroundStyle(.secondary)
  Text(conversation.status).font(.caption).foregroundStyle(.secondary)
  HStack { TextField("A note you want the companion to remember",text:$conversation.noteDraft); Button("Add note") { conversation.remember() }.disabled(conversation.noteDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty) }
  ForEach(conversation.notes) { note in HStack { Text(note.text).textSelection(.enabled); Spacer(); Button("Remove",role:.destructive) { conversation.removeNote(note.id) } }.padding(10).background(.quaternary,in:RoundedRectangle(cornerRadius:10)) }
  Divider()
  Text("Things we could explore").font(.headline)
  TextField("Topic or project",text:$conversation.proposalTitle)
  TextField("Why explore it?",text:$conversation.proposalPurpose)
  HStack { Picker("Kind",selection:$conversation.proposalKind) { ForEach(["Research","Video","Project","Question"],id:\.self) { Text($0) } }; Button("Add proposal") { conversation.queueProposal() } }
  ForEach(conversation.proposals) { proposal in
   GroupBox { VStack(alignment:.leading,spacing:8) { HStack { Text(proposal.title).font(.headline); Spacer(); Text(proposal.kind).font(.caption) }; Text(proposal.purpose).font(.callout); Text(proposal.decision).font(.caption).foregroundStyle(.secondary); if proposal.decision == "Waiting for you" { HStack { Button("Plan it") { conversation.decide(proposal.id,accepted:true) }; Button("Decline") { conversation.decide(proposal.id,accepted:false) } } } } }
  }
  Button("Delete all saved memory and topics",role:.destructive) { conversation.deleteConfirmation = true }.disabled(conversation.notes.isEmpty && conversation.proposals.isEmpty && !FileManager.default.fileExists(atPath:conversation.fileURL.path))
 }
 @ViewBuilder var googleSettings: some View {
  if live.hasKey { HStack { Text("Google key saved on this Mac"); Button("Remove key") { live.forgetKey() }.disabled(DesignPreview.enabled) } }
  else { HStack { SecureField("Google API key",text:$live.keyInput); Button("Save key") { live.saveKey() }.disabled(DesignPreview.enabled); Button("Get a key") { NSWorkspace.shared.open(URL(string:"https://aistudio.google.com/apikey")!) }.disabled(DesignPreview.enabled) } }
  Picker("Friday's job",selection:$live.role) { Text("Game buddy").tag(0); Text("Stream manager").tag(1) }.pickerStyle(.segmented).disabled(live.running)
  Picker("Live voice",selection:$live.voice) { ForEach(live.voices,id:\.self) { Text(live.voiceLabel($0)).tag($0) } }.disabled(live.running)
  Toggle("Pop up in a corner when the window is out of sight while Friday is live",isOn:$corner.enabled)
  Picker("Corner",selection:$corner.position) { Text("Top right").tag(0); Text("Top left").tag(1); Text("Bottom right").tag(2); Text("Bottom left").tag(3) }.pickerStyle(.segmented).disabled(!corner.enabled)
  TextField("Live model",text:$live.liveModel).disabled(live.running)
  Toggle("Look up game facts using the wiki",isOn:$live.wiki).disabled(live.running)
  Toggle("Use Google Search for game facts",isOn:$live.search).disabled(live.running)
  Picker("Screen usage",selection:$live.lowUsage) { Text("Low").tag(true); Text("Steady").tag(false) }.pickerStyle(.segmented)
  if live.lowUsage {
   Text("Low checks the screen mostly while you talk, with occasional quiet glances. Microphone audio still uses cloud allowance.").font(.caption).foregroundStyle(.secondary)
  } else {
   HStack { Text("Picture every"); Slider(value:$live.frameGap,in:1...5,step:1); Text("\(Int(live.frameGap)) s").monospacedDigit() }
   Text("Steady sends a picture on a timer, whether you talk or not. Shorter gaps use the free allowance faster. Google allows at most one picture per second.").font(.caption).foregroundStyle(.secondary)
  }
  Toggle("Let Friday scroll and point in the window she's watching",isOn:$hands.enabled)
  if hands.enabled && !hands.hasAccess { HStack { Text("Pointing works. For scrolling, macOS must allow this app (Privacy & Security, Accessibility).").font(.caption).foregroundStyle(.secondary); Button("Open Settings") { hands.openSettings() } } }
  Text("She gets her own cursor and can scroll the page. She can't click, type or press keys. Off every time the app opens, only works while she's live, and she leaves the page alone if you move the mouse.").font(.caption).foregroundStyle(.secondary)
  Picker("Sound output",selection:$live.output) { Text("Auto").tag(0); Text("Headphones").tag(1); Text("Speakers").tag(2) }.pickerStyle(.segmented)
  Text("On speakers the mic pauses while Friday talks, so she can't hear herself (you can't interrupt her then). On headphones the mic stays open so you can. Auto picks by what your Mac is playing through; if she still hears herself, choose Speakers.").font(.caption).foregroundStyle(.secondary)
  clipSettings
 }
 // Twitch clips: a separate Twitch account makes clips of the stream when asked (see Clips.swift and the README).
 @ViewBuilder var clipSettings: some View {
  Divider()
  Text("Twitch clips").font(.headline)
  HStack { Text("Your channel"); TextField("twitch.tv/…  (just the name)",text:$clips.channel) }
  if clips.signedIn {
   HStack {
    Button("Clip it now") { Task { await clips.clipNow() } }.disabled(clips.busy)
    Button("Sign out of Twitch") { clips.signOut() }
   }
   Toggle("Let the buddy clip when I say \"clip it\" (set before starting it)",isOn:$clips.voiceClips).disabled(live.running)
   Toggle("Let the buddy run my Stream page by voice: viewers, title, category, markers (set before starting it)",isOn:$clips.voiceStream).disabled(live.running)
   Toggle("Clean up each clip: download it and cut the highlight",isOn:$clips.autoEdit)
   Picker("Highlight length",selection:$clips.highlightSeconds) { Text("15 s").tag(15); Text("25 s").tag(25); Text("40 s").tag(40) }.pickerStyle(.segmented).disabled(!clips.autoEdit)
   Button("Open the clips folder") {
    try? FileManager.default.createDirectory(at:TwitchClips.clipsRoot,withIntermediateDirectories:true)
    NSWorkspace.shared.open(TwitchClips.clipsRoot)
   }
  } else {
   Text("One time: make a free Twitch account for clips, register this app at dev.twitch.tv/console (type: Public), and paste its Client ID here. The Client ID isn't a secret. See the README.").font(.caption).foregroundStyle(.secondary)
   HStack { TextField("Client ID",text:$clips.clientID); Button("Sign in") { clips.signIn() } }
   if !clips.userCode.isEmpty { Text("Code: \(clips.userCode)").font(.title3.monospaced()) }
  }
  if !clips.status.isEmpty { Text(clips.status).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
  if !clips.editStatus.isEmpty { Text(clips.editStatus).font(.callout).foregroundStyle(.secondary).textSelection(.enabled) }
 }
 @ViewBuilder var localSettings: some View {
  Toggle("Hands-free conversation",isOn:$c.handsFree).disabled(!c.voiceReady || DesignPreview.enabled)
  Toggle("Automatic game comments",isOn:$c.automatic).disabled(DesignPreview.enabled)
  Picker("Resources",selection:$c.conserve) { Text("Save memory").tag(true); Text("Fast · keeps AI loaded").tag(false) }.pickerStyle(.segmented).disabled(DesignPreview.enabled)
  Text("Fast mode loads the AI immediately and can slow this Mac. Save memory is the default.").font(.caption).foregroundStyle(.secondary)
  Picker("Replies",selection:$c.detailed) { Text("Short").tag(false); Text("Detailed").tag(true) }.pickerStyle(.segmented)
  HStack { Picker("Voice",selection:$c.selectedVoice) { ForEach(c.voices,id:\.identifier) { Text("\($0.name) · \($0.qualityName)").tag($0.identifier) } }; Button("Preview") { c.previewVoice() }.disabled(c.busy || DesignPreview.enabled) }
  HStack { Text("Voice speed"); Slider(value:$c.speechRate,in:0.35...0.6) }
  HStack { Text("Pause to send"); Slider(value:$c.pauseSeconds,in:0.5...1.5,step:0.1) }
  TextField("Local model",text:$c.model)
  Button("Free AI memory") { c.cancelResponse(); c.unloadModel() }.disabled(DesignPreview.enabled)
 }
}

// A preview identity must never instantiate the production engines or Keychain-backed model.
enum DesignPreview { static var enabled:Bool { Bundle.main.bundleIdentifier == "local.mattyb.gamecompanion.designpreview" } }
struct ContentView: View {
 @ViewBuilder var body:some View {
  if DesignPreview.enabled {
   Text("Review source build · engines disabled. Use the separate layout preview for visual review.").padding(24)
  } else {
   CompanionInterfaceView()
  }
 }
}
