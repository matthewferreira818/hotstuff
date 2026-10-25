import SwiftUI
import AppKit

// Friday's Helper: "another set of hands" (Matthew, 2026-10-14). He types or says a job; she looks at the controls in the window as a numbered
// text list, asks a brain what ONE next step is (a model on his own Mac through Ollama, or Google's free tier), does that step with the same
// hands as the live Friday (FridayHands: same switches, same off-limits list, same Allow box), looks again, and repeats until it is done,
// she has a question, or she hits 15 steps. The rules and shapes (what an answer may look like, what she may tell C.C, what she may type in a
// posting job) are in HelperData.swift and are tested. Nothing here loosens the live Friday's rules: logins, passwords and payments stay
// off-limits; anything that could send or buy needs his Allow.
// Free for now (Matthew, 2026-10-14: "use the best I can for free until I get some revenue"): the local model costs nothing and sends
// nothing anywhere; the Google option is the free tier with his own key.

@MainActor final class FridayHelper: ObservableObject {
 @Published var goal = ""
 @Published var running = false
 @Published var status = "Tell me a job and press Start."
 @Published var question = ""
 @Published var log: [String] = []
 @Published var brain: HelperBrain = HelperBrain(rawValue:UserDefaults.standard.string(forKey:"helper.brain") ?? "") ?? .local {
  didSet { UserDefaults.standard.set(brain.rawValue,forKey:"helper.brain") }
 }
 @Published var model = UserDefaults.standard.string(forKey:"helper.model") ?? "gemma3:4b" {
  didSet { UserDefaults.standard.set(model,forKey:"helper.model") }
 }
 @Published var teaching = false
 @Published var boxTaught = false
 private var hands: FridayHands?
 private var voice: VoiceOver?
 private var job: Task<Void,Never>?
 private var teachJob: Task<Void,Never>?
 private let session = URLSession(configuration:.ephemeral)

 func attach(hands h: FridayHands,voice v: VoiceOver) {
  hands = h
  voice = v
  boxTaught = h.taughtBox != nil
 }

 private func add(_ line: String) {
  log.append(line)
  if log.count > 60 { log.removeFirst(log.count - 60) }
 }

 // MARK: starting and stopping

 func start() {
  let words = goal.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !running else { return }
  guard !words.isEmpty else { status = "Tell me what you'd like done first."; return }
  guard let hands = hands else { return }
  guard hands.enabled else { status = "Her hands are switched off. Turn on \"Let Friday use her hands\" in Settings first."; return }
  question = ""
  log = []
  running = true
  status = "Starting…"
  job = Task { await run(goal:words) }
 }

 func stop() {
  job?.cancel()
  if running { status = "Stopping after this step…" }
 }

 // A standing job that already exists in the repo (like the daily posting session): she just tells C.C to do it.
 func tellCCStanding(_ key: String) {
  guard !running, let hands = hands, let text = HelperPlan.standing(key) else { return }
  guard hands.enabled else { status = "Her hands are switched off. Turn on \"Let Friday use her hands\" in Settings first."; return }
  question = ""
  running = true
  hands.helperRunning = true
  status = "Telling C.C…"
  job = Task {
   let result = await tellCC(text)
   status = result
   add("Told C.C: \(result)")
   hands.helperRunning = false
   running = false
   job = nil
  }
 }

 // Matthew shows her C.C's message box once: the real mouse on it, a few seconds' notice.
 func teachBox() {
  guard let hands = hands, !teaching, !running else { return }
  teaching = true
  teachJob = Task {
   for second in stride(from:6,through:1,by:-1) {
    status = "Put the mouse on C.C's message box in Chrome. Looking in \(second)…"
    try? await Task.sleep(nanoseconds:1_000_000_000)
   }
   let result = hands.teachBoxUnderMouse()
   status = result
   add(result)
   boxTaught = hands.taughtBox != nil
   teaching = false
  }
 }

 func forgetBox() {
  hands?.forgetTaughtBox()
  boxTaught = false
  status = "I forgot where C.C's box is."
 }

 // MARK: the loop

