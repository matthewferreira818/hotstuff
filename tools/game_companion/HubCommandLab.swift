import SwiftUI
import AppKit

// Command Core › Cyber Lab (Friday, 2026-11-06; Matthew's brief: device workspace, connected phones, tools like Nmap/Wireshark/ZAP/Kali, learning
// resources, experiment history, Friday contextual; later Linux, Windows, Android and iOS as well as macOS).
// Rules baked in:
//  - DEVICES are listed by YOU. This Mac is automatic. Every other device is "added by you", with an ownership tick, and says plainly that nothing
//    is probing it until a connector for its platform exists. (Each platform has its own connector slot; nothing Mac-only is built into the list.)
//  - TOOLS are only reported installed if the app or program was actually found on this Mac. Nothing is installed or downloaded by this tab.
//  - The ONE active tool is Nmap's quick port check, and only against a device you added, ticked as yours, with a private-network address
//    (ScopeRules, tested), after a confirmation box. Its result goes into the experiment history with the time.
//  - CONNECTED PHONES: "Look for USB devices" runs macOS's own read-only system_profiler and lists what it reports. Nothing is read from a phone.
//  - History, device list and notes stay in this Mac's Application Support folder (never in Git).

enum LabPlatform: String, Codable, CaseIterable, Identifiable {
 case macOS, linux, windows, android, iOS, other
 var id: String { rawValue }
 var label: String { switch self { case .macOS: return "macOS"; case .linux: return "Linux (Kali, Ubuntu…)"; case .windows: return "Windows"; case .android: return "Android"; case .iOS: return "iPhone / iPad"; case .other: return "Other" } }
 var symbol: String { switch self { case .macOS: return "laptopcomputer"; case .linux: return "terminal"; case .windows: return "pc"; case .android: return "smartphone"; case .iOS: return "iphone"; case .other: return "cpu" } }
 // The connector slot for each platform (design only for now; macOS is the only one wired).
 var connector: String {
  switch self {
  case .macOS: return "built in (this Mac)"
  case .linux: return "planned: SSH, with your key, to a machine you own"
  case .windows: return "planned: SSH or remote management, to a machine you own"
  case .android: return "planned: Android's own debug bridge over a cable"
  case .iOS: return "planned: Apple's own device tools over a cable"
  case .other: return "none yet"
  }
 }
}

struct LabDevice: Codable, Identifiable, Equatable {
 var id: String
 var name: String
 var platform: LabPlatform
 var address: String        // optional: a private-network address, for the Nmap check
 var notes: String
 var owned: Bool            // Matthew ticked "this is mine"
 var added: Date
}

struct LabExperiment: Codable, Identifiable, Equatable {
 var id: String
 var at: Date
 var device: String
 var tool: String
 var summary: String
 var output: String
}

struct LabTool: Identifiable {
 var id: String
 var name: String
 var role: String
 var installed: Bool
 var detail: String
 var appPath: String?       // opened with Open when installed
 var infoURL: String
}

// The scope rule for the active check. Pure logic, tested in checks.
enum ScopeRules {
 static func privateIPv4(_ s: String) -> Bool {
  let p = s.split(separator:".").compactMap { Int($0) }
  guard p.count == 4, p.allSatisfy({ (0...255).contains($0) }), s.split(separator:".").count == 4 else { return false }
  if p[0] == 10 { return true }
  if p[0] == 192 && p[1] == 168 { return true }
  if p[0] == 172 && (16...31).contains(p[1]) { return true }
  return false
 }
 // Returns nil when allowed, or the plain reason it is not.
 static func refusal(for device: LabDevice) -> String? {
  if !device.owned { return "This device isn't ticked as yours." }
  if device.address.isEmpty { return "This device has no address saved." }
  if !privateIPv4(device.address) { return "Only private home-network addresses (10.x, 172.16-31.x, 192.168.x) are allowed." }
  return nil
 }
}

@MainActor final class LabStore: ObservableObject {
 static let shared = LabStore()
 @Published private(set) var devices: [LabDevice] = []
 @Published private(set) var experiments: [LabExperiment] = []
 @Published private(set) var tools: [LabTool] = []
 @Published private(set) var usb: [String]?
 @Published private(set) var usbAt: Date?
 @Published private(set) var usbFailed = false
 @Published var running = false
 @Published var note = ""

