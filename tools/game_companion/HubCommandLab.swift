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

struct CoreLabView: View {
 @ObservedObject var store: LabStore
 @ObservedObject var ui = LabUI.shared
 var macFacts: [(String,String)]

 private func card<C: View>(_ title: String,@ViewBuilder _ content: () -> C) -> some View {
  VStack(alignment:.leading,spacing:9) {
   Text(title).font(.system(size:11,weight:.semibold,design:.rounded)).tracking(2).foregroundStyle(CoreStyle.dim)
   content()
  }
  .padding(16).frame(maxWidth:.infinity,alignment:.topLeading)
  .background(RoundedRectangle(cornerRadius:16).fill(LinearGradient(colors:[CoreStyle.card,CoreStyle.charcoal],startPoint:.top,endPoint:.bottom)))
  .overlay(RoundedRectangle(cornerRadius:16).stroke(LinearGradient(colors:[CoreStyle.crimson.opacity(0.30),Color.white.opacity(0.04)],startPoint:.top,endPoint:.bottom),lineWidth:1))
 }
 private func pill(_ text: String,_ color: Color = CoreStyle.teal,_ action: @escaping () -> Void) -> some View {
  Button(action:action) { Text(text).font(.system(size:12,weight:.medium,design:.rounded)).foregroundStyle(color).padding(.horizontal,11).padding(.vertical,5).overlay(Capsule().stroke(color.opacity(0.6),lineWidth:1)) }.buttonStyle(.plain)
 }
 private func ago(_ d: Date) -> String { let s = Int(Date().timeIntervalSince(d)); return s < 90 ? "just now" : (s < 3600 ? "\(s / 60) min ago" : (s < 86400 ? "\(s / 3600) h ago" : "\(s / 86400) d ago")) }

 var selectedDevice: LabDevice? { store.devices.first { $0.id == ui.selected } }

 var body: some View {
  ScrollView {
   VStack(alignment:.leading,spacing:14) {
    HStack(alignment:.top,spacing:14) {
     devicesCard.frame(width:235)
     centerCard
     toolsCard.frame(width:265)
    }
    experimentsCard
    learningCard
   }
   .padding(.horizontal,26).padding(.vertical,6)
  }
 }

 // MARK: devices

 var devicesCard: some View {
  card("DEVICES · \(store.devices.count + 1)") {
   deviceRow(id:"this-mac",name:"This Mac",sub:"macOS \(ProcessInfo.processInfo.operatingSystemVersion.majorVersion).\(ProcessInfo.processInfo.operatingSystemVersion.minorVersion) · automatic",symbol:"laptopcomputer",dot:CoreStyle.emerald)
   ForEach(store.devices) { d in deviceRow(id:d.id,name:d.name,sub:d.platform.rawValue + " · added by you",symbol:d.platform.symbol,dot:CoreStyle.dim) }
   if ui.adding {
    VStack(alignment:.leading,spacing:6) {
     TextField("Name (e.g. Old iPhone)",text:$ui.name).textFieldStyle(.roundedBorder)
     Picker("",selection:$ui.platform) { ForEach(LabPlatform.allCases) { Text($0.label).tag($0) } }.labelsHidden()
     TextField("Private address (optional, e.g. 192.168.1.20)",text:$ui.address).textFieldStyle(.roundedBorder)
     TextField("Notes",text:$ui.notes).textFieldStyle(.roundedBorder)
     Toggle("This device is mine",isOn:$ui.owned).font(.system(size:12.5,design:.rounded)).toggleStyle(.checkbox)
     HStack {
      pill("Add") { store.add(name:ui.name,platform:ui.platform,address:ui.address,notes:ui.notes,owned:ui.owned); ui.name = ""; ui.address = ""; ui.notes = ""; ui.owned = false; ui.adding = false }
      pill("Cancel",CoreStyle.dim) { ui.adding = false }
     }
    }
   } else {
    pill("+ Add a device you own") { ui.adding = true }
   }
  }
 }

