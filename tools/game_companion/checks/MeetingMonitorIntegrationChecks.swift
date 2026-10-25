import Foundation
import SwiftUI
import Cocoa

// macOS only. run_monitor_integration_checks.py extracts the real MeetingHub and card
// into an isolated fixture, stubs credentials and injects this offline transport/store.
final class IntegrationMonitorStore: MeetingMonitorStorage {
 var value = MeetingMonitorState()
 func load() throws -> MeetingMonitorState { value }
 func save(_ state: MeetingMonitorState) throws { value = state }
}
actor IntegrationMonitorTransport: MeetingMonitorTransport {
 var reads: [MeetingReadSource] = []
 func count() -> Int { reads.count }
 func read(_ request: MeetingReadRequest,etag: String?) async throws -> MeetingMonitorResponse {
  reads.append(request.source)
  let f = DateFormatter(); f.locale = Locale(identifier:"en_US_POSIX"); f.timeZone = TimeZone(secondsFromGMT:0)
  f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
  let body = request.source == .board ? "## On the table\n- [GPT] Offline fixture. Status: review" : "[]"
  return .init(status:200,headers:["Date":f.string(from:Date())],url:request.url,body:Data(body.utf8))
 }
}
@main struct MeetingMonitorIntegrationChecks {
 @MainActor static func main() async throws {
  var failures = 0
  func check(_ result: Bool,_ label: String) { if !result { failures += 1; print("FAIL: \(label)") } }
  let storage = IntegrationMonitorStore(), transport = IntegrationMonitorTransport()
  let monitor = try MeetingMonitor(transport:transport,storage:storage)
  let hub = MeetingHub(monitor:monitor)
  await hub.startMonitoring()
  await hub.refresh(minGap:0) // Friday's legacy automatic entry point.
  check(await transport.count() == 0,"startup and Friday automatic caller respect Off")
  check(!hub.commentsLoaded && hub.board == nil && !hub.loading,"initial snapshot honest and not spinning")
  await hub.refreshManually(source:.comments)
  check(await transport.count() == 1,"manual inbox reads only comments")
  check(hub.commentsLoaded && hub.monitorState.settings.mode == .off,"manual request publishes payload status but remains Off")
  await hub.refreshManually(source:.board)
  check(await transport.count() == 2 && hub.board != nil,"manual board read updates observed model")
  await hub.changeMonitor(.fast)
  check(hub.monitorState.settings.mode == .task && hub.monitorState.settings.lease != nil,"explicit Fast enables a bounded lease")
  await hub.changeMonitor(.finish)
  check(hub.monitorState.settings.mode == .hourly && hub.monitorState.settings.lease == nil,"Finish returns to hourly")
  await hub.changeMonitor(.stop)
  let count = await transport.count()
  await hub.refresh(minGap:0)
  check(await transport.count() == count && hub.monitorState.settings.mode == .off,"Stop blocks subsequent automatic caller")
  let restart = MeetingHub(monitor:try MeetingMonitor(transport:transport,storage:storage))
  await restart.startMonitoring()
  check(!restart.commentsLoaded && restart.board == nil && restart.monitorState.comments.lastSuccessfulCheck != nil,"restart retains metadata without pretending to have payloads")
  check(await transport.count() == count,"restart after Stop performs no read")
  hub.monitorState.unread = ["comment:1:new"]
  await hub.changeMonitor(.markRead)
  check(hub.monitorState.unread.isEmpty,"Mark read updates the card")

  // Render only the independent card. No Companion, LiveBuddy, production app or network is launched.
  if let output = CommandLine.arguments.dropFirst().first {
   _ = NSApplication.shared
   let out = URL(fileURLWithPath:output,isDirectory:true)
   try FileManager.default.createDirectory(at:out,withIntermediateDirectories:true)
   for name in ["off","fast","paused"] {
    hub.monitorProblem = name == "paused"
    if name == "fast" { _ = hub.monitorState.settings.startTask(id:"fixture",now:Date()); hub.monitorState.unread = ["comment:1:new"] }
    else { hub.monitorState.settings.stop() }
    let view = NSHostingView(rootView:MeetingMonitorCard(meeting:hub).padding(12).frame(width:344)
     .foregroundStyle(Color.white).background(Color.black).environment(\.colorScheme,.dark))
    let window = NSWindow(contentRect:NSRect(x:-10000,y:-10000,width:344,height:800),styleMask:[.borderless],backing:.buffered,defer:false)
    window.isReleasedWhenClosed = false
    window.contentView = view
    window.orderFront(nil)
    try await Task.sleep(nanoseconds:100_000_000)
    let height = max(1,ceil(view.fittingSize.height))
    check(height < 800,"compact card fits a scrollable content area")
    window.setContentSize(NSSize(width:344,height:height))
    view.layoutSubtreeIfNeeded(); window.displayIfNeeded()
    if let image = view.bitmapImageRepForCachingDisplay(in:view.bounds) {
     view.cacheDisplay(in:view.bounds,to:image)
     if let data = image.representation(using:.png,properties:[:]) { try data.write(to:out.appendingPathComponent(name + ".png")) }
    } else { check(false,"card bitmap is available") }
    if name == "fast" {
     await hub.changeMonitor(.fast)
     let key = NSEvent.keyEvent(with:.keyDown,location:.zero,modifierFlags:.command,timestamp:0,
                               windowNumber:window.windowNumber,context:nil,characters:".",charactersIgnoringModifiers:".",isARepeat:false,keyCode:47)!
     check(window.performKeyEquivalent(with:key),"Command-period reaches the Stop button")
     try await Task.sleep(nanoseconds:50_000_000)
     check(hub.monitorState.settings.mode == .off,"keyboard Stop changes monitor to Off")
    }
    window.close()
   }
  }
  if failures != 0 { exit(1) }
  print("MeetingHub integration checks passed (offline, isolated card).")
 }
}