 private let folder: URL = {
  let base = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("GameCompanion/CommandCore",isDirectory:true)
  try? FileManager.default.createDirectory(at:base,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
  return base
 }()
 private var devicesURL: URL { folder.appendingPathComponent("devices.json") }
 private var experimentsURL: URL { folder.appendingPathComponent("experiments.json") }

 init() {
  let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
  if let d = try? Data(contentsOf:devicesURL), let v = try? dec.decode([LabDevice].self,from:d) { devices = v }
  if let d = try? Data(contentsOf:experimentsURL), let v = try? dec.decode([LabExperiment].self,from:d) { experiments = v }
  detectTools()
 }

 private func save() {
  let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
  if let d = try? enc.encode(devices) { try? d.write(to:devicesURL,options:.atomic) }
  if let d = try? enc.encode(Array(experiments.suffix(200))) { try? d.write(to:experimentsURL,options:.atomic) }
 }

 func add(name: String,platform: LabPlatform,address: String,notes: String,owned: Bool) {
  let n = name.trimmingCharacters(in:.whitespacesAndNewlines)
  guard !n.isEmpty else { return }
  devices.append(LabDevice(id:UUID().uuidString,name:n,platform:platform,address:address.trimmingCharacters(in:.whitespaces),notes:notes,owned:owned,added:Date()))
  save()
 }
 func remove(_ id: String) { devices.removeAll { $0.id == id }; save() }
 func log(device: String,tool: String,summary: String,output: String = "") {
  experiments.append(LabExperiment(id:UUID().uuidString,at:Date(),device:device,tool:tool,summary:summary,output:String(output.prefix(2500))))
  save()
 }

 // MARK: tools actually found on this Mac

 func detectTools() {
  let fm = FileManager.default
  func firstApp(_ names: [String]) -> String? {
   for dir in ["/Applications",fm.homeDirectoryForCurrentUser.path + "/Applications"] {
    guard let items = try? fm.contentsOfDirectory(atPath:dir) else { continue }
    for item in items where item.hasSuffix(".app") { if names.contains(where:{ item.lowercased().hasPrefix($0) }) { return dir + "/" + item } }
   }
   return nil
  }
  let nmap = ["/opt/homebrew/bin/nmap","/usr/local/bin/nmap","/usr/bin/nmap"].first { fm.isExecutableFile(atPath:$0) }
  let wire = firstApp(["wireshark"])
  let zap = firstApp(["zap","owasp zap"])
  let vm = firstApp(["utm","parallels","vmware","virtualbox"])
  tools = [
   LabTool(id:"nmap",name:"Nmap",role:"network and port checker",installed:nmap != nil,detail:nmap ?? "not found on this Mac (free; installing it is your call)",appPath:nil,infoURL:"https://nmap.org"),
   LabTool(id:"wireshark",name:"Wireshark",role:"network traffic viewer",installed:wire != nil,detail:wire ?? "not found on this Mac (free)",appPath:wire,infoURL:"https://www.wireshark.org"),
   LabTool(id:"zap",name:"OWASP ZAP",role:"web app security tester",installed:zap != nil,detail:zap ?? "not found on this Mac (free)",appPath:zap,infoURL:"https://www.zaproxy.org"),
   LabTool(id:"kali",name:"Kali Linux",role:"security lab OS, runs in a virtual machine",installed:vm != nil,detail:vm.map { "a VM app is installed (\(URL(fileURLWithPath:$0).lastPathComponent)); I can't see whether you have a Kali image" } ?? "no VM app found (UTM is free; an 8 GB Mac runs one small VM at a time)",appPath:vm,infoURL:"https://www.kali.org"),
  ]
 }

 // MARK: connected phones: macOS's own read-only USB report

 func scanUSB() {
  guard !running else { return }
  running = true; usbFailed = false
  Task.detached {
   let p = Process()
   p.executableURL = URL(fileURLWithPath:"/usr/sbin/system_profiler")
   p.arguments = ["SPUSBDataType","-json"]
   let pipe = Pipe(); p.standardOutput = pipe; p.standardError = FileHandle.nullDevice
   var names: [String]? = nil
   if (try? p.run()) != nil {
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); p.waitUntilExit()
    if let obj = try? JSONSerialization.jsonObject(with:data) as? [String:Any], let buses = obj["SPUSBDataType"] as? [[String:Any]] {
     var out: [String] = []
     func walk(_ items: [[String:Any]]) {
      for i in items {
       if let n = i["_name"] as? String, i["vendor_id"] != nil || i["product_id"] != nil { out.append(n + ((i["manufacturer"] as? String).map { " (\($0))" } ?? "")) }
       if let sub = i["_items"] as? [[String:Any]] { walk(sub) }
      }
     }
     for b in buses { if let sub = b["_items"] as? [[String:Any]] { walk(sub) } }
     names = out
    }
   }
   await MainActor.run { LabStore.shared.usb = names; LabStore.shared.usbAt = Date(); LabStore.shared.usbFailed = names == nil; LabStore.shared.running = false }
  }
 }

 // MARK: the one active check: Nmap quick port look, owned devices on the private network only

