import SwiftUI
import AppKit
import Darwin

// Command Core › Systems (Friday, 2026-11-06). Matthew's reference photos: ring gauges for CPU, memory and storage, a live activity graph, system info,
// top processes, diagnostics. EVERY number here is measured on this Mac right now: CPU from the kernel's tick counters, memory from its page counts,
// storage from the file system, processes from `ps` (a fixed, read-only command), diagnostics from Guard's own read-only checks. Nothing is
// invented: before the first reading it says "reading…", and the graph only draws samples that were actually taken (every 2 seconds while this
// page is open; it stops when you leave).

struct SysProc: Identifiable { var id: String; var name: String; var cpu: Double; var mem: Double }

@MainActor final class SystemMonitor: ObservableObject {
 static let shared = SystemMonitor()
 @Published private(set) var cpu: Double?
 @Published private(set) var memUsedGB: Double?
 @Published private(set) var cpuHistory: [Double] = []
 @Published private(set) var memHistory: [Double] = []
 @Published private(set) var procs: [SysProc] = []
 @Published private(set) var sampledAt: Date?
 private var last: (user: UInt64,system: UInt64,idle: UInt64,nice: UInt64)?
 private var timer: Timer?
 private var tick = 0
 static let keep = 60

 func start() {
  guard timer == nil else { return }
  sample()
  timer = Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in Task { @MainActor in self?.sample() } }
 }
 func stop() { timer?.invalidate(); timer = nil; last = nil }

 private func sample() {
  var info = host_cpu_load_info()
  var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
  let r = withUnsafeMutablePointer(to:&info) { $0.withMemoryRebound(to:integer_t.self,capacity:Int(count)) { host_statistics(mach_host_self(),HOST_CPU_LOAD_INFO,$0,&count) } }
  if r == KERN_SUCCESS {
   let now = (user:UInt64(info.cpu_ticks.0),system:UInt64(info.cpu_ticks.1),idle:UInt64(info.cpu_ticks.2),nice:UInt64(info.cpu_ticks.3))
   if let l = last {
    let busy = Double((now.user - l.user) + (now.system - l.system) + (now.nice - l.nice))
    let total = busy + Double(now.idle - l.idle)
    if total > 0 { cpu = busy / total; cpuHistory = Array((cpuHistory + [busy / total]).suffix(Self.keep)) }
   }
   last = now
  }
  var vm = vm_statistics64()
  var vcount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
  let vr = withUnsafeMutablePointer(to:&vm) { $0.withMemoryRebound(to:integer_t.self,capacity:Int(vcount)) { host_statistics64(mach_host_self(),HOST_VM_INFO64,$0,&vcount) } }
  if vr == KERN_SUCCESS {
   let page = Double(getpagesize())
   let used = (Double(vm.internal_page_count) - Double(vm.purgeable_count) + Double(vm.wire_count) + Double(vm.compressor_page_count)) * page
   memUsedGB = used / 1_073_741_824
   memHistory = Array((memHistory + [used / Double(ProcessInfo.processInfo.physicalMemory)]).suffix(Self.keep))
  }
  sampledAt = Date()
  if tick % 3 == 0 { refreshProcs() }
  tick += 1
 }

 private func refreshProcs() {
  Task.detached {
   let p = Process()
   p.executableURL = URL(fileURLWithPath:"/bin/ps")
   p.arguments = ["-Ao","pcpu=,pmem=,comm=","-r"]
   let pipe = Pipe()
   p.standardOutput = pipe
   p.standardError = FileHandle.nullDevice
   guard (try? p.run()) != nil else { return }
   let data = pipe.fileHandleForReading.readDataToEndOfFile()
   p.waitUntilExit()
   var out: [SysProc] = []
   for line in String(decoding:data,as:UTF8.self).split(separator:"\n").prefix(40) {
    let parts = line.split(separator:" ",maxSplits:2,omittingEmptySubsequences:true)
    guard parts.count == 3, let c = Double(parts[0]), let m = Double(parts[1]) else { continue }
    let name = URL(fileURLWithPath:String(parts[2]).trimmingCharacters(in:.whitespaces)).lastPathComponent
    if name == "ps" { continue }
    out.append(SysProc(id:"\(name)-\(out.count)",name:name,cpu:c,mem:m))
    if out.count == 5 { break }
   }
   await MainActor.run { SystemMonitor.shared.procs = out }
  }
 }
}

enum SysFacts {
 static func string(_ name: String) -> String? {
  var size = 0
  guard sysctlbyname(name,nil,&size,nil,0) == 0, size > 0 else { return nil }
  var buf = [CChar](repeating:0,count:size)
  guard sysctlbyname(name,&buf,&size,nil,0) == 0 else { return nil }
  return String(cString:buf)
 }
 static func totalDiskGB() -> Double? {
  guard let v = try? URL(fileURLWithPath:"/").resourceValues(forKeys:[.volumeTotalCapacityKey]), let t = v.volumeTotalCapacity else { return nil }
  return Double(t) / 1_000_000_000
 }
}

