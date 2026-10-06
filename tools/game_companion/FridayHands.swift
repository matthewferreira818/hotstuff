import SwiftUI
import AppKit
import CoreGraphics
import ApplicationServices
import ScreenCaptureKit

// Friday's hands: her own on-screen cursor, scrolling, clicking, typing and pressing keys. Matthew's rules (2026-10-05):
//  - She acts when he tells her to. No box for ordinary clicks, typing and keys.
//  - Anything that could SEND or BUY needs his Allow on an on-screen box first (and she is told to ask him out loud too): pressing
//    Return or Enter, a button or label that says Send, Pay, Order, Post and the like, anything in a checkout, cart or payment window.
//  - Never in: banking and payment pages, trading apps (Moomoo), password pages and fields, login pages, System Settings, this app, or a
//    terminal. She also refuses to type what looks like a card number, and quit, log-out and Trash shortcuts. Scrolling follows the
//    same list.
//  - The on/off switch is remembered between launches (hand button on the Friday page, or Settings), and it only works while Friday is live.
//    At most 30 actions a minute, one at a time, and nothing else runs while an Allow box is open.
//  - Scrolling yields to the real mouse: if Matthew moved it in the last 1.5 seconds she leaves the page alone.
//  - Her cursor always glides to the spot first, so he can watch what she is about to do. Everything is checked again after the glide
//    and after any wait for Allow, because the screen can change in between.
//  - A click lands on whatever window is on top at that spot, of any kind (menus, pop-ups, her own Allow box), so that is the window
//    the rules are checked against. Her own windows are never clicked.
// The word lists are a safety net that matches the app name, the window title and the button's label. They can miss a page that
// doesn't say what it is; the Allow box is the hard backstop for send and buy.
// Needs macOS's Accessibility permission for clicking, typing, keys and scrolling. Pointing needs no permission.
// Checked against Apple's docs on 2026-10-05: CGEvent (scroll, mouse, keyboard), CGPreflightPostEventAccess and CGRequestPostEventAccess
// (macOS 10.15+), AXUIElementCopyElementAtPosition, SCContentFilter.includedWindows (macOS 15.2+).

// MARK: her cursor

@MainActor final class FridayCursorModel: ObservableObject {
 // In the overlay panel's own coordinates (origin top-left).
 @Published var point = CGPoint(x:-100,y:-100)
 @Published var visible = false
 @Published var label = ""
 @Published var tilt = 0.0
 @Published var trail: [CGPoint] = []
 @Published var ringAt: Date?
 private var smoothTilt = 0.0

 private func bezier(_ a: CGPoint,_ b: CGPoint,_ c: CGPoint,_ d: CGPoint,_ t: Double) -> CGPoint {
  let u = 1 - t
  let x = u * u * u * Double(a.x) + 3 * u * u * t * Double(b.x) + 3 * u * t * t * Double(c.x) + t * t * t * Double(d.x)
  let y = u * u * u * Double(a.y) + 3 * u * u * t * Double(b.y) + 3 * u * t * t * Double(c.y) + t * t * t * Double(d.y)
  return CGPoint(x:x,y:y)
 }

 // Moves her cursor along a gentle curve with an ease in and an ease out, leaving a short fading trail, and tilting a little with
 // its speed. It follows the clock, not the frame count, so it stays smooth if a frame is late.
 func glide(from start: CGPoint,to end: CGPoint,duration: Double) async {
  let dx = Double(end.x - start.x)
  let dy = Double(end.y - start.y)
  let distance = max(1,(dx * dx + dy * dy).squareRoot())
  let side: Double = Int(abs(Double(end.x) + Double(end.y))) % 2 == 0 ? 1 : -1
  let nx = -dy / distance * side
  let ny = dx / distance * side
  let bend = min(distance * 0.20,150)
  let c1 = CGPoint(x:Double(start.x) + dx * 0.25 + nx * bend,y:Double(start.y) + dy * 0.25 + ny * bend)
  let c2 = CGPoint(x:Double(start.x) + dx * 0.75 + nx * bend * 0.55,y:Double(start.y) + dy * 0.75 + ny * bend * 0.55)
  let begin = ContinuousClock.now
  var previous = start
  while !Task.isCancelled {
   let span = begin.duration(to:.now)
   let elapsed = Double(span.components.seconds) + Double(span.components.attoseconds) / 1e18
   let raw = min(1,elapsed / max(0.05,duration))
   let eased = raw < 0.5 ? 4 * raw * raw * raw : 1 - pow(-2 * raw + 2,3) / 2
   let here = bezier(start,c1,c2,end,eased)
   let sway = max(-14,min(14,Double(here.x - previous.x) * 1.4))
   smoothTilt += (sway - smoothTilt) * 0.25
   point = here
   tilt = smoothTilt
   trail.append(here)
   if trail.count > 16 { trail.removeFirst(trail.count - 16) }
   previous = here
   if raw >= 1 { break }
   try? await Task.sleep(nanoseconds:8_000_000)
  }
  point = end
  withAnimation(.easeOut(duration:0.5)) { tilt = 0; trail = [] }
  smoothTilt = 0
 }

