import Cocoa

// Friday's guard on the Mac (rules and tests in GuardData.swift). One shared hub, so the live session, the Helper and the Guard
// pages all see the same lockdown. Lockdown is remembered across launches; only Matthew's press of Unlock lifts it (Friday has no
// tool for it, and her hands are off while it is on). Every check runs a fixed program with fixed arguments, read-only.
@MainActor final class GuardHub: ObservableObject {
 static let shared = GuardHub()
 static var isLocked: Bool { UserDefaults.standard.bool(forKey:"guard.locked") }
 static var isOffline: Bool { UserDefaults.standard.bool(forKey:"guard.offline") }

 @Published private(set) var locked = GuardHub.isLocked
 @Published private(set) var offline = GuardHub.isOffline
 @Published private(set) var results: [GuardCheckResult] = []
 @Published private(set) var network: [GuardNetApp] = []
 @Published private(set) var log: [GuardEvent] = []
 @Published private(set) var checking = false
 @Published private(set) var lastChecked: Date?
 @Published var fakeText = ""
 @Published private(set) var fakeReport: FakeCheckReport?
 // Set by the live session when it starts, so lockdown can tell Friday at once.
 weak var live: LiveBuddy?

 private let logURL = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("GameCompanion/GuardLog.json")

 init() {
  if let data = try? Data(contentsOf:logURL), let saved = try? JSONDecoder().decode([GuardEvent].self,from:data) { log = saved }
 }

 var shield: (verdict: GuardVerdict,line: String) {
  if locked { return (.warn,"Lockdown is on.") }
  return GuardShield.summary(results)
 }

 // MARK: lockdown and offline

 func lock(_ reason: String) {
  guard !locked else { return }
  UserDefaults.standard.set(true,forKey:"guard.locked")
  locked = true
  note("lockdown","Lockdown ON (\(reason)).")
  live?.guardChanged(locked:true)
 }

 func unlock() {
  guard locked else { return }
  UserDefaults.standard.set(false,forKey:"guard.locked")
  locked = false
  note("unlock","Lockdown OFF (Matthew pressed Unlock).")
  live?.guardChanged(locked:false)
 }

 // Offline: The Helm stops starting its own internet calls (Friday's Google session, room reads, the Helper's Google brain).
 // To cut the Mac off completely he turns off Wi-Fi too; the Guard page says so.
 func setOffline(_ on: Bool) {
  guard on != offline else { return }
  UserDefaults.standard.set(on,forKey:"guard.offline")
  offline = on
  if on { live?.stop() }
  note("offline",on ? "Offline mode ON. Friday works with the brain on this Mac only." : "Offline mode OFF.")
 }

 // MARK: checks

 func runChecks() async {
  guard !checking else { return }
  checking = true
  defer { checking = false; lastChecked = Date() }
  var fresh: [GuardCheckResult] = []
  for kind in GuardCheckKind.allCases {
   let (path,args) = kind.command
   let answer = await Task.detached { GuardHub.run(path,args) }.value
   fresh.append(kind.read(answer.output,exitCode:answer.code))
  }
  // Things that start by themselves.
  let home = FileManager.default.homeDirectoryForCurrentUser
  var names: [String] = []
  for folder in GuardStartup.folders {
   let url = folder.hasPrefix("/") ? URL(fileURLWithPath:folder) : home.appendingPathComponent(folder)
   names += GuardStartup.names((try? FileManager.default.contentsOfDirectory(atPath:url.path)) ?? [])
  }
  names = Array(Set(names)).sorted()
  let knownStartup = UserDefaults.standard.stringArray(forKey:"guard.startup")
  fresh.append(GuardStartup.result(names,known:knownStartup))
  UserDefaults.standard.set(names,forKey:"guard.startup")
  // Apps using the internet.
  let (netPath,netArgs) = GuardNetwork.command
  let net = await Task.detached { GuardHub.run(netPath,netArgs) }.value
  let counts = GuardNetwork.parse(net.output)
  let knownNet = UserDefaults.standard.stringArray(forKey:"guard.network")
  network = GuardNetwork.apps(counts,known:knownNet)
  fresh.append(GuardNetwork.result(network,firstLook:knownNet == nil))
  UserDefaults.standard.set(Array(Set((knownNet ?? []) + counts.keys)).sorted(),forKey:"guard.network")
  results = fresh
  let warns = fresh.filter { $0.verdict == .warn }
  note("check",warns.isEmpty ? "Checks done: all clear." : "Checks done: " + warns.map { $0.title }.joined(separator:", ") + " need a look.")
  for warn in warns where warn.id == "startup" || warn.id == "network" { note("warning","\(warn.title): \(warn.detail)") }
 }

 // MARK: keys

 func isSaved(_ key: GuardKeyInfo) -> Bool { Keychain.exists(key.service) }

 func forget(_ key: GuardKeyInfo) {
  Keychain.remove(key.service)
  note("key","Forgot \(key.title) on this Mac. Make a fresh one at \(key.renew) when you need it again.")
 }

 // MARK: Real or Fake?

 func checkFake() {
  let report = FakeCheck.check(fakeText)
  fakeReport = report
  if !fakeText.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { note("fakecheck","Real or Fake? \(report.verdict) (\(report.flags.count) red flag\(report.flags.count == 1 ? "" : "s")).") }
 }

 // MARK: log

 func note(_ kind: String,_ text: String) {
  log = GuardLog.appending(log,GuardEvent(at:Date(),kind:kind,text:text))
  do {
   try FileManager.default.createDirectory(at:logURL.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
   try JSONEncoder().encode(log).write(to:logURL,options:.atomic)
   try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:logURL.path)
  } catch {}
 }

 func clearLog() { log = []; try? FileManager.default.removeItem(at:logURL) }

 // A fixed, read-only program, off the main thread, with a 15-second limit. The output is read on its own thread so a long
 // answer (lsof) can never fill the pipe and stall the program.
 nonisolated static func run(_ path: String,_ args: [String]) -> (output: String,code: Int32) {
  guard FileManager.default.isExecutableFile(atPath:path) else { return ("",127) }
  final class Box: @unchecked Sendable { var data = Data() }
  let process = Process()
  process.executableURL = URL(fileURLWithPath:path)
  process.arguments = args
  let out = Pipe()
  process.standardOutput = out
  process.standardError = out
  do { try process.run() } catch { return ("",126) }
  let box = Box()
  let done = DispatchSemaphore(value:0)
  let reader = out.fileHandleForReading
  DispatchQueue.global().async { box.data = reader.readDataToEndOfFile(); done.signal() }
  if done.wait(timeout:.now() + 15) == .timedOut {
   process.terminate()
   _ = done.wait(timeout:.now() + 2)
   return (String(data:box.data,encoding:.utf8) ?? "",124)
  }
  process.waitUntilExit()
  return (String(data:box.data,encoding:.utf8) ?? "",process.terminationStatus)
 }
}
