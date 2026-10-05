import Cocoa
import SwiftUI
import AVFoundation
import Combine

struct CompanionInterfaceView: View {
 @StateObject var c = Companion()
 @StateObject var live = LiveBuddy()
 @StateObject var conversation = ConversationStore(fileURL:DesignPreview.enabled ? URL(fileURLWithPath:NSTemporaryDirectory()).appendingPathComponent("GameCompanion-DesignPreviewMemory.json") : nil,load: !DesignPreview.enabled)
 private let heartbeat = Timer.publish(every:60,on:.main,in:.common).autoconnect()
 var body: some View {
  VStack(alignment:.leading,spacing:18) {
   HStack(spacing:12) {
    Image(systemName:"sparkles.rectangle.stack.fill").font(.system(size:28)).foregroundStyle(.cyan)
    VStack(alignment:.leading,spacing:3) { Text("Game Companion").font(.title2.bold()); Text(DesignPreview.enabled ? "Review draft · connections disabled" : "Play. Think. Explore together.").font(.caption).foregroundStyle(.secondary) }
    Spacer()
    Label(live.running ? "Live" : c.busy ? "Thinking" : "Ready",systemImage:live.running ? "circle.fill" : "circle").font(.caption).foregroundStyle(live.running ? .green : .secondary)
    Button("Stop all",systemImage:"stop.fill") { stopAll() }.buttonStyle(.borderedProminent).tint(.red)
   }
   Picker("View",selection:$conversation.page) { Text("Game").tag(0); Text("Conversation").tag(1); Text("Memory & topics").tag(2) }.pickerStyle(.segmented)
   ScrollView {
    VStack(alignment:.leading,spacing:16) {
     if conversation.page == 0 { gamePage }
     else if conversation.page == 1 { conversationPage }
     else { memoryPage }
    }.frame(maxWidth:.infinity,alignment:.leading)
   }
   HStack { Image(systemName:"lock.shield"); Text(conversation.memoryEnabled ? "Reviewed notes saved locally · chats and images not saved" : "Memory off · chats and images not saved by this app"); Spacer() }.font(.caption).foregroundStyle(.secondary)
  }.padding(22).frame(width:740,height:700)
  .onAppear { c.conversation = conversation; live.conversation = conversation }
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
  .alert("Delete saved memory and topics?",isPresented:$conversation.deleteConfirmation) {
   Button("Cancel",role:.cancel) {}
   Button("Delete",role:.destructive) { stopAll(); conversation.deleteAll() }
  } message: { Text("This removes the reviewed notes and topic queue from this Mac. Copies already sent to Google cannot be recalled by this app.") }
 }
 func stopAll() { conversation.stopInitiative(); live.clearSession(); c.stop() }
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
   HStack { Button(live.running ? "Stop live session" : "Start live session",systemImage:live.running ? "stop.circle" : "play.circle") { if live.running { live.stop() } else { c.stopMic(); c.cancelResponse(); live.start(filter:c.filter,notes:conversation.page == 0 ? c.gameNotes : "") } }.buttonStyle(.borderedProminent).disabled(DesignPreview.enabled || !live.hasKey || !c.sharing); Text(live.hasKey ? "Google key saved in Keychain" : "Add your key in Settings").font(.caption).foregroundStyle(.secondary) }
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
  HStack { TextField("What would you like to talk about?",text:c.tab == 0 ? $live.typed : $c.input).onSubmit { sendMessage() }; Button("Send",systemImage:"arrow.up.circle.fill") { sendMessage() }.disabled(DesignPreview.enabled || c.busy || (c.tab == 0 && !live.running)) }
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
  if live.hasKey { HStack { Text("Google key saved in Keychain"); Button("Remove key") { live.forgetKey() }.disabled(DesignPreview.enabled) } }
  else { HStack { SecureField("Google API key",text:$live.keyInput); Button("Save key") { live.saveKey() }.disabled(DesignPreview.enabled); Button("Get a key") { NSWorkspace.shared.open(URL(string:"https://aistudio.google.com/apikey")!) }.disabled(DesignPreview.enabled) } }
  Picker("Live voice",selection:$live.voice) { ForEach(live.voices,id:\.self) { Text($0) } }.disabled(live.running)
  TextField("Live model",text:$live.liveModel).disabled(live.running)
  Toggle("Look up game facts using the wiki",isOn:$live.wiki).disabled(live.running)
  Toggle("Use Google Search for game facts",isOn:$live.search).disabled(live.running)
  Picker("Screen usage",selection:$live.lowUsage) { Text("Low").tag(true); Text("Frequent").tag(false) }.pickerStyle(.segmented)
  Text("Low usage checks the screen mostly while you talk, with occasional quiet glances. Microphone audio still uses cloud allowance.").font(.caption).foregroundStyle(.secondary)
  Toggle("I'm wearing headphones",isOn:$live.headphones)
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