 func pulse() { ringAt = Date() }
}

struct FridayArrow: Shape {
 func path(in rect: CGRect) -> Path {
  var path = Path()
  let s = rect.width / 12.5
  path.move(to:CGPoint(x:0,y:0))
  path.addLine(to:CGPoint(x:0,y:17 * s))
  path.addLine(to:CGPoint(x:4.5 * s,y:13 * s))
  path.addLine(to:CGPoint(x:7.5 * s,y:20 * s))
  path.addLine(to:CGPoint(x:10 * s,y:19 * s))
  path.addLine(to:CGPoint(x:7 * s,y:12.5 * s))
  path.addLine(to:CGPoint(x:12.5 * s,y:12.5 * s))
  path.closeSubpath()
  return path
 }
}

struct FridayCursorView: View {
 @ObservedObject var model: FridayCursorModel

 var body: some View {
  TimelineView(.animation(minimumInterval:1.0 / 60.0,paused:model.ringAt == nil)) { timeline in
   ZStack(alignment:.topLeading) {
    Color.clear
    ForEach(Array(model.trail.enumerated()),id:\.offset) { index,spot in
     let fraction = Double(index + 1) / Double(max(1,model.trail.count))
     Circle().fill(Noir.crimsonLight.opacity(0.34 * fraction * fraction))
      .frame(width:3 + 9 * fraction,height:3 + 9 * fraction)
      .offset(x:spot.x - (1.5 + 4.5 * fraction),y:spot.y - (1.5 + 4.5 * fraction))
    }
    if let at = model.ringAt {
     let progress = timeline.date.timeIntervalSince(at) / 0.6
     if progress >= 0 && progress < 1 {
      Circle().stroke(Noir.crimsonLight.opacity(0.85 * (1 - progress)),lineWidth:2.5)
       .frame(width:20 + 60 * progress,height:20 + 60 * progress)
       .offset(x:model.point.x - (10 + 30 * progress),y:model.point.y - (10 + 30 * progress))
     }
    }
    ZStack(alignment:.topLeading) {
     Circle().fill(RadialGradient(colors:[Noir.crimson.opacity(0.55),Noir.crimson.opacity(0)],center:.center,startRadius:1,endRadius:34)).frame(width:68,height:68).offset(x:-34,y:-34)
     FridayArrow()
      .fill(LinearGradient(colors:[Noir.crimsonLight,Noir.crimson],startPoint:.topLeading,endPoint:.bottomTrailing))
      .overlay(FridayArrow().stroke(Color.white,lineWidth:1.6))
      .frame(width:20,height:32)
      .rotationEffect(.degrees(model.tilt),anchor:.topLeading)
      .shadow(color:Noir.crimson.opacity(0.7),radius:8)
     Text(model.label.isEmpty ? "Friday" : model.label)
      .font(.system(size:11.5,weight:.bold,design:.rounded)).foregroundStyle(Color.white)
      .padding(.horizontal,9).padding(.vertical,4)
      .background(Capsule().fill(Noir.crimson.opacity(0.92)))
      .overlay(Capsule().stroke(Color.white.opacity(0.5),lineWidth:1))
      .offset(x:16,y:30)
    }
    .offset(x:model.point.x,y:model.point.y)
    .opacity(model.visible ? 1 : 0)
   }
  }
  .allowsHitTesting(false)
 }
}

// MARK: the Allow box

// A small box at the top of the screen: what she wants to do, why it needs a yes, and Allow or Deny. It never takes keyboard focus away
// from what Matthew is doing. No answer within 25 seconds counts as Deny.
@MainActor final class FridayApproval: ObservableObject {
 @Published var title = ""
 @Published var detail = ""
 @Published var pending = false
 private var panel: NSPanel?
 private var continuation: CheckedContinuation<Bool,Never>?
 private var token = 0

 func ask(_ title: String,detail: String) async -> Bool {
  if pending { return false }
  self.title = title
  self.detail = detail
  pending = true
  token += 1
  let mine = token
  show()
  NSSound.beep()
  return await withCheckedContinuation { (waiting: CheckedContinuation<Bool,Never>) in
   continuation = waiting
   Task { [weak self] in
    try? await Task.sleep(nanoseconds:25_000_000_000)
    if let self = self, self.token == mine { self.answer(false) }
   }
  }
 }