 func nmapCheck(_ device: LabDevice) {
  guard !running else { return }
  if let why = ScopeRules.refusal(for:device) { note = "Not run: \(why)"; return }
  guard let exe = tools.first(where:{ $0.id == "nmap" && $0.installed })?.detail else { note = "Not run: Nmap isn't installed."; return }
  let alert = NSAlert()
  alert.messageText = "Check open ports on \(device.name)?"
  alert.informativeText = "Nmap will look at the most common ports on \(device.address). Only do this on a device you own, on your own network. The result goes into your experiment history."
  alert.addButton(withTitle:"Run the check"); alert.addButton(withTitle:"Cancel")
  guard alert.runModal() == .alertFirstButtonReturn else { note = "Cancelled. Nothing was run."; return }
  running = true; note = "Running… (up to a minute)"
  let address = device.address, name = device.name
  Task.detached {
   let p = Process()
   p.executableURL = URL(fileURLWithPath:exe)
   p.arguments = ["-Pn","-F","--max-retries","1","--host-timeout","50s",address]
   let pipe = Pipe(); p.standardOutput = pipe; p.standardError = pipe
   var text = ""
   if (try? p.run()) != nil { text = String(decoding:pipe.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self); p.waitUntilExit() } else { text = "Nmap couldn't start." }
   let open = text.split(separator:"\n").filter { $0.contains("/tcp") && $0.contains("open") }.count
   await MainActor.run {
    LabStore.shared.log(device:name,tool:"Nmap quick check",summary:"\(open) open port\(open == 1 ? "" : "s") on \(address)",output:text)
    LabStore.shared.running = false; LabStore.shared.note = "Done: \(open) open port\(open == 1 ? "" : "s"). Saved to history."
   }
  }
 }
}

@MainActor final class LabUI: ObservableObject {
 static let shared = LabUI()
 @Published var selected: String = "this-mac"
 @Published var adding = false
 @Published var name = ""
 @Published var platform: LabPlatform = .iOS
 @Published var address = ""
 @Published var notes = ""
 @Published var owned = false
 @Published var openExperiment: String?
}

// Research notes for the lab: plain text, this Mac only.
@MainActor final class LabNotes: ObservableObject {
 static let shared = LabNotes()
 private let url = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("GameCompanion/CommandCore/research-notes.txt")
 @Published var text: String { didSet { try? text.write(to:url,atomically:true,encoding:.utf8) } }
 init() { text = (try? String(contentsOf:FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("GameCompanion/CommandCore/research-notes.txt"),encoding:.utf8)) ?? "" }
}

// Cyber Lab, redesigned after Matthew's notes ("keep the engineering, redesign the cockpit"): device library left, the selected device drawn in the
// centre with its real readings around it, a compact Tool Vault right, small Experiments / Learn / Research panels underneath.
// The drawing is a picture of the KIND of device; every word and number on and around it is a real reading or says plainly that it isn't connected.
struct CoreLabView: View {
 @ObservedObject var store: LabStore
 @ObservedObject var ui = LabUI.shared
 @ObservedObject var monitor = SystemMonitor.shared
 @ObservedObject var notes = LabNotes.shared
 @ObservedObject var guardHub = GuardHub.shared
 var macFacts: [(String,String)]
 var askFriday: (String) -> Void

 private func pill(_ text: String,_ color: Color = CoreStyle.teal,_ action: @escaping () -> Void) -> some View {
  Button(action:action) { Text(text).font(.system(size:11.5,weight:.medium,design:.rounded)).foregroundStyle(color).padding(.horizontal,10).padding(.vertical,4).overlay(Capsule().stroke(color.opacity(0.55),lineWidth:1)) }.buttonStyle(.plain)
 }
 private func ago(_ d: Date) -> String { let s = Int(Date().timeIntervalSince(d)); return s < 90 ? "just now" : (s < 3600 ? "\(s / 60) min ago" : (s < 86400 ? "\(s / 3600) h ago" : "\(s / 86400) d ago")) }
 var selectedDevice: LabDevice? { store.devices.first { $0.id == ui.selected } }

 var body: some View {
  GeometryReader { geo in
   let wide = geo.size.width > 1100
   VStack(spacing:10) {
    HStack(alignment:.top,spacing:10) {
     library.frame(width:wide ? 220 : 190)
     workspace.frame(maxWidth:.infinity)
     vault.frame(width:wide ? 300 : 250)
    }
    .frame(maxHeight:.infinity)
    HStack(alignment:.top,spacing:10) {
     experiments
     learning
     research
    }
    .frame(height:wide ? 170 : 150)
   }
   .padding(.horizontal,22).padding(.top,2).padding(.bottom,8)
  }
  .onAppear { monitor.start() }
  .onDisappear { monitor.stop() }
 }

