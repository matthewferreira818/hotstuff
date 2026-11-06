import SwiftUI
import AppKit

// Phase 2 engine, the runner: wakes an OPEN Local Claude chat by name (room pings and the Friday-and-me DM). Rules are in SwitchboardPingData.swift.
// A wake is the same locked-down headless relay as a Hotline relay (tools: ToolSearch, ListAgents, SendMessage; dontAsk; no MCP; no hooks),
// run one at a time in an empty folder, killed at 3 minutes. It sends FIXED text only: a link to a room message, or the DM sentence.
// Nothing about a message's words is ever put into a wake, a log line or a stored result.

@MainActor final class WakeRunner: ObservableObject {
 static let shared = WakeRunner()

 // Per room message: who was pinged and how it went. The screen reads this (result(forComment:)); the same shape is saved to pings.json.
 @Published private(set) var results: [Int64: PingResult] = [:]

 enum Kind { case room(Int64),dm([String]) }
 struct Job { var chat: String; var text: String; var kind: Kind }

 private var queue: [Job] = []
 private var running = false
 private var lastWake: [String: Date] = [:]      // normalized chat name -> when it was last woken
 private var sent: [Date] = []                   // every wake sent (rooms and DMs), for the hourly/daily caps

 private let folder: URL = {
  let base = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0]
  let dir = base.appendingPathComponent("Switchboard-\(Bundle.main.bundleIdentifier ?? "helm")",isDirectory:true)
  try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  return dir
 }()
 private var resultsURL: URL { folder.appendingPathComponent("pings.json") }
 private var workURL: URL {
  let dir = folder.appendingPathComponent("wake-work",isDirectory:true)
  try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  return dir
 }

 private init() {
  if let d = try? Data(contentsOf:resultsURL), let r = try? DMRules.decoder.decode([PingResult].self,from:d) { results = Dictionary(uniqueKeysWithValues:r.map { ($0.id,$0) }) }
 }

 func result(forComment id: Int64) -> PingResult? { results[id] }

 private func saveResults() {
  let all = results.values.sorted { $0.at > $1.at }.prefix(PingLimits.keep)
  if let d = try? DMRules.encoder.encode(Array(all)) { try? d.write(to:resultsURL,options:.atomic) }
 }

 // MARK: room pings

 // One wake per chat per message (the caller marks the message seen). Gated by the per-chat 2-minute cooldown and the hourly/daily caps.
 func submitRoom(commentID: Int64,chats: [String],link: String,now: Date = Date()) {
  var r = PingResult(id:commentID,at:now,targets:[:])
  for chat in chats {
   switch PingRules.gate(chat:chat,now:now,last:lastWake,sent:sent) {
   case .go:
    lastWake[SwitchboardRules.normalized(chat)] = now
    sent.append(now)
    r.targets[chat] = "pending"
    queue.append(Job(chat:chat,text:PingRules.wakeText(link:link),kind:.room(commentID)))
   case .cooldown: r.targets[chat] = "cooldown"
   case .hourCap,.dayCap: r.targets[chat] = "limit"
   }
  }
  results[commentID] = r
  saveResults()
  pump()
 }

 func recordPointer(commentID: Int64,posted: Bool) {
  var r = results[commentID] ?? PingResult(id:commentID,at:Date(),targets:[:])
  r.pointer = posted ? "posted" : "failed"
  results[commentID] = r
  saveResults()
 }

 // MARK: DM wake (called by FridayDM)

 // `ids` are the inbox ids this wake covers. Returns false if the hourly cap says no (the DM stays "waiting" and is retried).
 @discardableResult func submitDM(ids: [String],now: Date = Date()) -> Bool {
  guard PingRules.gate(chat:"Friday",now:now,last:[:],sent:sent) == .go else { return false }
  sent.append(now)
  queue.append(Job(chat:"Friday",text:PingRules.dmWakeText,kind:.dm(ids)))
  pump()
  return true
 }

 // MARK: the queue

 private func pump() {
  guard !running, !queue.isEmpty else { return }
  running = true
  let job = queue.removeFirst()
  Task {
   let state = await run(job)
   finish(job,state:state)
   running = false
   pump()
  }
 }

 private func finish(_ job: Job,state: String) {
  switch job.kind {
  case .room(let id):
   if var r = results[id] { r.targets[job.chat] = state; results[id] = r; saveResults() }
   Switchboard.shared.logPing("Room message \(id): pinged \(job.chat): \(state).")
  case .dm(let ids):
   FridayDM.shared.record(ids:ids,state:state == "delivered" ? "woken" : (state == "not open" ? "closed" : (state == "unconfirmed" ? "unconfirmed" : "failed")))
   Switchboard.shared.logPing("Friday DM wake: \(state).")   // never the DM
  }
 }

 // Returns "delivered" | "not open" | "unconfirmed" | "failed".
 private func run(_ job: Job) async -> String {
  let found = Switchboard.checkClaude()
  guard let exe = found.exe, found.version != nil else { return "failed" }
  let settings = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
  if SwitchboardRules.settingsProblem(try? Data(contentsOf:settings)) != nil { return "failed" }
  let args = PingRules.wakeArguments(name:job.chat,message:job.text)
  guard PingRules.wakeArgumentsAreSafe(args) else { return "failed" }
  let out = await runProcess(exe,args)
  if out.timedOut { return "failed" }
  let r = SwitchboardRules.parseRelay(out.data,target:job.chat,expected:job.text)
  if r.delivered { return "delivered" }
  if r.unproven { return "unconfirmed" }
  return r.detail.contains("isn't open") ? "not open" : "failed"
 }

 private func runProcess(_ exe: URL,_ args: [String]) async -> (data: Data,timedOut: Bool) {
  let cwd = workURL
  return await withCheckedContinuation { cont in
   DispatchQueue.global().async {
    let p = Process()
    p.executableURL = exe
    p.arguments = args
    p.currentDirectoryURL = cwd
    p.standardInput = FileHandle.nullDevice
    p.standardError = FileHandle.nullDevice
    let pipe = Pipe()
    p.standardOutput = pipe
    do { try p.run() } catch { cont.resume(returning:(Data(),true)); return }
    var timedOut = false
    let killer = DispatchWorkItem {
     timedOut = true
     p.terminate()
     DispatchQueue.global().asyncAfter(deadline:.now() + SwitchboardLimits.killGrace) { if p.isRunning { kill(p.processIdentifier,SIGKILL) } }
    }
    DispatchQueue.global().asyncAfter(deadline:.now() + PingLimits.timeout,execute:killer)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    killer.cancel()
    cont.resume(returning:(data,timedOut))
   }
  }
 }
}