 func deviceRow(id: String,name: String,sub: String,symbol: String,dot: Color) -> some View {
  let on = ui.selected == id
  return Button { ui.selected = id } label: {
   HStack(spacing:9) {
    Image(systemName:symbol).font(.system(size:15)).foregroundStyle(on ? CoreStyle.crimson : CoreStyle.ink.opacity(0.8)).frame(width:20)
    VStack(alignment:.leading,spacing:1) {
     Text(name).font(.system(size:13.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink).lineLimit(1)
     Text(sub).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim).lineLimit(1)
    }
    Spacer(minLength:4)
    Circle().fill(dot).frame(width:7,height:7)
   }
   .padding(8).frame(maxWidth:.infinity,alignment:.leading)
   .background(RoundedRectangle(cornerRadius:10).fill(on ? CoreStyle.crimson.opacity(0.10) : Color.clear))
   .overlay(RoundedRectangle(cornerRadius:10).stroke(on ? CoreStyle.crimson.opacity(0.55) : Color.white.opacity(0.05),lineWidth:1))
   .contentShape(Rectangle())
  }.buttonStyle(.plain)
 }

 // MARK: the selected device

 var centerCard: some View {
  Group {
   if ui.selected == "this-mac" {
    card("THIS MAC · LOCAL, MEASURED NOW") {
     ForEach(Array(macFacts.enumerated()),id:\.offset) { _,f in row(f.0,f.1) }
     Divider().overlay(Color.white.opacity(0.06))
     Text("CONNECTED PHONES AND OTHER USB DEVICES").font(.system(size:10.5,weight:.semibold,design:.rounded)).tracking(1.5).foregroundStyle(CoreStyle.dim)
     if let usb = store.usb {
      if usb.isEmpty { Text("macOS reports no USB devices right now.").font(.system(size:13,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.8)) }
      ForEach(Array(usb.enumerated()),id:\.offset) { _,n in Text("• " + n).font(.system(size:13,design:.rounded)).foregroundStyle(CoreStyle.ink) }
      if let at = store.usbAt { Text("from macOS's own USB report, \(ago(at))").font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim) }
     } else {
      Text(store.usbFailed ? "macOS didn't return a USB report." : "Not looked yet. Plug a phone in by cable, then look.").font(.system(size:13,design:.rounded)).foregroundStyle(CoreStyle.dim)
     }
     pill(store.running ? "looking…" : "Look for USB devices") { store.scanUSB() }.disabled(store.running)
    }
   } else if let d = selectedDevice {
    card("\(d.name.uppercased()) · ADDED BY YOU") {
     row("Platform",d.platform.label); row("Owned by you",d.owned ? "yes (you ticked it)" : "not ticked",d.owned ? 1 : 2)
     row("Address",d.address.isEmpty ? "none saved" : d.address); row("Added",ago(d.added))
     if !d.notes.isEmpty { row("Notes",d.notes) }
     row("Connector",d.platform.connector)
     Text("Nothing is probing this device. It is only a record until a connector for its platform exists.").font(.system(size:12.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.75)).fixedSize(horizontal:false,vertical:true)
     HStack(spacing:8) {
      pill(store.running ? "running…" : "Nmap quick port check") { store.nmapCheck(d) }.disabled(store.running)
      pill("Remove",CoreStyle.crimson) { let id = d.id; ui.selected = "this-mac"; store.remove(id) }
     }
     if let why = ScopeRules.refusal(for:d) { Text("The port check is off for this device: \(why)").font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.dim).fixedSize(horizontal:false,vertical:true) }
     if !store.note.isEmpty { Text(store.note).font(.system(size:12,design:.rounded)).foregroundStyle(CoreStyle.teal) }
    }
   } else {
    card("DEVICE") { Text("Pick a device on the left.").font(.system(size:13,design:.rounded)).foregroundStyle(CoreStyle.dim) }
   }
  }
 }

 func row(_ k: String,_ v: String,_ tone: Int = 0) -> some View {
  HStack(alignment:.firstTextBaseline) {
   Text(k).font(.system(size:12.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
   Spacer(minLength:8)
   Text(v).font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(tone == 1 ? CoreStyle.emerald : (tone == 2 ? CoreStyle.amber : CoreStyle.ink)).multilineTextAlignment(.trailing)
  }
 }

 // MARK: tools

 var toolsCard: some View {
  card("TOOLS · FOUND ON THIS MAC") {
   ForEach(store.tools) { t in
    VStack(alignment:.leading,spacing:2) {
     HStack(spacing:8) {
      Circle().fill(t.installed ? CoreStyle.emerald : Color.clear).overlay(Circle().stroke(t.installed ? CoreStyle.emerald : CoreStyle.dim,lineWidth:1)).frame(width:8,height:8)
      Text(t.name).font(.system(size:13.5,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink)
      Spacer(minLength:4)
      Text(t.installed ? "installed" : "not found").font(.system(size:11.5,design:.rounded)).foregroundStyle(t.installed ? CoreStyle.emerald : CoreStyle.dim)
     }
     Text(t.role + " · " + t.detail).font(.system(size:11,design:.rounded)).foregroundStyle(CoreStyle.dim).fixedSize(horizontal:false,vertical:true)
     HStack(spacing:8) {
      if t.installed, let path = t.appPath { pill("Open") { NSWorkspace.shared.open(URL(fileURLWithPath:path)) } }
      pill("About",CoreStyle.dim) { if let u = URL(string:t.infoURL) { NSWorkspace.shared.open(u) } }
     }
    }
    Divider().overlay(Color.white.opacity(0.05))
   }
   pill("Look again") { store.detectTools() }
  }
 }

 // MARK: experiments + learning

 var experimentsCard: some View {
  card("EXPERIMENT HISTORY · THIS MAC ONLY") {
   if store.experiments.isEmpty { Text("No experiments yet. A check you run from a device you added shows up here with its time and result.").font(.system(size:13,design:.rounded)).foregroundStyle(CoreStyle.dim) }
   ForEach(store.experiments.suffix(6).reversed()) { e in
    Button { ui.openExperiment = ui.openExperiment == e.id ? nil : e.id } label: {
     VStack(alignment:.leading,spacing:3) {
      HStack {
       Text("\(e.tool) · \(e.device)").font(.system(size:13,weight:.medium,design:.rounded)).foregroundStyle(CoreStyle.ink)
       Spacer(minLength:6)
       Text(ago(e.at)).font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
      }
      Text(e.summary).font(.system(size:12.5,design:.rounded)).foregroundStyle(CoreStyle.ink.opacity(0.8))
      if ui.openExperiment == e.id, !e.output.isEmpty { Text(e.output).font(DeckMono.font(11)).foregroundStyle(CoreStyle.ink.opacity(0.75)).textSelection(.enabled).fixedSize(horizontal:false,vertical:true) }
     }
     .contentShape(Rectangle())
    }.buttonStyle(.plain)
   }
  }
 }

 var learningCard: some View {
  card("LEARN · LINKS THAT OPEN IN YOUR BROWSER") {
   HStack(spacing:8) {
    ForEach([("TryHackMe","https://tryhackme.com"),("Hack The Box","https://www.hackthebox.com"),("OWASP","https://owasp.org"),("Kali docs","https://www.kali.org/docs/"),("Nmap guide","https://nmap.org/book/man.html"),("Wireshark docs","https://www.wireshark.org/docs/")],id:\.0) { l in
     pill(l.0) { if let u = URL(string:l.1) { NSWorkspace.shared.open(u) } }
    }
    Spacer(minLength:0)
   }
   Text("Practise only on your own devices or on sites built for practice. Signing up for any of these is your hands.").font(.system(size:11.5,design:.rounded)).foregroundStyle(CoreStyle.dim)
  }
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
                   content:AnyView(CoreLabView(store:store,macFacts:facts)))
 }
}
