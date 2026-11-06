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

 // .handoff: this wake goes to a BACKUP (Friday / LC-Manager) because `original` chat was closed; `rest` are the backups still to try.
 // .held: a later probe, delivering the copy kept for the chat that was closed.
 enum Kind { case room(Int64),dm([String]),handoff(origin: Int64,original: String,body: String,rest: [String],ref: String),held(String),job(String),jobBackup(String) }
 struct Job { var chat: String; var text: String; var kind: Kind }
 @Published private(set) var held: [PingRules.Held] = []
 private var probeLoop: Task<Void,Never>?

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
 private var heldURL: URL { folder.appendingPathComponent("held.json") }
 private var resultsURL: URL { folder.appendingPathComponent("pings.json") }
 private var workURL: URL {
  let dir = folder.appendingPathComponent("wake-work",isDirectory:true)
  try? FileManager.default.createDirectory(at:dir,withIntermediateDirectories:true)
  return dir
 }

 private init() {
  if let d = try? Data(contentsOf:resultsURL), let r = try? DMRules.decoder.decode([PingResult].self,from:d) { results = Dictionary(uniqueKeysWithValues:r.map { ($0.id,$0) }) }
  if let d = try? Data(contentsOf:heldURL), let h = try? DMRules.decoder.decode([PingRules.Held].self,from:d) { held = h }
 }

 // Called once at app start (Switchboard.boot): resumes the 15-minute probes for copies still held for a closed chat.
 func start() {
  guard probeLoop == nil else { return }
  probeLoop = Task { [weak self] in
   while !Task.isCancelled {
    try? await Task.sleep(nanoseconds:60_000_000_000)
    self?.probeHeld()
   }
  }
 }

 private func saveHeld() { if let d = try? DMRules.encoder.encode(held) { try? d.write(to:heldURL,options:.atomic) } }

 private func probeHeld(now: Date = Date()) {
  let expired = held.filter { PingRules.heldExpired($0,now:now) }
  if !expired.isEmpty {
   held.removeAll { h in expired.contains { $0.id == h.id } }
   saveHeld()
   for h in expired { Switchboard.shared.logPing("Held copy for \(h.chat) (message \(h.origin)) dropped after 12 hours.") }
  }
  guard queue.isEmpty, !running else { return }
  guard let i = held.firstIndex(where:{ PingRules.heldDue($0,now:now) }) else { return }
  guard PingRules.gate(chat:held[i].chat,now:now,last:[:],sent:sent) == .go else { return }
  held[i].lastTry = now
  saveHeld()
  sent.append(now)
  queue.append(Job(chat:held[i].chat,text:PingRules.heldText(held[i]),kind:.held(held[i].id)))
  pump()
 }

 // MARK: closed chats (a wake or relay came back "isn't open")

 // Hand the message to the backup manager AT ONCE, and keep one copy for the original chat.
 func handOff(chat: String,original: String,origin: Int64,ref: String,now: Date = Date()) {
  var r = results[origin] ?? PingResult(id:origin,at:now,targets:[:])
  r.targets[chat] = "pending"
  results[origin] = r
  saveResults()
  let id = "\(origin)-\(SwitchboardRules.NameMatch.loose(chat))"
  if !held.contains(where:{ $0.id == id }) {
   held.append(PingRules.Held(id:id,chat:chat,text:original,origin:origin,since:now))
   saveHeld()
  }
  startHandOff(chat:chat,original:original,rest:PingRules.backups(for:chat),origin:origin,ref:ref)
 }

 private func startHandOff(chat: String,original: String,rest: [String],origin: Int64,ref: String) {
  guard let backup = rest.first else {
   // nobody could take it: the screen says so, the Hotline gets one line, the held copy stays for when the chat reopens
   setTarget(origin,chat,"closed")
   Task { _ = await Switchboard.shared.postHotline(PingRules.hotlineLine(chat:chat,backup:nil,ref:ref)) }
   return
  }
  queue.append(Job(chat:backup,text:PingRules.handOffText(chat:chat,original:original),kind:.handoff(origin:origin,original:chat,body:original,rest:Array(rest.dropFirst()),ref:ref)))
  pump()
 }

 private func setTarget(_ origin: Int64,_ chat: String,_ state: String) {
  var r = results[origin] ?? PingResult(id:origin,at:Date(),targets:[:])
  r.targets[chat] = state
  results[origin] = r
  saveResults()
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
    lastWake[SwitchboardRules.NameMatch.loose(chat)] = now
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

 // Crew job cards (JobHealing.swift): wake the job's own chat with the job id only. Same caps and cooldowns as every wake.
 @discardableResult func submitJob(id: String,chat: String,now: Date = Date()) -> Bool {
  guard PingRules.gate(chat:chat,now:now,last:lastWake,sent:sent) == .go else { return false }
  lastWake[SwitchboardRules.NameMatch.loose(chat)] = now
  sent.append(now)
  queue.append(Job(chat:chat,text:JobHeal.wakeText(id:id),kind:.job(id)))
  pump()
  return true
 }

 @discardableResult func submitJobBackup(id: String,backup: String,text: String,now: Date = Date()) -> Bool {
  guard PingRules.gate(chat:backup,now:now,last:[:],sent:sent) == .go else { return false }
  sent.append(now)
  queue.append(Job(chat:backup,text:text,kind:.jobBackup(id)))
  pump()
  return true
 }

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
   Switchboard.shared.logPing("Room message \(id): pinged \(job.chat): \(state).")
   if state == "not open" {
    // The text of a room ping is a link, so it can be passed on as is.
    let link = job.text.hasPrefix(PingRules.wakeFor) ? String(job.text.dropFirst(PingRules.wakeFor.count)) : job.text
    handOff(chat:job.chat,original:"new room message for \(job.chat): \(link)",origin:id,ref:"room message \(id)")
   } else {
    setTarget(id,job.chat,state)
   }
  case .dm(let ids):
   FridayDM.shared.record(ids:ids,state:state == "delivered" ? "woken" : (state == "not open" ? "closed" : (state == "unconfirmed" ? "unconfirmed" : "failed")))
   Switchboard.shared.logPing("Friday DM wake: \(state).")   // never the DM
  case .handoff(let origin,let original,let body,let rest,let ref):
   if state == "delivered" {
    setTarget(origin,original,"handed to \(job.chat)")
    Switchboard.shared.logPing("\(original) is closed: \(job.chat) has \(ref).")
    Task { _ = await Switchboard.shared.postHotline(PingRules.hotlineLine(chat:original,backup:job.chat,ref:ref)) }
   } else {
    Switchboard.shared.logPing("\(original) is closed and \(job.chat) couldn't take \(ref): \(state).")
    startHandOff(chat:original,original:body,rest:rest,origin:origin,ref:ref)
   }
  case .job(let id):
   Switchboard.shared.logPing("Job \(id): woke \(job.chat): \(state).")   // id and chat only, never the job's title
   if state == "delivered" { JobWatcher.shared.resendDelivered(id:id) }
   if state == "not open" { JobWatcher.shared.handBack(id:id,chat:job.chat,closed:true) }
  case .jobBackup(let id):
   Switchboard.shared.logPing("Job \(id): handed to \(job.chat) as backup: \(state).")
   JobWatcher.shared.handOffFinished(id:id,backup:job.chat,delivered:state == "delivered")
  case .held(let id):
   guard let h = held.first(where:{ $0.id == id }) else { return }
   if state == "delivered" {
    held.removeAll { $0.id == id }
    saveHeld()
    setTarget(h.origin,h.chat,"delivered later")
    Switchboard.shared.logPing("\(h.chat) reopened: the held copy for message \(h.origin) was delivered.")
   }   // not open / failed: it stays held, the next probe is in 15 minutes
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
  let began = Date()
  let out = await runProcess(exe,args)
  let r = SwitchboardRules.parseRelay(out.data,target:job.chat,expected:job.text)
  // Ledger "ok" = delivery PROVEN (New beginning, rule 1). A wake that only finished, or is unproven, is not a green check.
  UsageLedger.shared.record(who:"Wake",job:job.chat,started:began,ok:!out.timedOut && r.delivered,data:out.data)
  if out.timedOut { return "failed" }
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
