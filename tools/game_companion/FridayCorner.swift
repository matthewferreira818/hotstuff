import SwiftUI
import Cocoa
import Combine

// A small Siri-style popup in a corner of the screen while Friday is live and watching. It floats above other windows (a full-screen game
// included) and shows her orb in our colours with a line of what she is hearing or saying. It appears whenever the app's window is out of
// sight (minimized, hidden, or another app such as your game is in front) and tucks away when you come back to the window. Clicking it
// brings the app forward; drag it to move it.
// It only shows what the live session already knows. It starts nothing, records nothing and sends nothing.
@MainActor final class FridayCornerController: ObservableObject {
 static let width: CGFloat = 340
 static let height: CGFloat = 150

 @Published var enabled = UserDefaults.standard.object(forKey:"corner.enabled") as? Bool ?? true {
  didSet { UserDefaults.standard.set(enabled,forKey:"corner.enabled"); refresh() }
 }
 // 0 top right (like Siri), 1 top left, 2 bottom right, 3 bottom left.
 @Published var position = UserDefaults.standard.integer(forKey:"corner.position") {
  didSet { UserDefaults.standard.set(position,forKey:"corner.position"); place() }
 }
 // Drives the pop-in and tuck-away animation.
 @Published var shown = false
 // Set by the small close button; lasts until Friday is started again.
 @Published var dismissed = false

 private var panel: NSPanel?
 private var live: LiveBuddy?
 private var watchers: [AnyCancellable] = []
 private var hideTask: Task<Void,Never>?

 func attach(_ buddy: LiveBuddy) {
  guard live == nil else { return }
  live = buddy
  watchers.append(buddy.$running.removeDuplicates().sink { [weak self] running in
   Task { @MainActor in
    if running { self?.dismissed = false }
    self?.refresh()
   }
  })
  let names: [Notification.Name] = [NSApplication.didBecomeActiveNotification,NSApplication.didResignActiveNotification,NSApplication.didHideNotification,NSApplication.didUnhideNotification,NSWindow.didMiniaturizeNotification,NSWindow.didDeminiaturizeNotification,NSWindow.didBecomeMainNotification]
  for name in names {
   watchers.append(NotificationCenter.default.publisher(for:name).sink { [weak self] _ in
    Task { @MainActor in self?.refresh() }
   })
  }
 }

 // True when you can see the app's own window: the app is in front, not hidden, and the window is not minimized.
 // (The popup itself is a panel and doesn't count.)
 private var windowInSight: Bool {
  NSApp.isActive && !NSApp.isHidden && NSApp.windows.contains { !($0 is NSPanel) && $0.isVisible && !$0.isMiniaturized }
 }

 func refresh() {
  let watching = live?.running ?? false
  if enabled && watching && !dismissed && !windowInSight { show() } else { hide() }
 }

 func dismiss() { dismissed = true; refresh() }

 func openMain() {
  NSApp.activate()
  for window in NSApp.windows where !(window is NSPanel) { window.makeKeyAndOrderFront(nil) }
 }

 private func show() {
  hideTask?.cancel()
  guard let live = live else { return }
  if panel == nil {
   let made = NSPanel(contentRect:NSRect(x:0,y:0,width:FridayCornerController.width,height:FridayCornerController.height),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
   made.isFloatingPanel = true
   made.level = .statusBar
   made.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary]
   made.isOpaque = false
   made.backgroundColor = .clear
   made.hasShadow = false
   made.hidesOnDeactivate = false
   made.isMovableByWindowBackground = true
   made.contentView = NSHostingView(rootView:FridayCornerView(controller:self,live:live))
   panel = made
  }
  place()
  panel?.orderFrontRegardless()
  withAnimation(.spring(response:0.5,dampingFraction:0.78)) { shown = true }
 }

 private func hide() {
  withAnimation(.easeIn(duration:0.25)) { shown = false }
  hideTask?.cancel()
  hideTask = Task { [weak self] in
   try? await Task.sleep(nanoseconds:350_000_000)
   guard !Task.isCancelled else { return }
   self?.panel?.orderOut(nil)
  }
 }

 func place() {
  guard let panel = panel, let screen = NSScreen.main else { return }
  let area = screen.visibleFrame
  let margin: CGFloat = 14
  let left = position == 1 || position == 3
  let bottom = position == 2 || position == 3
  let x = left ? area.minX + margin : area.maxX - FridayCornerController.width - margin
  let y = bottom ? area.minY + margin : area.maxY - FridayCornerController.height - margin
  panel.setFrame(NSRect(x:x,y:y,width:FridayCornerController.width,height:FridayCornerController.height),display:true)
 }
}

struct FridayCornerView: View {
 @ObservedObject var controller: FridayCornerController
 @ObservedObject var live: LiveBuddy