 private func run(goal: String) async {
  guard let hands = hands else { status = "My hands aren't connected."; running = false; return }
  hands.helperRunning = true
  defer { hands.helperRunning = false; running = false; job = nil }
  var history: [String] = []
  for number in 1...HelperPlan.maxSteps {
   if Task.isCancelled { status = "Stopped."; return }
   let look = hands.helperLook()
   if let problem = look.problem { status = problem; add(problem); return }
   let shown = HelperPlan.view(look.items.map { $0.element })
   let prompt = HelperPlan.stepPrompt(goal:goal,app:look.app,windowTitle:look.title,controls:shown.text,history:history)
   status = "Step \(number): thinking…"
   guard let step = await nextStep(prompt) else { return }
   if !step.say.isEmpty { add("Friday: \(step.say)") }
   status = "Step \(number): \(step.say.isEmpty ? "working" : step.say)"
   let outcome = await perform(step,look:look,shown:shown,goal:goal)
   add(outcome.summary)
   history.append(outcome.summary)
   if outcome.finished { return }
   if HelperPlan.isLooping(history) { status = "I'm repeating myself, so I stopped. Tell me what's going wrong."; add(status); return }
   if Task.isCancelled { status = "Stopped."; return }
   try? await Task.sleep(nanoseconds:700_000_000)
  }
  status = "That's \(HelperPlan.maxSteps) steps, so I stopped. Tell me what's next and press Start again."
  add(status)
 }

 // Asks the brain, and if the answer isn't something she can use, tells it why and asks again (twice at most).
 private func nextStep(_ prompt: String) async -> HelperStep? {
  var note = ""
  for _ in 0..<3 {
   let reply = await think(prompt + note)
   guard let text = reply.text else { status = reply.problem ?? "I got no answer from the brain."; add(status); return nil }
   switch HelperPlan.parse(text) {
   case .ok(let step): return step
   case .bad(let why): note = "\n\nYour last answer could not be used: \(why)"
   }
  }
  status = "The brain kept giving answers I couldn't use, so I stopped."
  add(status)
  return nil
 }

 private struct Outcome { var summary: String; var finished: Bool }

 private func stopWords(_ result: String) -> Bool { result.contains("didn't allow") || result.contains("not live") || result.contains("switched off") || result.contains("stopped") }

 private func activate(_ pid: Int) async {
  guard pid > 0, let app = NSRunningApplication(processIdentifier:pid_t(pid)) else { return }
  app.activate(options:[.activateIgnoringOtherApps])
  try? await Task.sleep(nanoseconds:350_000_000)
 }

 private func perform(_ step: HelperStep,look: FridayHands.HelperLook,shown: HelperView,goal: String) async -> Outcome {
  guard let hands = hands else { return Outcome(summary:"My hands aren't connected.",finished:true) }
  let action = step.action
  switch action.kind {
  case .click:
   guard let n = action.element, n >= 1, n <= shown.map.count else { return Outcome(summary:"There is no control number \(action.element ?? 0) in the list.",finished:false) }
   let item = look.items[shown.map[n - 1]]
   if item.element.secure { return Outcome(summary:"Control \(n) is a password box. That's Matthew's own, so I stopped.",finished:true) }
   await activate(look.pid)
   let label = HelperPlan.cleanLabel(item.element.label)
   let result = await hands.clickDesk(at:item.center,what:label)
   return Outcome(summary:"Clicked \"\(label.isEmpty ? "control \(n)" : label)\": \(result)",finished:stopWords(result))
  case .type:
   guard HelperPlan.typingAllowed(action.text,goal:goal) else {
    return Outcome(summary:"I won't type that: in a posting job I only type words Matthew gave me exactly.",finished:true)
   }
   await activate(look.pid)
   let result = await hands.type(action.text)
   return Outcome(summary:"Typed \(action.text.count) characters: \(result)",finished:stopWords(result))
  case .press:
   await activate(look.pid)
   let result = await hands.press(action.text)
   return Outcome(summary:"Pressed \(action.text): \(result)",finished:stopWords(result))
  case .scroll:
   await activate(look.pid)
   let result = await hands.scroll(direction:action.direction,amount:action.amount,x:nil,y:nil)
   return Outcome(summary:"Scrolled \(action.direction): \(result)",finished:stopWords(result))
  case .tellCC:
   let result = await tellCC(action.text)
   return Outcome(summary:"Told C.C: \(result)",finished:stopWords(result))
  case .ask:
   question = action.text
   status = "I need to ask you something."
   return Outcome(summary:"Asked: \(action.text)",finished:true)
  case .done:
   status = "Done: \(action.text)"
   return Outcome(summary:"Done: \(action.text)",finished:true)
  }
 }