extension CompanionInterfaceView {
 func systemsObservations() -> [CoreObservation] {
  let m = SystemMonitor.shared
  var out: [CoreObservation] = []
  let when = m.sampledAt.map { "measured \(coreAgo($0))" } ?? "measuring"
  if let c = m.cpu, c > 0.8 {
   out.append(CoreObservation(tone:2,text:"CPU is busy: \(Int((c * 100).rounded()))% in use.",why:(m.procs.first.map { "The busiest process is \($0.name). " } ?? "") + "If this isn't expected, close what you don't need.",source:"kernel CPU counters, \(when)"))
  }
  if let used = m.memUsedGB {
   let total = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
   if used / total > 0.85 { out.append(CoreObservation(tone:2,text:"Memory is nearly full: \(String(format:"%.1f",used)) of \(Int(total.rounded())) GB.",why:"On an 8 GB Mac this slows everything down. Quit apps you aren't using.",source:"kernel memory counters, \(when)")) }
  }
  if let free = CoreFacts.freeDiskGB(), let total = SysFacts.totalDiskGB(), free / total < 0.10 {
   out.append(CoreObservation(tone:2,text:"Storage is almost full: \(Int(free.rounded())) GB free.",why:"Under 10% free can slow the Mac and break updates.",source:"file system, now"))
  }
  if m.cpu == nil { out.append(CoreObservation(tone:0,text:"Still taking the first readings.",why:"CPU needs two readings, 2 seconds apart.",source:"measuring")) }
  if out.isEmpty, m.cpu != nil {
   out.append(CoreObservation(tone:1,text:"This Mac is running comfortably.",why:"CPU, memory and storage are all in a normal range.",source:"kernel counters and file system, \(when)"))
  }
  return out
 }

 var commandCoreSystems: some View {
  coreFrame("Systems","Measured on this Mac right now · CPU, memory, storage, processes",observations:systemsObservations(),
            content:AnyView(CoreSystemsView(monitor:SystemMonitor.shared,guardHub:GuardHub.shared,runs:ventures.runs,runsFailed:ventures.failed)))
 }
}

struct CoreSystemsView: View {
 @ObservedObject var monitor: SystemMonitor
 @ObservedObject var guardHub: GuardHub
 var runs: [AutomationRun]?
 var runsFailed: Bool

 private func card<C: View>(_ title: String,@ViewBuilder _ content: () -> C) -> some View {
  CoreCard(title:coreTitle(title)) { content() }
 }

 private func ring(_ title: String,_ value: Double?,_ big: String,_ small: String) -> some View {
  card(title) {
   ZStack {
    Circle().stroke(Color.white.opacity(0.07),lineWidth:6)
    Circle().trim(from:0,to:CGFloat(min(1,max(0,value ?? 0)))).stroke(LinearGradient(colors:[CoreStyle.teal,CoreStyle.emerald],startPoint:.leading,endPoint:.trailing),style:StrokeStyle(lineWidth:6,lineCap:.round))
     .rotationEffect(.degrees(-90)).animation(.easeOut(duration:0.6),value:value)
    VStack(spacing:1) {
     Text(big).font(.system(size:22,weight:.light,design:.rounded)).foregroundStyle(CoreStyle.ink)
     Text(small).font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
    }
   }
   .frame(width:112,height:112).frame(maxWidth:.infinity)
  }
 }