 private var onRight: Bool { controller.position == 0 || controller.position == 2 }
 private var onTop: Bool { controller.position == 0 || controller.position == 1 }
 private var alignment: Alignment {
  switch controller.position {
  case 1: return .topLeading
  case 2: return .bottomTrailing
  case 3: return .bottomLeading
  default: return .topTrailing
  }
 }

 var body: some View {
  TimelineView(.animation(minimumInterval:1.0 / 30.0)) { timeline in
   card(timeline.date)
  }
  .frame(width:FridayCornerController.width,height:FridayCornerController.height,alignment:alignment)
 }

 // Same rules as the main window's orb, for the live session.
 private func state(at now: Date) -> OrbState {
  guard live.running else { return .off }
  guard live.ready else { return .thinking }
  if now < live.speakingUntil { return .speaking }
  if live.status.hasPrefix("Looking up") { return .thinking }
  let since = now.timeIntervalSince(live.lastVoice)
  if since < 1.2 { return .listening }
  if since < 6 { return .thinking }
  return .idle
 }

 private func level(at now: Date) -> Double {
  let voice = live.voiceLevel * max(0,1 - now.timeIntervalSince(live.voiceLevelAt) * 5)
  let mic = live.micLevel * max(0,1 - now.timeIntervalSince(live.micLevelAt) * 5)
  return min(1,max(voice,mic))
 }

 private func label(_ state: OrbState) -> String {
  switch state {
  case .off: return "ASLEEP"
  case .idle: return "WATCHING"
  case .listening: return "LISTENING"
  case .thinking: return "THINKING"
  case .speaking: return "SPEAKING"
  }
 }

 // The newest words, so a long reply shows its latest part.
 private func tail(_ text: String) -> String {
  let clean = text.trimmingCharacters(in:.whitespacesAndNewlines)
  return clean.count > 80 ? "…" + String(clean.suffix(80)) : clean
 }

 private func line(_ state: OrbState) -> String {
  switch state {
  case .speaking:
   let said = tail(live.said)
   return said.isEmpty ? "…" : said
  case .listening:
   let heard = tail(live.heard)
   return heard.isEmpty ? "Go ahead, I'm listening." : heard
  case .thinking: return live.status.hasPrefix("Looking up") ? live.status : "Thinking about it…"
  case .idle: return "Watching your game. Just talk to me."
  case .off: return ""
  }
 }

 private func card(_ now: Date) -> some View {
  let current = state(at:now)
  let sound = level(at:now)
  let spin = now.timeIntervalSinceReferenceDate * 10
  return HStack(spacing:4) {
   FridayOrb(state:current,t:now.timeIntervalSinceReferenceDate,level:sound,size:44,animated:true,showsPicker:false)
    .frame(width:66,height:60)
   VStack(alignment:.leading,spacing:3) {
    Text(label(current)).font(.system(size:10.5,weight:.bold,design:.rounded)).tracking(1.2).foregroundStyle(Noir.crimsonLight)
    Text(line(current)).font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(Color.white.opacity(0.92)).lineLimit(2).multilineTextAlignment(.leading)
   }
   Spacer(minLength:0)
   Button { controller.dismiss() } label: {
    Image(systemName:"xmark").font(.system(size:9,weight:.bold)).foregroundStyle(Color.white.opacity(0.55))
     .frame(width:20,height:20).background(Circle().fill(Color.white.opacity(0.10)))
   }
   .buttonStyle(.plain)
   .help("Hide until Friday is started again")
  }
  .padding(.leading,6).padding(.trailing,12).padding(.vertical,8)
  .frame(width:300)
  .background(RoundedRectangle(cornerRadius:28,style:.continuous).fill(LinearGradient(colors:[Noir.crimsonDeep.opacity(0.55),Color.black.opacity(0.42)],startPoint:.topLeading,endPoint:.bottomTrailing)))
  .background(.ultraThinMaterial,in:RoundedRectangle(cornerRadius:28,style:.continuous))
  .overlay(RoundedRectangle(cornerRadius:28,style:.continuous).strokeBorder(AngularGradient(colors:[Color.white.opacity(0.45),Noir.crimsonLight.opacity(0.15),Color.white.opacity(0.05),Noir.crimsonLight.opacity(0.45),Color.white.opacity(0.45)],center:.center,angle:.degrees(spin)),lineWidth:1))
  .shadow(color:Noir.crimson.opacity(0.30 + sound * 0.30),radius:18,y:6)
  .scaleEffect(controller.shown ? 1 : 0.6,anchor:UnitPoint(x:onRight ? 1 : 0,y:onTop ? 0 : 1))
  .opacity(controller.shown ? 1 : 0)
  .offset(y:controller.shown ? 0 : (onTop ? -14 : 14))
  .contentShape(Rectangle())
  .onTapGesture { controller.openMain() }
 }
}