 func answer(_ allow: Bool) {
  guard let waiting = continuation else { return }
  continuation = nil
  pending = false
  panel?.orderOut(nil)
  waiting.resume(returning:allow)
 }

 private func show() {
  guard let screen = NSScreen.main else { return }
  if panel == nil {
   let made = NSPanel(contentRect:NSRect(x:0,y:0,width:460,height:150),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
   made.isFloatingPanel = true
   made.level = NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue + 2)
   made.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
   made.isOpaque = false
   made.backgroundColor = .clear
   made.hasShadow = true
   made.hidesOnDeactivate = false
   made.contentView = NSHostingView(rootView:FridayApprovalView(model:self))
   panel = made
  }
  let area = screen.visibleFrame
  panel?.setFrame(NSRect(x:area.midX - 230,y:area.maxY - 170,width:460,height:150),display:true)
  panel?.orderFrontRegardless()
 }
}

struct FridayApprovalView: View {
 @ObservedObject var model: FridayApproval

 var body: some View {
  VStack(alignment:.leading,spacing:10) {
   HStack(spacing:8) {
    Image(systemName:"hand.raised.fill").foregroundStyle(Noir.crimsonLight)
    Text("Friday is asking").font(.system(size:11,weight:.bold,design:.rounded)).tracking(1.2).foregroundStyle(Noir.crimsonLight)
   }
   Text(model.title).font(.system(size:16,weight:.semibold,design:.rounded)).foregroundStyle(Color.white).lineLimit(2)
   Text(model.detail).font(.system(size:12.5,design:.rounded)).foregroundStyle(Color.white.opacity(0.65)).lineLimit(2)
   HStack(spacing:10) {
    Spacer()
    Button { model.answer(false) } label: { Text("Deny").frame(width:84) }.buttonStyle(PillButtonStyle(tint:Color.white.opacity(0.14)))
    Button { model.answer(true) } label: { Text("Allow").frame(width:84) }.buttonStyle(PillButtonStyle())
   }
  }
  .padding(16)
  .frame(width:460,alignment:.leading)
  .background(RoundedRectangle(cornerRadius:20,style:.continuous).fill(Color(red:0.10,green:0.07,blue:0.10).opacity(0.96)))
  .overlay(RoundedRectangle(cornerRadius:20,style:.continuous).stroke(Noir.crimsonLight.opacity(0.45),lineWidth:1))
  .padding(10)
 }
}

// MARK: the hands

@MainActor final class FridayHands: ObservableObject {
 // Remembered between launches (Matthew, 2026-10-06: "I want her to be able to do anything I ask"). It still only works while Friday is live,
 // and everything that could send or buy still needs his Allow. The hand button on the Friday page switches it off in one tap.
 @Published var enabled = UserDefaults.standard.bool(forKey:"hands.on") {
  didSet {
   UserDefaults.standard.set(enabled,forKey:"hands.on")
   if enabled { checkAccess() } else { hideCursor(after:0) }
  }
 }
 @Published var hasAccess = AXIsProcessTrusted()
 @Published var status = ""
 let cursor = FridayCursorModel()
 let approval = FridayApproval()
 private var live: LiveBuddy?
 private var panel: NSPanel?
 private var recent: [Date] = []
 private var lastAction = Date.distantPast
 private var hideTask: Task<Void,Never>?
 private var busy = false
 private var cursorDesk: CGPoint?

 func attach(_ buddy: LiveBuddy) { if live == nil { live = buddy } }

