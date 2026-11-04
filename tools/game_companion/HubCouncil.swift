import SwiftUI

// Project Trinity, Phase 1A (2026-11-04): the Council page, where Roxy, Claude and Grok take turns on Matthew's question and he
// can interrupt or Stop at any time. Matthew chose Phase 1A only: NO real AI is connected yet, every reply comes from
// CouncilTestProvider (Roxy's CouncilData.swift) and says "[test reply]" on screen. Real models wait for client #1's first invoice
// (money mode). Nothing here touches the network, keys, the public Meeting Room thread, or posts anything. The transcript lives
// only in memory and is gone when the app quits. Spec: meeting-room/notes/live-ai-council-phase-1.md (branch gpt/live-council-spec).

@MainActor final class CouncilModel: ObservableObject {
 @Published private(set) var session = CouncilSession()
 @Published var draft = ""
 private var task: Task<Void,Never>? = nil

 var running: Bool { session.state == .running }

 func send() {
  let words = draft
  if session.state == .idle {
   guard session.start(words) else { return }
  } else if running {
   task?.cancel()
   guard session.interrupt(with:words) else { return }
  } else {
   session = CouncilSession()
   guard session.start(words) else { return }
  }
  draft = ""
  run()
 }

 func stop() {
  task?.cancel()
  task = nil
  session.stop()
 }

 func reset() {
  stop()
  session = CouncilSession()
 }

 // One turn at a time: ask the session for permission, stream the test reply in small chunks, finish, repeat.
 private func run() {
  task?.cancel()
  task = Task { [weak self] in
   while let self = self, !Task.isCancelled, let request = self.session.next() {
    let reply = CouncilTestProvider.reply(to:request)
    var accepted = true
    for chunk in Self.chunks(reply) {
     try? await Task.sleep(nanoseconds:45_000_000)
     if Task.isCancelled { return }
     accepted = self.session.append(chunk,for:request)
     if !accepted { break }
    }
    if Task.isCancelled { return }
    self.session.finish(request)
    try? await Task.sleep(nanoseconds:350_000_000)
   }
  }
 }

 private static func chunks(_ text: String) -> [String] {
  var out: [String] = []
  var current = ""
  for word in text.split(separator:" ",omittingEmptySubsequences:false) {
   current += (current.isEmpty ? "" : " ") + word
   if current.count >= 12 { out.append(current + " "); current = "" }
  }
  if !current.isEmpty { out.append(current) }
  return out
 }
}

enum CouncilLook {
 static func tint(_ speaker: CouncilSpeaker) -> Color {
  switch speaker {
  case .matthew: return HubTheme.text
  case .roxy: return HubTheme.orbRoxy
  case .claude: return HubTheme.orbClaude
  case .grok: return HubTheme.green
  }
 }
 static func icon(_ speaker: CouncilSpeaker) -> String {
  switch speaker {
  case .matthew: return "person.fill"
  case .roxy: return "sparkles"
  case .claude: return "asterisk"
  case .grok: return "bolt.fill"
  }
 }
 static func role(_ speaker: CouncilSpeaker) -> String {
  switch speaker {
  case .matthew: return "You"
  case .roxy: return "Roxy · proposes"
  case .claude: return "Claude · pressure-tests"
  case .grok: return "Grok · research and alternatives"
  }
 }
}

struct CouncilPage: View {
 @StateObject private var model = CouncilModel()

 var body: some View {
  VStack(alignment:.leading,spacing:14) {
   header
   banner
   ScrollViewReader { proxy in
    ScrollView {
     VStack(alignment:.leading,spacing:12) {
      if model.session.turns.isEmpty { emptyState }
      ForEach(model.session.turns) { turn in bubble(turn).id(turn.id) }
      if let error = model.session.lastError {
       Label(error,systemImage:"exclamationmark.triangle.fill").font(.system(size:12.5)).foregroundStyle(HubTheme.crimson)
      }
      statusLine.id("bottom")
     }
     .padding(.vertical,4)
    }
    .onChange(of:model.session.turns.last?.text ?? "") { _ in proxy.scrollTo("bottom",anchor:.bottom) }
   }
   composer
  }
  .padding(HubTheme.pagePadding)
  .background(HubTheme.background)
 }

 private var header: some View {
  HStack(spacing:10) {
   Image(systemName:"person.3.sequence.fill").font(.system(size:20,weight:.semibold)).foregroundStyle(HubTheme.orbClaude)
   Text("Council").font(.system(size:HubTheme.titleSize,weight:.bold)).foregroundStyle(HubTheme.text)
   Spacer()
   ForEach([CouncilSpeaker.roxy,.claude,.grok],id:\.self) { s in
    Label(s.rawValue,systemImage:CouncilLook.icon(s))
     .font(.system(size:12,weight:.semibold)).foregroundStyle(CouncilLook.tint(s))
     .padding(.horizontal,10).padding(.vertical,6)
     .background(Capsule().fill(CouncilLook.tint(s).opacity(0.12)))
   }
  }
 }