 // MARK: telling C.C (the Chrome extension Claude)
 // Vetted first (never secrets, spending or logins), then Matthew sees the full words in the Allow box. If he has taught her where C.C's
 // box is, she clicks it, pastes the words and presses Return herself; if not, the words go on the clipboard and Chrome comes forward.

 private func copyToClipboard(_ text: String) {
  let board = NSPasteboard.general
  board.clearContents()
  board.setString(text,forType:.string)
 }

 private func tellCC(_ text: String) async -> String {
  guard let hands = hands else { return "My hands aren't connected." }
  var flags: [String] = []
  switch HelperPlan.vetCC(text) {
  case .refuse(let why): return "I won't tell C.C that: \(why)."
  case .allow(let found): flags = found
  }
  let intro = flags.isEmpty ? "C.C will do this in your Chrome, from your own accounts." : flags.joined(separator:" ")
  guard await hands.approval.ask("Tell C.C to do this?",detail:intro,words:text) else { return "Matthew didn't allow it, so I didn't tell C.C." }
  guard let chrome = NSRunningApplication.runningApplications(withBundleIdentifier:"com.google.Chrome").first else {
   copyToClipboard(text)
   return "Chrome isn't open, so I put the words on the clipboard. Open C.C in Chrome and paste them."
  }
  chrome.activate(options:[.activateIgnoringOtherApps])
  try? await Task.sleep(nanoseconds:900_000_000)
  let look = hands.helperLook()
  guard look.problem == nil, let taught = hands.taughtBox, let box = hands.matchTaughtBox(taught,in:look) else {
   copyToClipboard(text)
   return "I put the words on the clipboard and brought Chrome forward. Click C.C's box, paste (Cmd+V) and press Return. (Press \"Teach C.C's box\" once and I'll do that part myself.)"
  }
  let clicked = await hands.clickDesk(at:box.center,what:"C.C's message box")
  if !clicked.lowercased().contains("clicked") { return clicked }
  let board = NSPasteboard.general
  let before = board.string(forType:.string)
  copyToClipboard(text)
  let pasted = await hands.press("cmd+v")
  try? await Task.sleep(nanoseconds:600_000_000)
  if let before = before { board.clearContents(); board.setString(before,forType:.string) }
  if !pasted.lowercased().contains("pressed") { return pasted }
  let sent = await hands.pressApprovedReturn()
  return sent.lowercased().contains("pressed") ? "Sent it to C.C (\(text.count) characters)." : sent
 }

 // MARK: the brains

 private func think(_ prompt: String) async -> (text: String?,problem: String?) {
  switch brain {
  case .local: return await askLocal(prompt)
  case .google:
   guard let voice = voice else { return (nil,"The Google helper isn't connected.") }
   return await voice.helperThink(HelperPlan.systemLine + "\n\n" + prompt)
  }
 }

 private func askLocal(_ prompt: String) async -> (text: String?,problem: String?) {
  guard let body = HelperPlan.ollamaBody(model:model,user:prompt) else { return (nil,"Couldn't put the question together.") }
  var request = URLRequest(url:URL(string:"http://127.0.0.1:11434/api/chat")!,timeoutInterval:150)
  request.httpMethod = "POST"
  request.setValue("application/json",forHTTPHeaderField:"Content-Type")
  request.httpBody = body
  do {
   let (data,response) = try await session.data(for:request)
   guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (nil,"Ollama didn't answer. Is it running, and is the model \"\(model)\" installed?") }
   let json = (try? JSONSerialization.jsonObject(with:data)) as? [String:Any] ?? [:]
   guard let text = HelperPlan.ollamaReply(json) else { return (nil,"The local model sent back no words.") }
   return (text,nil)
  } catch {
   return (nil,"Couldn't reach Ollama on this Mac (\(error.localizedDescription)). Is it running?")
  }
 }
}

// MARK: the Helper page