 func checkAccess() {
  // Accessibility is required, not just permission to post events: the password-field and button-name checks read it.
  hasAccess = AXIsProcessTrusted()
  if !hasAccess {
   _ = CGRequestPostEventAccess()
   _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary)
   hasAccess = AXIsProcessTrusted()
  }
  status = hasAccess ? "" : "Pointing works now. For clicking, typing and scrolling, allow this app in System Settings, Privacy & Security, Accessibility."
 }

 func openSettings() {
  if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
 }

 // MARK: windows and screens (desk coordinates: origin top-left of the main screen)

 private struct Win { var id: CGWindowID; var rect: CGRect; var owner: String; var title: String; var pid: Int; var layer: Int; var alpha: Double }

 private let ownPid = Int(ProcessInfo.processInfo.processIdentifier)

 // Every window on screen of every kind (normal windows, menus, pop-ups, panels, the Dock), front-most first.
 private func allWindows() -> [Win] {
  guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] else { return [] }
  var found: [Win] = []
  for info in list {
   guard let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
         let rect = CGRect(dictionaryRepresentation:boundsInfo as CFDictionary), rect.width > 0, rect.height > 0,
         let number = info[kCGWindowNumber as String] as? Int, let id = UInt32(exactly:number) else { continue }
   found.append(Win(id:id,rect:rect,owner:info[kCGWindowOwnerName as String] as? String ?? "",title:info[kCGWindowName as String] as? String ?? "",
                    pid:info[kCGWindowOwnerPID as String] as? Int ?? 0,layer:info[kCGWindowLayer as String] as? Int ?? 0,alpha:info[kCGWindowAlpha as String] as? Double ?? 1))
  }
  return found
 }

 // Ordinary app windows only, front-most first.
 private func windows() -> [Win] { allWindows().filter { $0.layer == 0 && $0.rect.width > 40 && $0.rect.height > 40 } }

 // What a click or a scroll at this spot would really land on: the top-most visible window of ANY kind. Only her own cursor overlay
 // (which lets the mouse through) and the invisible bits of macOS itself are skipped. That means her own Allow box is found, not the
 // page under it.
 private func hitWindow(at point: CGPoint) -> Win? {
  let skip = (panel?.windowNumber).flatMap { UInt32(exactly:$0) }
  return allWindows().first { $0.rect.contains(point) && $0.alpha > 0.05 && $0.id != skip && !($0.owner == "Window Server" && $0.title != "Menubar") }
 }

 // nil when she may act in this window; otherwise the reason, as part of a sentence.
 private func refusal(for window: Win) -> String? {
  if window.pid == ownPid { return "that's my own app, and she must not change her own switches or press her own Allow button" }
  if window.owner == "Dock" || window.title == "Menubar" { return "that's the Dock or the menu bar" }
  return HandsPlan.blockedReason(owner:window.owner,title:window.title)
 }

 private func frontWindow() -> Win? {
  guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
  return windows().first { $0.pid == Int(pid) }
 }

 private func deskUnion() -> CGRect? {
  var ids = [CGDirectDisplayID](repeating:0,count:16)
  var count: UInt32 = 0
  guard CGGetActiveDisplayList(16,&ids,&count) == .success, count > 0 else { return nil }
  return HandsPlan.union(ids.prefix(Int(count)).map { CGDisplayBounds($0) })
 }

 // The window Matthew chose in "Just the window I pick" mode.
 private func chosenWindow() -> Win? {
  guard let filter = live?.filter, let window = filter.includedWindows.first else { return nil }
  return windows().first { $0.id == window.windowID }
 }

 // The part of the desk her picture covers: every screen, or the chosen window.
 private func pictureArea() -> CGRect? {
  if live?.sees == 1 { return chosenWindow()?.rect }
  return deskUnion()
 }

 private func usingMouse() -> Bool {
  if NSEvent.pressedMouseButtons != 0 { return true }
  return CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType:.mouseMoved) < 1.5
 }

 private func rateProblem() -> String? {
  let now = Date()
  if now.timeIntervalSince(lastAction) < 0.3 { return "Too fast. Give it a second." }
  recent = recent.filter { now.timeIntervalSince($0) < 60 }
  if recent.count >= 30 { return "That's a lot of moves in a minute, so I'm pausing for a bit." }
  return nil
 }

 private func noteAction() { lastAction = Date(); recent.append(lastAction) }

 // The label of the button or field under a point, read from macOS's accessibility information. Used only to spot Send, Pay and
 // similar words; it is not stored or sent anywhere. It never reads what is typed into a field.
 private func elementLabel(at point: CGPoint) -> String {
  guard AXIsProcessTrusted() else { return "" }
  var element: AXUIElement?
  guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(point.x),Float(point.y),&element) == .success, let found = element else { return "" }
  var parts: [String] = []
  for attribute in [kAXTitleAttribute,kAXDescriptionAttribute,kAXHelpAttribute,kAXRoleDescriptionAttribute] {
   var value: CFTypeRef?
   if AXUIElementCopyAttributeValue(found,attribute as CFString,&value) == .success, let text = value as? String, !text.isEmpty { parts.append(String(text.prefix(80))) }
  }
  return parts.joined(separator:" ")
 }

 // True when the field that has the keyboard is a password box (or when macOS won't let her look, which counts as "yes").
 private func passwordFieldFocused() -> Bool {
  guard AXIsProcessTrusted() else { return true }
  var focused: CFTypeRef?
  guard AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(),kAXFocusedUIElementAttribute as CFString,&focused) == .success, let field = focused else { return false }
  var subrole: CFTypeRef?
  guard AXUIElementCopyAttributeValue(field as! AXUIElement,kAXSubroleAttribute as CFString,&subrole) == .success else { return false }
  return (subrole as? String) == "AXSecureTextField"
 }

 // MARK: her cursor on screen

 private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

 private func screen(for desk: CGPoint) -> NSScreen? {
  let appKit = NSPoint(x:desk.x,y:primaryHeight - desk.y)
  return NSScreen.screens.first { $0.frame.contains(appKit) } ?? NSScreen.main
 }

 private func local(_ desk: CGPoint,in screen: NSScreen) -> CGPoint {
  CGPoint(x:desk.x - screen.frame.minX,y:screen.frame.maxY - (primaryHeight - desk.y))
 }

 private func ensurePanel(on screen: NSScreen) {
  if panel == nil {
   let made = NSPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
   made.isFloatingPanel = true
   made.level = NSWindow.Level(rawValue:NSWindow.Level.statusBar.rawValue + 1)
   made.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.stationary,.ignoresCycle]
   made.isOpaque = false
   made.backgroundColor = .clear
   made.hasShadow = false
   made.ignoresMouseEvents = true
   made.hidesOnDeactivate = false
   made.contentView = NSHostingView(rootView:FridayCursorView(model:cursor))
   panel = made
  }
  if panel?.frame != screen.frame { panel?.setFrame(screen.frame,display:true) }
  panel?.orderFrontRegardless()
 }

 // Glides her cursor to a spot on the desk, starting from where it last was (or from the real pointer), and waits until it arrives.
 private func moveCursor(to desk: CGPoint,label: String) async {
  guard let screen = screen(for:desk) else { return }
  hideTask?.cancel()
  ensurePanel(on:screen)
  cursor.label = label
  let destination = local(desk,in:screen)
  if !cursor.visible || cursorDesk == nil {
   let mouse = NSEvent.mouseLocation
   cursor.point = screen.frame.contains(mouse) ? CGPoint(x:mouse.x - screen.frame.minX,y:screen.frame.maxY - mouse.y) : destination
   cursor.trail = []
   withAnimation(.easeOut(duration:0.25)) { cursor.visible = true }
   try? await Task.sleep(nanoseconds:200_000_000)
  } else if let before = cursorDesk {
   // The overlay may have just moved to another screen: say where the cursor was in this screen's own terms.
   cursor.point = local(before,in:screen)
  }
  let start = cursor.point
  let distance = Double(hypot(destination.x - start.x,destination.y - start.y))
  // Slow enough to watch: 0.7 seconds for a short hop, up to 1.4 for a long one.
  await cursor.glide(from:start,to:destination,duration:min(1.4,0.7 + distance / 1600))
  cursorDesk = desk
  try? await Task.sleep(nanoseconds:180_000_000)
 }

 private func hideCursor(after seconds: Double) {
  hideTask?.cancel()
  hideTask = Task { [weak self] in
   try? await Task.sleep(nanoseconds:UInt64(seconds * 1_000_000_000))
   guard !Task.isCancelled, let self = self else { return }
   withAnimation(.easeIn(duration:0.5)) { self.cursor.visible = false }
   self.cursorDesk = nil
   try? await Task.sleep(nanoseconds:550_000_000)
   if !Task.isCancelled { self.panel?.orderOut(nil) }
  }
 }

 // MARK: checks every tool shares

 private func gate(needsAccess: Bool) -> String? {
  guard let live = live, live.running else { return "I'm not live right now, so I can't use my hands." }
  guard enabled else { return "My hands are switched off. Matthew can turn them on in Settings: Let Friday use her hands." }
  if approval.pending { return "I'm waiting for Matthew to answer the Allow box, so I'm not doing anything else until he does." }
  if busy { return "I'm still in the middle of another move. One thing at a time." }
  if needsAccess && !hasAccess {
   checkAccess()
   if !hasAccess { return "macOS hasn't let this app control the Mac yet. Matthew needs to allow it in System Settings, Privacy and Security, Accessibility. I can still point." }
  }
  return rateProblem()
 }

 // The same switches, checked again after anything that takes time (the glide, the wait for Allow, a long typing job).
 private func stillAllowed() -> String? {
  guard let live = live, live.running, enabled else { return "I'm not live any more, or my hands were switched off, so I stopped." }
  guard hasAccess, AXIsProcessTrusted() else { return "macOS no longer lets this app control the Mac, so I stopped." }
  return nil
 }

 // Asks for his Allow when something could send or buy. Returns nil if it can go ahead, or a sentence for Friday if it can't.
 private func needAllow(_ title: String,detail: String) async -> String? {
  let allowed = await approval.ask(title,detail:detail)
  return allowed ? nil : "Matthew didn't allow it, so I didn't do it. Ask him what he'd like instead."
 }

 // What is under a spot, judged by the window that would really receive the click.
 private struct Aim { var win: Win; var label: String; var risky: Bool }
 private enum AimResult { case ok(Aim); case no(String) }

 private func aim(at spot: CGPoint,named: String) -> AimResult {
  guard let hit = hitWindow(at:spot) else { return .no("I can't tell what is at that spot, so I didn't.") }
  if let why = refusal(for:hit) { return .no("I won't act there: \(why).") }
  let label = elementLabel(at:spot)
  let risky = HandsPlan.riskyIntent(named) || HandsPlan.riskyIntent(label) || HandsPlan.riskyWindow(title:hit.title)
  return .ok(Aim(win:hit,label:label,risky:risky))
 }

 // The window that has the keyboard, or why she can't type or press keys there.
 private func keyboardTarget() -> (win: Win?,problem: String?) {
  guard let front = frontWindow() else { return (nil,"I can't tell which window has the keyboard, so I didn't.") }
  if let why = refusal(for:front) { return (nil,"I won't use the keyboard there: \(why).") }
  if passwordFieldFocused() { return (nil,"A password box has the keyboard (or macOS won't let me check), so I won't. Matthew does that himself.") }
  return (front,nil)
 }

 private func sameWindow(_ a: Win,_ b: Win) -> Bool { a.id == b.id && a.pid == b.pid && a.title == b.title }

 // MARK: Friday's tools. Each returns a sentence she can say.

 // The page he means when he says "scroll" without pointing at anything: the top-most ordinary window that isn't hers. Just after he
 // talks to her, the front window IS Friday, so "the front window" would mean scrolling herself.
 private func pageWindow() -> Win? {
  windows().first { $0.pid != ownPid && $0.owner != "Dock" && $0.alpha > 0.05 && $0.rect.width >= 200 && $0.rect.height >= 150 }
 }

 // A spot inside the window that really belongs to it (nothing floating over it). Tries the spot she aimed at, then the middle and a few others.
 private func scrollSpot(in window: Win,preferred: CGPoint?) -> CGPoint? {
  var tries: [CGPoint] = []
  if let spot = preferred { tries.append(spot) }
  for (fx,fy) in [(0.5,0.5),(0.5,0.35),(0.5,0.65),(0.35,0.5),(0.65,0.5),(0.5,0.2),(0.5,0.8)] {
   tries.append(CGPoint(x:window.rect.minX + window.rect.width * CGFloat(fx),y:window.rect.minY + window.rect.height * CGFloat(fy)))
  }
  return tries.first { hitWindow(at:$0)?.id == window.id }
 }

 // x and y are 0 to 1000 across the picture she sees. Give them (the middle of the page) and she scrolls exactly that page, on any screen.
 func scroll(direction: String,amount: String,x: Double?,y: Double?) async -> String {
  if let problem = gate(needsAccess:true) { return problem }
  busy = true
  defer { busy = false }
  var target: Win?
  var aimed: CGPoint?
  if live?.sees == 1, let chosen = chosenWindow() { target = chosen }
  else if live?.sees != 1, let x = x, let y = y, let area = deskUnion() {
   let spot = HandsPlan.desk(x,y,in:area)
   target = hitWindow(at:spot)
   aimed = spot
  } else { target = pageWindow() }
  guard let found = target else { return "I can't find a page to scroll, so I didn't. Tell me which window, or open the page and try again." }
  if let why = refusal(for:found) {
   // Only an aimed-at spot can land on her own window; without one she already skipped it. Say it plainly.
   return "I won't scroll there: \(why)."
  }
  guard let spot = scrollSpot(in:found,preferred:aimed) else { return "Something is covering that window, so I didn't scroll." }
  if usingMouse() { return "Matthew is using the mouse right now, so I left the page alone." }
  noteAction()
  let way = direction.lowercased()
  let size = amount.lowercased()
  let page = Double(found.rect.height) * 0.85
  var total: Double
  var steps = 10
  var words: String
  switch way {
  case "top": total = 30_000; steps = 12; words = "all the way to the top"
  case "bottom": total = -30_000; steps = 12; words = "all the way to the bottom"
  default:
   let distance = size == "small" ? min(220,page) : (size == "large" ? page : min(520,page))
   total = way == "up" ? distance : -distance
   words = "\(way == "up" ? "up" : "down") about \(size == "small" ? "a little" : (size == "large" ? "a page" : "half a page"))"
  }
  await moveCursor(to:spot,label:"Friday")
  // The glide takes a second or two: look again before touching anything.
  if let problem = stillAllowed() { hideCursor(after:0.4); return problem }
  guard let now = hitWindow(at:spot), sameWindow(now,found), refusal(for:now) == nil else { hideCursor(after:0.4); return "The window changed while my cursor was moving, so I didn't scroll." }
  if usingMouse() { hideCursor(after:0.4); return "Matthew picked up the mouse, so I left the page alone." }
  let saved = CGEvent(source:nil)?.location ?? spot
  CGWarpMouseCursorPosition(spot)
  let each = Int32((total / Double(steps)).rounded())
  for _ in 0..<steps {
   if let event = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:each,wheel2:0,wheel3:0) {
    event.location = spot
    event.post(tap:.cghidEventTap)
   }
   try? await Task.sleep(nanoseconds:14_000_000)
  }
  try? await Task.sleep(nanoseconds:80_000_000)
  CGWarpMouseCursorPosition(saved)
  hideCursor(after:1.8)
  status = "Scrolled \(words)."
  return "Scrolled \(words) in \(found.owner)."
 }

 func point(x: Double,y: Double,label: String) async -> String {
  if let problem = gate(needsAccess:false) { return problem }
  busy = true
  defer { busy = false }
  guard let area = pictureArea() else { return "I can't tell where my picture is on the desk, so I can't point." }
  noteAction()
  let spot = HandsPlan.desk(x,y,in:area)
  let words = String(label.trimmingCharacters(in:.whitespacesAndNewlines).prefix(28))
  await moveCursor(to:spot,label:words.isEmpty ? "Friday" : words)
  cursor.pulse()
  hideCursor(after:3.5)
  return "Pointed there with my cursor."
 }

 func click(x: Double,y: Double,what: String,button: String,double: Bool) async -> String {
  if let problem = gate(needsAccess:true) { return problem }
  busy = true
  defer { busy = false }
  guard let area = pictureArea() else { return "I can't tell where my picture is on the desk, so I didn't click." }
  let spot = HandsPlan.desk(x,y,in:area)
  let named = what.trimmingCharacters(in:.whitespacesAndNewlines)
  let first: Aim
  switch aim(at:spot,named:named) {
  case .no(let problem): return problem
  case .ok(let found): first = found
  }
  noteAction()
  let shownName = String((named.isEmpty ? (first.label.isEmpty ? "Friday" : first.label) : named).prefix(28))
  await moveCursor(to:spot,label:shownName)
  // The glide takes a second or two, so the screen may have changed: decide again from scratch.
  if let problem = stillAllowed() { hideCursor(after:0.4); return problem }
  var now: Aim
  switch aim(at:spot,named:named) {
  case .no(let problem): hideCursor(after:0.4); return problem
  case .ok(let found): now = found
  }
  guard sameWindow(now.win,first.win) else { hideCursor(after:0.4); return "The window changed while my cursor was moving, so I didn't click." }
  let verb = double ? "Double-click" : (button.lowercased() == "right" ? "Right-click" : "Click")
  if now.risky {
   let where_ = "in \(now.win.owner)\(now.win.title.isEmpty ? "" : " — \(String(now.win.title.prefix(60)))")"
   if let refusal = await needAllow("\(verb) “\(shownName)”? This might send or buy something.",detail:where_) { hideCursor(after:0.4); return refusal }
   // Up to 25 seconds passed: check everything once more.
   if let problem = stillAllowed() { hideCursor(after:0.4); return problem }
   switch aim(at:spot,named:named) {
   case .no(let problem): hideCursor(after:0.4); return problem
   case .ok(let found): now = found
   }
   guard sameWindow(now.win,first.win) else { hideCursor(after:0.4); return "The window changed while I waited, so I didn't click." }
  }
  let saved = CGEvent(source:nil)?.location ?? spot
  CGWarpMouseCursorPosition(spot)
  try? await Task.sleep(nanoseconds:60_000_000)
  let right = button.lowercased() == "right"
  let downType: CGEventType = right ? .rightMouseDown : .leftMouseDown
  let upType: CGEventType = right ? .rightMouseUp : .leftMouseUp
  let mouseButton: CGMouseButton = right ? .right : .left
  for count in 1...(double ? 2 : 1) {
   for type in [downType,upType] {
    if let event = CGEvent(mouseEventSource:nil,mouseType:type,mouseCursorPosition:spot,mouseButton:mouseButton) {
     event.setIntegerValueField(.mouseEventClickState,value:Int64(count))
     event.post(tap:.cghidEventTap)
    }
    try? await Task.sleep(nanoseconds:35_000_000)
   }
  }
  cursor.pulse()
  try? await Task.sleep(nanoseconds:250_000_000)
  CGWarpMouseCursorPosition(saved)
  hideCursor(after:1.6)
  status = "\(verb)ed \(shownName)."
  return "\(verb == "Click" ? "Clicked" : (verb == "Right-click" ? "Right-clicked" : "Double-clicked")) \(shownName) in \(now.win.owner)."
 }

 // Types plain text into whatever has the keyboard. A line break (Return) needs his Allow, like any Return.
 func type(_ raw: String) async -> String {
  if let problem = gate(needsAccess:true) { return problem }
  busy = true
  defer { busy = false }
  guard let text = HandsPlan.cleanTyped(raw) else { return "I can only type plain text up to \(HandsPlan.maxTyped) characters. Nothing was typed." }
  if HandsPlan.looksLikeCardNumber(text) { return "That has a long run of digits that could be a card number, so I won't type it. Matthew types those himself." }
  let checked = keyboardTarget()
  guard let front = checked.win else { return checked.problem ?? "I couldn't tell where to type, so I didn't." }
  noteAction()
  let needsReturn = text.contains("\n")
  if needsReturn || HandsPlan.riskyWindow(title:front.title) {
   let preview = String(text.prefix(70)).replacingOccurrences(of:"\n",with:" ⏎ ")
   let why = needsReturn ? "It includes a line break, which can send or submit." : "This window looks like a checkout or payment page."
   if let refusal = await needAllow("Type “\(preview)”? \(why)",detail:"into \(front.owner)\(front.title.isEmpty ? "" : " — \(String(front.title.prefix(60)))")") { return refusal }
  }
  var typed = 0
  // Before every piece: same switches, same window, no password box. If anything moved, stop where we are.
  func stillGood() -> String? {
   if let problem = stillAllowed() { return problem }
   let again = keyboardTarget()
   guard let now = again.win else { return again.problem }
   return sameWindow(now,front) ? nil : "The window changed, so I stopped."
  }
  for (index,line) in text.components(separatedBy:"\n").enumerated() {
   if index > 0 {
    if let problem = stillGood() { return typed == 0 ? problem : "\(problem) I had typed \(typed) characters." }
    await postKey(code:36,flags:[])
    typed += 1
   }
   var chunk = ""
   for character in line {
    chunk.append(character)
    if chunk.count >= 10 {
     if let problem = stillGood() { return typed == 0 ? problem : "\(problem) I had typed \(typed) characters." }
     await postText(chunk)
     typed += chunk.count
     chunk = ""
    }
   }
   if !chunk.isEmpty {
    if let problem = stillGood() { return typed == 0 ? problem : "\(problem) I had typed \(typed) characters." }
    await postText(chunk)
    typed += chunk.count
   }
  }
  status = "Typed \(text.count) characters."
  return "Typed it into \(front.owner)."
 }

 // Presses a key or a combination such as cmd+t or escape. Return and Enter need his Allow.
 func press(_ spec: String) async -> String {
  if let problem = gate(needsAccess:true) { return problem }
  busy = true
  defer { busy = false }
  guard let press = HandsPlan.parseKeys(spec) else { return "I don't know that key. Use names like enter, escape, tab, space, down, or combinations like cmd+t." }
  if let why = HandsPlan.blockedCombo(press) { return "I won't press \(press.label): that's for \(why)." }
  let checked = keyboardTarget()
  guard let front = checked.win else { return checked.problem ?? "I couldn't tell where to press keys, so I didn't." }
  noteAction()
  if HandsPlan.needsAllow(press) || HandsPlan.riskyWindow(title:front.title) {
   let why = HandsPlan.needsAllow(press) ? "Return can send or submit something." : "This window looks like a checkout or payment page."
   if let refusal = await needAllow("Press \(press.label)? \(why)",detail:"in \(front.owner)\(front.title.isEmpty ? "" : " — \(String(front.title.prefix(60)))")") { return refusal }
   // Up to 25 seconds passed: the keyboard may be somewhere else now.
   if let problem = stillAllowed() { return problem }
   let again = keyboardTarget()
   guard let now = again.win else { return again.problem ?? "I couldn't tell where the keyboard is now, so I didn't press anything." }
   guard sameWindow(now,front) else { return "The window changed while I waited, so I didn't press anything." }
  }
  await postKey(code:press.code,flags:press.modifiers)
  status = "Pressed \(press.label)."
  return "Pressed \(press.label) in \(front.owner)."
 }

 // MARK: sending the actual events

 private func postText(_ chunk: String) async {
  let units = Array(chunk.utf16)
  guard !units.isEmpty else { return }
  for down in [true,false] {
   if let event = CGEvent(keyboardEventSource:nil,virtualKey:0,keyDown:down) {
    event.keyboardSetUnicodeString(stringLength:units.count,unicodeString:units)
    event.post(tap:.cghidEventTap)
   }
  }
  try? await Task.sleep(nanoseconds:12_000_000)
 }

 private func postKey(code: UInt16,flags names: [String]) async {
  var flags = CGEventFlags()
  for name in names {
   switch name {
   case "cmd": flags.insert(.maskCommand)
   case "shift": flags.insert(.maskShift)
   case "opt": flags.insert(.maskAlternate)
   case "ctrl": flags.insert(.maskControl)
   default: break
   }
  }
  for down in [true,false] {
   if let event = CGEvent(keyboardEventSource:nil,virtualKey:CGKeyCode(code),keyDown:down) {
    event.flags = flags
    event.post(tap:.cghidEventTap)
   }
   try? await Task.sleep(nanoseconds:25_000_000)
  }
 }
}
