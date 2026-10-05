import SwiftUI
import AppKit
import CoreGraphics
import ScreenCaptureKit

// Friday's hands: she can scroll the window she is watching, and show her own cursor (a crimson pointer that glides across the
// screen) to point at things. She can NOT click, type or press keys. Safety rules, all enforced here:
//  - Off every time the app opens. Matthew switches it on in Settings.
//  - Works only while Friday is live, only in the window (or display) Matthew chose to share, and only if that window is the
//    front-most thing at its middle, so a scroll can never land on some other app.
//  - If Matthew is using the mouse (moved it in the last 1.5 seconds, or a button is down) she leaves the page alone.
//  - At most one action every 0.4 seconds and 30 a minute. Every action shows her cursor first, so he can always see it.
//  - Pointing never moves the real mouse and needs no permission. Scrolling needs macOS's Accessibility ("post events") permission.
// Checked against Apple's docs on 2026-10-05: CGEvent(scrollWheelEvent2Source:), CGPreflightPostEventAccess and
// CGRequestPostEventAccess (macOS 10.15+), SCContentFilter.includedWindows (macOS 15.2+), SCWindow.windowID.

@MainActor final class FridayCursorModel: ObservableObject {
 // In the overlay panel's own coordinates (origin top-left).
 @Published var point = CGPoint(x:-100,y:-100)
 @Published var visible = false
 @Published var label = ""
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
  ZStack(alignment:.topLeading) {
   Color.clear
   ZStack(alignment:.topLeading) {
    Circle().fill(RadialGradient(colors:[Noir.crimson.opacity(0.55),Noir.crimson.opacity(0)],center:.center,startRadius:1,endRadius:34)).frame(width:68,height:68).offset(x:-34,y:-34)
    FridayArrow()
     .fill(LinearGradient(colors:[Noir.crimsonLight,Noir.crimson],startPoint:.topLeading,endPoint:.bottomTrailing))
     .overlay(FridayArrow().stroke(Color.white,lineWidth:1.6))
     .frame(width:20,height:32)
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
  .allowsHitTesting(false)
 }
}

@MainActor final class FridayHands: ObservableObject {
 // Not saved: off every time the app opens.
 @Published var enabled = false {
  didSet {
   if enabled { checkAccess() } else { hideCursor(after:0) }
  }
 }
 @Published var hasAccess = CGPreflightPostEventAccess()
 @Published var status = ""
 let cursor = FridayCursorModel()
 private var live: LiveBuddy?
 private var panel: NSPanel?
 private var recent: [Date] = []
 private var lastAction = Date.distantPast
 private var hideTask: Task<Void,Never>?

 func attach(_ buddy: LiveBuddy) { if live == nil { live = buddy } }

 func checkAccess() {
  hasAccess = CGPreflightPostEventAccess()
  if !hasAccess {
   _ = CGRequestPostEventAccess()
   hasAccess = CGPreflightPostEventAccess()
  }
  status = hasAccess ? "" : "Pointing works now. For scrolling, allow this app in System Settings, Privacy & Security, Accessibility."
 }

 func openSettings() {
  if let url = URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
 }

 // MARK: finding the window she is watching (Quartz coordinates: origin top-left of the main screen)

 private struct Target { var id: CGWindowID?; var rect: CGRect }

 private func target() -> Target? {
  guard let filter = live?.filter else { return nil }
  if let window = filter.includedWindows.first {
   let id = window.windowID
   if let info = CGWindowListCopyWindowInfo([.optionIncludingWindow],id) as? [[String:Any]],
      let boundsInfo = info.first?[kCGWindowBounds as String] as? NSDictionary,
      let rect = CGRect(dictionaryRepresentation:boundsInfo as CFDictionary), rect.width > 100, rect.height > 100 {
    return Target(id:id,rect:rect)
   }
   return nil
  }
  if let display = filter.includedDisplays.first { return Target(id:nil,rect:CGDisplayBounds(display.displayID)) }
  return nil
 }

 // True when the target window is the front-most normal window at that point, so a scroll can only reach it.
 private func isFront(_ target: Target,at point: CGPoint) -> Bool {
  guard let id = target.id else { return true }   // a whole display: the top window there is whatever Matthew is looking at
  guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] else { return false }
  for info in list {
   guard (info[kCGWindowLayer as String] as? Int) == 0,
         let boundsInfo = info[kCGWindowBounds as String] as? NSDictionary,
         let rect = CGRect(dictionaryRepresentation:boundsInfo as CFDictionary), rect.contains(point) else { continue }
   return (info[kCGWindowNumber as String] as? Int).map { CGWindowID($0) } == id
  }
  return false
 }

 private func usingMouse() -> Bool {
  if NSEvent.pressedMouseButtons != 0 { return true }
  return CGEventSource.secondsSinceLastEventType(.combinedSessionState,eventType:.mouseMoved) < 1.5
 }

