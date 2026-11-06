import SwiftUI
import AppKit

// Command Core, step 1 (Friday's solo project, Matthew's GO 2026-11-06 ~9:49 AM; plan in Helm-Private friday/command-core-proposal.md).
// The dashboard row on top of the Hack Room's live tape: four tiles, each from something the app ACTUALLY reads. No source = no number.
//  THIS MAC     : the OS, memory, free disk and uptime straight from macOS (ProcessInfo, file system), plus Guard's last check result.
//  NETWORK      : the apps Guard saw using the internet at its last check (it does not scan anything else).
//  DEVICES      : this Mac. Other devices come in step 2 (a list Matthew fills in himself); until then it says so.
//  OPERATIONS   : jobs the Switchboard is running, GitHub automations running or failing, the practice robots.
// The only thing a button here can do is run Guard's existing read-only checks (the same fixed commands the Guard page runs).
// Read-only otherwise. Nothing is sent anywhere. Lockdown and Offline (Guard) still apply: Run checks is refused while Lockdown is on.

enum CoreFacts {
 static func memoryGB() -> Double { Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824 }
 static func uptimeText(_ seconds: TimeInterval) -> String {
  let m = Int(seconds / 60)
  if m < 60 { return "\(m) min" }
  if m < 60 * 48 { return "\(m / 60) h \(m % 60) min" }
  return "\(m / 1440) days"
 }
 // Free space on the startup disk as macOS reports it (important-usage capacity counts what can be freed).
 static func freeDiskGB() -> Double? {
  let url = URL(fileURLWithPath:"/")
  guard let values = try? url.resourceValues(forKeys:[.volumeAvailableCapacityForImportantUsageKey]),
        let bytes = values.volumeAvailableCapacityForImportantUsage else { return nil }
  return Double(bytes) / 1_000_000_000
 }
 static func summarize(_ results: [GuardCheckResult]) -> (ok: Int,warn: Int,unknown: Int) {
  (results.filter { $0.verdict == .ok }.count,results.filter { $0.verdict == .warn }.count,results.filter { $0.verdict == .unknown }.count)
 }
}

extension CompanionInterfaceView {

 var coreTiles: some View {
  CoreTilesView(guardHub:GuardHub.shared,switchboard:Switchboard.shared,
                runs:ventures.runs,robotsLoaded:deckRobots.filter { $0.robot != nil }.count,robotsFailed:stocks.failed)
 }
}

struct CoreTilesView: View {
 @ObservedObject var guardHub: GuardHub
 @ObservedObject var switchboard: Switchboard
 var runs: [AutomationRun]?
 var robotsLoaded: Int
 var robotsFailed: Bool

 private func ago(_ d: Date) -> String {
  let s = Int(Date().timeIntervalSince(d))
  return s < 90 ? "just now" : (s < 3600 ? "\(s / 60) min ago" : "\(s / 3600) h ago")
 }

 private func tile<C: View>(_ title: String,_ light: Color,@ViewBuilder _ content: () -> C) -> some View {
  VStack(alignment:.leading,spacing:5) {
   HStack(spacing:6) {
    Circle().fill(light).frame(width:7,height:7).shadow(color:light.opacity(0.8),radius:3)
    Text(title).font(DeckMono.font(10.5,.bold)).foregroundStyle(HackPalette.crimson.opacity(0.9)).tracking(1.5)
   }
   content()
  }
  .padding(11).frame(maxWidth:.infinity,minHeight:96,alignment:.topLeading)
  .background(HackPalette.panel,in:RoundedRectangle(cornerRadius:6))
  .overlay(RoundedRectangle(cornerRadius:6).stroke(HubTheme.green.opacity(0.22),lineWidth:1))
 }

 private func line(_ text: String,_ dim: Bool = false) -> some View {
  Text(text).font(DeckMono.font(11)).foregroundStyle(dim ? HubTheme.subtext : HubTheme.text).fixedSize(horizontal:false,vertical:true)
 }

 var body: some View {
  HStack(alignment:.top,spacing:10) {
   macTile
   networkTile
   devicesTile
   operationsTile
  }
 }

 var macTile: some View {
  let counts = CoreFacts.summarize(guardHub.results)
  let light: Color = guardHub.locked ? HubTheme.amber : (guardHub.results.isEmpty ? HubTheme.subtext : (counts.warn > 0 ? HubTheme.amber : HubTheme.green))
  return tile("THIS MAC",light) {
   line("macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion) · \(Int(CoreFacts.memoryGB().rounded())) GB memory")
   line("up \(CoreFacts.uptimeText(ProcessInfo.processInfo.systemUptime))" + (CoreFacts.freeDiskGB().map { " · \(Int($0.rounded())) GB free" } ?? ""),true)
   if guardHub.locked {
    line("Lockdown is ON (checks paused)",true)
   } else if let at = guardHub.lastChecked, !guardHub.results.isEmpty {
    line("\(counts.ok) ok · \(counts.warn) need a look · \(counts.unknown) unknown",counts.warn == 0)
    Text("Guard checked \(ago(at))").font(DeckMono.font(9.5)).foregroundStyle(HubTheme.subtext)
   } else {
    line("Guard hasn't checked yet",true)
   }
   Button { Task { await guardHub.runChecks() } } label: {
    Text(guardHub.checking ? "checking…" : "run checks ›").font(DeckMono.font(10.5)).foregroundStyle(HubTheme.teal)
   }
   .buttonStyle(.plain).disabled(guardHub.checking || guardHub.locked)
  }
 }

 var networkTile: some View {
  let apps = guardHub.network
  let fresh = apps.filter { $0.isNew }.count
  return tile("NETWORK",guardHub.offline ? HubTheme.amber : (apps.isEmpty ? HubTheme.subtext : HubTheme.green)) {
   if guardHub.offline {
    line("Offline mode is ON: The Helm makes no internet calls of its own")
   } else if apps.isEmpty {
    line("not read yet: run checks",true)
   } else {
    line("\(apps.count) apps using the internet" + (fresh > 0 ? " · \(fresh) new" : ""),fresh == 0)
    Text(apps.sorted { $0.connections > $1.connections }.prefix(3).map { "\($0.name) \($0.connections)" }.joined(separator:" · "))
     .font(DeckMono.font(9.5)).foregroundStyle(HubTheme.subtext).lineLimit(2)
    if let at = guardHub.lastChecked { Text("as of \(ago(at))").font(DeckMono.font(9.5)).foregroundStyle(HubTheme.subtext) }
   }
  }
 }

 var devicesTile: some View {
  tile("DEVICES",HubTheme.green) {
   line("1 · this Mac")
   line("Other devices you own (an old phone, a tablet) get added here in step 2, by you, by hand.",true)
  }
 }

 var operationsTile: some View {
  let failing = (runs ?? []).filter { $0.isFailing }.count
  let running = (runs ?? []).filter { $0.isRunning }.count
  let light: Color = failing > 0 ? Color(red:0.95,green:0.40,blue:0.40) : (runs == nil ? HubTheme.subtext : HubTheme.green)
  return tile("OPERATIONS",light) {
   if let job = switchboard.runningJob {
    line("job #\(job) running" + (switchboard.runningSince.map { " since \(ago($0))" } ?? ""))
   } else {
    line(switchboard.on ? "Switchboard ON · no job running" : "Switchboard OFF",true)
   }
   if let runs { line("\(runs.count) automations · \(running) running · \(failing) failing",failing == 0) } else { line("automations not read yet",true) }
   line(robotsFailed ? "robot snapshots unavailable" : "\(robotsLoaded) of 7 practice robots loaded",!robotsFailed)
  }
 }
}