 var body: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:14) {
    HStack(alignment:.top,spacing:14) {
     ring("CPU",monitor.cpu,monitor.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "…",monitor.cpu == nil ? "reading…" : "in use")
     ring("MEMORY",monitor.memUsedGB.map { $0 / (Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824) },
          monitor.memUsedGB.map { String(format:"%.1f GB",$0) } ?? "…",
          "of \(Int(CoreFacts.memoryGB().rounded())) GB")
     ring("STORAGE",SysFacts.totalDiskGB().flatMap { t in CoreFacts.freeDiskGB().map { 1 - $0 / t } },
          CoreFacts.freeDiskGB().map { "\(Int($0.rounded())) GB" } ?? "…","free")
    }
    card("ACTIVITY · LAST \(monitor.cpuHistory.count * 2) SECONDS") {
     Canvas { ctx, size in
      for g in 1..<4 { var l = Path(); l.move(to:CGPoint(x:0,y:size.height * CGFloat(g) / 4)); l.addLine(to:CGPoint(x:size.width,y:size.height * CGFloat(g) / 4)); ctx.stroke(l,with:.color(Color.white.opacity(0.05)),lineWidth:1) }
      func line(_ data: [Double],_ color: Color) {
       guard data.count > 1 else { return }
       var p = Path()
       for (i,v) in data.enumerated() {
        let pt = CGPoint(x:size.width * CGFloat(i) / CGFloat(SystemMonitor.keep - 1),y:size.height * (1 - CGFloat(min(1,max(0,v)))))
        i == 0 ? p.move(to:pt) : p.addLine(to:pt)
       }
       ctx.stroke(p,with:.color(color),style:StrokeStyle(lineWidth:1.6,lineCap:.round,lineJoin:.round))
      }
      line(monitor.memHistory,CoreStyle.teal)
      line(monitor.cpuHistory,CoreStyle.emerald)
     }
     .frame(height:90)
     HStack(spacing:14) {
      Label("CPU",systemImage:"circle.fill").font(.system(size:10,design:.rounded)).foregroundStyle(CoreStyle.emerald)
      Label("Memory",systemImage:"circle.fill").font(.system(size:10,design:.rounded)).foregroundStyle(CoreStyle.teal)
      Spacer()
      Text(monitor.cpuHistory.count < 2 ? "collecting readings…" : "one reading every 2 seconds").font(.system(size:10,design:.rounded)).foregroundStyle(CoreStyle.dim)
     }
    }
    HStack(alignment:.top,spacing:14) {
     card("SYSTEM INFO") {
      infoRow("Chip",SysFacts.string("machdep.cpu.brand_string") ?? "unknown")
      infoRow("Model",SysFacts.string("hw.model") ?? "unknown")
      infoRow("macOS","\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)")
      infoRow("Memory","\(Int(CoreFacts.memoryGB().rounded())) GB")
      infoRow("Up for",CoreFacts.uptimeText(ProcessInfo.processInfo.systemUptime))
     }
     card("TOP PROCESSES") {
      if monitor.procs.isEmpty { Text("reading…").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim) }
      ForEach(monitor.procs) { p in
       HStack {
        Text(p.name).font(.system(size:13,design:.rounded)).foregroundStyle(CoreStyle.ink).lineLimit(1)
        Spacer(minLength:6)
        Text(String(format:"%.1f%% cpu",p.cpu)).font(.system(size:12.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.emerald)
       }
      }
     }
     card("DIAGNOSTICS · GUARD'S CHECKS") {
      if guardHub.results.isEmpty { Text("not checked yet").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim) }
      ForEach(Array(guardHub.results.enumerated()),id:\.offset) { _,r in
       HStack(spacing:6) {
        Circle().fill(r.verdict == .ok ? CoreStyle.emerald : (r.verdict == .warn ? CoreStyle.amber : CoreStyle.dim)).frame(width:6,height:6)
        Text(r.title).font(.system(size:12.5,design:.rounded)).foregroundStyle(CoreStyle.ink).lineLimit(1)
        Spacer(minLength:4)
        Text(r.verdict == .ok ? "ok" : (r.verdict == .warn ? "look" : "?")).font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
       }
      }
      Button { Task { await guardHub.runChecks() } } label: {
       Text(guardHub.checking ? "checking…" : "Run checks").font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.teal)
        .padding(.horizontal,11).padding(.vertical,5).overlay(Capsule().stroke(CoreStyle.teal.opacity(0.6),lineWidth:1))
      }
      .buttonStyle(.plain).disabled(guardHub.checking || guardHub.locked)
     }
    }
    card("AUTOMATIONS · GITHUB") {
     if let runs {
      Text("\(runs.count) seen · \(runs.filter { $0.isRunning }.count) running · \(runs.filter { $0.isFailing }.count) failing")
       .font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.ink)
      ForEach(runs.filter { $0.isFailing || $0.isRunning }.prefix(6)) { r in
       HStack(spacing:6) {
        Circle().fill(r.isFailing ? CoreStyle.crimson : CoreStyle.emerald).frame(width:6,height:6)
        Text(r.name).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.ink).lineLimit(1)
        Spacer(minLength:4)
        Text(r.isFailing ? "failing" : "running").font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
       }
      }
     } else {
      Text(runsFailed ? "couldn't read GitHub's automation status" : "not read yet").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim)
     }
    }
   }
   .padding(.horizontal,22).padding(.vertical,4)
  }
  .onAppear { monitor.start() }
  .onDisappear { monitor.stop() }
 }

 private func infoRow(_ k: String,_ v: String) -> some View {
  HStack(alignment:.firstTextBaseline) {
   Text(k).font(.system(size:12.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
   Spacer(minLength:6)
   Text(v).font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink).lineLimit(1)
  }
 }
}