 private func rateProblem() -> String? {
  let now = Date()
  if now.timeIntervalSince(lastAction) < 0.4 { return "Too fast. Give it a second." }
  recent = recent.filter { now.timeIntervalSince($0) < 60 }
  if recent.count >= 30 { return "That's a lot of moves in a minute, so I'm pausing for a bit." }
  return nil
 }

 private func noteAction() { lastAction = Date(); recent.append(lastAction) }

 // MARK: her cursor on screen

 private var primaryHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

 private func screen(for quartz: CGPoint) -> NSScreen? {
  let appKit = NSPoint(x:quartz.x,y:primaryHeight - quartz.y)
  return NSScreen.screens.first { $0.frame.contains(appKit) } ?? NSScreen.main
 }

 private func local(_ quartz: CGPoint,in screen: NSScreen) -> CGPoint {
  CGPoint(x:quartz.x - screen.frame.minX,y:screen.frame.maxY - (primaryHeight - quartz.y))
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

 // Glides her cursor to a spot (Quartz coordinates), starting from where the real pointer is, and waits for it to arrive.
 private func showCursor(at quartz: CGPoint,label: String) async {
  guard let screen = screen(for:quartz) else { return }
  hideTask?.cancel()
  ensurePanel(on:screen)
  cursor.label = label
  let destination = local(quartz,in:screen)
  if !cursor.visible {
   let mouse = NSEvent.mouseLocation
   cursor.point = screen.frame.contains(mouse) ? CGPoint(x:mouse.x - screen.frame.minX,y:screen.frame.maxY - mouse.y) : destination
   withAnimation(.easeOut(duration:0.2)) { cursor.visible = true }
   try? await Task.sleep(nanoseconds:120_000_000)
  }
  withAnimation(.spring(response:0.5,dampingFraction:0.82)) { cursor.point = destination }
  try? await Task.sleep(nanoseconds:550_000_000)
 }

 private func hideCursor(after seconds: Double) {
  hideTask?.cancel()
  hideTask = Task { [weak self] in
   try? await Task.sleep(nanoseconds:UInt64(seconds * 1_000_000_000))
   guard !Task.isCancelled, let self = self else { return }
   withAnimation(.easeIn(duration:0.4)) { self.cursor.visible = false }
   try? await Task.sleep(nanoseconds:450_000_000)
   if !Task.isCancelled { self.panel?.orderOut(nil) }
  }
 }

 // MARK: Friday's tools. Each returns a sentence she can say.

 private func gate(needsAccess: Bool) -> String? {
  guard let live = live, live.running else { return "I'm not live right now, so I can't use my hands." }
  guard enabled else { return "My hands are switched off. Matthew can turn them on in Settings: Let Friday scroll and point." }
  if needsAccess && !hasAccess {
   checkAccess()
   if !hasAccess { return "macOS hasn't let this app scroll yet. Matthew needs to allow it in System Settings, Privacy and Security, Accessibility. I can still point." }
  }
  return rateProblem()
 }

 func scroll(direction: String,amount: String) async -> String {
  if let problem = gate(needsAccess:true) { return problem }
  guard let found = target() else { return "I can't find the window I'm watching, so I didn't scroll." }
  let middle = CGPoint(x:found.rect.midX,y:found.rect.midY)
  guard isFront(found,at:middle) else { return "The window I'm watching isn't in front at its middle (something is covering it), so I didn't scroll." }
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
  await showCursor(at:middle,label:"Friday")
  // The real pointer has to be over the page for the scroll to reach it. It goes back right after.
  let saved = CGEvent(source:nil)?.location ?? middle
  CGWarpMouseCursorPosition(middle)
  let each = Int32((total / Double(steps)).rounded())
  for _ in 0..<steps {
   if let event = CGEvent(scrollWheelEvent2Source:nil,units:.pixel,wheelCount:1,wheel1:each,wheel2:0,wheel3:0) {
    event.location = middle
    event.post(tap:.cghidEventTap)
   }
   try? await Task.sleep(nanoseconds:14_000_000)
  }
  try? await Task.sleep(nanoseconds:80_000_000)
  CGWarpMouseCursorPosition(saved)
  hideCursor(after:1.8)
  status = "Scrolled \(words)."
  return "Scrolled \(words)."
 }

 // x and y are 0 to 1000 across the picture she sees of the shared window: left to right, top to bottom.
 func point(x: Double,y: Double,label: String) async -> String {
  if let problem = gate(needsAccess:false) { return problem }
  guard let found = target() else { return "I can't find the window I'm watching, so I can't point." }
  noteAction()
  let nx = min(max(x,0),1000) / 1000
  let ny = min(max(y,0),1000) / 1000
  let spot = CGPoint(x:found.rect.minX + found.rect.width * nx,y:found.rect.minY + found.rect.height * ny)
  let words = String(label.trimmingCharacters(in:.whitespacesAndNewlines).prefix(28))
  await showCursor(at:spot,label:words.isEmpty ? "Friday" : words)
  hideCursor(after:3.5)
  return "Pointed there with my cursor. I can only point and scroll; I can't click."
 }
}