 // MARK: device library

 var library: some View {
  CoreCard(title:"Devices",icon:"square.stack.3d.up") {
   ScrollView {
    VStack(spacing:6) {
     deviceRow(id:"this-mac",name:"This Mac",sub:"connected · local",symbol:"laptopcomputer",dot:CoreStyle.emerald)
     ForEach(store.devices) { d in deviceRow(id:d.id,name:d.name,sub:"record only · \(d.platform.rawValue)",symbol:d.platform.symbol,dot:Color.white.opacity(0.3)) }
     if let usb = store.usb, !usb.isEmpty {
      Text("ON USB NOW").font(.system(size:10,weight:.semibold,design:.rounded)).tracking(1.2).foregroundStyle(CoreStyle.dim).frame(maxWidth:.infinity,alignment:.leading).padding(.top,4)
      ForEach(Array(usb.prefix(4).enumerated()),id:\.offset) { _,n in
       HStack(spacing:7) { Image(systemName:"cable.connector").font(.system(size:11)).foregroundStyle(CoreStyle.teal); Text(n).font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.85)).lineLimit(1); Spacer(minLength:0) }
      }
     }
     if ui.adding { addForm } else {
      HStack { pill("+ Add device") { ui.adding = true }; pill(store.running ? "…" : "USB") { store.scanUSB() }.disabled(store.running); Spacer(minLength:0) }.padding(.top,4)
     }
    }
   }
  }
 }

 var addForm: some View {
  VStack(alignment:.leading,spacing:5) {
   TextField("Name",text:$ui.name).textFieldStyle(.roundedBorder).font(.system(size:12))
   Picker("",selection:$ui.platform) { ForEach(LabPlatform.allCases) { Text($0.label).tag($0) } }.labelsHidden().font(.system(size:12))
   TextField("Private address (optional)",text:$ui.address).textFieldStyle(.roundedBorder).font(.system(size:12))
   TextField("Notes",text:$ui.notes).textFieldStyle(.roundedBorder).font(.system(size:12))
   Toggle("This device is mine",isOn:$ui.owned).font(.system(size:11.5,design:.rounded)).toggleStyle(.checkbox)
   HStack {
    pill("Add") { store.add(name:ui.name,platform:ui.platform,address:ui.address,notes:ui.notes,owned:ui.owned); ui.name = ""; ui.address = ""; ui.notes = ""; ui.owned = false; ui.adding = false }
    pill("Cancel",CoreStyle.dim) { ui.adding = false }
   }
  }
  .padding(.top,4)
 }

 func deviceRow(id: String,name: String,sub: String,symbol: String,dot: Color) -> some View {
  let on = ui.selected == id
  return Button { withAnimation(.easeOut(duration:0.2)) { ui.selected = id } } label: {
   HStack(spacing:9) {
    Image(systemName:symbol).font(.system(size:14)).foregroundStyle(on ? Color.white : CoreStyle.ink.opacity(0.7)).frame(width:20)
    VStack(alignment:.leading,spacing:1) {
     Text(name).font(.system(size:12.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink).lineLimit(1)
     Text(sub).font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(1)
    }
    Spacer(minLength:4)
    Circle().fill(dot).frame(width:6,height:6)
   }
   .padding(.horizontal,8).padding(.vertical,7).frame(maxWidth:.infinity,alignment:.leading)
   .background(RoundedRectangle(cornerRadius:8).fill(on ? Color.white.opacity(0.06) : Color.clear))
   .overlay(alignment:.leading) { if on { RoundedRectangle(cornerRadius:1).fill(CoreStyle.crimson).frame(width:2).padding(.vertical,6) } }
   .contentShape(Rectangle())
  }.buttonStyle(.plain)
 }

 // MARK: the device workspace

 var workspace: some View {
  let isMac = ui.selected == "this-mac"
  let d = selectedDevice
  let platform: LabPlatform = isMac ? .macOS : (d?.platform ?? .other)
  return VStack(spacing:10) {
   HStack(alignment:.firstTextBaseline) {
    VStack(alignment:.leading,spacing:2) {
     HStack(spacing:6) {
      Circle().fill(isMac ? CoreStyle.emerald : Color.white.opacity(0.3)).frame(width:6,height:6)
      Text(isMac ? "Connected · readings are live" : "Not connected · a record you added · \(platform.connector)").font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(1)
     }
    }
    Spacer()
    Button { askFriday(isMac ? "Look at this Mac's readings in Command Core and tell me anything worth doing." : "Explain how we could safely look at my \(platform.label) device (\(d?.name ?? "")) and what Command Core would need.") } label: {
     Label("Ask Friday about this",systemImage:"sparkles").font(.system(size:11.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.teal)
    }.buttonStyle(.plain)
   }
   GeometryReader { g in
    let side = min(g.size.width * 0.55,g.size.height * 0.62)
    VStack(spacing:10) {
     Spacer(minLength:0)
     deviceArt(platform:platform,isMac:isMac,size:side)
     HStack(spacing:8) {
      Text(isMac ? "This Mac" : (d?.name ?? "Device")).font(.system(size:16,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink)
      Text(isMac ? "Active" : "Record only").font(.system(size:10.5,weight:.medium,design:.rounded)).foregroundStyle(isMac ? CoreStyle.emerald : CoreStyle.dim)
       .padding(.horizontal,8).padding(.vertical,2).overlay(Capsule().stroke((isMac ? CoreStyle.emerald : CoreStyle.dim).opacity(0.6),lineWidth:1))
     }
     Text(factLine(isMac:isMac,d:d)).font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(1)
     if isMac {
      HStack(spacing:8) { ForEach(rightFacts(isMac:true,d:nil),id:\.0) { f in miniStat(f.0,f.1,f.2) } }
     }
     HStack(spacing:8) { ForEach(store.tools) { t in toolChip(t) } }
     Spacer(minLength:0)
    }
    .frame(width:g.size.width,height:g.size.height)
   }
   HStack(spacing:8) {
    if isMac {
     pill(guardHub.checking ? "checking…" : "Run Mac checks") { Task { await guardHub.runChecks() } }.disabled(guardHub.checking || guardHub.locked)
     pill(store.running ? "looking…" : "Look for USB devices") { store.scanUSB() }.disabled(store.running)
    } else if let d {
     pill(store.running ? "running…" : "Nmap quick port check") { store.nmapCheck(d) }.disabled(store.running || ScopeRules.refusal(for:d) != nil)
     pill("Remove",CoreStyle.crimson) { let id = d.id; ui.selected = "this-mac"; store.remove(id) }
     if let why = ScopeRules.refusal(for:d) { Text("Port check off: \(why)").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(1) }
    }
    Spacer(minLength:0)
    if !store.note.isEmpty { Text(store.note).font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.teal).lineLimit(1) }
   }
  }
  .padding(13).frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.top)
  .background(RoundedRectangle(cornerRadius:11).fill(HubTheme.hex(0x0E0E11)))
  .overlay(RoundedRectangle(cornerRadius:11).stroke(Color.white.opacity(0.065),lineWidth:1))
 }

 func factLine(isMac: Bool,d: LabDevice?) -> String {
  if isMac {
   let os = macFacts.first { $0.0 == "macOS" }.map { "macOS " + $0.1 } ?? "macOS"
   let chip = macFacts.first { $0.0 == "Chip" }?.1 ?? ""
   let mem = macFacts.first { $0.0 == "Memory" }?.1 ?? ""
   return [os,chip,mem.isEmpty ? "" : mem + " RAM",CoreFacts.freeDiskGB().map { "\(Int($0.rounded())) GB free" } ?? ""].filter { !$0.isEmpty }.joined(separator:" · ")
  }
  guard let d else { return "" }
  return [d.platform.label,d.owned ? "yours" : "ownership not ticked",d.address.isEmpty ? "" : d.address,"not connected"].filter { !$0.isEmpty }.joined(separator:" · ")
 }

 func miniStat(_ k: String,_ v: String,_ tone: Int) -> some View {
  VStack(spacing:1) {
   Text(v).font(.system(size:12.5,weight:.medium,design:.rounded)).foregroundStyle(tone == 1 ? CoreStyle.emerald : (tone == 2 ? CoreStyle.amber : CoreStyle.ink)).lineLimit(1)
   Text(k).font(.system(size:10,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(1)
  }
  .padding(.horizontal,10).padding(.vertical,5)
  .background(RoundedRectangle(cornerRadius:7).fill(Color.white.opacity(0.03)))
  .overlay(RoundedRectangle(cornerRadius:7).stroke(Color.white.opacity(0.05),lineWidth:1))
 }

 // Small tool tiles under the device (reference). Status is what was found on this Mac.
 func toolChip(_ t: LabTool) -> some View {
  let icon = ["nmap":"dot.radiowaves.left.and.right","wireshark":"waveform.path","zap":"bolt.shield","kali":"terminal"][t.id] ?? "wrench.and.screwdriver"
  return Button { if t.installed, let path = t.appPath { NSWorkspace.shared.open(URL(fileURLWithPath:path)) } else if let u = URL(string:t.infoURL) { NSWorkspace.shared.open(u) } } label: {
   VStack(spacing:4) {
    Image(systemName:icon).font(.system(size:16)).foregroundStyle(t.installed ? CoreStyle.emerald : Color.white.opacity(0.5))
    Text(t.name).font(.system(size:10.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.85)).lineLimit(1)
    Circle().fill(t.installed ? CoreStyle.emerald : Color.clear).overlay(Circle().stroke(t.installed ? CoreStyle.emerald : CoreStyle.dim,lineWidth:1)).frame(width:5,height:5)
   }
   .frame(width:72,height:62)
   .background(RoundedRectangle(cornerRadius:9).fill(Color.white.opacity(0.03)))
   .overlay(RoundedRectangle(cornerRadius:9).stroke(Color.white.opacity(0.06),lineWidth:1))
  }
  .buttonStyle(.plain)
  .help(t.installed ? "Open \(t.name)" : "\(t.name) isn't installed on this Mac: opens its website")
 }

 func factTile(_ k: String,_ v: String,_ tone: Int) -> some View {
  VStack(alignment:.leading,spacing:2) {
   Text(k).font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
   Text(v).font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(tone == 1 ? CoreStyle.emerald : (tone == 2 ? CoreStyle.amber : CoreStyle.ink)).lineLimit(2).minimumScaleFactor(0.8)
  }
  .padding(.horizontal,10).padding(.vertical,7).frame(maxWidth:.infinity,alignment:.leading)
  .background(RoundedRectangle(cornerRadius:8).fill(Color.white.opacity(0.03)))
  .overlay(RoundedRectangle(cornerRadius:8).stroke(Color.white.opacity(0.05),lineWidth:1))
 }

 func leftFacts(isMac: Bool,d: LabDevice?) -> [(String,String,Int)] {
  if isMac {
   let os = macFacts.first { $0.0 == "macOS" }.map { "macOS " + $0.1 } ?? "macOS"
   let chip = macFacts.first { $0.0 == "Chip" }?.1 ?? "unknown"
   let mem = macFacts.first { $0.0 == "Memory" }?.1 ?? "?"
   return [("System",os,0),("Chip",chip,0),("Memory",mem,0),("Up for",CoreFacts.uptimeText(ProcessInfo.processInfo.systemUptime),0)]
  }
  guard let d else { return [] }
  return [("Platform",d.platform.label,0),("Yours",d.owned ? "yes (ticked)" : "not ticked",d.owned ? 1 : 2),("Address",d.address.isEmpty ? "none saved" : d.address,0),("Added",ago(d.added),0)]
 }

 func rightFacts(isMac: Bool,d: LabDevice?) -> [(String,String,Int)] {
  if isMac {
   let c = CoreFacts.summarize(guardHub.results)
   return [
    ("CPU now",monitor.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "measuring…",0),
    ("Memory used",monitor.memUsedGB.map { String(format:"%.1f GB",$0) } ?? "measuring…",0),
    ("Free disk",CoreFacts.freeDiskGB().map { "\(Int($0.rounded())) GB" } ?? "?",0),
    ("Guard",guardHub.results.isEmpty ? "not checked" : (c.warn == 0 ? "all \(c.ok) ok" : "\(c.warn) to look at"),guardHub.results.isEmpty ? 0 : (c.warn == 0 ? 1 : 2)),
   ]
  }
  guard let d else { return [] }
  return [("Connector",d.platform == .other ? "none" : "planned",0),("Readings","none: not connected",0),("Notes",d.notes.isEmpty ? "–" : d.notes,0)]
 }

 // A drawing of the kind of device, with real readings on its screen.
 @ViewBuilder func deviceArt(platform: LabPlatform,isMac: Bool,size: CGFloat) -> some View {
  let glow = isMac ? CoreStyle.crimson : Color.white.opacity(0.2)
  switch platform {
  case .iOS, .android:
   ZStack {
    RoundedRectangle(cornerRadius:26).fill(LinearGradient(colors:[HubTheme.hex(0x1A1A1E),HubTheme.hex(0x0C0C0E)],startPoint:.top,endPoint:.bottom))
    RoundedRectangle(cornerRadius:26).stroke(glow.opacity(0.7),lineWidth:1.5)
    VStack(spacing:6) {
     Capsule().fill(Color.black).frame(width:44,height:10).padding(.top,10)
     Spacer()
     Image(systemName:platform.symbol).font(.system(size:26,weight:.light)).foregroundStyle(Color.white.opacity(0.35))
     Text("not connected").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim)
     Spacer()
    }
   }
   .frame(width:min(140,size * 0.42),height:min(270,size * 0.82))
   .shadow(color:glow.opacity(0.25),radius:18)
  default:
   VStack(spacing:0) {
    ZStack {
     RoundedRectangle(cornerRadius:10).fill(LinearGradient(colors:[HubTheme.hex(0x1B0B0F),HubTheme.hex(0x09090B)],startPoint:.top,endPoint:.bottom))
     RoundedRectangle(cornerRadius:10).stroke(glow.opacity(0.8),lineWidth:1.4)
     if isMac {
      VStack(spacing:6) {
       Image(systemName:"apple.logo").font(.system(size:24)).foregroundStyle(CoreStyle.crimson)
       HStack(spacing:14) {
        screenStat("CPU",monitor.cpu.map { "\(Int(($0 * 100).rounded()))%" } ?? "…")
        screenStat("MEM",monitor.memUsedGB.map { String(format:"%.1f",$0) + "G" } ?? "…")
        screenStat("DISK",CoreFacts.freeDiskGB().map { "\(Int($0.rounded()))G" } ?? "…")
       }
       Text("live").font(.system(size:9.5,design:.rounded)).foregroundStyle(CoreStyle.emerald.opacity(0.8))
      }
     } else {
      VStack(spacing:4) {
       Image(systemName:platform.symbol).font(.system(size:24,weight:.light)).foregroundStyle(Color.white.opacity(0.35))
       Text("not connected").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim)
      }
     }
    }
    .frame(width:min(380,size * 1.2),height:min(230,size * 0.72))
    Trapezoid().fill(LinearGradient(colors:[HubTheme.hex(0x2A2A2F),HubTheme.hex(0x121214)],startPoint:.top,endPoint:.bottom))
     .frame(width:min(440,size * 1.38),height:12)
   }
   .shadow(color:glow.opacity(0.28),radius:22)
  }
 }

 func screenStat(_ k: String,_ v: String) -> some View {
  VStack(spacing:1) {
   Text(v).font(.system(size:15,weight:.light,design:.rounded)).foregroundStyle(CoreStyle.ink)
   Text(k).font(.system(size:9,weight:.semibold,design:.rounded)).tracking(1).foregroundStyle(CoreStyle.dim)
  }
 }

 // MARK: Tool Vault

 var vault: some View {
  CoreCard(title:"Tool Vault",icon:"shippingbox") {
   ScrollView {
    VStack(spacing:7) {
     ForEach(store.tools) { t in toolTile(t) }
     HStack(spacing:8) {
      Image(systemName:"plus.circle").foregroundStyle(CoreStyle.dim)
      Text("More free tools later: each one is added as its own module.").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim)
     }.padding(.top,2)
     HStack { pill("Check again") { store.detectTools() }; Spacer(minLength:0) }
    }
   }
  }
 }

 func toolTile(_ t: LabTool) -> some View {
  let icon = ["nmap":"dot.radiowaves.left.and.right","wireshark":"waveform.path","zap":"bolt.shield","kali":"terminal"][t.id] ?? "wrench.and.screwdriver"
  let purpose = ["nmap":"Find open ports on your own devices","wireshark":"Watch your own network traffic","zap":"Test your own web apps","kali":"Security lab system, in a virtual machine"][t.id] ?? t.role
  return HStack(alignment:.top,spacing:10) {
   ZStack {
    RoundedRectangle(cornerRadius:8).fill(Color.white.opacity(0.04)).frame(width:34,height:34)
    Image(systemName:icon).font(.system(size:15)).foregroundStyle(t.installed ? CoreStyle.emerald : Color.white.opacity(0.45))
   }
   VStack(alignment:.leading,spacing:3) {
    HStack(spacing:6) {
     Text(t.name).font(.system(size:12.5,weight:.semibold,design:.rounded)).foregroundStyle(CoreStyle.ink)
     Text(t.installed ? "installed" : "not installed").font(.system(size:10,weight:.medium,design:.rounded)).foregroundStyle(t.installed ? CoreStyle.emerald : CoreStyle.dim)
      .padding(.horizontal,6).padding(.vertical,1).background(Capsule().fill((t.installed ? CoreStyle.emerald : Color.white).opacity(0.08)))
    }
    Text(purpose).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.7)).lineLimit(2)
    HStack(spacing:10) {
     if t.installed, let path = t.appPath { Button("Open") { NSWorkspace.shared.open(URL(fileURLWithPath:path)) }.buttonStyle(.plain).font(.system(size:11,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.teal) }
     Button("About") { if let u = URL(string:t.infoURL) { NSWorkspace.shared.open(u) } }.buttonStyle(.plain).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.teal)
     Button("Ask Friday") { askFriday("Explain \(t.name) in plain words: what it's for, how I'd use it safely on my own devices, and whether it's worth installing on my 8 GB Mac.") }.buttonStyle(.plain).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.teal)
    }
   }
   Spacer(minLength:0)
  }
  .padding(8).background(RoundedRectangle(cornerRadius:9).fill(Color.white.opacity(0.025)))
 }

 // MARK: small panels underneath

 var experiments: some View {
  CoreCard(title:"Experiments",icon:"flask") {
   ScrollView {
    VStack(alignment:.leading,spacing:6) {
     if store.experiments.isEmpty { Text("None yet. A check you run on a device you added lands here with its time and result.").font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.dim) }
     ForEach(store.experiments.suffix(5).reversed()) { e in
      Button { ui.openExperiment = ui.openExperiment == e.id ? nil : e.id } label: {
       VStack(alignment:.leading,spacing:2) {
        HStack { Text("\(e.tool) · \(e.device)").font(.system(size:11.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink).lineLimit(1); Spacer(minLength:4); Text(ago(e.at)).font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim) }
        Text(e.summary).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.75))
        if ui.openExperiment == e.id, !e.output.isEmpty { Text(e.output).font(DeckMono.font(10)).foregroundStyle(CoreStyle.ink.opacity(0.7)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true) }
       }.contentShape(Rectangle())
      }.buttonStyle(.plain)
     }
    }
   }
  }
 }

 var learning: some View {
  CoreCard(title:"Learn",icon:"graduationcap") {
   let links = [("TryHackMe","https://tryhackme.com"),("Hack The Box","https://www.hackthebox.com"),("OWASP","https://owasp.org"),("Kali docs","https://www.kali.org/docs/"),("Nmap guide","https://nmap.org/book/man.html"),("Wireshark docs","https://www.wireshark.org/docs/")]
   LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],alignment:.leading,spacing:6) {
    ForEach(links,id:\.0) { l in
     Button { if let u = URL(string:l.1) { NSWorkspace.shared.open(u) } } label: {
      HStack(spacing:5) { Image(systemName:"arrow.up.right.square").font(.system(size:10)); Text(l.0).font(.system(size:11.5,design:.rounded)) }.foregroundStyle(CoreStyle.teal)
     }.buttonStyle(.plain)
    }
   }
   Text("Practise only on your own gear or practice sites.").font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
  }
 }

 var research: some View {
  CoreCard(title:"Research notes",icon:"note.text") {
   TextEditor(text:$notes.text).font(.system(size:12,design:.rounded)).scrollContentBackground(.hidden).foregroundStyle(CoreStyle.ink)
    .background(RoundedRectangle(cornerRadius:6).fill(Color.white.opacity(0.03)))
   Text("Saved on this Mac as you type.").font(.system(size:10.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
  }
 }
}

struct Trapezoid: Shape {
 func path(in r: CGRect) -> Path {
  var p = Path()
  p.move(to:CGPoint(x:r.minX + r.width * 0.06,y:r.minY)); p.addLine(to:CGPoint(x:r.maxX - r.width * 0.06,y:r.minY))
  p.addLine(to:CGPoint(x:r.maxX,y:r.maxY)); p.addLine(to:CGPoint(x:r.minX,y:r.maxY)); p.closeSubpath()
  return p
 }
}

extension CompanionInterfaceView {
 var commandCoreLab: some View {
  let store = LabStore.shared
  let installed = store.tools.filter { $0.installed }.count
  var facts: [(String,String)] = [
   ("macOS","\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion)"),
   ("Chip",SysFacts.string("machdep.cpu.brand_string") ?? "unknown"),
   ("Memory","\(Int(CoreFacts.memoryGB().rounded())) GB"),
   ("Up for",CoreFacts.uptimeText(ProcessInfo.processInfo.systemUptime)),
  ]
  if let free = CoreFacts.freeDiskGB() { facts.append(("Free disk","\(Int(free.rounded())) GB")) }
  let g = GuardHub.shared
  if !g.results.isEmpty { let c = CoreFacts.summarize(g.results); facts.append(("Guard's checks","\(c.ok) ok · \(c.warn) need a look")) }
  var obs = coreObservations()
  obs.insert(CoreObservation(tone:0,text:store.devices.isEmpty ? "Only this Mac is listed." : "\(store.devices.count) device\(store.devices.count == 1 ? "" : "s") added by you.",
   why:"Add an old phone or another machine you own and I'll keep a record of it. Nothing is scanned unless you ask, and only devices you tick as yours.",source:"your device list, now",
   actionTitle:"Look for USB devices",run:{ LabStore.shared.scanUSB() }),at:0)
  obs.append(CoreObservation(tone:0,text:"\(installed) of 4 lab tools found on this Mac.",why:"Nmap, Wireshark, OWASP ZAP and a VM app for Kali. I never install anything myself; that stays your call.",source:"app and program search, now"))
  return coreFrame("Cyber Lab","Your devices, tools and experiments · authorized, your own equipment only",observations:obs,
                   content:AnyView(CoreLabView(store:store,macFacts:facts,askFriday:{ q in FridayBrain.shared.draft = q; CoreShellUI.shared.drawerOpen = true })))
 }
}