 // Honest status, always visible: nobody may mistake a test reply for a real model.
 private var banner: some View {
  Label("Test mode: no AI is connected yet. Every reply below is a scripted test, marked [test reply]. Real Roxy, Claude and Grok switch on after client #1's first invoice.",systemImage:"testtube.2")
   .font(.system(size:12.5,weight:.medium)).foregroundStyle(HubTheme.amber)
   .padding(12).frame(maxWidth:.infinity,alignment:.leading)
   .background(RoundedRectangle(cornerRadius:12,style:.continuous).fill(HubTheme.amber.opacity(0.10)))
   .overlay(RoundedRectangle(cornerRadius:12,style:.continuous).stroke(HubTheme.amber.opacity(0.35),lineWidth:1))
 }

 private var emptyState: some View {
  VStack(alignment:.leading,spacing:6) {
   Text("Ask the council something.").font(.system(size:HubTheme.headingSize,weight:.semibold)).foregroundStyle(HubTheme.text)
   Text("They take turns: Roxy proposes, Claude pressure-tests, Grok brings research and alternatives, twice around (6 replies at most). Type while they talk to jump in; Stop ends it for good.")
    .font(.system(size:HubTheme.bodySize)).foregroundStyle(HubTheme.subtext).fixedSize(horizontal:false,vertical:true)
  }
  .padding(HubTheme.cardPadding).frame(maxWidth:.infinity,alignment:.leading)
  .background(RoundedRectangle(cornerRadius:HubTheme.cardRadius,style:.continuous).fill(HubTheme.card))
 }

 private func bubble(_ turn: CouncilTurn) -> some View {
  let tint = CouncilLook.tint(turn.speaker)
  let mine = turn.speaker == .matthew
  return VStack(alignment:.leading,spacing:6) {
   HStack(spacing:6) {
    Image(systemName:CouncilLook.icon(turn.speaker)).foregroundStyle(tint)
    Text(CouncilLook.role(turn.speaker)).font(.system(size:12,weight:.semibold)).foregroundStyle(tint)
    Spacer()
    switch turn.state {
    case .streaming: ProgressView().controlSize(.small)
    case .stopped: Text("stopped").font(.system(size:11)).foregroundStyle(HubTheme.subtext)
    case .failed: Text("failed").font(.system(size:11)).foregroundStyle(HubTheme.crimson)
    case .complete: EmptyView()
    }
   }
   Text(turn.text.isEmpty ? "…" : turn.text)
    .font(.system(size:HubTheme.bodySize)).foregroundStyle(HubTheme.text)
    .textSelection(.enabled).fixedSize(horizontal:false,vertical:true)
  }
  .padding(14).frame(maxWidth:.infinity,alignment:.leading)
  .background(RoundedRectangle(cornerRadius:14,style:.continuous).fill(mine ? HubTheme.card : tint.opacity(0.08)))
  .overlay(RoundedRectangle(cornerRadius:14,style:.continuous).stroke(tint.opacity(mine ? 0.15 : 0.30),lineWidth:1))
 }

 private var statusLine: some View {
  let s = model.session
  let word: String
  switch s.state {
  case .idle: word = "Ready"
  case .running: word = "In session"
  case .complete: word = "Round finished"
  case .stopped: word = "Stopped"
  }
  return Text("\(word) · \(s.agentTurnsUsed) of \(s.limits.maxAgentTurns) replies used")
   .font(.system(size:11.5)).foregroundStyle(HubTheme.subtext)
 }

 private var composer: some View {
  HStack(spacing:10) {
   TextField(model.running ? "Jump in…" : "Your question for the council",text:$model.draft)
    .textFieldStyle(.plain).font(.system(size:HubTheme.bodySize)).foregroundStyle(HubTheme.text)
    .padding(.horizontal,14).frame(minHeight:HubTheme.minTarget)
    .background(RoundedRectangle(cornerRadius:12,style:.continuous).fill(HubTheme.control))
    .overlay(RoundedRectangle(cornerRadius:12,style:.continuous).stroke(HubTheme.controlOutline,lineWidth:1))
    .onSubmit { model.send() }
   Button { model.send() } label: { Label(model.running ? "Jump in" : "Start",systemImage:"arrow.up.circle.fill") }
    .buttonStyle(GuardButtonStyle(tint:HubTheme.orbClaude.opacity(0.85)))
    .disabled(model.draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || (model.running && !model.session.canInterrupt))
   Button { model.stop() } label: { Label("Stop",systemImage:"stop.fill") }
    .buttonStyle(GuardButtonStyle(tint:HubTheme.crimson.opacity(0.85)))
    .disabled(!model.running)
    .keyboardShortcut(".",modifiers:.command)
   Button { model.reset() } label: { Image(systemName:"arrow.counterclockwise") }
    .buttonStyle(GuardButtonStyle(tint:Color.white.opacity(0.10)))
    .help("Clear and start over")
  }
 }
}

extension CompanionInterfaceView {
 var hubCouncil: some View { CouncilPage() }
}