extension CompanionInterfaceView {
 var hubHelper: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:18) {
    VStack(alignment:.leading,spacing:12) {
     HStack(spacing:10) {
      Text("Helper: another set of hands").font(.system(size:17,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
      hubPill(hands.enabled ? "HANDS ON" : "HANDS OFF",tint:hands.enabled ? HubColor.green : HubColor.slate)
      if helper.running { ProgressView().controlSize(.small) }
      Spacer()
     }
     Text("Tell Friday a job in plain words. She looks at the window's buttons and boxes, picks one small step at a time, and does it with her hands. She asks you before anything that sends or buys, never touches logins, passwords or payments, and stops after 15 steps.").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.65))
     if !hands.enabled {
      Toggle("Let Friday use her hands: scroll, point, click and type",isOn:$hands.enabled).toggleStyle(.switch).font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.8))
     }
     Picker("Brain",selection:$helper.brain) {
      Text("On this Mac (free, private)").tag(HelperBrain.local)
      Text("Google free tier (smarter)").tag(HelperBrain.google)
     }.pickerStyle(.segmented).disabled(helper.running)
     if helper.brain == .local {
      HStack(spacing:10) {
       Text("Model").font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.6))
       TextField("gemma3:4b",text:$helper.model).noirField().frame(maxWidth:260).disabled(helper.running)
       Text("(installed with Ollama)").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
      }
     }
     Text(HelperPlan.privacy(helper.brain)).font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.5))
     if helper.brain == .local {
      Text("On an 8 GB Mac the local model uses about 3 GB while she works and lets go a minute and a half after the last step. While you're gaming or streaming, the Google option is kinder to your memory.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
     }
     TextField("What should I do? For a post, give me the exact words in quotes.",text:$helper.goal,axis:.vertical).lineLimit(2...5).noirField().disabled(helper.running)
     HStack(spacing:8) {
      ForEach(Array(HelperPlan.starters.enumerated()),id:\.offset) { entry in
       Button { helper.goal = entry.element.goal } label: { Text(entry.element.title).font(.system(size:11.5,weight:.medium,design:.rounded)) }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.10))).disabled(helper.running).help(entry.element.goal)
      }
     }
     HStack(spacing:10) {
      Button { helper.start() } label: { Label("Start",systemImage:"play.fill") }.buttonStyle(PillButtonStyle()).disabled(helper.running || helper.goal.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
      if helper.running { Button { helper.stop() } label: { Label("Stop",systemImage:"stop.fill") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.14))) }
     }
     Text(helper.status).font(.system(size:12.5,weight:.semibold,design:.rounded)).foregroundStyle(Color.white.opacity(0.85)).textSelection(.enabled)
     if !helper.question.isEmpty {
      Text("Friday asks: \(helper.question)").font(.system(size:13,weight:.semibold,design:.rounded)).foregroundStyle(HubColor.amber).textSelection(.enabled)
     }
     if !helper.log.isEmpty {
      VStack(alignment:.leading,spacing:4) {
       ForEach(Array(helper.log.suffix(14).enumerated()),id:\.offset) { item in
        Text(item.element).font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.6)).textSelection(.enabled)
       }
      }
     }
    }
    .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()

    VStack(alignment:.leading,spacing:12) {
     HStack(spacing:10) {
      Text("C.C (Claude in Chrome)").font(.system(size:15,weight:.semibold,design:.rounded)).foregroundStyle(Color.white)
      hubPill(helper.boxTaught ? "BOX TAUGHT" : "BOX NOT TAUGHT",tint:helper.boxTaught ? HubColor.green : HubColor.slate)
      Spacer()
     }
     Text("Friday can give C.C a command. You always see the full words in the Allow box first. She never sends C.C a secret, a login or anything that spends money, and C.C only publishes text Claude has approved. Teach her where C.C's message box is once, and she will click it, paste and press Return herself; until then she puts the words on your clipboard and brings Chrome forward.").font(.system(size:12,design:.rounded)).foregroundStyle(Color.white.opacity(0.6))
     HStack(spacing:10) {
      ForEach(Array(HelperPlan.standingCC.enumerated()),id:\.offset) { entry in
       Button { helper.tellCCStanding(entry.element.key) } label: { Label(entry.element.title,systemImage:"paperplane") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12))).disabled(helper.running || !hands.enabled)
      }
      Button { helper.teachBox() } label: { Label(helper.teaching ? "Looking…" : "Teach C.C's box",systemImage:"scope") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12))).disabled(helper.running || helper.teaching)
      if helper.boxTaught { Button { helper.forgetBox() } label: { Label("Forget it",systemImage:"xmark") }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.12))) }
     }
    }
    .padding(18).frame(maxWidth:.infinity,alignment:.leading).hubCard()

    Text("Posting: she types only words you give her exactly, because everything public has to be true. The outreach batch isn't here on purpose: it needs your own footer, so you start that one yourself.").font(.system(size:11.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.4))
   }
   .padding(.horizontal,32).padding(.bottom,30)
  }
  .scrollIndicators(.hidden)
 }
}
